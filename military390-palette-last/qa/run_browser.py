#!/usr/bin/env python3
"""Explicitly invoked, fail-closed fresh-GitHub-hosted Docker browser supervisor.

No subprocess is launched on import. Lock is reviewed separately, never generated
by this program. Prep/downloads happen outside this 120-second offline operation.
"""
import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import re
import secrets
import signal
import subprocess
import time
from guard_contract import require, check_owner, create_args, abort_reason, GIB

SOURCE_COMMIT = 'ce2ea3d2513bd79cf62cf5c651abe3c47aad8513'
IMAGE_DIGESTS = {'3bed4b1a12f2338642f3d8cba28e291deef3c66bd4a964bbeb3e57bbff511dbd',
                 '8fb7af3bb488c51364d6554876a8eddf377736608327dbdf4177b4901faf7bc9'}
NPM_INTEGRITY = 'sha512-ilYQj1s8sr2ppEJ2YVadYBN0Mb3mdo9J0wQ+UuDhzYqURwSoW4n1Xs5vs7ORwgDGmyEh33tRMeS8KhdkMoLXQw=='
CORE_INTEGRITY = 'sha512-agTcKlMw/mjBWOnD6kFZttAAGHgi/Nw0CZ2o6JqWSbMlI219lAFLZZCyqByTsvVAJq5XA5H8cA6PrvBRpBWEuQ=='


def sha(path, kind='sha256'):
    with Path(path).open('rb') as stream:
        return hashlib.file_digest(stream, kind).digest()


def inventory(root):
    require(root.is_dir() and not root.is_symlink(), 'Input root must be a real directory')
    result = {}
    for path in sorted(root.rglob('*')):
        require(not path.is_symlink(), 'Input symlink: ' + str(path))
        require(path.is_dir() or path.is_file(), 'Special input file')
        if path.is_file():
            result[path.relative_to(root).as_posix()] = sha(path).hex()
    return result


def read_json(path):
    return json.loads(Path(path).read_text())


def save(path, data):
    temporary = path.with_suffix('.tmp')
    temporary.write_text(json.dumps(data, indent=2) + '\n')
    temporary.replace(path)


def available_memory():
    for line in Path('/proc/meminfo').read_text().splitlines():
        if line.startswith('MemAvailable:'):
            return int(line.split()[1]) * 1024
    raise RuntimeError('MemAvailable unavailable')


def host_oom():
    return int(dict(line.split() for line in Path('/proc/vmstat').read_text().splitlines())['oom_kill'])


class Docker:
    def call(self, args, timeout=4, check=True):
        # No shell, inherited credentials or unbounded output streams.
        proc = subprocess.run(['docker', *args], stdin=subprocess.DEVNULL,
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                              timeout=timeout, env={'PATH': '/usr/bin:/bin', 'HOME': '/tmp'}, text=True)
        require(len(proc.stdout) <= 2 * 1024 * 1024 and len(proc.stderr) <= 65536, 'Oversized Docker response')
        if check:
            require(proc.returncode == 0, 'Docker ' + args[0] + ': ' + proc.stderr[:1200])
        return proc

    def inspect(self, identifier, timeout=4):
        return json.loads(self.call(['inspect', '--type=container', identifier], timeout=timeout).stdout)[0]

    def find(self, name):
        result = self.call(['container', 'ls', '-aq', '--no-trunc', '--filter', 'name=^/' + name + '$'])
        ids = result.stdout.split()
        require(len(ids) <= 1, 'Ambiguous exact container name')
        return ids[0] if ids else None


def resolve_creation(docker, name, owner, returned_id=None):
    cid = returned_id if returned_id and re.fullmatch('[0-9a-f]{64}', returned_id) else docker.find(name)
    if cid is not None:
        check_owner(cid, owner, docker.inspect(cid))
    return cid


def cleanup(docker, receipt, persist):
    """Resolve uncertain create; reverify exact owner before every mutation."""
    cid = resolve_creation(docker, receipt['name'], receipt['owner'], receipt.get('container_id'))
    if cid is None:
        receipt['cleanup_verified'] = True
        persist(); return
    receipt['container_id'] = cid
    persist()
    current = docker.inspect(cid)
    check_owner(cid, receipt['owner'], current)
    if current['State']['Running']:
        try:
            docker.call(['stop', '--time=3', cid], timeout=5)
        except (RuntimeError, ValueError, subprocess.TimeoutExpired):
            receipt.setdefault('cleanup_warnings', []).append('Stop failed/uncertain; inspected before exact-ID kill')
        current = docker.inspect(cid)
        check_owner(cid, receipt['owner'], current)
        if current['State']['Running']:
            docker.call(['kill', cid])
            current = docker.inspect(cid)
            check_owner(cid, receipt['owner'], current)
            require(not current['State']['Running'], 'Exact owned container still running')
    receipt['final_container_state'] = current['State']
    check_owner(cid, receipt['owner'], docker.inspect(cid))
    try:
        docker.call(['rm', cid])
    except (RuntimeError, ValueError, subprocess.TimeoutExpired):
        receipt.setdefault('cleanup_warnings', []).append('Remove failed/uncertain; verifying absence')
    # Enumeration errors are NOT treated as absence.
    ids = docker.call(['container', 'ls', '-aq', '--no-trunc']).stdout.split()
    require(cid not in ids and docker.find(receipt['name']) is None, 'Cleanup absence unverified')
    receipt['cleanup_verified'] = True
    persist()


def verify_effective(record, image_id):
    h, c = record['HostConfig'], record['Config']
    require(record['Image'] == image_id, 'Effective image identity mismatch')
    require(h['Memory'] == 3 * GIB and h['MemorySwap'] == 3 * GIB, 'Memory/swap limits missing')
    require(h['PidsLimit'] == 256 and h['NanoCpus'] == 2_000_000_000, 'PID/CPU limits missing')
    require(h['NetworkMode'] == 'none' and h['ShmSize'] == 256 * 1024 ** 2, 'Network/shm mismatch')
    require(h['IpcMode'] == 'private' and not h['Privileged'] and not h.get('CapAdd'), 'Unsafe privileges/IPC')
    require(not h.get('SecurityOpt') and not h.get('Sysctls'), 'Unexpected security override')
    require(not h.get('OomKillDisable') and h.get('OomScoreAdj', 0) == 0, 'OOM protection changed')
    require(c['User'] == 'pwuser' and not h.get('PortBindings'), 'Wrong user/published ports')
    require(h.get('Init') is True, 'Init reaper missing')
    mounts = {m['Destination']: m for m in record['Mounts']}
    require(set(mounts) == {'/export', '/qa', '/deps/node_modules/playwright', '/deps/node_modules/playwright-core', '/artifacts'}, 'Unexpected mounts')
    require(all(m['Type'] == 'bind' and m['RW'] == (dest == '/artifacts') for dest, m in mounts.items()), 'Unexpected mount write access')
    require(c['Cmd'] == ['node', '/qa/container_main.mjs'], 'Unexpected container command')


def cgroup_for(pid):
    require(type(pid) is int and pid > 0, 'Missing owned init PID')
    entries = Path(f'/proc/{pid}/cgroup').read_text().splitlines()
    path = next((x[3:] for x in entries if x.startswith('0::')), None)
    require(path is not None and '..' not in Path(path).parts, 'cgroup v2 unavailable')
    root = Path('/sys/fs/cgroup')
    group = root / path.lstrip('/')
    require(group.resolve().is_relative_to(root), 'Unsafe cgroup path')
    require(int((group / 'memory.max').read_text()) == 3 * GIB, 'Effective cgroup memory mismatch')
    require(int((group / 'memory.swap.max').read_text()) == 0, 'Effective swap mismatch')
    require(int((group / 'pids.max').read_text()) == 256, 'Effective PID bound mismatch')
    quota, period = (group / 'cpu.max').read_text().split()
    require(int(quota) == 2 * int(period), 'Effective CPU cgroup mismatch')
    return group


def sample(group):
    events = {k: int(v) for k, v in (line.split() for line in (group / 'memory.events').read_text().splitlines())}
    return {'host_available': available_memory(), 'host_oom_kill': host_oom(),
            'memory_current': int((group / 'memory.current').read_text()),
            'pids_current': int((group / 'pids.current').read_text()), 'events': events}


def validate_dependency_tree(deps, expected):
    require(inventory(deps) == expected, 'Complete dependency inventory mismatch')


def validate_inputs(lock, export, bundle, deps, require_image=True):
    require(lock.get('reviewed') is True, 'Explicit reviewed lock required')
    require(lock.get('build') == 'vc-79ebcaef19e3', 'Wrong build')
    require(lock.get('source_commit') == SOURCE_COMMIT, 'Exact reviewed source commit required')
    if require_image:
        require(re.fullmatch(r'mcr\.microsoft\.com/playwright:v1\.57\.0-noble@sha256:[0-9a-f]{64}', lock.get('image', '')), 'Pin official v1.57.0 digest')
        require(lock['image'].rsplit(':', 1)[1] in IMAGE_DIGESTS, 'Unreviewed official image digest')
    actual = inventory(export)
    require(actual == lock.get('files_sha256') and 'index.html' in actual and any(x.endswith('.wasm') for x in actual) and any(x.endswith('.pck') for x in actual), 'Exact verified export inventory mismatch')
    require(inventory(bundle) == lock.get('qa_files_sha256'), 'QA bundle inventory mismatch')
    validate_dependency_tree(deps, lock.get('deps_files_sha256'))
    require(sha(deps / 'package-lock.json').hex() == lock.get('npm_lock_sha256'), 'npm lock mismatch')
    require(sha(deps / 'playwright-1.57.0.tgz').hex() == lock.get('npm_tarball_sha256'), 'npm tarball hash mismatch')
    integrity = 'sha512-' + base64.b64encode(sha(deps / 'playwright-1.57.0.tgz', 'sha512')).decode()
    require(integrity == lock.get('npm_registry_integrity') == NPM_INTEGRITY, 'npm registry integrity mismatch')
    core_tar = deps / 'playwright-core-1.57.0.tgz'
    require(sha(core_tar).hex() == lock.get('npm_core_tarball_sha256'), 'npm core tarball hash mismatch')
    core_integrity = 'sha512-' + base64.b64encode(sha(core_tar, 'sha512')).decode()
    require(core_integrity == lock.get('npm_core_registry_integrity') == CORE_INTEGRITY, 'npm core registry integrity mismatch')
    npm = read_json(deps / 'package-lock.json')['packages']
    for name in ['playwright', 'playwright-core']:
        entry = npm['node_modules/' + name]
        require(entry['version'] == '1.57.0' and entry['resolved'] == f'https://registry.npmjs.org/{name}/-/{name}-1.57.0.tgz', 'Unofficial/mismatched package')
        require(read_json(deps / 'node_modules' / name / 'package.json')['version'] == '1.57.0', 'Installed version mismatch')
    require(npm['node_modules/playwright']['integrity'] == integrity, 'Lock integrity mismatch')
    require(npm['node_modules/playwright-core']['integrity'] == core_integrity, 'Core lock integrity mismatch')
    # npm creates .bin links. Bind only real package trees; pin every installed byte.
    installed = {name: inventory(deps / 'node_modules' / name) for name in ['playwright', 'playwright-core']}
    require(installed == lock.get('npm_package_files_sha256'), 'Installed package inventory mismatch')


def run(lock_path, export, bundle, deps, output, receipt_path):
    docker = Docker()
    require(os.environ.get('GITHUB_ACTIONS') == 'true' and os.environ.get('RUNNER_ENVIRONMENT') == 'github-hosted', 'Only fresh GitHub-hosted runner')
    require('VERSION_ID="24.04"' in Path('/etc/os-release').read_text() and 'ID=ubuntu' in Path('/etc/os-release').read_text(), 'Ubuntu 24.04 required')
    require(not receipt_path.exists() and not output.exists(), 'Fresh receipt/artifact paths required')
    lock = read_json(lock_path)
    validate_inputs(lock, export, bundle, deps)
    require(available_memory() >= 4 * GIB, 'Need 4 GiB host available')
    require(not docker.call(['container', 'ls', '-aq']).stdout.strip(), 'Fresh dedicated job must have no containers')
    image = json.loads(docker.call(['image', 'inspect', lock['image']]).stdout)[0]
    require(lock['image'].split('@')[0].split(':')[0] + '@' + lock['image'].split('@')[1] in image['RepoDigests'], 'Image registry digest not present')
    require(image.get('Architecture') == 'amd64', 'Expected amd64 image')
    output.mkdir(mode=0o777); output.chmod(0o777)  # Only this fresh artifact dir is writable by pwuser.
    receipt_path.parent.mkdir(parents=True, exist_ok=True)
    owner = secrets.token_hex(16)
    receipt = {'owner': owner, 'name': 'rts-web-qa-' + owner, 'lock_sha256': sha(lock_path).hex(),
               'build': lock['build'], 'source_commit': lock['source_commit'], 'image': lock['image'],
               'files_sha256': lock['files_sha256'], 'qa_files_sha256': lock['qa_files_sha256'],
               'npm_lock_sha256': lock['npm_lock_sha256'], 'cleanup_verified': False, 'samples': [], 'passed': False}
    persist = lambda: save(receipt_path, receipt)
    persist()
    def interrupted(signum, frame):
        raise RuntimeError('Interrupted by signal ' + str(signum))
    signal.signal(signal.SIGTERM, interrupted); signal.signal(signal.SIGINT, interrupted)
    start = time.monotonic()
    host_baseline = host_oom()
    try:
        args = create_args(lock['image'], owner)[1:-1]
        args += ['--ipc=private', '--user=pwuser', '--workdir=/qa',
                 '--mount', f'type=bind,src={export},dst=/export,readonly',
                 '--mount', f'type=bind,src={bundle},dst=/qa,readonly',
                 '--mount', f'type=bind,src={deps / "node_modules/playwright"},dst=/deps/node_modules/playwright,readonly',
                 '--mount', f'type=bind,src={deps / "node_modules/playwright-core"},dst=/deps/node_modules/playwright-core,readonly',
                 '--mount', f'type=bind,src={output},dst=/artifacts',
                 lock['image'], 'node', '/qa/container_main.mjs']
        # Persist name+owner before create; cleanup resolves timeout/uncertain create.
        result = docker.call(args, timeout=8)
        receipt['container_id'] = resolve_creation(docker, receipt['name'], owner, result.stdout.strip())
        require(receipt['container_id'], 'Create returned no resolvable owned container')
        persist()
        cid = receipt['container_id']
        record = docker.inspect(cid); check_owner(cid, owner, record)
        verify_effective(record, image['Id'])
        require(available_memory() >= 4 * GIB and host_oom() == host_baseline, 'Admission changed before start')
        docker.call(['start', cid])
        record = docker.inspect(cid); check_owner(cid, owner, record)
        require(record['State']['Running'], 'Container exited before cgroup admission')
        group = cgroup_for(record['State']['Pid'])
        first = sample(group)
        require(first['events'].get('oom', 0) == 0 and first['events'].get('oom_kill', 0) == 0, 'Container OOM at startup')
        require(host_oom() == host_baseline, 'Host OOM during startup')
        # Browser/server wait for this file: limits + baseline are verified first.
        (output / 'admitted.json').write_text(json.dumps({'owner': owner, 'remaining_seconds': max(0, 120 - (time.monotonic() - start))}))
        while True:
            elapsed = time.monotonic() - start
            # Reserve five seconds for own stop/kill; no inspection may postpone
            # pressure sampling for multiple seconds. Slow Docker fails closed.
            require(elapsed < 115, 'Runtime cleanup reserve reached')
            record = docker.inspect(cid, timeout=0.4); check_owner(cid, owner, record)
            if not record['State']['Running']:
                receipt['exit_code'] = record['State']['ExitCode']
                require(not record['State'].get('OOMKilled') and host_oom() == host_baseline, 'OOM on exit')
                require(record['State']['ExitCode'] == 0, 'Container QA exited nonzero')
                evidence = read_json(output / 'browser-evidence.json')
                require(evidence.get('basicSmokePassed') is True, 'Smoke evidence absent/failed')
                receipt['passed'] = True
                break
            try:
                values = sample(group)
            except FileNotFoundError:
                # Docker may remove the cgroup between inspect and sample.
                record = docker.inspect(cid, timeout=0.4)
                check_owner(cid, owner, record)
                require(not record['State']['Running'], 'Monitoring vanished while running')
                continue
            receipt['samples'].append({'elapsed': elapsed, **values})
            reason = abort_reason(elapsed, values['host_available'],
                                  (host_baseline, 0, 0), (values['host_oom_kill'], values['events'].get('oom', 0), values['events'].get('oom_kill', 0)), record['State'])
            require(reason is None, reason or '')
            persist()
            time.sleep(0.5)
    except BaseException as error:
        receipt['failure'] = str(error)[:3000]
        receipt['passed'] = False
    finally:
        # Do not let a second ordinary interrupt skip owned cleanup. GitHub always
        # cleanup step is required for SIGKILL/runner termination contingency.
        signal.signal(signal.SIGTERM, signal.SIG_IGN); signal.signal(signal.SIGINT, signal.SIG_IGN)
        receipt['elapsed_seconds'] = time.monotonic() - start
        try:
            cid = resolve_creation(docker, receipt['name'], owner, receipt.get('container_id'))
            if cid:
                receipt['container_id'] = cid
                logs = docker.call(['logs', '--tail=150', cid], check=False)
                (output / 'container.log').write_text((logs.stdout + logs.stderr)[-100000:])
        except BaseException as error:
            receipt['log_error'] = str(error)[:1000]
        try:
            cleanup(docker, receipt, persist)
        except BaseException as error:
            receipt['cleanup_error'] = str(error)[:2000]
            receipt['passed'] = False
        try:
            require(sha(lock_path).hex() == receipt['lock_sha256'], 'Reviewed lock changed during run')
            validate_inputs(lock, export, bundle, deps)
            receipt['post_run_inputs_unchanged'] = True
        except BaseException as error:
            receipt['post_run_integrity_error'] = str(error)[:2000]
            receipt['passed'] = False
        persist()
    return 0 if receipt['passed'] and receipt['cleanup_verified'] else 1


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--cleanup', type=Path)
    for name in ['lock', 'export', 'bundle', 'deps', 'output', 'receipt']:
        parser.add_argument('--' + name, type=Path)
    args = parser.parse_args()
    if args.cleanup:
        receipt = read_json(args.cleanup)
        if receipt.get('cleanup_verified') is True:
            return 0
        cleanup(Docker(), receipt, lambda: save(args.cleanup, receipt))
        return 0
    require(all(getattr(args, x) for x in ['lock', 'export', 'bundle', 'deps', 'output', 'receipt']), 'All paths required')
    paths = [getattr(args, x).resolve() for x in ['lock', 'export', 'bundle', 'deps', 'output', 'receipt']]
    require(all(',' not in str(x) for x in paths), 'Comma in bind path')
    return run(*paths)


if __name__ == '__main__':
    raise SystemExit(main())

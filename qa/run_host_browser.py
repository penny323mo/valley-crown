#!/usr/bin/env python3
"""Explicit invocation only: own a transient systemd service, not a host session.

Prepared file-only. No service/browser/probe runs on import. No system settings
are modified. sudo is used only for this exact transient unit's bounded lifecycle.
"""
import argparse
import grp
import json
import os
from pathlib import Path
import pwd
import re
import secrets
import signal
import subprocess
import time
from guard_contract import require, GIB
from run_browser import sha, read_json, save, available_memory, host_oom, sample, validate_inputs


def call(argv, timeout=4, check=True):
    result = subprocess.run(argv, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, timeout=timeout, text=True,
                            env={'PATH': '/usr/bin:/bin', 'HOME': '/tmp', 'LANG': 'C.UTF-8'})
    require(len(result.stdout) <= 2*1024**2 and len(result.stderr) <= 65536, 'Oversized command response')
    require(not check or result.returncode == 0, 'Command failed: ' + result.stderr[:1800])
    return result


class Systemd:
    def show(self, name, timeout=4):
        result = call(['/usr/bin/systemctl', 'show', name, '--no-pager',
                       '--property=Id,Description,LoadState,ActiveState,SubState,MainPID,ControlGroup,User,Group,Result,ExecMainCode,ExecMainStatus,MemoryMax,MemorySwapMax,TasksMax,KillMode,RuntimeMaxUSec,TimeoutStopUSec'], timeout=timeout, check=False)
        record = dict(line.split('=', 1) for line in result.stdout.splitlines() if '=' in line)
        require(result.returncode == 0 or (result.returncode == 1 and record.get('LoadState') == 'not-found'), 'Cannot inspect exact unit: ' + result.stderr[:1000])
        return record
    def create(self, args):
        return call(['/usr/bin/sudo', '-n', '/usr/bin/systemd-run', *args], timeout=8)
    def stop(self, name):
        return call(['/usr/bin/sudo', '-n', '/usr/bin/systemctl', 'stop', name], timeout=7)
    def kill(self, name):
        return call(['/usr/bin/sudo', '-n', '/usr/bin/systemctl', 'kill', '--kill-whom=all', '--signal=KILL', name])
    def reset(self, name):
        return call(['/usr/bin/sudo', '-n', '/usr/bin/systemctl', 'reset-failed', name])


def owner_check(record, receipt):
    require(re.fullmatch(r'rts-webqa-[0-9a-f]{32}\.service', receipt['unit']), 'Invalid exact unit name')
    require(record.get('Id') == receipt['unit'], 'Unit identity mismatch')
    require(record.get('Description') == 'rts-webqa:' + receipt['owner'], 'Unit owner mismatch')


def owned_group(record, receipt, verify_limits=True):
    owner_check(record, receipt)
    expected = '/system.slice/' + receipt['unit']
    require(record.get('ControlGroup') == expected, 'Unexpected owned cgroup')
    group = Path('/sys/fs/cgroup') / expected.lstrip('/')
    require(group.resolve() == group, 'Owned cgroup symlink mismatch')
    if verify_limits:
        require(int((group/'memory.max').read_text()) == 3*GIB, 'Memory limit missing')
        require(int((group/'memory.swap.max').read_text()) == 0, 'Swap limit missing')
        require(int((group/'pids.max').read_text()) == 256, 'PID limit missing')
        quota, period = (group/'cpu.max').read_text().split()
        require(int(quota) == 2*int(period), 'CPU quota missing')
    return group


def cgroup_empty(group):
    if not group.exists():
        return True
    entries = [group, *[x for x in group.rglob('*') if x.is_dir()]]
    return all(not (entry/'cgroup.procs').read_text().strip() for entry in entries)


def cleanup(systemd, receipt, persist, empty=cgroup_empty):
    name = receipt['unit']
    record = systemd.show(name)
    if record.get('LoadState') == 'not-found':
        # Exact canonical path still must have no descendants after uncertain create.
        require(re.fullmatch(r'rts-webqa-[0-9a-f]{32}\.service', name), 'Unsafe cleanup name')
        require(empty(Path('/sys/fs/cgroup/system.slice')/name), 'Unloaded unit has descendants')
        receipt['cleanup_verified'] = True; persist(); return
    owner_check(record, receipt)
    group = Path('/sys/fs/cgroup/system.slice') / name
    receipt['final_unit_before_stop'] = record
    try:
        systemd.stop(name)
    except (RuntimeError, ValueError, subprocess.TimeoutExpired):
        receipt.setdefault('cleanup_warnings', []).append('Stop failed/uncertain; reinspecting before kill')
    record = systemd.show(name)
    if record.get('LoadState') != 'not-found':
        owner_check(record, receipt)
        if record.get('ActiveState') not in ('inactive', 'failed') or not empty(group):
            systemd.kill(name)
            record = systemd.show(name)
            if record.get('LoadState') != 'not-found': owner_check(record, receipt)
        require(empty(group), 'Owned descendants remain')
        if record.get('LoadState') != 'not-found' and record.get('ActiveState') == 'failed':
            owner_check(record, receipt)
            systemd.reset(name)
    require(empty(group), 'Cleanup cgroup not empty')
    final = systemd.show(name)
    if final.get('LoadState') != 'not-found':
        owner_check(final, receipt)
        require(final.get('ActiveState') in ('inactive', 'failed') and final.get('MainPID') == '0', 'Unit not stopped')
    receipt['final_unit_after_stop'] = final
    receipt['cleanup_verified'] = True
    persist()


def verify_unit(record, receipt, user, group):
    owner_check(record, receipt)
    require(record.get('User') == user and record.get('Group') == group, 'Browser service must be current nonroot runner')
    require(record.get('MemoryMax') == str(3*GIB) and record.get('MemorySwapMax') == '0', 'Effective systemd memory limit mismatch')
    require(record.get('TasksMax') == '256' and record.get('KillMode') == 'control-group', 'Unit descendant scope missing')
    require(record.get('RuntimeMaxUSec') in ('1min 40s', '100s') and record.get('TimeoutStopUSec') == '5s', 'Unit deadline mismatch')


def verify_chrome(lock):
    require(lock.get('chrome_path') == '/opt/google/chrome/chrome', 'Only stock official Chrome path accepted')
    chrome = Path(lock['chrome_path'])
    require(chrome.is_file() and not chrome.is_symlink(), 'Stock Chrome executable missing')
    require(sha(chrome).hex() == lock.get('chrome_sha256'), 'Recorded stock Chrome changed')
    require(isinstance(lock.get('chrome_version'), str) and bool(lock['chrome_version']), 'Recorded stock Chrome version missing')
    node = Path(lock.get('node_path', ''))
    require(node.is_absolute() and node.is_file() and not node.is_symlink(), 'Exact regular Node executable required')
    require(str(node) == '/usr/bin/node' or str(node).startswith('/opt/hostedtoolcache/node/') or (str(node) == '/usr/local/bin/node' and lock.get('node_sha256') == '94efd062ed066c1a0b332e18249859c905e920eeada5df55d24c99b919629a90'), 'Unexpected stock Node source')
    require(sha(node).hex() == lock.get('node_sha256'), 'Recorded Node executable changed')


def run(lock_path, export, bundle, deps, output, receipt_path):
    require(os.environ.get('GITHUB_ACTIONS') == 'true' and os.environ.get('RUNNER_ENVIRONMENT') == 'github-hosted', 'Fresh GitHub-hosted runner only')
    os_release = dict(line.split('=', 1) for line in Path('/etc/os-release').read_text().splitlines() if '=' in line)
    require(os_release.get('ID', '').strip('"') == 'ubuntu' and os_release.get('VERSION_ID', '').strip('"') == '24.04', 'Ubuntu 24.04 required')
    require(os.getuid() != 0, 'Supervisor must be ordinary runner')
    user, group = pwd.getpwuid(os.getuid()).pw_name, grp.getgrgid(os.getgid()).gr_name
    require(user == 'runner', 'Expected fresh hosted runner identity')
    require(not output.exists() and not receipt_path.exists(), 'Fresh output/receipt paths required')
    lock = read_json(lock_path)
    require(lock.get('profile') in ('desktop', 'portrait'), 'One reviewed profile required')
    validate_inputs(lock, export, bundle, deps, require_image=False); verify_chrome(lock)
    require(available_memory() >= 4*GIB, 'Need 4 GiB host available')
    output.mkdir(); (output/'home').mkdir(); (output/'tmp').mkdir()
    receipt_path.parent.mkdir(parents=True, exist_ok=True)
    owner = secrets.token_hex(16)
    receipt = {'unit': 'rts-webqa-' + owner + '.service', 'owner': owner, 'passed': False,
               'cleanup_verified': False, 'lock_sha256': sha(lock_path).hex(), 'samples': [],
               'build': lock['build'], 'source_commit': lock['source_commit'], 'files_sha256': lock['files_sha256'],
               'chrome_path': lock['chrome_path'], 'chrome_sha256': lock['chrome_sha256'], 'chrome_version': lock['chrome_version']}
    receipt['node_path'], receipt['node_sha256'] = lock['node_path'], lock['node_sha256']
    receipt['profile'] = lock['profile']
    receipt['limits'] = {'systemd_runtime_seconds':100, 'node_runtime_seconds':90,
                         'supervisor_cleanup_seconds':105, 'stop_timeout_seconds':5,
                         'memory_bytes':3*GIB, 'swap_bytes':0, 'tasks':256, 'cpu_percent':200}
    persist = lambda: save(receipt_path, receipt)
    persist()
    systemd = Systemd()
    start, baseline = time.monotonic(), host_oom()
    def interrupted(signum, frame): raise RuntimeError('Interrupted: ' + str(signum))
    signal.signal(signal.SIGTERM, interrupted); signal.signal(signal.SIGINT, interrupted)
    try:
        require(systemd.show(receipt['unit']).get('LoadState') == 'not-found', 'Unit name unexpectedly exists')
        args = ['--quiet', '--unit=' + receipt['unit'], '--description=rts-webqa:' + owner,
                '--service-type=exec', '--uid=' + user, '--gid=' + group,
                '--working-directory=' + str(bundle), '--property=RemainAfterExit=yes',
                '--property=MemoryMax=3G', '--property=MemorySwapMax=0', '--property=TasksMax=256',
                '--property=CPUQuota=200%', '--property=RuntimeMaxSec=100', '--property=TimeoutStopSec=5',
                '--property=KillMode=control-group', '--property=OOMPolicy=stop',
                '/usr/bin/env', '-i', 'PATH=/usr/bin:/bin', 'LANG=C.UTF-8', 'HOME=' + str(output/'home'),
                'TMPDIR=' + str(output/'tmp'), lock['node_path'], str(bundle/'host_main.mjs'),
                str(export), str(output), str(deps), lock['chrome_path'], lock['profile']]
        # Uncertain creation is not retried; finally resolves exact owner unit.
        systemd.create(args)
        record = systemd.show(receipt['unit'])
        verify_unit(record, receipt, user, group)
        cg = owned_group(record, receipt)
        first = sample(cg)
        require(first['events'].get('oom', 0) == 0 and first['events'].get('oom_kill', 0) == 0 and host_oom() == baseline, 'OOM before admission')
        require(available_memory() >= 4*GIB, 'Admission reserve changed')
        (output/'admitted.json').write_text(json.dumps({'remaining_seconds': 90 - (time.monotonic()-start)}))
        while True:
            elapsed = time.monotonic()-start
            require(elapsed < 105, 'Runtime cleanup reserve reached')
            record = systemd.show(receipt['unit'], timeout=0.4)
            owner_check(record, receipt)
            done = record.get('SubState') in ('exited', 'dead', 'failed') or record.get('ActiveState') in ('inactive', 'failed')
            if done:
                receipt['exit_unit'] = record
                require(record.get('Result') == 'success' and record.get('ExecMainCode') == '1' and record.get('ExecMainStatus') == '0', 'Browser unit failed')
                require(host_oom() == baseline, 'Host OOM on exit')
                require(cgroup_empty(cg), 'Browser descendants remain after node exit')
                if cg.exists():
                    last = sample(cg)
                    require(last['events'].get('oom', 0) == 0 and last['events'].get('oom_kill', 0) == 0, 'Owned OOM on exit')
                evidence = read_json(output/'browser-evidence.json')
                require(evidence.get('basicSmokePassed') is True and evidence.get('phase') == 'completed' and evidence.get('profile') == lock['profile'], 'Selected profile smoke failed/missing')
                receipt['passed'] = True
                break
            try:
                values = sample(cg)
            except FileNotFoundError:
                exact = systemd.show(receipt['unit'], timeout=0.4); owner_check(exact, receipt)
                require(exact.get('SubState') in ('exited', 'dead', 'failed'), 'Owned monitoring vanished while live')
                continue
            receipt['samples'].append({'elapsed': elapsed, **values})
            require(values['host_available'] >= GIB, 'Host reserve below 1 GiB')
            require(values['host_oom_kill'] == baseline and values['events'].get('oom', 0) == 0 and values['events'].get('oom_kill', 0) == 0, 'OOM changed')
            persist(); time.sleep(0.5)
    except BaseException as error:
        receipt['failure'] = str(error)[:3000]; receipt['passed'] = False
    finally:
        signal.signal(signal.SIGTERM, signal.SIG_IGN); signal.signal(signal.SIGINT, signal.SIG_IGN)
        receipt['elapsed_seconds'] = time.monotonic()-start
        try:
            cleanup(systemd, receipt, persist)
            receipt['cleanup_finished_seconds'] = time.monotonic()-start
        except BaseException as error:
            receipt['cleanup_error'] = str(error)[:2000]; receipt['passed'] = False
        try:
            # Never spend cleanup reserve reading logs while children may live.
            # A now-unloaded transient unit still has journal records by exact name.
            if receipt.get('cleanup_verified') and receipt.get('final_unit_before_stop'):
                owner_check(receipt['final_unit_before_stop'], receipt)
                logs = call(['/usr/bin/sudo', '-n', '/usr/bin/journalctl', '--unit=' + receipt['unit'], '--no-pager', '--lines=150'], check=False)
                (output/'host-unit.log').write_text((logs.stdout + logs.stderr)[-100000:])
        except BaseException as error:
            receipt['log_error'] = str(error)[:1000]
        try:
            require(sha(lock_path).hex() == receipt['lock_sha256'], 'Lock changed')
            validate_inputs(lock, export, bundle, deps, require_image=False); verify_chrome(lock)
            require(host_oom() == baseline, 'Host OOM changed during final cleanup')
            receipt['host_oom_unchanged_after_cleanup'] = True
            receipt['post_run_inputs_unchanged'] = True
        except BaseException as error:
            receipt['integrity_error'] = str(error)[:2000]; receipt['passed'] = False
        persist()
    return 0 if receipt['passed'] and receipt['cleanup_verified'] else 1


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--cleanup', type=Path)
    for key in ('lock', 'export', 'bundle', 'deps', 'output', 'receipt'): parser.add_argument('--'+key, type=Path)
    args = parser.parse_args()
    if args.cleanup:
        receipt = read_json(args.cleanup)
        cleanup(Systemd(), receipt, lambda: save(args.cleanup, receipt))
        return 0
    require(all(getattr(args, key) for key in ('lock', 'export', 'bundle', 'deps', 'output', 'receipt')), 'All paths required')
    return run(*(getattr(args, key).resolve() for key in ('lock', 'export', 'bundle', 'deps', 'output', 'receipt')))


if __name__ == '__main__': raise SystemExit(main())

#!/usr/bin/env python3
"""DRAFT: own, bound and reap Xvfb + native Godot without shell wrappers.

This helper deliberately refuses execution until a reviewed lock enables it.
It is not a browser tool and must never be used as a browser-policy workaround.
"""
from pathlib import Path
import argparse
import datetime
import hashlib
import json
import os
import re
import secrets
import select
import signal
import socket
import stat
import struct
import subprocess
import time
from types import SimpleNamespace
import xvfb_startup
import guarded_manifest_ci

NATIVE_RENDER_ENV = {'DRI_PRIME': '0', 'LIBGL_ALWAYS_SOFTWARE': '1', 'GALLIUM_DRIVER': 'llvmpipe'}


def require(value, message):
    if not value:
        raise RuntimeError(message)


def digest(path):
    with Path(path).open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def regular(path):
    path = Path(path)
    require(path.is_file() and not path.is_symlink(), 'Nonregular input: ' + str(path))
    return path


def tree(root, exclude_cache=False):
    result = {}
    for path in sorted(root.rglob('*')):
        rel = path.relative_to(root)
        if exclude_cache and rel.parts[0] == '.godot':
            continue
        require(not path.is_symlink(), 'Symlink in input tree: ' + str(rel))
        if path.is_file():
            result[rel.as_posix()] = digest(path)
        else:
            require(path.is_dir(), 'Special file in input tree')
    return result


UID_ALPHABET = b'abcdefghijklmnopqrstuvwxy012345678'
SENSITIVE_TEXT = re.compile(r'(?:gh[pousr]_[A-Za-z0-9]{36,255}|github_pat_[A-Za-z0-9_]{40,255}|AKIA[0-9A-Z]{16}|sk-(?:proj-|svcacct-)?[A-Za-z0-9_-]{40,255}|xox[baprs]-[A-Za-z0-9-]{20,255}|-----BEGIN .*PRIVATE KEY-----|(?i:authorization:|password\s*[=:]|access_token\s*[=:]|secret\s*[=:]))')


def safe_diagnostic_text(value):
    """Bound, redact and flatten diagnostics; never dump environment/file contents."""
    value = str(value)
    if SENSITIVE_TEXT.search(value):
        return '[redacted-sensitive-pattern]'
    value = re.sub(r'/(?:home/agent|workspace/scratch|workspace/shared|agent_notes|user_notes)/[^\s]*', '[private-path]', value)
    value = re.sub(r'\x1b\[[0-?]*[ -/]*[@-~]', '', value)
    return ''.join(char if char.isprintable() else ' ' for char in value)[:240]


def inventory_differences(actual, original, generated):
    original_names, actual_names, generated_names = set(original), set(actual), set(generated)
    groups = {
        'missing_original': sorted(original_names - actual_names),
        'changed_original': sorted(name for name in original_names & actual_names if actual[name] != original[name]),
        'missing_generated_uid': sorted(generated_names - actual_names),
        'unexpected_files': sorted(actual_names - original_names - generated_names),
    }
    return {key: {'count': len(names), 'paths': [safe_diagnostic_text(name) for name in names[:32]],
                  'truncated': len(names) > 32} for key, names in groups.items()}


def parse_generated_uid(data):
    # Godot 4.6.3 ResourceUID::id_to_text: base 34, no z/9, canonical 63-bit ID.
    require(re.fullmatch(rb'uid://[a-y0-8]{1,13}\n', data) is not None, 'Malformed generated UID sidecar')
    digits = data[6:-1]
    require(len(digits) == 1 or digits[0] != ord('a'), 'Noncanonical generated UID sidecar')
    number = 0
    for digit in digits:
        number = number * 34 + UID_ALPHABET.index(digit)
    require(number <= 0x7fffffffffffffff, 'Generated UID exceeds Godot signed ID range')
    return number


def source_inventory(project, lock, expected_generated=None):
    """Original archive hashes stay mandatory; only explicit generated UIDs exist."""
    original = lock['project_files']
    allowed = lock['allowed_generated_uid_files']
    expected = sorted(name + '.uid' for name in original if name.endswith('.gd') and name + '.uid' not in original)
    if 'assets/mature/shaders/building_damage_soot.gdshader' in original and 'assets/mature/shaders/building_damage_soot.gdshader.uid' not in original: expected = sorted(expected + ['assets/mature/shaders/building_damage_soot.gdshader.uid'])
    require(type(allowed) is list and allowed == expected, 'Generated UID allowlist differs from exact frozen script set')
    actual = tree(project, exclude_cache=True)
    differences = inventory_differences(actual, original, allowed)
    if any(row['count'] for row in differences.values()):
        print('NATIVE_INVENTORY_FAILURE ' + json.dumps(differences, sort_keys=True), flush=True)
        raise RuntimeError('Frozen source/explicit generated UID inventory mismatch')
    ids = set()
    original_uid_contents = {(project / name).read_bytes() for name in original if name.endswith('.uid')}
    for name in allowed:
        try:
            path = regular(project / name)
            require(path.stat().st_size <= 20, 'Oversize generated UID sidecar')
            data = path.read_bytes()
            number = parse_generated_uid(data)
            require(number not in ids and data not in original_uid_contents, 'Duplicate generated UID sidecar')
        except Exception as exc:
            print('NATIVE_UID_FAILURE ' + json.dumps({'path': safe_diagnostic_text(name),
                  'reason': safe_diagnostic_text(exc)}, sort_keys=True), flush=True)
            raise
        ids.add(number)
    generated = {name: actual[name] for name in allowed}
    if expected_generated is not None and generated != expected_generated:
        changed = sorted(name for name in set(generated) | set(expected_generated) if generated.get(name) != expected_generated.get(name))
        print('NATIVE_UID_DRIFT ' + json.dumps({'count': len(changed), 'paths': changed[:32]}, sort_keys=True), flush=True)
        raise RuntimeError('Generated UID hashes changed after import binding')
    return actual, generated


def emit_result_diagnostics(out, receipt):
    summary = {key: receipt.get(key) for key in ('passed', 'cleanup_complete', 'capture_completed', 'seconds')}
    summary['children'] = {name: {key: info.get(key) for key in ('complete', 'exit', 'signals')}
                           for name, info in receipt.get('cleanup', {}).items()}
    summary['unexpected_descendants'] = receipt.get('unexpected_descendants', [])[:16]
    summary['observed_descendant_cleanup'] = receipt.get('observed_descendant_cleanup', [])[:16]
    summary['startup'] = receipt.get('startup', {})
    summary['renderer_configuration'] = receipt.get('renderer_configuration', {})
    for key in ('error', 'final_error'):
        if receipt.get(key):
            summary[key] = {name: safe_diagnostic_text(value) for name, value in receipt[key].items()}
    # Only diagnostic lines from owned child logs, never entire logs or private dirs.
    errors = []
    for name in ('godot', 'xvfb'):
        path = out / (name + '.log')
        if path.is_file() and not path.is_symlink():
            with path.open('rb') as stream:
                prefix = stream.read(65536).decode('utf-8', errors='replace')
            for line in prefix.splitlines():
                if re.search(r'(?i)(script error:|parse error:|error:|fatal:|at:.*(?:res://|\.gd:))', line):
                    errors.append({'process': name, 'line': safe_diagnostic_text(line)})
                    if len(errors) >= 12:
                        break
        if len(errors) >= 12:
            break
    summary['bounded_child_errors'] = errors
    print('NATIVE_RESULT ' + json.dumps(summary, sort_keys=True), flush=True)


def metrics():
    mem = dict((line.split(':')[0], int(line.split()[1])) for line in Path('/proc/meminfo').read_text().splitlines())
    vm = dict((line.split()[0], int(line.split()[1])) for line in Path('/proc/vmstat').read_text().splitlines())
    return {'available_kib': mem['MemAvailable'], 'oom_kill': vm['oom_kill']}


def cache_inputs(project):
    cache = tree(project / '.godot/imported')
    result = {'.godot/imported/' + key: value for key, value in cache.items()}
    for name in ('uid_cache.bin', 'global_script_class_cache.cfg'):
        path = project / '.godot' / name
        if path.exists():
            result['.godot/' + name] = digest(regular(path))
    return result


def process_metrics(child):
    fields = dict(line.split(':', 1) for line in Path(f'/proc/{child.pid}/status').read_text().splitlines() if ':' in line)
    values = {key: int(fields[key].split()[0]) for key in ('VmRSS', 'VmHWM', 'Threads')}
    require(all(value >= 0 for value in values.values()), 'Negative process telemetry')
    # Only threads are expected. No helper process may escape direct ownership.
    children = []
    for task in Path(f'/proc/{child.pid}/task').iterdir():
        try:
            children.extend((task / 'children').read_text().split())
        except FileNotFoundError:
            if task.exists():
                raise
    values['child_pids'] = sorted(set(children))
    return values


def process_identity(pid):
    """Read only bounded identity fields. Never cmdline, environment or full exe path."""
    require(type(pid) is int and pid > 0, 'Invalid observed process ID')
    proc = Path('/proc') / str(pid)
    raw = (proc / 'stat').read_text()
    close = raw.rfind(')'); opened = raw.find('(')
    require(opened > 0 and close > opened, 'Malformed process stat')
    fields = raw[close + 2:].split()
    require(len(fields) >= 20 and int(raw[:opened].strip()) == pid, 'Incomplete process identity')
    status = dict(line.split(':', 1) for line in (proc / 'status').read_text().splitlines() if ':' in line)
    tgid = int(status['Tgid'].strip())
    require(tgid == pid, 'Observed identifier is a thread, not a subprocess')
    executable = Path(os.readlink(proc / 'exe')).name
    return {'pid': pid, 'ppid': int(fields[1]), 'tgid': tgid, 'starttime_ticks': int(fields[19]),
            'comm': safe_diagnostic_text(raw[opened + 1:close]),
            'executable_basename': safe_diagnostic_text(executable)}


def same_lifetime(first, second):
    return all(first[key] == second[key] for key in ('pid', 'tgid', 'starttime_ticks'))


def observe_descendants(parent_name, parent, pids, tracked):
    """Capture observed descendants and pidfds only after ancestry/lifetime checks.

    Unexpected children remain fatal. This is diagnostics and cleanup, NOT an
    executable allowlist. A bounded snapshot cannot prove no unseen forks escaped.
    """
    evidence = []
    try:
        require(parent.poll() is None, 'Owned parent already exited')
        owner = process_identity(parent.pid)
    except Exception as exc:
        return [{'parent': parent_name, 'parent_pid': parent.pid, 'pids': pids[:16],
                 'status': 'parent_identity_unavailable', 'error_type': type(exc).__name__}]
    queue = [(owner, int(pid), 1) for pid in pids[:16]]
    seen = set()
    while queue and len(evidence) < 16:
        ancestor, pid, depth = queue.pop(0)
        if pid in seen:
            continue
        seen.add(pid)
        row = {'parent': parent_name, 'parent_pid': ancestor['pid'], 'pid': pid, 'depth': depth}
        fd = None
        try:
            first = process_identity(pid)
            row['identity'] = first  # Preserve observed identity even if it exits before pidfd open.
            require(first['ppid'] == ancestor['pid'], 'Observed process no longer has the claimed parent')
            require(same_lifetime(process_identity(ancestor['pid']), ancestor), 'Ancestor lifetime changed')
            fd = os.pidfd_open(pid, 0)
            second = process_identity(pid)
            require(same_lifetime(first, second) and second['ppid'] == ancestor['pid'], 'Process identity changed while binding pidfd')
            # An exited pidfd must never be associated with a newly reused numeric PID.
            require(not select.select([fd], [], [], 0)[0], 'Observed process exited while binding pidfd')
            tracked.append({'fd': fd, 'identity': second, 'parent': parent_name})
            fd = None  # Ownership transferred; always closed by cleanup.
            row['status'] = 'pidfd_bound'
            if depth < 3:
                grandchildren = set()
                for task in (Path('/proc') / str(pid) / 'task').iterdir():
                    try:
                        grandchildren.update((task / 'children').read_text().split())
                    except FileNotFoundError:
                        continue
                for descendant in sorted(grandchildren)[:16]:
                    queue.append((second, int(descendant), depth + 1))
        except Exception as exc:
            row['status'] = 'identity_or_binding_incomplete'
            row['error_type'] = type(exc).__name__
        finally:
            if fd is not None:
                try:
                    os.close(fd)
                    row['pidfd_closed'] = True
                except Exception as exc:
                    # A failed close must not discard the known child/identity.
                    # Do not retry a numeric fd whose close outcome is uncertain.
                    row['pidfd_closed'] = False
                    row['pidfd_close_error_type'] = type(exc).__name__
        evidence.append(row)
    if queue or len(pids) > 16:
        evidence.append({'parent': parent_name, 'status': 'descendant_snapshot_truncated'})
    return evidence


def cleanup_observed_descendant(tracked):
    """Signal only the bound pidfd, after rechecking numeric PID/start time."""
    fd, identity = tracked['fd'], tracked['identity']
    result = {'pid': identity['pid'], 'starttime_ticks': identity['starttime_ticks'],
              'parent': tracked['parent'], 'exited': False, 'signals': []}
    try:
        if select.select([fd], [], [], 0)[0]:
            result['exited'] = True
            result['status'] = 'exited_after_owned_parent_cleanup'
        else:
            current = process_identity(identity['pid'])
            require(same_lifetime(identity, current), 'Observed descendant PID/start time changed; do not signal')
            result['cleanup_identity'] = current
            for sig, label in ((signal.SIGTERM, 'SIGTERM'), (signal.SIGKILL, 'SIGKILL')):
                result['signals'].append(label)
                try:
                    signal.pidfd_send_signal(fd, sig, None, 0)
                except ProcessLookupError:
                    pass  # Exit is still confirmed only by the same pidfd becoming ready.
                if select.select([fd], [], [], 1)[0]:
                    result['exited'] = True
                    result['status'] = 'pidfd_confirmed_exit'
                    break
            if not result['exited']:
                result['status'] = 'exit_unconfirmed'
    except Exception as exc:
        result['status'] = 'cleanup_unconfirmed'
        result['error_type'] = type(exc).__name__
    finally:
        try:
            os.close(fd)
            result['pidfd_closed'] = True
        except OSError:
            result['pidfd_closed'] = False
    return result


def private_auth(path, display):
    # Local, ephemeral authentication. Do not write the cookie into logs/receipts.
    def field(value):
        return struct.pack('>H', len(value)) + value
    cookie = secrets.token_bytes(16)
    value = struct.pack('>H', 256) + field(socket.gethostname().encode())
    value += field(str(display).encode()) + field(b'MIT-MAGIC-COOKIE-1') + field(cookie)
    with path.open('xb') as stream:
        os.chmod(path, 0o600)
        stream.write(value)


def clean_environment(private):
    # No GitHub token, cloud credential, inherited display, or browser setting.
    env = {'PATH': '/usr/bin:/bin', 'LANG': 'C.UTF-8', 'TZ': 'UTC',
           'GODOT_SILENCE_ROOT_WARNING': '1', **NATIVE_RENDER_ENV,
           'LP_NUM_THREADS': '2', 'OMP_NUM_THREADS': '1'}
    for key, name in [('HOME', 'home'), ('TMPDIR', 'tmp'), ('XDG_DATA_HOME', 'data'),
                      ('XDG_CONFIG_HOME', 'config'), ('XDG_CACHE_HOME', 'cache'),
                      ('MESA_SHADER_CACHE_DIR', 'mesa')]:
        path = private / name
        path.mkdir(mode=0o700)
        env[key] = str(path)
    return env


REAL_DEPENDENCIES = (subprocess.Popen, metrics, process_metrics, time.monotonic, time.sleep, signal.signal,
                     process_identity, os.pidfd_open, signal.pidfd_send_signal, select.select, os.close,
                     os.pipe2, os.read, xvfb_startup.distribution_inventory, xvfb_startup.StartupTree)


def reap_owned(child):
    """Try every bounded cleanup stage even when TERM/poll/wait raises."""
    info = {'complete': False, 'signals': [], 'errors': []}
    try:
        alive = child.poll() is None
    except BaseException as exc:
        info['errors'].append('poll: ' + repr(exc)); alive = True
    if alive:
        info['signals'].append('SIGTERM')
        try:
            child.terminate()
        except BaseException as exc:
            info['errors'].append('terminate: ' + repr(exc))
        try:
            child.wait(timeout=5)
        except subprocess.TimeoutExpired:
            pass
        except BaseException as exc:
            info['errors'].append('terminate_wait: ' + repr(exc))
        try:
            alive = child.poll() is None
        except BaseException as exc:
            info['errors'].append('poll_after_term: ' + repr(exc)); alive = True
        if alive:
            info['signals'].append('SIGKILL')
            try:
                child.kill()
            except BaseException as exc:
                info['errors'].append('kill: ' + repr(exc))
    try:
        info['exit'] = child.wait(timeout=5); info['complete'] = True
    except BaseException as exc:
        info['errors'].append('final_wait: ' + repr(exc))
    return info



def validate_capture_lock(lock):
    """File-only schema checks shared by preparation, renderer and scanner.

    Identity against actual source, tools, import receipt and outputs remains
    enforced by the existing consumers; this validates their required inputs.
    """
    require(type(lock) is dict, 'Lock must be an object')
    require(lock.get('reviewed_for_execution') is True, 'Draft lock is not approved for execution')
    require(lock.get('native_renderer') == 'linux-x11-mesa-llvmpipe-gl_compatibility', 'Renderer scope differs')
    require(type(lock.get('build')) is str and re.fullmatch(r'vc-[0-9a-f]{12}', lock['build']), 'Invalid build identity')
    for key in ('harness', 'godot', 'supervisor', 'source_archive', 'import_manifest'):
        value = lock.get(key + '_sha256')
        require(type(value) is str and re.fullmatch(r'[0-9a-f]{64}', value), 'Missing/invalid tool hash: ' + key)
    for key in ('project_files', 'support_files'):
        values = lock.get(key)
        require(type(values) is dict and values, 'Missing hash map: ' + key)
        for name, value in values.items():
            require(type(name) is str and name and not Path(name).is_absolute() and '..' not in Path(name).parts,
                    'Invalid bound file path')
            require(type(value) is str and re.fullmatch(r'[0-9a-f]{64}', value), 'Invalid bound file hash')
    for name in ('ci/xvfb_startup.py', 'ci/guarded_manifest_ci.py'):
        require(name in lock['support_files'], 'Missing required support file: ' + name)
    for name in ('scripts/game.gd', 'scripts/rules.gd') + tuple(
            'assets/mature/models/' + kind + '_action.scn' for kind in ('villager','spearman','archer','scout')):
        require(name in lock['project_files'], 'Missing required source file: ' + name)
    uids = lock.get('allowed_generated_uid_files')
    require(type(uids) is list and all(type(n) is str for n in uids) and len(uids) == len(set(uids)), 'Invalid UID list')
    expected = {n + '.uid' for n in lock['project_files'] if n.endswith('.gd') and n + '.uid' not in lock['project_files']}
    shader = 'assets/mature/shaders/building_damage_soot.gdshader'
    if shader in lock['project_files'] and shader + '.uid' not in lock['project_files']:
        expected.add(shader + '.uid')
    require(set(uids) == expected, 'Generated UID scope differs')
    contract = lock.get('capture_contract')
    require(contract in [
        {'mode': 'gameplay', 'kind': 'genuine_native_game_viewport', 'frame_count': 10},
        {'mode': 'rig_studies', 'kind': 'native_controlled_rig_study', 'frame_count': 25},
        {'mode': 'occlusion', 'kind': 'native_controlled_occlusion_fixture', 'frame_count': 6}], 'Unreviewed capture contract')
    return contract


def run(args):
    lock_path = regular(args.lock).resolve()
    lock = json.loads(lock_path.read_text())
    validate_capture_lock(lock)
    require(lock.get('reviewed_for_execution') is True, 'Draft lock is not approved for execution')
    require(os.environ.get('GITHUB_ACTIONS') == 'true' and os.environ.get('RUNNER_ENVIRONMENT') == 'github-hosted',
            'Only an isolated GitHub-hosted runner is within this draft scope')
    require((args.width, args.height) in [(390, 844), (844, 390)], 'Unreviewed viewport')
    contract = lock['capture_contract']
    require(contract in [
        {'mode': 'gameplay', 'kind': 'genuine_native_game_viewport', 'frame_count': 10},
        {'mode': 'rig_studies', 'kind': 'native_controlled_rig_study', 'frame_count': 25},
        {'mode': 'occlusion', 'kind': 'native_controlled_occlusion_fixture', 'frame_count': 6}], 'Unreviewed capture contract')
    require(contract['mode'] != 'rig_studies' or (args.width,args.height) == (844,390), 'Rig study viewport differs')
    require(contract['mode'] != 'occlusion' or (args.width,args.height) == (390,844), 'Occlusion viewport differs')
    project = args.project.resolve()
    out, private = args.output.resolve(), args.private.resolve()
    require(not out.exists() and not private.exists(), 'Output and private directory must be new')
    require(not out.is_relative_to(project) and not private.is_relative_to(project), 'Outputs must be outside source')
    source, generated_uids = source_inventory(project, lock)
    require((project / '.godot/imported').is_dir(), 'A successful fresh guarded import is required first')
    cache = cache_inputs(project)
    require(cache, 'Empty imported cache')
    import_marker = regular(args.import_marker).resolve()
    certificate = json.loads(import_marker.read_text())
    require(certificate['build'] == lock['build'] and certificate['project'] == str(project), 'Import belongs to another source')
    require(certificate['archive_sha256'] == lock['source_archive_sha256'] and
            certificate['engine_sha256'] == lock['godot_sha256'], 'Import input identity differs')
    require(certificate['cache_sha256'] == cache, 'Cache differs from successful guarded import')
    require(certificate['generated_uid_sha256'] == generated_uids, 'Generated UIDs differ from successful guarded import')
    require(certificate['manifest_sha256'] == lock['import_manifest_sha256'] and
            certificate['adapter_sha256'] == lock['support_files']['ci/guarded_manifest_ci.py'], 'Import package/adapter differs')
    import_receipt = regular(certificate['receipt']).resolve()
    import_invocation = regular(certificate['invocation']).resolve()
    require(digest(import_receipt) == certificate['receipt_sha256'] and
            digest(import_invocation) == certificate['invocation_sha256'], 'Import receipt/invocation changed')
    guarded_manifest_ci.guard_receipt(import_receipt, import_invocation)
    inputs = {'lock': lock_path, 'harness': regular(args.harness).resolve(),
              'godot': regular(args.godot).resolve(), 'xvfb': regular(args.xvfb).resolve(),
              'startup': regular(Path(__file__).with_name('xvfb_startup.py')).resolve(),
              'import_adapter': regular(Path(__file__).with_name('guarded_manifest_ci.py')).resolve(),
              'supervisor': Path(__file__).resolve(), 'import_marker': import_marker, 'import_receipt': import_receipt,
              'import_invocation': import_invocation, 'import_log': regular(import_receipt.with_suffix('.log')).resolve()}
    bindings = {key: digest(path) for key, path in inputs.items()}
    for key in ('harness', 'godot', 'supervisor'):
        require(bindings[key] == lock[key + '_sha256'], 'Reviewed helper/tool hash mismatch: ' + key)
    require(bindings['startup'] == lock['support_files']['ci/xvfb_startup.py'], 'Reviewed startup helper hash differs')
    require(bindings['import_adapter'] == lock['support_files']['ci/guarded_manifest_ci.py'], 'Reviewed import adapter hash differs')
    # Distribution-provided Xvfb is recorded, never substituted with a downloaded binary.
    require(str(inputs['xvfb']) == '/usr/bin/Xvfb', 'Expected Ubuntu distribution Xvfb')
    require(lock['native_renderer'] == 'linux-x11-mesa-llvmpipe-gl_compatibility', 'Renderer scope differs')
    distribution = xvfb_startup.distribution_inventory()
    require(distribution['xvfb']['sha256'] == bindings['xvfb'], 'Distribution Xvfb identity differs')
    before = metrics()
    require(before['available_kib'] >= 4 * 1024 * 1024, 'Less than 4 GiB available before launch')
    out.mkdir(parents=True)
    private.mkdir(parents=True, mode=0o700)
    frame_dir = out / 'frames'; frame_dir.mkdir()
    env = clean_environment(private)
    display = next((n for n in range(90, 190) if not Path(f'/tmp/.X{n}-lock').exists()
                    and not Path(f'/tmp/.X11-unix/X{n}').exists()), None)
    require(display is not None, 'No unused private X display; no shared-display fallback')
    auth = private / 'Xauthority'
    env['DISPLAY'] = ':' + str(display); env['XAUTHORITY'] = str(auth)
    started = time.monotonic()
    receipt = {'passed': False, 'scope': 'native_software_rendered_source', 'build': lock['build'],
               'diagnostic_only': lock.get('diagnostic_only') is True,
               'renderer_configuration': {key: env[key] for key in NATIVE_RENDER_ENV},
               'capture_contract': contract,
               'time_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
               'input_sha256': bindings, 'source_file_count': len(source),
               'original_file_count': len(lock['project_files']), 'generated_uid_sha256': generated_uids,
               'cache_files': len(cache), 'samples': [], 'children': {}, 'cleanup': {},
               'unexpected_descendants': [], 'cleanup_complete': False,
               'startup': {'complete': False, 'detected': False, 'helpers': [], 'distribution': distribution,
                           'timeout_seconds': 10, 'helper_limit': 2, 'helper_rss_hwm_kib': 131072, 'helper_threads': 4},
               'test_dependencies': any(actual is not original for actual, original in zip(
                   (subprocess.Popen, metrics, process_metrics, time.monotonic, time.sleep, signal.signal,
                    process_identity, os.pidfd_open, signal.pidfd_send_signal, select.select, os.close,
                    os.pipe2, os.read, xvfb_startup.distribution_inventory, xvfb_startup.StartupTree), REAL_DEPENDENCIES)),
               'system_before': before, 'limits': {'timeout_seconds': 120, 'minimum_available_kib': 1048576,
                   'aggregate_rss_kib': 3145728, 'godot_rss_kib': 2621440, 'xvfb_rss_kib': 524288},
               'fixed_fps': 30, 'expected_framebuffer': [args.width, args.height],
               'not_verified': ['Web', 'Safari', 'physical iPhone', 'mobile GPU', 'FPS', 'touch input', 'visual quality']}
    children = {}
    tracked_descendants = []
    handles = {}
    stopped = False

    def stop_signal(signum, frame):
        nonlocal stopped
        stopped = True

    old_handlers = {}
    ready_fds = set()
    startup_tree = None

    def save():
        (out / 'guard-receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')

    def close_ready(fd):
        ready_fds.remove(fd)
        try:
            os.close(fd)
        except Exception as exc:
            receipt.setdefault('readiness_cleanup_errors', []).append(type(exc).__name__)
            raise  # Never retry a descriptor whose close result is uncertain.

    def spawn(name, argv, pass_fds=()):
        handles[name] = (out / (name + '.log')).open('x')
        child = subprocess.Popen(argv, env=env, stdin=subprocess.DEVNULL,
                                 stdout=handles[name], stderr=subprocess.STDOUT, close_fds=True, pass_fds=pass_fds)
        children[name] = child
        receipt['children'][name] = {'pid': child.pid, 'executable_sha256': bindings[name]}
        save()
        return child

    def sample(startup=False):
        require(not stopped, 'Termination requested')
        require(time.monotonic() - started <= 120, 'Native capture timeout')
        system = metrics()
        require(system['available_kib'] >= 1048576, 'Available-memory guard')
        require(system['oom_kill'] == before['oom_kill'], 'System OOM count changed')
        rows, total = {}, 0
        for name, child in children.items():
            if child.poll() is not None:
                continue
            try:
                row = process_metrics(child)
            except (FileNotFoundError, KeyError, ProcessLookupError):
                # Bound the short exit race. Live or malformed telemetry fails closed.
                child.wait(timeout=0.05)
                continue
            limit = 2621440 if name == 'godot' else 524288
            if startup and name == 'xvfb':
                # Only this phase can inspect the verified Ubuntu compiler pair.
                # No Godot process has been started yet.
                if row['child_pids']:
                    receipt['startup']['detected'] = True
                    save()
                total += startup_tree.sample(row['child_pids'])
            elif row['child_pids']:
                # Persist detection before any fallible identity/descriptor work.
                # Even an observer failure leaves the unknown tree unconfirmed.
                receipt['unexpected_descendants'].append({'parent': name, 'parent_pid': child.pid,
                    'status': 'unexpected_child_detected',
                    'pids': [safe_diagnostic_text(pid) for pid in row['child_pids'][:16]],
                    'truncated': len(row['child_pids']) > 16})
                save()
                try:
                    observed = observe_descendants(name, child, row['child_pids'], tracked_descendants)
                    receipt['unexpected_descendants'].extend(observed[:17])
                except Exception as exc:
                    receipt['unexpected_descendants'].append({'parent': name, 'parent_pid': child.pid,
                        'status': 'observation_failed', 'error_type': type(exc).__name__})
                raise RuntimeError('Unexpected subprocess outside the reviewed direct-child model')
            require(row['VmRSS'] <= limit and row['VmHWM'] <= limit, 'Per-process memory guard: ' + name)
            total += row['VmRSS']; rows[name] = row
        require(total <= 3145728, 'Combined Xvfb/Godot memory guard')
        receipt['samples'].append({'seconds': round(time.monotonic() - started, 3), **system, 'processes': rows})

    try:
        save()  # Publish bindings/limits before any heavy process.
        for sig in (signal.SIGTERM, signal.SIGINT):
            old_handlers[sig] = signal.signal(sig, stop_signal)
        # Authentication setup is inside the same cleanup boundary as both children.
        private_auth(auth, display)
        ready_read, ready_write = os.pipe2(os.O_CLOEXEC | os.O_NONBLOCK)
        ready_fds.update((ready_read, ready_write))
        xvfb = spawn('xvfb', [str(inputs['xvfb']), ':' + str(display), '-screen', '0', '1024x1024x24',
                              '-nolisten', 'tcp', '-auth', str(auth), '-noreset',
                              '-displayfd', str(ready_write)], pass_fds=(ready_write,))
        close_ready(ready_write)
        startup_tree = xvfb_startup.StartupTree(xvfb, distribution,
            SimpleNamespace(process_identity=process_identity, process_metrics=process_metrics, same_lifetime=same_lifetime),
            receipt['startup'], tracked_descendants)
        ready_deadline = time.monotonic() + 10
        ready_data = b''
        while b'\n' not in ready_data:
            sample(startup=True); require(xvfb.poll() is None, 'Private Xvfb exited before readiness')
            require(time.monotonic() <= ready_deadline, 'Private Xvfb readiness timeout')
            try:
                chunk = os.read(ready_read, 16)
            except BlockingIOError:
                chunk = None
            require(chunk != b'', 'Private Xvfb readiness pipe closed before readiness')
            if chunk is not None:
                ready_data += chunk
            require(len(ready_data) <= 8, 'Malformed Xvfb readiness message')
            if b'\n' not in ready_data:
                time.sleep(0.005)
        require(ready_data == (str(display) + '\n').encode(), 'Wrong display in Xvfb readiness message')
        startup_tree.finish()
        close_ready(ready_read)
        require(stat.S_ISSOCK(Path(f'/tmp/.X11-unix/X{display}').stat().st_mode), 'X11 endpoint is not a socket')
        sample()
        require(xvfb.poll() is None, 'Private Xvfb exited before engine launch')
        godot = spawn('godot', [str(inputs['godot']), '--path', str(project), '--display-driver', 'x11',
            '--rendering-method', 'gl_compatibility', '--rendering-driver', 'opengl3',
            '--audio-driver', 'Dummy', '--resolution', f'{args.width}x{args.height}', '--fixed-fps', '30',
            '--script', str(inputs['harness']), '--', str(frame_dir), lock['build'], str(args.width), str(args.height)])
        diagnostic_deadline = time.monotonic() + 2.0
        while godot.poll() is None:
            sample(); require(xvfb.poll() is None, 'Display server failed during capture')
            if receipt['diagnostic_only']:
                require(time.monotonic() < diagnostic_deadline, 'Diagnostic startup window complete; no screenshot acceptance')
            time.sleep(0.05)
        sample()
        require(godot.wait(timeout=0.05) == 0, 'Godot capture exited nonzero')
        require(xvfb.poll() is None, 'Display server exited before capture acceptance')
        require(not receipt['diagnostic_only'], 'Diagnostic-only run cannot grant screenshot acceptance')
        report = json.loads((frame_dir / 'capture-report.json').read_text())
        require(report.get('passed') is True and report['build'] == lock['build'], 'Capture report failed/identity mismatch')
        require(report.get('frame_count') == contract['frame_count'] == len(report.get('frames', [])), 'Incomplete capture sequence')
        for item in report['frames']:
            require(item['capture_kind'] == contract['kind'], 'Capture scenario kind differs')
            require(item['display'] == 'X11' and 'llvmpipe' in item['adapter_name'].lower(), 'Wrong/dummy renderer')
            require(item['framebuffer'] == [args.width, args.height], 'Wrong framebuffer size')
            require(item['game_sha256'] == source['scripts/game.gd'], 'Screenshot source identity differs')
        # A pass here means evidence production only. Pixel/animation/human quality review follows.
        receipt['capture_completed'] = True
    except BaseException as exc:
        receipt['error'] = {'type': type(exc).__name__, 'message': str(exc)}
    finally:
        # Only owned Popen handles. Never broad pkill, process-group or unrelated PID signals.
        for name, child in reversed(list(children.items())):
            receipt['cleanup'][name] = reap_owned(child)
        receipt['observed_descendant_cleanup'] = [cleanup_observed_descendant(item) for item in reversed(tracked_descendants)]
        for fd in list(ready_fds):
            ready_fds.remove(fd)
            try:
                os.close(fd)
            except Exception as exc:
                receipt.setdefault('readiness_cleanup_errors', []).append(type(exc).__name__)
        for handle in handles.values():
            handle.close()
        for sig, handler in old_handlers.items():
            try:
                signal.signal(sig, handler)
            except BaseException as exc:
                receipt.setdefault('signal_restore_errors', []).append(str(exc))
        try:
            auth.unlink(missing_ok=True)
        except BaseException as exc:
            receipt['private_cleanup_error'] = str(exc)
        startup_unknown = receipt['startup']['detected'] and not receipt['startup']['complete']
        receipt['cleanup_complete'] = (all(item['complete'] for item in receipt['cleanup'].values())
            and all(item['exited'] and item['pidfd_closed'] for item in receipt['observed_descendant_cleanup'])
            and not startup_unknown and not receipt['unexpected_descendants']
            and not receipt.get('readiness_cleanup_errors') and 'private_cleanup_error' not in receipt)
        try:
            after = metrics(); receipt['system_after'] = after
            require(after['oom_kill'] == before['oom_kill'], 'Final OOM count changed')
            final_source, final_uids = source_inventory(project, lock, generated_uids)
            require(final_source == source and final_uids == generated_uids, 'Source/generated UID changed during rendering')
            require(cache_inputs(project) == cache, 'Imported cache changed during rendering')
            require(xvfb_startup.distribution_inventory() == distribution, 'Distribution tool identity changed during rendering')
            require(all(digest(path) == bindings[key] for key, path in inputs.items()), 'Bound helper changed')
            for name in children:
                log = (out / (name + '.log')).read_text(errors='replace')
                require(not re.search(r'(?im)^\s*(?:SCRIPT ERROR:|ERROR:|FATAL:)', log), 'Renderer error in ' + name)
            require(receipt.get('capture_completed') is True and 'error' not in receipt, 'Capture incomplete')
            require(all(item['complete'] for item in receipt['cleanup'].values()), 'Owned-child cleanup incomplete')
            require(not any(item['errors'] for item in receipt['cleanup'].values()), 'Owned-child cleanup reported errors')
            require(not receipt['unexpected_descendants'], 'Unexpected descendant cleanup is unconfirmed; do not retry')
            require(receipt['startup']['complete'] and receipt['cleanup_complete'], 'Startup/readiness cleanup is incomplete')
            require('private_cleanup_error' not in receipt, 'Private authentication cleanup failed')
            require(not receipt.get('signal_restore_errors'), 'Signal handler restoration failed')
            receipt['passed'] = True
        except BaseException as exc:
            receipt['final_error'] = {'type': type(exc).__name__, 'message': str(exc)}
        receipt['seconds'] = round(time.monotonic() - started, 3); save()
        emit_result_diagnostics(out, receipt)
    return 0 if receipt['passed'] else 1


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('project', 'godot', 'harness', 'lock', 'output', 'private', 'import-marker'):
        parser.add_argument('--' + name, type=Path, required=True)
    parser.add_argument('--xvfb', type=Path, default=Path('/usr/bin/Xvfb'))
    parser.add_argument('--width', type=int, required=True)
    parser.add_argument('--height', type=int, required=True)
    raise SystemExit(run(parser.parse_args()))

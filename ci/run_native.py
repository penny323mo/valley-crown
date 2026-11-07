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
import signal
import socket
import stat
import struct
import subprocess
import time


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
           'GODOT_SILENCE_ROOT_WARNING': '1', 'LIBGL_ALWAYS_SOFTWARE': '1',
           'GALLIUM_DRIVER': 'llvmpipe', 'LP_NUM_THREADS': '2', 'OMP_NUM_THREADS': '1'}
    for key, name in [('HOME', 'home'), ('TMPDIR', 'tmp'), ('XDG_DATA_HOME', 'data'),
                      ('XDG_CONFIG_HOME', 'config'), ('XDG_CACHE_HOME', 'cache'),
                      ('MESA_SHADER_CACHE_DIR', 'mesa')]:
        path = private / name
        path.mkdir(mode=0o700)
        env[key] = str(path)
    return env


REAL_DEPENDENCIES = (subprocess.Popen, metrics, process_metrics, time.monotonic, time.sleep, signal.signal)


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


def run(args):
    lock_path = regular(args.lock).resolve()
    lock = json.loads(lock_path.read_text())
    require(lock.get('reviewed_for_execution') is True, 'Draft lock is not approved for execution')
    require(os.environ.get('GITHUB_ACTIONS') == 'true' and os.environ.get('RUNNER_ENVIRONMENT') == 'github-hosted',
            'Only an isolated GitHub-hosted runner is within this draft scope')
    require((args.width, args.height) in [(390, 844), (844, 390)], 'Unreviewed viewport')
    project = args.project.resolve()
    out, private = args.output.resolve(), args.private.resolve()
    require(not out.exists() and not private.exists(), 'Output and private directory must be new')
    require(not out.is_relative_to(project) and not private.is_relative_to(project), 'Outputs must be outside source')
    source = tree(project, exclude_cache=True)
    require(source == lock['project_files'], 'Project file set or hashes differ from reviewed lock')
    require((project / '.godot/imported').is_dir(), 'A successful fresh guarded import is required first')
    cache = cache_inputs(project)
    require(cache, 'Empty imported cache')
    import_marker = regular(args.import_marker).resolve()
    certificate = json.loads(import_marker.read_text())
    require(certificate['build'] == lock['build'] and certificate['project'] == str(project), 'Import belongs to another source')
    require(certificate['archive_sha256'] == lock['source_archive_sha256'] and
            certificate['engine_sha256'] == lock['godot_sha256'], 'Import input identity differs')
    require(certificate['cache_sha256'] == cache, 'Cache differs from successful guarded import')
    import_receipt = regular(certificate['monitor_receipt']).resolve()
    require(digest(import_receipt) == certificate['monitor_receipt_sha256'], 'Import receipt changed')
    prior = json.loads(import_receipt.read_text())
    require(prior.get('passed') is True and prior.get('cleanup_complete') is True, 'Import did not pass its guard')
    inputs = {'lock': lock_path, 'harness': regular(args.harness).resolve(),
              'godot': regular(args.godot).resolve(), 'xvfb': regular(args.xvfb).resolve(),
              'supervisor': Path(__file__).resolve(), 'import_marker': import_marker, 'import_receipt': import_receipt}
    bindings = {key: digest(path) for key, path in inputs.items()}
    for key in ('harness', 'godot', 'supervisor'):
        require(bindings[key] == lock[key + '_sha256'], 'Reviewed helper/tool hash mismatch: ' + key)
    # Distribution-provided Xvfb is recorded, never substituted with a downloaded binary.
    require(str(inputs['xvfb']) == '/usr/bin/Xvfb', 'Expected Ubuntu distribution Xvfb')
    require(lock['native_renderer'] == 'linux-x11-mesa-llvmpipe-gl_compatibility', 'Renderer scope differs')
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
               'time_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
               'input_sha256': bindings, 'source_file_count': len(source),
               'cache_files': len(cache), 'samples': [], 'children': {}, 'cleanup': {},
               'unexpected_descendants': [], 'cleanup_complete': False,
               'test_dependencies': any(actual is not original for actual, original in zip(
                   (subprocess.Popen, metrics, process_metrics, time.monotonic, time.sleep, signal.signal), REAL_DEPENDENCIES)),
               'system_before': before, 'limits': {'timeout_seconds': 120, 'minimum_available_kib': 1048576,
                   'aggregate_rss_kib': 3145728, 'godot_rss_kib': 2621440, 'xvfb_rss_kib': 524288},
               'fixed_fps': 30, 'expected_framebuffer': [args.width, args.height],
               'not_verified': ['Web', 'Safari', 'physical iPhone', 'mobile GPU', 'FPS', 'touch input', 'visual quality']}
    children = {}
    handles = {}
    stopped = False

    def stop_signal(signum, frame):
        nonlocal stopped
        stopped = True

    old_handlers = {}

    def save():
        (out / 'guard-receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')

    def spawn(name, argv):
        handles[name] = (out / (name + '.log')).open('x')
        child = subprocess.Popen(argv, env=env, stdin=subprocess.DEVNULL,
                                 stdout=handles[name], stderr=subprocess.STDOUT, close_fds=True)
        children[name] = child
        receipt['children'][name] = {'pid': child.pid, 'executable_sha256': bindings[name]}
        save()
        return child

    def sample():
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
            if row['child_pids']:
                receipt['unexpected_descendants'].append({'parent': name, 'pids': row['child_pids']})
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
        xvfb = spawn('xvfb', [str(inputs['xvfb']), ':' + str(display), '-screen', '0', '1024x1024x24',
                              '-nolisten', 'tcp', '-auth', str(auth), '-noreset'])
        ready_deadline = time.monotonic() + 10
        while not Path(f'/tmp/.X11-unix/X{display}').exists():
            sample(); require(xvfb.poll() is None, 'Private Xvfb exited before readiness')
            require(time.monotonic() <= ready_deadline, 'Private Xvfb readiness timeout')
            time.sleep(0.05)
        require(stat.S_ISSOCK(Path(f'/tmp/.X11-unix/X{display}').stat().st_mode), 'X11 endpoint is not a socket')
        sample()
        require(xvfb.poll() is None, 'Private Xvfb exited before engine launch')
        godot = spawn('godot', [str(inputs['godot']), '--path', str(project), '--display-driver', 'x11',
            '--rendering-method', 'gl_compatibility', '--rendering-driver', 'opengl3',
            '--audio-driver', 'Dummy', '--resolution', f'{args.width}x{args.height}', '--fixed-fps', '30',
            '--script', str(inputs['harness']), '--', str(frame_dir), lock['build'], str(args.width), str(args.height)])
        while godot.poll() is None:
            sample(); require(xvfb.poll() is None, 'Display server failed during capture')
            time.sleep(0.05)
        sample()
        require(godot.wait(timeout=0.05) == 0, 'Godot capture exited nonzero')
        require(xvfb.poll() is None, 'Display server exited before capture acceptance')
        report = json.loads((frame_dir / 'capture-report.json').read_text())
        require(report.get('passed') is True and report['build'] == lock['build'], 'Capture report failed/identity mismatch')
        require(report.get('frame_count') == 10, 'Incomplete capture sequence')
        for item in report['frames']:
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
        receipt['cleanup_complete'] = all(item['complete'] for item in receipt['cleanup'].values()) and not receipt['unexpected_descendants'] and 'private_cleanup_error' not in receipt
        try:
            after = metrics(); receipt['system_after'] = after
            require(after['oom_kill'] == before['oom_kill'], 'Final OOM count changed')
            require(tree(project, exclude_cache=True) == source, 'Source changed during rendering')
            require(cache_inputs(project) == cache, 'Imported cache changed during rendering')
            require(all(digest(path) == bindings[key] for key, path in inputs.items()), 'Bound helper changed')
            for name in children:
                log = (out / (name + '.log')).read_text(errors='replace')
                require(not re.search(r'(?im)^\s*(?:SCRIPT ERROR:|ERROR:|FATAL:)', log), 'Renderer error in ' + name)
            require(receipt.get('capture_completed') is True and 'error' not in receipt, 'Capture incomplete')
            require(all(item['complete'] for item in receipt['cleanup'].values()), 'Owned-child cleanup incomplete')
            require(not any(item['errors'] for item in receipt['cleanup'].values()), 'Owned-child cleanup reported errors')
            require(not receipt['unexpected_descendants'], 'Unexpected descendant cleanup is unconfirmed; do not retry')
            require('private_cleanup_error' not in receipt, 'Private authentication cleanup failed')
            require(not receipt.get('signal_restore_errors'), 'Signal handler restoration failed')
            receipt['passed'] = True
        except BaseException as exc:
            receipt['final_error'] = {'type': type(exc).__name__, 'message': str(exc)}
        receipt['seconds'] = round(time.monotonic() - started, 3); save()
    return 0 if receipt['passed'] else 1


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('project', 'godot', 'harness', 'lock', 'output', 'private', 'import-marker'):
        parser.add_argument('--' + name, type=Path, required=True)
    parser.add_argument('--xvfb', type=Path, default=Path('/usr/bin/Xvfb'))
    parser.add_argument('--width', type=int, required=True)
    parser.add_argument('--height', type=int, required=True)
    raise SystemExit(run(parser.parse_args()))

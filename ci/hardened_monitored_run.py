"""Bounded direct-child monitor. NOT a validated Godot export or resource fix.

The public run() defaults use real /proc telemetry. Private dependency injection
exists solely for lightweight lifecycle tests and is recorded in the receipt.
No process group, unrelated PID or operating-system setting is modified.
"""
from pathlib import Path
from dataclasses import dataclass, asdict
import datetime
import hashlib
import inspect
import json
import os
import re
import shutil
import subprocess
import sys
import time

SELF = Path(__file__).resolve()
sha = lambda p: hashlib.sha256(Path(p).read_bytes()).hexdigest()
LOADED_HELPER_SHA256 = sha(SELF)

@dataclass(frozen=True)
class Limits:
    timeout_s: float = 240.0
    sample_target_s: float = 0.05
    terminate_grace_s: float = 10.0
    kill_reap_grace_s: float = 10.0
    launch_min_available_kib: int = 1250000
    runtime_min_available_kib: int = 450000
    max_rss_kib: int = 768000

    def validate(self):
        for key, value in asdict(self).items():
            if isinstance(value, bool) or not isinstance(value, (int, float)) or not (0 < value < float('inf')):
                raise ValueError('Invalid positive finite limit: ' + key)

def system_metrics():
    mem = {line.split(':')[0]: int(line.split()[1]) for line in Path('/proc/meminfo').read_text().splitlines()}
    vm = {line.split()[0]: int(line.split()[1]) for line in Path('/proc/vmstat').read_text().splitlines()}
    return {'MemAvailable_kB': mem['MemAvailable'], 'oom_kill': vm['oom_kill']}

def process_metrics(pid):
    fields = dict(line.split(':', 1) for line in Path(f'/proc/{pid}/status').read_text().splitlines() if ':' in line)
    return {key: int(fields[key].split()[0]) for key in ('VmRSS', 'VmHWM', 'VmSize', 'Threads') if key in fields}

def validate_metrics(data, required):
    if not isinstance(data, dict):
        raise ValueError('Telemetry must be a mapping')
    for key in required:
        value = data.get(key)
        if isinstance(value, bool) or not isinstance(value, int) or value < 0:
            raise ValueError('Invalid/missing nonnegative integer telemetry: ' + key)
    return data

def callback_binding(callback):
    obj = callback if inspect.isfunction(callback) or inspect.isclass(callback) else type(callback)
    path = inspect.getsourcefile(obj)
    return {'name': getattr(obj, '__qualname__', str(obj)), 'file': str(Path(path).resolve()) if path else None,
            'sha256': sha(path) if path else None}

def run(out, argv, env=None, limits=Limits(), artifacts=None, expected_artifact_hashes=None,
        *, _system=system_metrics, _process=process_metrics, _popen=subprocess.Popen, _sleep=time.sleep):
    """Return an explicit pass/fail receipt. Even exceptions trigger child cleanup.

    Failure to terminate/reap is explicitly returned as cleanup_complete=False.
    A later caller must never treat such a receipt as permission to retry.
    """
    limits.validate()
    out = Path(out).resolve()
    out.parent.mkdir(parents=True, exist_ok=True)
    paths = {key: out.with_suffix(suffix) for key, suffix in
             [('invocation', '.invocation.json'), ('log', '.log'), ('result', '.json')]}
    # Exclusive creation rejects existing files and dangling symlinks. Never overwrite.
    if any(path.exists() or path.is_symlink() for path in paths.values()):
        raise FileExistsError('Refusing to overwrite monitor evidence')
    handles = {}
    try:
        for key, path in paths.items():
            handles[key] = path.open('x')
    except BaseException:
        for handle in handles.values():
            handle.close()
        raise
    child = None
    start = time.monotonic()
    result = {'passed': False, 'child_started': False, 'cleanup_complete': False, 'pid': None,
              'exit': None, 'stop_reason': None, 'exception': None, 'cleanup_errors': [],
              'signal_attempts': [], 'samples': [], 'terminal_telemetry_gaps': [],
              'system_before': None, 'system_after': None,
              'post_run_binding_matches': {}, 'output_errors': []}
    invocation = {'time_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
                  'requested_argv': list(argv), 'limits': asdict(limits),
                  'helper': {'path': str(SELF), 'load_sha256': LOADED_HELPER_SHA256},
                  'test_dependencies': any(a is not b for a, b in
                      [(_system, system_metrics), (_process, process_metrics), (_popen, subprocess.Popen), (_sleep, time.sleep)]),
                  'dependencies': {}, 'artifacts': {}, 'no_process_group_signals': True}
    bound_paths = {}
    invocation_written = False

    def write_invocation():
        nonlocal invocation_written
        if invocation_written:
            return
        handles['invocation'].write(json.dumps(invocation, indent=2) + '\n')
        handles['invocation'].flush()
        os.fsync(handles['invocation'].fileno())
        invocation_written = True

    def cleanup():
        if child is None:
            result['cleanup_complete'] = True
            return
        try:
            alive = child.poll() is None
        except BaseException as exc:
            result['cleanup_errors'].append('poll: ' + repr(exc))
            alive = True
        if alive:
            result['signal_attempts'].append({'pid': child.pid, 'signal': 'SIGTERM'})
            try:
                child.terminate()
            except BaseException as exc:
                result['cleanup_errors'].append('terminate: ' + repr(exc))
            try:
                child.wait(timeout=limits.terminate_grace_s)
            except subprocess.TimeoutExpired:
                # Popen.poll checks/reaps the same owned child before any kill.
                try:
                    if child.poll() is None:
                        result['signal_attempts'].append({'pid': child.pid, 'signal': 'SIGKILL'})
                        child.kill()
                except BaseException as exc:
                    result['cleanup_errors'].append('kill: ' + repr(exc))
            except BaseException as exc:
                result['cleanup_errors'].append('terminate_wait: ' + repr(exc))
                try:
                    if child.poll() is None:
                        result['signal_attempts'].append({'pid': child.pid, 'signal': 'SIGKILL'})
                        child.kill()
                except BaseException as kill_exc:
                    result['cleanup_errors'].append('kill_after_wait_error: ' + repr(kill_exc))
        try:
            result['exit'] = child.wait(timeout=limits.kill_reap_grace_s)
            result['cleanup_complete'] = True
        except BaseException as exc:
            result['cleanup_errors'].append('final_wait: ' + repr(exc))
            result['cleanup_complete'] = False

    try:
        helper_now = sha(SELF)
        invocation['helper']['invocation_sha256'] = helper_now
        if helper_now != LOADED_HELPER_SHA256:
            raise RuntimeError('Helper changed since module load')
        bound_paths['helper'] = (SELF, helper_now)
        for name, callback in [('system', _system), ('process', _process), ('popen', _popen), ('sleep', _sleep)]:
            if callback is time.sleep:
                invocation['dependencies'][name] = {'name': 'time.sleep', 'builtin': True}
            else:
                invocation['dependencies'][name] = callback_binding(callback)
        if not argv:
            raise ValueError('Empty argv')
        environment = dict(os.environ if env is None else env)
        executable = shutil.which(str(argv[0]), path=environment.get('PATH'))
        if executable is None:
            raise FileNotFoundError('Executable not found')
        executable = Path(executable).resolve()
        invocation['argv'] = [str(executable)] + [str(value) for value in argv[1:]]
        invocation['executable'] = {'path': str(executable), 'sha256': sha(executable)}
        bound_paths['executable'] = (executable, invocation['executable']['sha256'])
        invocation['python_interpreter'] = {'path': str(Path(sys.executable).resolve()), 'sha256': sha(sys.executable)}
        invocation['env_overrides'] = {key: environment.get(key) for key in
                                      ('XDG_DATA_HOME', 'XDG_CONFIG_HOME', 'XDG_CACHE_HOME', 'MALLOC_ARENA_MAX')}
        for name, path in (artifacts or {}).items():
            path = Path(path).resolve()
            digest = sha(path)
            invocation['artifacts'][name] = {'path': str(path), 'sha256': digest}
            bound_paths['artifact:' + name] = (path, digest)
            expected = (expected_artifact_hashes or {}).get(name)
            if expected is not None and digest != expected:
                raise ValueError('Artifact hash mismatch: ' + name)
        if set(expected_artifact_hashes or {}) - set(artifacts or {}):
            raise ValueError('Expected artifact has no bound input')
        result['system_before'] = validate_metrics(_system(), ('MemAvailable_kB', 'oom_kill'))
        invocation['system_before'] = result['system_before']
        if result['system_before']['MemAvailable_kB'] < limits.launch_min_available_kib:
            raise RuntimeError('Insufficient available memory before launch')
        # Persist the hashes and launch plan BEFORE Popen is called.
        write_invocation()
        child = _popen(invocation['argv'], env=environment, stdout=handles['log'], stderr=subprocess.STDOUT)
        result['child_started'] = True
        result['pid'] = child.pid
        child_started = time.monotonic()
        while child.poll() is None:
            now = time.monotonic()
            if now - child_started > limits.timeout_s:
                result['stop_reason'] = 'OWNED_PROCESS_TIMEOUT'
                break
            system = validate_metrics(_system(), ('MemAvailable_kB', 'oom_kill'))
            try:
                process = _process(child.pid)
                if isinstance(process, dict) and 'VmRSS' not in process:
                    # Linux may release an exiting child's mm before waitpid can
                    # observe its exit. Never invent RSS or accept a live gap.
                    remaining = limits.timeout_s - (time.monotonic() - child_started)
                    grace = min(0.05, limits.sample_target_s, max(0.0, remaining))
                    try:
                        exit_code = child.wait(timeout=grace)
                    except subprocess.TimeoutExpired:
                        pass  # Still live: normal validation below must fail.
                    else:
                        result['terminal_telemetry_gaps'].append({
                            'elapsed_s': round(time.monotonic() - child_started, 6),
                            'reason': 'VmRSS absent; owned child exit confirmed',
                            'wait_bound_s': grace, 'exit': exit_code, 'system': system})
                        if system['oom_kill'] > result['system_before']['oom_kill']:
                            result['stop_reason'] = 'GLOBAL_OOM_INCREMENT_STOP_OWNED_PROCESS'
                        elif system['MemAvailable_kB'] < limits.runtime_min_available_kib:
                            result['stop_reason'] = 'LOW_AVAILABLE_MEMORY_STOP_OWNED_PROCESS'
                        break
                process = validate_metrics(process, ('VmRSS',))
            except (FileNotFoundError, ProcessLookupError):
                if child.poll() is not None:
                    break
                raise
            sample = {'elapsed_s': round(now - child_started, 6), 'system': system, 'process': process}
            result['samples'].append(sample)
            if process['VmRSS'] > limits.max_rss_kib:
                result['stop_reason'] = 'OWNED_PROCESS_RSS_GUARD'
            elif system['oom_kill'] > result['system_before']['oom_kill']:
                result['stop_reason'] = 'GLOBAL_OOM_INCREMENT_STOP_OWNED_PROCESS'
            elif system['MemAvailable_kB'] < limits.runtime_min_available_kib:
                result['stop_reason'] = 'LOW_AVAILABLE_MEMORY_STOP_OWNED_PROCESS'
            if result['stop_reason']:
                break
            _sleep(limits.sample_target_s)
    except BaseException as exc:
        result['exception'] = {'type': type(exc).__name__, 'message': str(exc)}
        result['stop_reason'] = result['stop_reason'] or 'MONITOR_EXCEPTION'
        invocation['prelaunch_exception'] = result['exception'] if child is None else None
    finally:
        # The child's lifetime ends before any final telemetry, output parsing,
        # receipt writes or post-run hashes can fail.
        cleanup()
        try:
            write_invocation()
            result['invocation_sha256'] = sha(paths['invocation'])
        except BaseException as exc:
            result['cleanup_errors'].append('invocation_finalize: ' + repr(exc))
        try:
            handles['log'].flush()
        except BaseException as exc:
            result['cleanup_errors'].append('log_flush: ' + repr(exc))
        try:
            handles['log'].close()
        except BaseException as exc:
            result['cleanup_errors'].append('log_close: ' + repr(exc))
        try:
            result['system_after'] = validate_metrics(_system(), ('MemAvailable_kB', 'oom_kill'))
            if (result['child_started'] and result['system_before'] is not None
                    and result['system_after']['oom_kill'] > result['system_before']['oom_kill']
                    and result['stop_reason'] is None):
                result['stop_reason'] = 'GLOBAL_OOM_INCREMENT_OBSERVED_AT_FINAL_TELEMETRY'
        except BaseException as exc:
            result['cleanup_errors'].append('final_telemetry: ' + repr(exc))
        for name, (path, digest) in bound_paths.items():
            try:
                result['post_run_binding_matches'][name] = sha(path) == digest
            except BaseException:
                result['post_run_binding_matches'][name] = False
        try:
            raw = paths['log'].read_text(errors='replace')
            result['log_sha256'] = sha(paths['log'])
            # Preserve raw log bytes, but normalize terminal decoration for detection.
            ansi = re.compile(r'\x1b\[[0-?]*[ -/]*[@-~]|\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)')
            normalized_lines = [ansi.sub('', line).lstrip() for line in raw.splitlines()]
            result['output_errors'] = [line for line in normalized_lines
                                      if line.startswith(('ERROR:', 'WARNING:')) or 'SCRIPT ERROR:' in line or 'Fontconfig error:' in line]
        except BaseException as exc:
            result['cleanup_errors'].append('output_read: ' + repr(exc))
        elapsed = [sample['elapsed_s'] for sample in result['samples']]
        gaps = [b - a for a, b in zip(elapsed, elapsed[1:])]
        result.update(seconds=round(time.monotonic() - start, 6), sample_target_s=limits.sample_target_s,
                      sample_count=len(elapsed), actual_max_sample_gap_s=max(gaps, default=None),
                      sampled_peak_rss_kib=max((x['process']['VmRSS'] for x in result['samples']), default=0),
                      scope='Direct-child lifecycle/telemetry only. Not export, browser, phone or OOM root-cause validation.')
        result['passed'] = bool(result['child_started'] and result['cleanup_complete'] and result['exit'] == 0
                                and not result['stop_reason'] and not result['exception'] and not result['cleanup_errors']
                                and not result['output_errors'] and all(result['post_run_binding_matches'].values()))
        try:
            handles['result'].write(json.dumps(result, indent=2) + '\n')
            handles['result'].flush()
            os.fsync(handles['result'].fileno())
        finally:
            for handle in handles.values():
                if not handle.closed:
                    handle.close()
    return result

if __name__ == '__main__':
    receipt = run(sys.argv[1], sys.argv[2:])
    print(json.dumps({key: receipt[key] for key in ('passed', 'pid', 'exit', 'stop_reason', 'cleanup_complete')}))
    sys.exit(0 if receipt['passed'] else 1)

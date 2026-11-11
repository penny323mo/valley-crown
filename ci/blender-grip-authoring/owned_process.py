# Exact function copies from reviewed run_native.py; no native/Xvfb entrypoint.
from pathlib import Path
import hashlib,json,os,re,select,signal,subprocess,time
UID_ALPHABET = b"abcdefghijklmnopqrstuvwxy012345678"
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


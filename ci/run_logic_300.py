#!/usr/bin/env python3
"""Inert until hash-bound lock explicitly approves one hosted combat-logic run."""
import argparse
import datetime
import json
import os
from pathlib import Path
import re
import types
import signal
import subprocess
import time
import owned_process as p

ENGINE_SHA = 'f64d4ed19fc9df9440321653fcc80df8c6e365ba7b6de0a29e2cfa9fa71bfeb3'
SOURCE = 'c5b78df4dab1e1f58f83bc2d8678512ddc628045'
GAME_TREE = 'c133ed816d338bfabab2ae617bee917f4080799b'
BUILD = 'vc-dd795d96905c'
MONITOR_SHA = '4c7802bcfb53a2f73f501635cdf483e1459d3d86eb881a7450dccd3bbd705d50'
REAL = (subprocess.Popen, p.metrics, p.process_metrics, p.observe_descendants,
        p.cleanup_observed_descendant, p.reap_owned, time.monotonic, time.sleep,
        signal.signal, p.process_identity, os.pidfd_open, signal.pidfd_send_signal,
        p.select.select, os.close)


def path_checked(path):
    path = Path(path).absolute()
    p.require(not any(x.is_symlink() for x in [path, *path.parents]), 'Symlink path')
    return path


def checked(path, expected):
    path = path_checked(path)
    p.require(p.digest(p.regular(path)) == expected, 'Hash mismatch: ' + path.name)
    return path


def hash_value(value):
    p.require(type(value) is str and re.fullmatch('[a-f0-9]{64}', value), 'Invalid digest')


def validate_lock(lock):
    p.require(lock.get('reviewed_for_execution') is True, 'Execution not reviewed')
    p.require(lock.get('schema') == 'vc-headless-combat-logic-v1', 'Wrong lock schema')
    p.require((lock.get('source_commit'), lock.get('game_tree'), lock.get('build')) ==
              (SOURCE, GAME_TREE, BUILD), 'Source scope differs')
    p.require(lock.get('godot_sha256') == ENGINE_SHA, 'Wrong official engine')
    for name in ('runner_sha256', 'owned_process_sha256', 'harness_sha256', 'validator_sha256',
                 'source_archive_sha256', 'import_manifest_sha256', 'import_adapter_sha256'):
        hash_value(lock.get(name))
    files = lock.get('project_files')
    p.require(type(files) is dict and files and 'project.godot' in files, 'Missing source inventory')
    for name, value in files.items():
        p.require(type(name) is str and name and not Path(name).is_absolute() and '\\' not in name
                  and all(x not in ('', '.', '..') for x in name.split('/'))
                  and not name.startswith('.godot/'), 'Invalid source path')
        hash_value(value)
    p.require(type(lock.get('allowed_generated_uid_files')) is list, 'Missing UID allowlist')


def validate_import(project, lock, marker, cache, uids):
    cert = json.loads(p.regular(marker).read_text())
    expected = {'build': BUILD, 'project': str(project), 'archive_sha256': lock['source_archive_sha256'],
                'engine_sha256': ENGINE_SHA, 'manifest_sha256': lock['import_manifest_sha256'],
                'adapter_sha256': lock['import_adapter_sha256'], 'cache_sha256': cache,
                'generated_uid_sha256': uids}
    p.require(all(cert.get(k) == v for k, v in expected.items()), 'Import identity mismatch')
    receipt = checked(cert['receipt'], cert['receipt_sha256'])
    invocation = checked(cert['invocation'], cert['invocation_sha256'])
    result = json.loads(receipt.read_text()); request = json.loads(invocation.read_text())
    p.require(result.get('passed') is True and result.get('cleanup_complete') is True and
              result.get('child_started') is True and type(result.get('exit')) is int and result['exit'] == 0,
              'Import guard failed')
    log = checked(receipt.with_suffix('.log'), result['log_sha256'])
    p.require(result.get('invocation_sha256') == p.digest(invocation) and request.get('test_dependencies') is False,
              'Mocked/mismatched import invocation')
    p.require(request['helper']['load_sha256'] == request['helper']['invocation_sha256'] == MONITOR_SHA,
              'Wrong import monitor')
    p.require(not result.get('exception') and not result.get('stop_reason') and not result.get('cleanup_errors')
              and not result.get('output_errors') and result.get('post_run_binding_matches')
              and all(v is True for v in result['post_run_binding_matches'].values()), 'Incomplete import evidence')
    return [receipt, invocation, log]


def check_sample(system, before, row):
    p.require(system['available_kib'] >= 1048576, 'Available-memory guard')
    p.require(system['oom_kill'] == before['oom_kill'], 'OOM count changed')
    if row:
        p.require(row['VmRSS'] <= 2621440 and row['VmHWM'] <= 2621440, 'Godot RSS/HWM guard')
        p.require(row['VmRSS'] <= 3145728, 'Combined RSS guard')


def supervise(argv, env, directory, before):
    """One owned child, no shells or process groups; all descendants fatal."""
    receipt = {'passed': False, 'cleanup_complete': False, 'unexpected_descendants': [],
               'samples': [], 'argv': argv, 'system_before': before,
               'limits': {'timeout_seconds': 300, 'admission_kib': 4194304,
                          'reserve_kib': 1048576, 'godot_rss_hwm_kib': 2621440,
                          'combined_rss_kib': 3145728},
               'test_dependencies': any(a is not b for a,b in zip(
                   (subprocess.Popen, p.metrics, p.process_metrics, p.observe_descendants,
                    p.cleanup_observed_descendant, p.reap_owned, time.monotonic, time.sleep,
                    signal.signal, p.process_identity, os.pidfd_open, signal.pidfd_send_signal,
                    p.select.select, os.close), REAL))}
    child = None; tracked = []; handlers = {}; stopped = False
    start = time.monotonic()
    def save():
        (directory / 'receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
    def stop(sig, frame):
        nonlocal stopped
        stopped = True
    def sample():
        p.require(not stopped, 'Termination requested')
        p.require(time.monotonic() - start <= 300, 'Logic timeout')
        system = p.metrics(); row = None
        logpath = directory / 'godot.log'
        if logpath.exists():
            p.require(logpath.stat().st_size <= 16*1024*1024, 'Logic log oversized')
        if child is not None and child.poll() is None:
            try:
                row = p.process_metrics(child)
            except (FileNotFoundError, KeyError, ProcessLookupError):
                child.wait(timeout=0.05)
            if row and row['child_pids']:
                receipt['unexpected_descendants'].append({'status': 'unexpected_child_detected',
                    'parent_pid': child.pid, 'pids': row['child_pids'][:16], 'truncated': len(row['child_pids']) > 16})
                save()
                try:
                    receipt['unexpected_descendants'].extend(p.observe_descendants('godot', child, row['child_pids'], tracked))
                except Exception as exc:
                    receipt['unexpected_descendants'].append({'status': 'observation_failed', 'type': type(exc).__name__})
                raise RuntimeError('Unexpected descendant; no retry')
        check_sample(system, before, row)
        receipt['samples'].append({'seconds': round(time.monotonic()-start, 3), **system, 'process': row})
        return system
    try:
        save()
        p.require(before['available_kib'] >= 4194304, 'Admission below 4 GiB')
        for sig in (signal.SIGTERM, signal.SIGINT):
            handlers[sig] = signal.signal(sig, stop)
        with (directory / 'godot.log').open('x') as log:
            admission = sample()
            p.require(admission['available_kib'] >= 4194304, 'Fresh admission below 4 GiB')
            receipt['launch_admission'] = admission
            child = subprocess.Popen(argv, env=env, stdin=subprocess.DEVNULL, stdout=log,
                                     stderr=subprocess.STDOUT, close_fds=True)
            receipt['pid'] = child.pid; save()
            while child.poll() is None:
                sample(); time.sleep(0.05)
            sample()
            receipt['exit'] = child.wait(timeout=0.05)
            p.require(receipt['exit'] == 0, 'Logic nonzero exit')
            receipt['logic_completed'] = True
    except BaseException as exc:
        receipt['error'] = {'type': type(exc).__name__, 'message': p.safe_diagnostic_text(exc)}
    finally:
        receipt['cleanup'] = p.reap_owned(child) if child is not None else {'complete': True, 'errors': [], 'signals': []}
        receipt['descendant_cleanup'] = [p.cleanup_observed_descendant(x) for x in reversed(tracked)]
        for sig, handler in handlers.items():
            try: signal.signal(sig, handler)
            except BaseException as exc: receipt.setdefault('handler_errors', []).append(type(exc).__name__)
        receipt['cleanup_complete'] = (receipt['cleanup']['complete'] and not receipt['cleanup']['errors']
            and not receipt['unexpected_descendants'] and not receipt.get('handler_errors')
            and all(x['exited'] and x['pidfd_closed'] for x in receipt['descendant_cleanup']))
        try:
            receipt['system_after'] = p.metrics(); check_sample(receipt['system_after'], before, None)
            p.require(receipt.get('logic_completed') and 'error' not in receipt and receipt['cleanup_complete'], 'Incomplete logic run')
            log = directory / 'godot.log'
            p.require(log.stat().st_size <= 16*1024*1024, 'Logic log oversized')
            p.require(not re.search(r'(?im)^\s*(?:SCRIPT ERROR:|ERROR:|FATAL:)', log.read_text(errors='replace')), 'Logic log error')
            receipt['log_sha256'] = p.digest(log)
            receipt['passed'] = True
        except BaseException as exc:
            receipt['final_error'] = {'type': type(exc).__name__, 'message': p.safe_diagnostic_text(exc)}
        receipt['seconds'] = round(time.monotonic()-start, 3); save()
    return receipt


def fixed_argv(godot, project, harness, output):
    return [str(godot), '--headless', '--path', str(project), '--audio-driver', 'Dummy',
            '--resolution', '390x844', '--fixed-fps', '30', '--script', str(harness),
            '--', str(output / 'combat-report.json'), BUILD]


def read_report(path):
    path_checked(path); p.regular(path)
    p.require(0 < path.stat().st_size <= 4*1024*1024, 'Empty/oversized combat report')
    def unique(pairs):
        result = {}
        for key, value in pairs:
            p.require(key not in result, 'Duplicate report JSON key')
            result[key] = value
        return result
    def invalid_constant(value):
        raise ValueError('Nonfinite report JSON')
    report = json.loads(path.read_text(), object_pairs_hook=unique, parse_constant=invalid_constant)
    p.require(type(report) is dict, 'Combat report must be an object')
    return report


def run(args):
    lockpath = path_checked(args.lock)
    lock = json.loads(p.regular(lockpath).read_text()); validate_lock(lock)
    p.require(os.environ.get('GITHUB_ACTIONS') == 'true' and os.environ.get('RUNNER_ENVIRONMENT') == 'github-hosted',
              'Fresh GitHub-hosted runner required')
    p.require('VERSION_ID="24.04"' in Path('/etc/os-release').read_text(), 'Ubuntu 24.04 required')
    project, output, private = map(path_checked, (args.project, args.output, args.private))
    p.require(project.is_dir() and not output.exists() and not private.exists(), 'Fresh output/private paths required')
    paths = [project, output, private]
    p.require(all(not a.is_relative_to(b) for a in paths for b in paths if a != b) and len(set(paths)) == 3,
              'Source/output/private overlap')
    godot = checked(args.godot, ENGINE_SHA)
    runner = checked(__file__, lock['runner_sha256']); helper = checked(p.__file__, lock['owned_process_sha256'])
    harness = checked(args.harness, lock['harness_sha256']); validator = checked(args.validator, lock['validator_sha256'])
    p.require(not harness.is_relative_to(project) and not validator.is_relative_to(project), 'Harness/validator must be outside frozen project')
    source, uids = p.source_inventory(project, lock)
    cache = p.cache_inputs(project); p.require(cache, 'Fresh guarded import required')
    marker = path_checked(args.import_marker)
    bound = [lockpath, godot, runner, helper, harness, validator, marker] + validate_import(project, lock, marker, cache, uids)
    bindings = {str(x): p.digest(x) for x in bound}
    output.mkdir(parents=True, mode=0o700); private.mkdir(parents=True, mode=0o700)
    overall = {'passed': False, 'schema': 'vc-headless-combat-logic-v1', 'build': BUILD,
               'source_commit': SOURCE, 'game_tree': GAME_TREE, 'scope': 'single_headless_combat_logic',
               'not_verified': ['browser behavior', 'touch input', 'visual quality', 'device performance'],
               'input_sha256': bindings, 'generated_uid_sha256': uids,
               'time_utc': datetime.datetime.now(datetime.timezone.utc).isoformat()}
    def recheck():
        p.require(p.source_inventory(project, lock, uids)[0] == source, 'Source/UID drift')
        p.require(p.cache_inputs(project) == cache, 'Imported cache drift')
        p.require(all(p.digest(p.regular(path_checked(x))) == h for x,h in bindings.items()), 'Bound tool/evidence drift')
    try:
        env = {'PATH': '/usr/bin:/bin', 'LANG': 'C.UTF-8', 'TZ': 'UTC', 'GODOT_SILENCE_ROOT_WARNING': '1',
               'OMP_NUM_THREADS': '1'}
        for key, name in [('HOME','home'), ('TMPDIR','tmp'), ('XDG_DATA_HOME','data'),
                          ('XDG_CONFIG_HOME','config'), ('XDG_CACHE_HOME','cache')]:
            path = private / name; path.mkdir(mode=0o700); env[key] = str(path)
        recheck()
        reportpath = output / 'combat-report.json'
        p.require(not reportpath.exists(), 'Report must be new')
        result = supervise(fixed_argv(godot, project, harness, output), env, output, p.metrics())
        overall['process_guard'] = result
        recheck()
        p.require(result['passed'] and not result['test_dependencies'], 'Logic monitor failed or mocked')
        report = read_report(reportpath)
        overall['report_sha256'] = p.digest(reportpath)
        module = types.ModuleType('bound_combat_validator')
        module.__file__ = str(validator)
        exec(compile(validator.read_bytes(), str(validator), 'exec'), module.__dict__)
        validated = module.validate(report, lock)
        p.require(type(validated) is dict, 'Validator returned invalid result')
        overall['validation'] = validated
        p.require(p.digest(p.regular(reportpath)) == overall['report_sha256'], 'Report drift during validation')
        recheck()
        p.require(set(p.tree(output)) == {'receipt.json', 'godot.log', 'combat-report.json'}, 'Unexpected output files')
        overall['passed'] = True
    except BaseException as exc:
        overall['error'] = {'type': type(exc).__name__, 'message': p.safe_diagnostic_text(exc)}
    finally:
        # Failure reports remain evidence only, never a successful result.
        try:
            recheck()
            overall['post_run_binding_matches'] = True
        except BaseException as exc:
            overall['passed'] = False
            overall['post_run_binding_matches'] = False
            overall['binding_error'] = {'type': type(exc).__name__, 'message': p.safe_diagnostic_text(exc)}
        (output / 'combat-logic-receipt.json').write_text(json.dumps(overall, indent=2)+'\n')
        print(json.dumps({'passed': overall['passed'], 'scope': overall['scope'], 'error': overall.get('error')}))
    return 0 if overall['passed'] else 1

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('lock', 'project', 'output', 'private', 'godot', 'harness', 'validator', 'import-marker'):
        parser.add_argument('--'+name, required=True, type=Path)
    raise SystemExit(run(parser.parse_args()))

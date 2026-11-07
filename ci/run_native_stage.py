#!/usr/bin/env python3
"""Guarded hosted conversion of the exact combined prototype; never export/deploy.

No engine runs on import. The CLI requires an independently approved GitHub-hosted
job. The unchanged reviewed monitor owns every child, timeout and cleanup.
"""
from pathlib import Path, PurePosixPath
import argparse
import hashlib
import importlib.util
import json
import math
import os
import re
import sys
import zipfile

MONITOR_SHA = '4c7802bcfb53a2f73f501635cdf483e1459d3d86eb881a7450dccd3bbd705d50'
ENGINE_SHA = 'f64d4ed19fc9df9440321653fcc80df8c6e365ba7b6de0a29e2cfa9fa71bfeb3'
ENGINE_VERSION = '4.6.3.stable.official.7d41c59c4'
SOURCE_LOCK_SHA = '4b9d3be677442f8dad17cf01d14885be33540442f5f8730afd99064b3136d6df'
LOADED_ADAPTER_SHA = hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
KINDS = ('villager', 'spearman', 'archer', 'scout')
COMMON = {'idle', 'walk', 'attack', 'hit', 'death'}
VILLAGER_EXTRA = {'carry_walk', 'gather_wood', 'gather_food', 'build', 'repair'}
NATIVE = {f'assets/mature/models/{k}_action.scn' for k in KINDS}
IMPORT_REPORT = 'reports/native-action-import.json'
TEST_REPORT = 'reports/action-character-tests.json'
BUILD_REPORT = 'reports/build-manifest.json'
RULES = 'scripts/rules.gd'
BUILD_RE = rb'const BUILD_ID = "[^"]*"'
MATURE_SUFFIXES = {'.gd', '.scn', '.tscn', '.tres', '.res', '.png', '.jpg', '.jpeg', '.webp', '.svg', '.import', '.uid', '.gdshader', '.shader'}


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def sha(path):
    with Path(path).open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def read_json(path):
    def invalid(value):
        raise ValueError('Nonfinite JSON: ' + value)
    return json.loads(Path(path).read_text(), parse_constant=invalid)


def write_json(path, value):
    with Path(path).open('x') as stream:
        json.dump(value, stream, indent=2, allow_nan=False)
        stream.write('\n')


def relative(name):
    require(type(name) is str and name and '\\' not in name, 'Invalid relative name')
    p = PurePosixPath(name)
    require(not p.is_absolute() and all(x not in ('', '.', '..') for x in name.split('/')), 'Unsafe relative name')
    return name


def clean_path(path):
    path = Path(path).absolute()
    require(not any(p.is_symlink() for p in (path, *path.parents)), 'Symlink path forbidden: ' + str(path))
    return path.resolve()


def checked(path, digest):
    path = clean_path(path)
    require(path.is_file() and sha(path) == digest, 'Missing or changed bound file: ' + str(path))
    return path


def inventory(root):
    require(root.is_dir() and not root.is_symlink(), 'Missing/nonregular project root')
    found = {}
    for path in root.rglob('*'):
        require(not path.is_symlink(), 'Symlink in project: ' + str(path))
        require(path.is_file() or path.is_dir(), 'Special project file forbidden')
        if path.is_file():
            found[relative(path.relative_to(root).as_posix())] = sha(path)
    return dict(sorted(found.items()))


def require_exact(actual, expected, context):
    require(actual == expected, context + ': missing=' + str(sorted(set(expected)-set(actual)))
            + ', unexpected=' + str(sorted(set(actual)-set(expected)))
            + ', changed=' + str(sorted(n for n in actual.keys() & expected.keys() if actual[n] != expected[n])))


def transition(before, after, allowed_new=(), mutable=(), allow_initial_cache=False):
    allowed_new, mutable = set(allowed_new), set(mutable)
    require(set(before) <= set(after), 'Phase deleted a project file')
    for name, digest in before.items():
        require(name in mutable or after[name] == digest, 'Phase changed forbidden file: ' + name)
    for name in set(after)-set(before):
        require(name in allowed_new or (allow_initial_cache and name.startswith('.godot/')), 'Unexpected phase write: ' + name)
    return after


def clips_for(kind):
    return COMMON | (VILLAGER_EXTRA if kind == 'villager' else set())


def validate_import_report(project, manifest):
    report = read_json(project / IMPORT_REPORT)
    require(type(report) is dict and set(report) == set(KINDS), 'Wrong native import coverage')
    for kind in KINDS:
        unit, expected = report[kind], manifest['units'][kind]
        require(unit['source_glb_sha256'] == expected['glb_sha256'], 'Native GLB identity differs')
        require(unit['native_sha256'] == sha(project / f'assets/mature/models/{kind}_action.scn'), 'Native scene identity differs')
        for key, expected_value in [('bones', len(expected['bones'])), ('triangles', expected['triangles']), ('surfaces', 2)]:
            require(type(unit.get(key)) is int and unit[key] == expected_value, 'Native count differs: ' + key)
        require(set(unit['clips']) - {'RESET'} == clips_for(kind), 'Native clip coverage differs')
        for clip, data in unit['clips'].items():
            require(type(data.get('seconds')) in (int, float) and math.isfinite(data['seconds']) and data['seconds'] > 0, 'Invalid clip time')
            require(type(data.get('tracks')) is list and data['tracks'] and all(type(p) is str and ':' in p for p in data['tracks']), 'Non-joint clip paths')
    return report


def validate_test_report(project, manifest):
    report = read_json(project / TEST_REPORT)
    require(type(report.get('failed')) is int and report['failed'] == 0, 'Native checks report failure')
    rows = report.get('checks')
    require(type(rows) is list and len(rows) == 128, 'Native check count differs from exact source')
    require(all(type(r) is dict and type(r.get('pass')) is bool and r['pass'] and type(r.get('name')) is str for r in rows), 'Failed/malformed native check')
    require(len({r['name'] for r in rows}) == 128, 'Duplicate native check names')
    poses = report.get('pose_evidence')
    require(type(poses) is dict and set(poses) == set(KINDS), 'Missing per-class native evidence')
    for kind, clips in poses.items():
        require(set(clips) == clips_for(kind), 'Missing per-action native evidence')
        scene = f'assets/mature/models/{kind}_action.scn'
        for clip, pose in clips.items():
            require(pose['kind'] == kind and pose['clip'] == clip and pose['asset_path'] == 'res://' + scene, 'Native pose identity differs')
            require(pose['asset_sha256'] == sha(project / scene), 'Native pose source differs')
            require(type(pose['bone_count']) is int and pose['bone_count'] == len(manifest['units'][kind]['bones']), 'Native bone count differs')
            require(type(pose['poses']) is list and len(pose['poses']) == pose['bone_count'], 'Native compact transforms missing')
            require({p['bone'] for p in pose['poses']} == set(manifest['units'][kind]['bones']), 'Native bone names differ')
            require(all(type(p.get('pose')) is str and not re.search(r'(?i)\b(?:nan|inf|infinity)\b', p['pose']) for p in pose['poses']), 'Invalid native transform serialization')
            require(re.fullmatch('[0-9a-f]{64}', pose['pose_sha256']) is not None, 'Invalid pose digest')
            serialized = json.dumps(pose['poses'], sort_keys=True, ensure_ascii=False, separators=(',', ':'))
            require(hashlib.sha256(serialized.encode()).hexdigest() == pose['pose_sha256'], 'Native pose digest does not bind transforms')
            require(type(pose['seek_seconds']) in (int, float) and math.isfinite(pose['seek_seconds']) and pose['seek_seconds'] > 0, 'Invalid sampled pose time')
    return report


def runtime_names(names):
    selected = {'project.godot', 'main.tscn', 'export_presets.cfg'}
    folders = {'scripts/': {'.gd', '.uid'}, 'assets/audio/': {'.wav', '.import'},
               'assets/models/': {'.glb', '.import'}, 'assets/fonts/': {'.otf', '.ttf', '.import'},
               'assets/mature/': MATURE_SUFFIXES}
    for name in names:
        for folder, suffixes in folders.items():
            if name.startswith(folder) and Path(name).suffix.lower() in suffixes:
                if folder == 'assets/mature/' and any(name.lower().endswith(x + '.import') for x in ('.glb', '.gltf', '.blend')):
                    continue
                selected.add(name)
    return selected


def validate_stamp(project, original_rules, project_files):
    report = read_json(project / BUILD_REPORT)
    require(report.get('engine') == ENGINE_VERSION, 'Stamped engine differs')
    names = runtime_names(project_files)
    require(NATIVE <= names and set(report['source_sha256']) == names, 'Runtime stamp scope differs')
    h = hashlib.sha256()
    for name in sorted(names):
        data = (project / name).read_bytes()
        require(hashlib.sha256(data).hexdigest() == report['source_sha256'][name], 'Runtime manifest hash differs')
        if name == RULES:
            require(len(re.findall(BUILD_RE, data)) == 1, 'Ambiguous BUILD_ID')
            data = re.sub(BUILD_RE, b'const BUILD_ID = "normalized"', data)
        h.update(name.encode()); h.update(b'\0'); h.update(data)
    build = 'vc-' + h.hexdigest()[:12]
    require(report['build'] == build and build not in ('vc-8fcc302051f0', 'vc-eb734476b9f1'), 'Inherited or invalid runtime identity')
    expected_rules = re.sub(BUILD_RE, ('const BUILD_ID = "' + build + '"').encode(), original_rules)
    require((project / RULES).read_bytes() == expected_rules, 'Stamp changed normalized rule logic')
    return report


def validate_receipt(output, name, argv, artifacts, expected):
    path = output / (name + '.json')
    invocation_path = output / (name + '.invocation.json')
    result, invocation = read_json(path), read_json(invocation_path)
    require(result.get('passed') is True and result.get('cleanup_complete') is True and result.get('child_started') is True
            and type(result.get('exit')) is int and result['exit'] == 0, 'Guarded process did not pass: ' + name)
    require(not any(result.get(k) for k in ('stop_reason', 'exception', 'cleanup_errors', 'output_errors')), 'Guarded process evidence has errors')
    require(result.get('log_sha256') == sha(output / (name + '.log')) and result.get('invocation_sha256') == sha(invocation_path), 'Guard receipt content binding failed')
    require(invocation.get('test_dependencies') is False and invocation.get('requested_argv') == argv and invocation.get('argv') == argv, 'Wrong or injected invocation')
    require(invocation['helper']['load_sha256'] == invocation['helper']['invocation_sha256'] == MONITOR_SHA, 'Wrong monitor provenance')
    require(set(invocation['artifacts']) == set(artifacts), 'Missing bound phase inputs')
    for key, path_in in artifacts.items():
        require(invocation['artifacts'][key] == {'path': str(path_in.resolve()), 'sha256': expected[key]}, 'Wrong bound phase input: ' + key)
    bindings = result.get('post_run_binding_matches', {})
    require({'helper', 'executable'} | {'artifact:' + k for k in artifacts} <= set(bindings), 'Missing post-run bindings')
    require(all(v is True for v in bindings.values()), 'Post-run artifact drift')
    return result


def export_runtime_delta(project, output, initial, final, generated_uids, build):
    accepted = output / 'accepted-runtime'; accepted.mkdir()
    delta = NATIVE | {RULES, BUILD_REPORT} | (set(final) & set(generated_uids))
    lock_names = set(initial) | delta
    final_lock = {'build': build, 'scope': 'Exact reassembly of initial158-file source plus reviewed native runtime delta, excluding caches/private/test outputs',
                  'source_input_lock_sha256': SOURCE_LOCK_SHA,
                  'files': [{'file': n, 'sha256': final[n], 'size': (project/n).stat().st_size} for n in sorted(lock_names)]}
    write_json(accepted / 'final-source-lock.json', final_lock)
    archive = accepted / 'runtime-delta.zip'
    with zipfile.ZipFile(archive, 'x', compression=zipfile.ZIP_DEFLATED, compresslevel=6) as z:
        for name in sorted(delta):
            info = zipfile.ZipInfo(name, date_time=(2026, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED; info.external_attr = 0o100644 << 16
            z.writestr(info, (project/name).read_bytes())
    with zipfile.ZipFile(archive) as z:
        require(z.testzip() is None and set(z.namelist()) == delta, 'Runtime delta ZIP invalid')
        require(all(hashlib.sha256(z.read(n)).hexdigest() == final[n] for n in delta), 'Runtime delta member changed')
    receipt = {'build': build, 'archive_sha256': sha(archive), 'archive_bytes': archive.stat().st_size,
               'member_sha256': {n: final[n] for n in sorted(delta)},
               'final_source_lock_sha256': sha(accepted/'final-source-lock.json'),
               'scope': 'Native import/current-class playback prototype only; no rendered art, phone performance, full combined gameplay regression or deployment acceptance'}
    write_json(accepted / 'receipt.json', receipt)
    return receipt


def run(args):
    require(args.hosted_execution_approved and os.environ.get('GITHUB_ACTIONS') == 'true'
            and os.environ.get('RUNNER_ENVIRONMENT') == 'github-hosted', 'Reviewed GitHub-hosted execution only; never local/self-hosted')
    project, output, private = (clean_path(getattr(args, n)) for n in ('project', 'output', 'private'))
    require(all(not a.is_relative_to(b) and not b.is_relative_to(a) for a, b in ((project, output), (project, private), (output, private))), 'Project/evidence/private roots must be disjoint')
    require(not output.exists() and not private.exists(), 'Fresh evidence/private roots required')
    lock_path = checked(args.source_lock, SOURCE_LOCK_SHA)
    engine = checked(args.godot, ENGINE_SHA)
    monitor_path = checked(args.monitor, MONITOR_SHA)
    lock = read_json(lock_path)
    initial = {relative(r['file']): r['sha256'] for r in lock['files']}
    require(len(initial) == len(lock['files']) == 158 and lock['execution_enabled'] is False, 'Wrong closed source lock')
    require_exact(inventory(project), initial, 'Initial source inventory')
    require((project/'art/.gdignore').read_bytes() == b'', 'Editable source not safely ignored')
    generated_uids = {n+'.uid' for n in initial if n.endswith(('.gd', '.gdshader')) and n+'.uid' not in initial}
    original_rules = (project/RULES).read_bytes()
    require(len(re.findall(BUILD_RE, original_rules)) == 1, 'Ambiguous original rules identity')
    manifest = read_json(project/'reports/asset_manifest.json')
    require(set(manifest['units']) == set(KINDS), 'Wrong authored class coverage')
    output.mkdir(); private.mkdir()
    env = {k: os.environ[k] for k in ('PATH', 'LANG', 'LC_ALL', 'TZ') if k in os.environ}
    for key, name in [('HOME', 'home'), ('TMPDIR', 'tmp'), ('XDG_DATA_HOME', 'data'), ('XDG_CONFIG_HOME', 'config'), ('XDG_CACHE_HOME', 'cache')]:
        folder = private/name; folder.mkdir(); env[key] = str(folder)
    env.update({'GODOT_SILENCE_ROOT_WARNING': '1', 'OMP_NUM_THREADS': '1', 'OPENBLAS_NUM_THREADS': '1',
                'PYTHONDONTWRITEBYTECODE': '1'})
    spec = importlib.util.spec_from_file_location('native_stage_reviewed_monitor', monitor_path)
    monitor = importlib.util.module_from_spec(spec); sys.modules[spec.name] = monitor; spec.loader.exec_module(monitor)
    limits = monitor.Limits(timeout_s=300, sample_target_s=.05, terminate_grace_s=5, kill_reap_grace_s=5,
                            launch_min_available_kib=4194304, runtime_min_available_kib=1048576, max_rss_kib=2097152)
    current = dict(initial)
    frozen_evidence = {}
    controls = {'adapter': (Path(__file__).resolve(), LOADED_ADAPTER_SHA),
                'monitor': (monitor_path, MONITOR_SHA), 'engine': (engine, ENGINE_SHA),
                'python': (Path(sys.executable).resolve(), sha(Path(sys.executable).resolve())),
                'source-lock': (lock_path, SOURCE_LOCK_SHA)}
    summary = {'passed': False, 'runtime_build': None, 'source_lock_sha256': SOURCE_LOCK_SHA, 'commands': [],
               'scope': 'Guarded native pack/reload/current-class contracts only; no full combined gameplay, rendered, Web, device or deployment acceptance'}

    def save():
        (output/'summary.json').write_text(json.dumps(summary, indent=2, allow_nan=False)+'\n')

    def invoke(name, argv, allowed_new=(), mutable=(), initial_cache=False, sentinel=None):
        nonlocal current
        require_exact(inventory(project), current, 'Before '+name)
        snapshot = output/(name+'.before.json'); write_json(snapshot, current)
        artifacts = {key: checked(path, digest) for key, (path, digest) in controls.items()}
        expected = {key: digest for key, (path, digest) in controls.items()}
        artifacts['phase-input-inventory'] = snapshot; expected['phase-input-inventory'] = sha(snapshot)
        artifacts.update({'project:'+n: project/n for n in current if n not in set(mutable)})
        expected.update({'project:'+n: digest for n, digest in current.items() if n not in set(mutable)})
        artifacts.update({'prior-evidence:'+n: output/n for n in frozen_evidence})
        expected.update({'prior-evidence:'+n: digest for n, digest in frozen_evidence.items()})
        for n, h in frozen_evidence.items(): checked(output/n, h)
        summary['active_phase'] = name; save()
        print('START '+name, flush=True)
        monitor.run(output/name, argv, env=env, limits=limits, artifacts=artifacts, expected_artifact_hashes=expected)
        result = validate_receipt(output, name, argv, artifacts, expected)
        if sentinel:
            require(sentinel in (output/(name+'.log')).read_text(), 'Missing phase success marker: '+name)
        after = inventory(project)
        transition(current, after, allowed_new, mutable, initial_cache)
        current = after
        row = {k: result[k] for k in ('passed', 'exit', 'cleanup_complete', 'stop_reason', 'seconds', 'sampled_peak_rss_kib')}
        row.update(name=name, before_inventory_sha256=sha(snapshot), receipt_sha256=sha(output/(name+'.json')),
                   invocation_sha256=sha(output/(name+'.invocation.json')), log_sha256=sha(output/(name+'.log')))
        summary['commands'].append(row)
        summary['active_phase'] = None
        for suffix in ('.before.json', '.json', '.invocation.json', '.log'):
            frozen_evidence[name+suffix] = sha(output/(name+suffix))
        save()
        return row

    def preserve_report(name, relative_path, data):
        destination = output/(name+'.report.json')
        with destination.open('xb') as stream: stream.write((project/relative_path).read_bytes())
        frozen_evidence[destination.name] = sha(destination)
        summary['commands'][-1]['validated_report'] = {'sha256': sha(destination), 'path': destination.name,
                                                       'class_count': len(KINDS), 'clip_count': 25}
        save()

    save()
    try:
        godot = [str(engine), '--headless', '--path', str(project)]
        invoke('import', godot+['--editor', '--import'], generated_uids, initial_cache=True)
        require(any(n.startswith('.godot/imported/') for n in current), 'Clean import produced no cache')
        # Native scene saves may update only the UID registry, not imported assets.
        invoke('native-pack', godot+['--script', 'res://tools/import_action_characters.gd'],
               NATIVE | {IMPORT_REPORT, '.godot/uid_cache.bin'}, {'.godot/uid_cache.bin'}, sentinel='ACTION_CHARACTER_IMPORT_PASS ')
        native_report = validate_import_report(project, manifest)
        preserve_report('native-pack', IMPORT_REPORT, native_report)
        invoke('reload-diagnostic', godot+['--script', 'res://tests/action_characters.gd'],
               {TEST_REPORT}, sentinel='ACTION_CHARACTER_TESTS 128 failed=0')
        diagnostic = validate_test_report(project, manifest)
        preserve_report('reload-diagnostic', TEST_REPORT, diagnostic)
        # Preserve the validated pre-stamp report before making room for a fresh
        # final report. No user/source data is removed, and the hash is checked.
        checked(project/TEST_REPORT, current[TEST_REPORT]).unlink(); current.pop(TEST_REPORT)
        invoke('stamp', [str(Path(sys.executable).resolve()), str(project/'tools/stamp_build.py'), '--root', str(project)],
               {BUILD_REPORT}, {RULES})
        stamped = validate_stamp(project, original_rules, current)
        summary['runtime_build'] = stamped['build']
        preserve_report('stamp', BUILD_REPORT, stamped)
        invoke('reload-final', godot+['--script', 'res://tests/action_characters.gd'],
               {TEST_REPORT}, sentinel='ACTION_CHARACTER_TESTS 128 failed=0')
        final_report = validate_test_report(project, manifest)
        preserve_report('reload-final', TEST_REPORT, final_report)
        validate_stamp(project, original_rules, current)
        require_exact(inventory(project), current, 'Final source/cache inventory')
        summary['runtime_delivery'] = export_runtime_delta(project, output, initial, current, generated_uids, stamped['build'])
        summary['passed'] = True; save(); return 0
    except BaseException as exc:
        summary['error'] = {'type': type(exc).__name__, 'message': str(exc)}
        save(); print(json.dumps(summary['error']), flush=True); return 1


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('project', 'source-lock', 'godot', 'monitor', 'output', 'private'):
        parser.add_argument('--'+name, type=Path, required=True)
    parser.add_argument('--hosted-execution-approved', action='store_true')
    return run(parser.parse_args())


if __name__ == '__main__':
    sys.exit(main())

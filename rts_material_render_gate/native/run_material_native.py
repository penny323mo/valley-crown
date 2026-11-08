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
SOURCE_LOCK_SHA = None  # Bound only by the reviewed material input contract.
BASELINE_SHA = '36e6441b6dac681d4194a6d21e14c18660b38ea7082c1cddc7d9e48e5b07a93c'
GENERATOR_SHA = None  # Final regenerated generator provenance awaits peer review.
IMPORTER_SHA = '648e439a934ff6ab6cfcb721d572a119f6d2a986fc777003bd18a2b9651d2621'
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
            require(type(data.get('tracks')) is list and len(data['tracks']) == len(expected['bones'])*3 and all(type(p) is str and ':' in p for p in data['tracks']), 'Missing or non-joint clip paths')
            channels = data.get('joint_trs')
            require(type(channels) is dict and set(channels) == set(expected['bones']), 'Missing joint TRS coverage')
            for bone, types in channels.items():
                require(type(types) is list and len(types) == 3 and all(type(t) is int for t in types) and set(types) == {1,2,3}, 'Incomplete joint TRS types')
                require(sum(p.split(':')[-1] == bone for p in data['tracks']) == 3, 'Joint path/type coverage mismatch')
    return report


def validate_test_report(project, manifest):
    report = read_json(project / TEST_REPORT)
    require(type(report.get('failed')) is int and report['failed'] == 0, 'Native checks report failure')
    rows = report.get('checks')
    require(type(rows) is list and len(rows) == 153, 'Native check count differs from exact source')
    require(all(type(r) is dict and type(r.get('pass')) is bool and r['pass'] and type(r.get('name')) is str for r in rows), 'Failed/malformed native check')
    require(len({r['name'] for r in rows}) == 153, 'Duplicate native check names')
    transitions = report.get('tool_transitions')
    sequence = ['idle','gather_wood','idle','gather_food','build','repair','attack','carry_walk','walk','idle']
    require(type(transitions) is list and len(transitions) == len(sequence), 'Missing tool transitions')
    for index, clip in enumerate(sequence):
        row = transitions[index]
        require(type(row.get('index')) is int and row['index'] == index and row.get('clip') == clip, 'Wrong tool transition sequence')
        data = row.get('tools', {})
        active = {'attack':'axe','gather_wood':'axe','gather_food':'sickle','build':'hammer','repair':'hammer'}.get(clip, '')
        require(data.get('pass') is True and data.get('active') == active and set(data.get('scales', {})) == {'axe','hammer','sickle'}, 'Failed tool transition')
        for prop, scale in data['scales'].items():
            expected = 1.0 if prop == active else .001
            require(type(scale) is list and len(scale) == 3 and all(type(x) in (int,float) and math.isfinite(x) and abs(x-expected) <= 1e-5 for x in scale), 'Incorrect tool scale')
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
    require(report['build'] == build and build not in ('vc-fe500d2ea0b5', 'vc-8fcc302051f0', 'vc-eb734476b9f1', 'vc-f659b53824e3'), 'Inherited or invalid runtime identity')
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
    final_lock = {'build': build, 'scope': 'Exact reassembly of assembled192-file source plus reviewed native runtime delta, excluding caches/private/test outputs',
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



GENERATED_MUTABLE = {f'art/action_characters/{k}.blend' for k in KINDS} | {f'art/action_characters/interchange/{k}.glb' for k in KINDS} | {f'art/action_characters/textures/{k}_atlas.png' for k in KINDS} | {'reports/asset_manifest.json'}
IMMUTABLE_GENERATED = {'art/action_characters/input-manifest.json'} | {f'art/action_characters/licenses/{n}.txt' for n in ('kaykit-animations','quaternius-base','quaternius-outfits','quaternius-ual','quaternius-ual2')}

def bind_material_inputs(args):
    global SOURCE_LOCK_SHA, GENERATOR_SHA
    contract_path = checked(args.inputs, args.inputs_sha256)
    contract = read_json(contract_path)
    require(contract.get('execution_enabled') is True, 'Material native execution remains disabled')
    for key in ('generated_inventory_sha256','asset_manifest_sha256','assembled_source_lock_sha256','review_pin_sha256','probe_sha256','generator_sha256'):
        require(type(contract.get(key)) is str and re.fullmatch('[0-9a-f]{64}',contract[key]), 'Unbound material input: '+key)
    review_path = checked(args.review_pin, contract['review_pin_sha256'])
    review = read_json(review_path)
    require(review.get('peer_reviewed') is True and review.get('adapter_sha256') == LOADED_ADAPTER_SHA and review.get('probe_sha256') == contract['probe_sha256'], 'Unreviewed adapter/probe')
    base_path = checked(args.baseline_lock, BASELINE_SHA)
    base = read_json(base_path)
    require(base['build'] == 'vc-fe500d2ea0b5' and len(base['files']) == 192, 'Wrong accepted baseline')
    generated_lock_path = checked(args.generated_inventory, contract['generated_inventory_sha256'])
    generated = read_json(generated_lock_path)
    require(type(generated) is dict and set(generated) == GENERATED_MUTABLE | IMMUTABLE_GENERATED and len(generated)==19, 'Generated inventory must be exact19')
    require_exact(inventory(clean_path(args.generated)), generated, 'Generated artifact inventory')
    require(all(generated[n] == base['files'][n] for n in IMMUTABLE_GENERATED), 'Generated license/input provenance changed')
    require(generated['reports/asset_manifest.json'] == contract['asset_manifest_sha256'], 'Generated manifest not bound')
    GENERATOR_SHA = contract['generator_sha256']
    require(review.get('generator_sha256') == GENERATOR_SHA, 'Generator provenance not peer reviewed')
    SOURCE_LOCK_SHA = contract['assembled_source_lock_sha256']
    lock = read_json(checked(args.source_lock,SOURCE_LOCK_SHA))
    assembled = {relative(r['file']):r['sha256'] for r in lock['files']}
    expected = dict(base['files']); expected.update({n:generated[n] for n in GENERATED_MUTABLE})
    expected['tools/build_licensed_action_characters.py'] = GENERATOR_SHA
    require(len(assembled)==len(lock['files'])==192, 'Assembled source must remain192')
    require_exact(assembled,expected,'Only generated material inputs and pinned generator may change')
    require(assembled['tools/import_action_characters.gd']==IMPORTER_SHA,'Importer drift')
    require(review.get('assembled_source_lock_sha256') == SOURCE_LOCK_SHA and review.get('generated_inventory_sha256') == contract['generated_inventory_sha256'], 'Review does not bind actual generated/source inputs')
    probe = checked(args.probe,contract['probe_sha256'])
    return {'material-inputs':(contract_path,args.inputs_sha256),'review-pin':(review_path,contract['review_pin_sha256']), 'baseline-lock':(base_path,BASELINE_SHA),'generated-inventory':(generated_lock_path,contract['generated_inventory_sha256']),'material-probe':(probe,contract['probe_sha256'])}


def validate_material_report(project):
    report=read_json(project/'reports/native-material-proof.json')
    require(type(report) is dict and set(report)==set(KINDS),'Missing material class proof')
    for kind,row in report.items():
        require(row.get('passed') is True and row.get('native_sha256')==sha(project/f'assets/mature/models/{kind}_action.scn'),'Material native identity differs')
        require(row.get('atlas_sha256')==sha(project/f'art/action_characters/textures/{kind}_atlas.png'),'Material atlas identity differs')
        require(row.get('rgba_equal') is True and row.get('uv0') is True and row.get('white_body_vertex_tint') is True and row.get('source_prop_tint_equal') is True and row.get('team_unchanged') is True,'Material probe failed')
        require(row.get('source_glb_sha256') == sha(project/f'art/action_characters/interchange/{kind}.glb'), 'Probe source GLB identity differs')
        require(type(row.get('native_rgba_sha256')) is str and re.fullmatch('[0-9a-f]{64}',row['native_rgba_sha256']) and row['native_rgba_sha256'] == row.get('atlas_rgba_sha256'), 'Missing/differing normalized image hashes')
        require(row.get('dimensions') == [1024,1024], 'Native texture size differs')
        require(all(type(row.get(k)) is int and row[k] > 0 for k in ('body_vertices','prop_vertices','field_vertices')), 'Missing actual field/prop counts')
        require(row['field_vertices'] == row['body_vertices'] + row['prop_vertices'] and row.get('field_surfaces') == row.get('team_surfaces') == 1, 'Material surface/vertex counts differ')
        state = row.get('field_state',{})
        require(state.get('vertex_tint') is True and state.get('albedo_rgba') == [1,1,1,1] and state.get('uv1_triplanar') is False and state.get('uv1_scale') == [1,1,1] and state.get('uv1_offset') == [0,0,0], 'Unexpected field material state')
        require(type(state.get('roughness')) in (int,float) and abs(state['roughness']-.94)<1e-5 and type(state.get('specular')) in (int,float) and abs(state['specular']-.15)<1e-5,'Field material roughness/specular drift')
    return report

def expected_phase_argv(paths):
    require(type(paths) is dict and set(paths) == {'project','engine','python','probe'}, 'Missing reviewed hosted execution paths')
    require(all(type(p) is str and Path(p).is_absolute() and '..' not in Path(p).parts for p in paths.values()), 'Invalid hosted execution path')
    godot = [paths['engine'],'--headless','--path',paths['project']]
    return {
        'import':godot+['--editor','--import'],
        'material-baseline':godot+['--script',paths['probe'],'--','--baseline'],
        'native-pack':godot+['--script','res://tools/import_action_characters.gd'],
        'reload-diagnostic':godot+['--script','res://tests/action_characters.gd'],
        'material-proof':godot+['--script',paths['probe']],
        'stamp':[paths['python'],str(Path(paths['project'])/'tools/stamp_build.py'),'--root',paths['project']],
        'reload-final':godot+['--script','res://tests/action_characters.gd'],
    }

def run(args):
    material_controls = bind_material_inputs(args)
    review = read_json(args.review_pin)
    expected_commands = expected_phase_argv(review.get('execution_paths'))
    require(review['execution_paths'] == {'project':str(clean_path(args.project)), 'engine':str(clean_path(args.godot)), 'python':str(Path(sys.executable).resolve()), 'probe':str(clean_path(args.probe))}, 'Hosted execution paths differ from review')
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
    require(len(initial) == len(lock['files']) == 192 and lock['execution_enabled'] is False, 'Wrong closed source lock')
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
    controls.update(material_controls)
    summary = {'passed': False, 'runtime_build': None, 'source_lock_sha256': SOURCE_LOCK_SHA, 'commands': [],
               'scope': 'Guarded native pack/reload/current-class contracts only; no full combined gameplay, rendered, Web, device or deployment acceptance'}

    def save():
        (output/'summary.json').write_text(json.dumps(summary, indent=2, allow_nan=False)+'\n')

    def invoke(name, argv, allowed_new=(), mutable=(), initial_cache=False, sentinel=None):
        nonlocal current
        require(argv == expected_commands[name], 'Invocation differs from reviewed phase argv')
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
        invoke('material-baseline', godot+['--script', str(controls['material-probe'][0]), '--', '--baseline'], {'reports/native-material-baseline.json'}, sentinel='NATIVE_MATERIAL_BASELINE_PASS')
        material_baseline = read_json(project/'reports/native-material-baseline.json')
        require(set(material_baseline) == set(KINDS), 'Missing baseline material coverage')
        for kind in KINDS:
            require(material_baseline[kind]['native_sha256'] == initial[f'assets/mature/models/{kind}_action.scn'], 'Baseline material scene drift')
        preserve_report('material-baseline', 'reports/native-material-baseline.json', material_baseline)
        # Native scene saves may update only the UID registry, not imported assets.
        invoke('native-pack', godot+['--script', 'res://tools/import_action_characters.gd'],
               NATIVE | {IMPORT_REPORT, '.godot/uid_cache.bin'}, NATIVE | {'.godot/uid_cache.bin'}, sentinel='ACTION_CHARACTER_IMPORT_PASS ')
        native_report = validate_import_report(project, manifest)
        preserve_report('native-pack', IMPORT_REPORT, native_report)
        invoke('reload-diagnostic', godot+['--script', 'res://tests/action_characters.gd'],
               {TEST_REPORT}, sentinel='ACTION_CHARACTER_TESTS 153 failed=0')
        diagnostic = validate_test_report(project, manifest)
        preserve_report('reload-diagnostic', TEST_REPORT, diagnostic)
        invoke('material-proof', godot+['--script', str(controls['material-probe'][0])], {'reports/native-material-proof.json'}, sentinel='NATIVE_MATERIAL_PROOF_PASS')
        preserve_report('material-proof', 'reports/native-material-proof.json', validate_material_report(project))
        # Preserve the validated pre-stamp report before making room for a fresh
        # final report. No user/source data is removed, and the hash is checked.
        checked(project/TEST_REPORT, current[TEST_REPORT]).unlink(); current.pop(TEST_REPORT)
        invoke('stamp', [str(Path(sys.executable).resolve()), str(project/'tools/stamp_build.py'), '--root', str(project)],
               {BUILD_REPORT}, {RULES, BUILD_REPORT})
        stamped = validate_stamp(project, original_rules, current)
        summary['runtime_build'] = stamped['build']
        preserve_report('stamp', BUILD_REPORT, stamped)
        invoke('reload-final', godot+['--script', 'res://tests/action_characters.gd'],
               {TEST_REPORT}, sentinel='ACTION_CHARACTER_TESTS 153 failed=0')
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
    for name in ('project', 'source-lock', 'godot', 'monitor', 'output', 'private', 'inputs', 'review-pin', 'baseline-lock', 'generated-inventory', 'generated', 'probe'):
        parser.add_argument('--'+name, type=Path, required=True)
    parser.add_argument('--inputs-sha256', required=True)
    parser.add_argument('--hosted-execution-approved', action='store_true')
    return run(parser.parse_args())


if __name__ == '__main__':
    sys.exit(main())

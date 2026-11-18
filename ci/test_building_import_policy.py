"""Inert synthetic parser negatives. Fixtures are NOT generated engine evidence.

No engine, subprocess, monitor, browser, resource telemetry or network is used.
Temporary synthetic descriptors/cache signatures test rejection behavior only.
"""
from pathlib import Path
import hashlib
import json
import tempfile
import types
import unittest
from unittest.mock import patch
import building_import_policy as p
import guarded_manifest_ci as adapter

ROOT = Path(__file__).resolve().parents[1]


class PolicyTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='synthetic-policy-test-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name) / 'project'; self.root.mkdir()
        self.entries = {}
        for kind in p.PAIRS:
            for suffix in ('.gltf', '.bin'):
                name = p.PREFIX + kind + suffix
                path = self.root / name; path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes((ROOT / 'game' / name).read_bytes()); self.entries[name] = p.digest(path)
        (self.root / 'art').mkdir(); (self.root / 'art/.gdignore').write_bytes(b'')
        self.entries['art/.gdignore'] = p.digest(self.root / 'art/.gdignore')
        self.fixture = (ROOT / 'game/assets/models/house.glb.import').read_text()

    def synthetic(self, kind='stable'):
        name = p.PREFIX + kind + '.gltf'; uri = 'res://' + name
        dest = 'res://.godot/imported/' + kind + '.gltf-' + hashlib.md5(uri.encode()).hexdigest() + '.scn'
        uid = 'uid://' + 'bcde'[list(p.PAIRS).index(kind)]
        return (self.fixture.replace('res://assets/models/house.glb', uri)
                .replace('res://.godot/imported/house.glb-1974b53afbc06013dc2fc6f61f1c678d.scn', dest)
                .replace('uid://cnbmabb8x7c7u', uid)).encode()

    def plant(self, kind='stable'):
        data = self.synthetic(kind); name = p.PREFIX + kind + '.gltf'
        (self.root / (name + '.import')).write_bytes(data)
        row = p.parse(data, name); scene = self.root / row['compiled']; scene.parent.mkdir(parents=True, exist_ok=True)
        # This is deliberately not a real compiled scene. Only signature/hash
        # validation is exercised; no loader ever consumes the fixture.
        scene.write_bytes(b'RSCCsynthetic-unit-fixture-not-a-Godot-scene')
        md5 = scene.with_suffix('.md5')
        md5.write_text('source_md5="' + p.digest(self.root / name, 'md5') + '"\n' +
                       'dest_md5="' + p.digest(scene, 'md5') + '"\n\n')
        return row

    def reject(self, data):
        with self.assertRaises((ValueError, UnicodeError)):
            p.parse(data, p.PREFIX + 'stable.gltf')

    def test_exact_creation_paths(self):
        self.assertEqual(p.expected(self.entries), {p.PREFIX + k + '.gltf.import' for k in p.PAIRS})
        self.assertEqual(adapter.inventory(self.root, self.entries), {})

    def test_source_binding_negatives(self):
        for key in self.entries:
            bad = dict(self.entries); bad[key] = '0' * 64
            with self.subTest(key=key), self.assertRaises(ValueError): p.expected(bad)
        for kind in p.PAIRS:
            bad = dict(self.entries); bad[p.PREFIX + kind + '.gltf.import'] = '0' * 64
            with self.subTest(kind=kind), self.assertRaises(ValueError): p.expected(bad)

    def test_four_synthetic_schema_fixtures(self):
        for kind in p.PAIRS:
            row = p.parse(self.synthetic(kind), p.PREFIX + kind + '.gltf')
            self.assertEqual(row['source'], p.PREFIX + kind + '.gltf')

    def test_malformed_or_expanded_descriptors(self):
        good = self.synthetic()
        cases = {
            'duplicate key': good.replace(b'importer="scene"', b'importer="scene"\nimporter="scene"'),
            'duplicate section': good + b'[params]\n',
            'section order': good.replace(b'[remap]', b'[deps]', 1),
            'unknown key': good.replace(b'[params]\n', b'[params]\nextra=true\n'),
            'wrong importer': good.replace(b'importer="scene"', b'importer="texture"'),
            'wrong importer version': good.replace(b'importer_version=1', b'importer_version=2'),
            'wrong type': good.replace(b'type="PackedScene"', b'type="Script"'),
            'wrong source': good.replace(b'source_file="res://assets/', b'source_file="res://other/'),
            'path traversal': good.replace(b'res://.godot/imported/', b'res://.godot/../'),
            'external output': good.replace(b'res://.godot/imported/', b'https://invalid.test/'),
            'wrong output digest': good.replace(hashlib.md5(b'res://assets/advanced_buildings/stable.gltf').hexdigest().encode(), b'0' * 32),
            'multiple output': good.replace(b'dest_files=[', b'dest_files=["res://extra", '),
            'unexpected source write': good.replace(b'[deps]\n', b'[deps]\nfiles=["res://evil.gd"]\n'),
            'root script': good.replace(b'nodes/root_script=null', b'nodes/root_script=ExtResource("evil")'),
            'import script': good.replace(b'import_script/path=""', b'import_script/path="res://evil.gd"'),
            'material extraction': good.replace(b'materials/extract=0', b'materials/extract=1'),
            'material output path': good.replace(b'materials/extract_path=""', b'materials/extract_path="res://"'),
            'non-native scale': good.replace(b'nodes/root_scale=1.0', b'nodes/root_scale=2.0'),
            'changed LOD': good.replace(b'meshes/generate_lods=true', b'meshes/generate_lods=false'),
            'subresources': good.replace(b'_subresources={}', b'_subresources={"script": "res://evil.gd"}'),
            'noncanonical float': good.replace(b'nodes/root_scale=1.0', b'nodes/root_scale=1e0'),
            'trailing assignment comment': good.replace(b'importer_version=1', b'importer_version=1 # comment'),
            'carriage return': good.replace(b'\n', b'\r\n'),
            'missing newline': good[:-1],
            'nul': good + b'\0',
            'bad utf8': good + b'\xff\n',
            'oversized': good + b'\n' * 8192,
        }
        for label, data in cases.items():
            with self.subTest(label=label): self.reject(data)

    def test_uid_negatives(self):
        for uid in ['uid://a', 'uid://ab', 'uid://z', 'uid://9', 'uid://8888888888888', 'res://b', 'uid://', 'uid://b/']:
            with self.subTest(uid=uid): self.reject(self.synthetic().replace(b'uid://b', uid.encode()))

    def test_descriptor_collision_and_completeness(self):
        self.plant('stable')
        with self.assertRaises(ValueError): p.descriptors(self.root, self.entries, complete=True)
        self.plant('workshop')
        path = self.root / (p.PREFIX + 'workshop.gltf.import')
        path.write_bytes(path.read_bytes().replace(b'uid://c', b'uid://b'))
        with self.assertRaises(ValueError): p.descriptors(self.root, self.entries)

    def test_generated_script_uid_collision(self):
        self.plant(); path = self.root / 'test.gd'; path.write_text('extends RefCounted\n')
        self.entries['test.gd'] = p.digest(path); (self.root / 'test.gd.uid').write_text('uid://b\n')
        with self.assertRaises(ValueError): p.descriptors(self.root, self.entries)

    def test_source_inventory_remains_immutable(self):
        self.plant()
        # Current adapter accepts only tracked, hash-bound descriptors, never a
        # dynamically created descriptor via the retired building-policy hook.
        with self.assertRaises(RuntimeError): adapter.inventory(self.root, self.entries)
        descriptor = p.PREFIX + 'stable.gltf.import'
        self.entries[descriptor] = p.digest(self.root / descriptor)
        adapter.inventory(self.root, self.entries)
        original = (self.root / descriptor).read_bytes()
        (self.root / descriptor).write_bytes(b'descriptor-drift')
        with self.assertRaises(RuntimeError): adapter.inventory(self.root, self.entries)
        (self.root / descriptor).write_bytes(original)
        path = self.root / 'unplanned.txt'; path.write_text('x')
        with self.assertRaises(RuntimeError): adapter.inventory(self.root, self.entries)
        path.unlink(); path = self.root / (p.PREFIX + 'stable.bin'); path.write_bytes(b'drift')
        with self.assertRaises(RuntimeError): adapter.inventory(self.root, self.entries)

    def test_symlink_descriptor(self):
        target = self.root / 'outside'; target.write_bytes(self.synthetic())
        (self.root / (p.PREFIX + 'stable.gltf.import')).symlink_to(target)
        with self.assertRaises(ValueError): p.descriptors(self.root, self.entries)

    def test_compiled_binding_and_retention(self):
        rows = {kind: self.plant(kind) for kind in p.PAIRS}
        validated = p.validate_outputs(self.root, self.entries); self.assertEqual(len(validated), 4)
        out = Path(self.temp.name) / 'evidence'; out.mkdir()
        retained = p.retain_actual(self.root, out, self.entries)
        self.assertEqual(len(retained['files']), 12); self.assertEqual(retained['errors'], [])
        self.assertFalse(retained['accepted'])
        for name, item in retained['files'].items():
            self.assertEqual((self.root / name).read_bytes(), (out / 'actual-generated' / item['retained']).read_bytes())
        scene = self.root / rows['stable']['compiled']; scene.write_bytes(b'RSCCchanged')
        with self.assertRaises(ValueError): p.validate_outputs(self.root, self.entries)
        scene.write_bytes(b'BAD!changed')
        with self.assertRaises(ValueError): p.validate_outputs(self.root, self.entries)
        scene.unlink()
        with self.assertRaises(ValueError): p.validate_outputs(self.root, self.entries)

    def test_invalid_descriptor_is_retained_only_as_failed_diagnostic(self):
        self.plant(); path = self.root / (p.PREFIX + 'stable.gltf.import'); path.write_bytes(b'invalid-but-actual-unit-fixture\n')
        out = Path(self.temp.name) / 'evidence'; out.mkdir()
        retained = p.retain_actual(self.root, out, self.entries)
        self.assertFalse(retained['accepted']); self.assertTrue(retained['errors'])
        self.assertEqual(path.read_bytes(), (out / 'actual-generated/descriptors/stable.gltf.import').read_bytes())

    def test_monitor_and_download_are_unchanged(self):
        restored=(ROOT / 'ci/hardened_monitored_run.py').read_text()
        for added,removed in reversed([('            raise ValueError(\'Invalid/missing nonnegative integer telemetry: \' + key)\n    return data\n\ndef exit_read(path):\n    with path.open() as stream:\n        value = stream.read(65537)\n    if len(value) > 65536:\n        raise RuntimeError(\'Oversized exit-phase field\')\n    return value\n\nclass ExitPhaseDescendants(RuntimeError):\n    def __init__(self, pids):\n        super().__init__(\'Exit-phase unexpected descendants\')\n        self.pids = pids\n\ndef exit_identity(pid, root=Path(\'/proc\')):\n    raw = exit_read(root / str(pid) / \'stat\')\n    opened, closed = raw.find(\'(\'), raw.rfind(\')\')\n    if opened <= 0 or closed <= opened:\n        raise RuntimeError(\'Malformed exit-phase identity\')\n    tail = raw[closed + 2:].split()\n    if len(tail) < 50 or int(raw[:opened].strip()) != pid:\n        raise RuntimeError(\'Incomplete exit-phase identity\')\n    return {\'pid\': pid, \'ppid\': int(tail[1]), \'starttime_ticks\': int(tail[19]),\n            \'flags\': int(tail[6]), \'state\': tail[0]}\n\ndef exit_snapshot(pid, expected, root=Path(\'/proc\')):\n    """All reads must succeed; identity and single-task proof bracket status/mm."""\n    path = root / str(pid)\n    before = exit_identity(pid, root)\n    for key in (\'pid\', \'ppid\', \'starttime_ticks\'):\n        if before[key] != expected[key]:\n            raise RuntimeError(\'Exit-phase lifetime changed\')\n    if before[\'flags\'] & 4 == 0:\n        raise RuntimeError(\'Exit-phase PF_EXITING absent\')\n    tasks = sorted(x.name for x in (path / \'task\').iterdir())\n    if tasks != [str(pid)]:\n        raise RuntimeError(\'Exit-phase task set not sole owned leader\')\n    task_identity = exit_identity(pid, path / \'task\')\n    if any(task_identity[k] != before[k] for k in (\'pid\',\'ppid\',\'starttime_ticks\')) or task_identity[\'flags\'] & 4 == 0:\n        raise RuntimeError(\'Exit-phase task identity/flag mismatch\')\n    for current in (path, path / \'task\' / str(pid)):\n        status = dict(line.split(\':\', 1) for line in exit_read(current / \'status\').splitlines() if \':\' in line)\n        if any(int(status[k]) != v for k, v in ((\'Pid\',pid),(\'Tgid\',pid),(\'Threads\',1))):\n            raise RuntimeError(\'Exit-phase status identity mismatch\')\n        if \'VmRSS\' in status or \'VmHWM\' in status:\n            raise RuntimeError(\'Exit-phase memory still present\')\n        mm = exit_read(current / \'statm\').split()\n        if mm != [\'0\'] * 7:\n            raise RuntimeError(\'Exit-phase mm not detached\')\n    children = exit_read(path / \'task\' / str(pid) / \'children\').split()\n    if children:\n        if len(children) > 128 or any(not x.isdigit() or int(x) <= 0 for x in children):\n            raise RuntimeError(\'Invalid exit-phase descendants\')\n        raise ExitPhaseDescendants(children)\n    after = exit_identity(pid, root)\n    if any(after[k] != before[k] for k in (\'pid\',\'ppid\',\'starttime_ticks\')) or after[\'flags\'] & 4 == 0:\n        raise RuntimeError(\'Exit-phase identity/flag changed\')\n    if sorted(x.name for x in (path / \'task\').iterdir()) != [str(pid)]:\n        raise RuntimeError(\'Exit-phase task set changed\')\n    return {\'pid\':pid,\'starttime_ticks\':before[\'starttime_ticks\'],\'flags\':after[\'flags\'],\n            \'single_task\':True,\'mm_detached\':True,\'children_empty\':True}\n\n\nREAL_EXIT = (exit_read, exit_identity, exit_snapshot)\n\ndef callback_binding(callback):\n    obj = callback if inspect.isfunction(callback) or inspect.isclass(callback) else type(callback)\n    path = inspect.getsourcefile(obj)\n', "            raise ValueError('Invalid/missing nonnegative integer telemetry: ' + key)\n    return data\n\ndef callback_binding(callback):\n    obj = callback if inspect.isfunction(callback) or inspect.isclass(callback) else type(callback)\n    path = inspect.getsourcefile(obj)\n"), ("                  'requested_argv': list(argv), 'limits': asdict(limits),\n                  'helper': {'path': str(SELF), 'load_sha256': LOADED_HELPER_SHA256},\n                  'test_dependencies': any(a is not b for a, b in\n                      [(_system, system_metrics), (_process, process_metrics), (_popen, subprocess.Popen), (_sleep, time.sleep), *zip((exit_read, exit_identity, exit_snapshot), REAL_EXIT)]),\n                  'dependencies': {}, 'artifacts': {}, 'no_process_group_signals': True}\n    bound_paths = {}\n    invocation_written = False\n", "                  'requested_argv': list(argv), 'limits': asdict(limits),\n                  'helper': {'path': str(SELF), 'load_sha256': LOADED_HELPER_SHA256},\n                  'test_dependencies': any(a is not b for a, b in\n                      [(_system, system_metrics), (_process, process_metrics), (_popen, subprocess.Popen), (_sleep, time.sleep)]),\n                  'dependencies': {}, 'artifacts': {}, 'no_process_group_signals': True}\n    bound_paths = {}\n    invocation_written = False\n"), ("            result['cleanup_errors'].append('final_wait: ' + repr(exc))\n            result['cleanup_complete'] = False\n\n    def terminal_system_check():\n        if time.monotonic() - child_started > limits.timeout_s:\n            raise RuntimeError('Owned process timeout during terminal observation')\n        current = validate_metrics(_system(), ('MemAvailable_kB', 'oom_kill'))\n        if current['oom_kill'] > result['system_before']['oom_kill']:\n            raise RuntimeError('Global OOM increment during terminal observation')\n        if current['MemAvailable_kB'] < limits.runtime_min_available_kib:\n            raise RuntimeError('Low available memory during terminal observation')\n        return current\n\n    def observe_exit(event):\n        if not complete_sample_seen:\n            raise RuntimeError('No prior complete owned sample')\n        terminal_system_check()\n        if child.poll() is not None:\n            event.update(outcome='confirmed_exit',exit=child.poll(),system=terminal_system_check())\n            return\n        identity = exit_identity(child.pid)\n        if identity['pid'] != child.pid or identity['ppid'] != os.getpid():\n            raise RuntimeError('Owned import parent mismatch')\n        if child.poll() is not None:\n            terminal_system_check()\n            event['outcome'] = 'confirmed_exit'\n            return\n        phase_start = time.monotonic()\n        observations = []\n        attempt = {'elapsed_s':phase_start-child_started,'observations':observations,'pending_pair':[]}\n        result.setdefault('exit_phase_attempts', []).append(attempt)\n        def check():\n            current = terminal_system_check()\n            if time.monotonic() - phase_start > 1.0:\n                raise RuntimeError('Exit-phase observation timeout')\n            return current\n        while True:\n            check()\n            if child.poll() is not None:\n                break\n            try:\n                pair = []\n                attempt['pending_pair'] = pair\n                pair.append(exit_snapshot(child.pid,identity))\n                pair.append(exit_snapshot(child.pid,identity))\n            except ExitPhaseDescendants as exc:\n                result.setdefault('unexpected_exit_phase_children', []).append(exc.pids)\n                raise\n            except (FileNotFoundError, ProcessLookupError):\n                if child.poll() is None:\n                    raise\n                break\n            observations.append({'elapsed_s':time.monotonic()-child_started,'proof':pair})\n            attempt['pending_pair'] = []\n            if len(observations)>101:\n                raise RuntimeError('Exit-phase observation count exceeded')\n            check()\n            _sleep(0.01)\n        event['system'] = check()\n        event['outcome'] = 'verified_exit_phase_then_owned_exit' if observations else 'confirmed_exit'\n        event['exit'] = child.poll()\n        if observations:\n            result.setdefault('verified_exit_phase', []).append({'observations':observations,'owned_exit':event['exit']})\n\n    try:\n        helper_now = sha(SELF)\n        invocation['helper']['invocation_sha256'] = helper_now\n        if helper_now != LOADED_HELPER_SHA256:\n            raise RuntimeError('Helper changed since module load')\n        bound_paths['helper'] = (SELF, helper_now)\n        for name, callback in [('system', _system), ('process', _process), ('popen', _popen), ('sleep', _sleep), ('exit_read', exit_read), ('exit_identity', exit_identity), ('exit_snapshot', exit_snapshot)]:\n            if callback is time.sleep:\n                invocation['dependencies'][name] = {'name': 'time.sleep', 'builtin': True}\n            else:\n", "            result['cleanup_errors'].append('final_wait: ' + repr(exc))\n            result['cleanup_complete'] = False\n\n    try:\n        helper_now = sha(SELF)\n        invocation['helper']['invocation_sha256'] = helper_now\n        if helper_now != LOADED_HELPER_SHA256:\n            raise RuntimeError('Helper changed since module load')\n        bound_paths['helper'] = (SELF, helper_now)\n        for name, callback in [('system', _system), ('process', _process), ('popen', _popen), ('sleep', _sleep)]:\n            if callback is time.sleep:\n                invocation['dependencies'][name] = {'name': 'time.sleep', 'builtin': True}\n            else:\n"), ("        result['child_started'] = True\n        result['pid'] = child.pid\n        child_started = time.monotonic()\n        complete_sample_seen = False\n        while child.poll() is None:\n            now = time.monotonic()\n            if now - child_started > limits.timeout_s:\n", "        result['child_started'] = True\n        result['pid'] = child.pid\n        child_started = time.monotonic()\n        while child.poll() is None:\n            now = time.monotonic()\n            if now - child_started > limits.timeout_s:\n"), ("                    try:\n                        exit_code = child.wait(timeout=grace)\n                    except subprocess.TimeoutExpired:\n                        event = {'elapsed_s':time.monotonic()-child_started,'wait_bound_s':grace}\n                        result['terminal_telemetry_gaps'].append(event)\n                        system = terminal_system_check()\n                        if child.poll() is not None:\n                            event.update(outcome='confirmed_exit',exit=child.poll(),system=terminal_system_check())\n                            break\n                        process = _process(child.pid)\n                        system = terminal_system_check()\n                        if isinstance(process,dict) and 'VmRSS' not in process and 'VmHWM' not in process:\n                            observe_exit(event)\n                            break\n                        process = validate_metrics(process, ('VmRSS','VmHWM','VmSize','Threads'))\n                        event['outcome'] = 'recovered_live_complete_telemetry'\n                        now = time.monotonic()\n                    else:\n                        system = terminal_system_check()\n                        result['terminal_telemetry_gaps'].append({\n                            'elapsed_s': round(time.monotonic() - child_started, 6),\n                            'reason': 'VmRSS absent; owned child exit confirmed',\n", "                    try:\n                        exit_code = child.wait(timeout=grace)\n                    except subprocess.TimeoutExpired:\n                        pass  # Still live: normal validation below must fail.\n                    else:\n                        result['terminal_telemetry_gaps'].append({\n                            'elapsed_s': round(time.monotonic() - child_started, 6),\n                            'reason': 'VmRSS absent; owned child exit confirmed',\n"), ("                result['stop_reason'] = 'LOW_AVAILABLE_MEMORY_STOP_OWNED_PROCESS'\n            if result['stop_reason']:\n                break\n            if all(type(process.get(k)) is int and process[k]>=0 for k in ('VmRSS','VmHWM','VmSize','Threads')):\n                complete_sample_seen = True\n            _sleep(limits.sample_target_s)\n    except BaseException as exc:\n        result['exception'] = {'type': type(exc).__name__, 'message': str(exc)}\n", "                result['stop_reason'] = 'LOW_AVAILABLE_MEMORY_STOP_OWNED_PROCESS'\n            if result['stop_reason']:\n                break\n            _sleep(limits.sample_target_s)\n    except BaseException as exc:\n        result['exception'] = {'type': type(exc).__name__, 'message': str(exc)}\n")]):
            self.assertEqual(restored.count(added),1)
            restored=restored.replace(added,removed,1)
        self.assertEqual(__import__('hashlib').sha256(restored.encode()).hexdigest(), '4c7802bcfb53a2f73f501635cdf483e1459d3d86eb881a7450dccd3bbd705d50')
        self.assertEqual(p.digest(ROOT / 'ci/official_download.py'), '3dc01d98dd01638960db2634e3c0c3efbf1b67626d1d43745ddc6f1169367d42')


    def test_full_main_mocked_orchestration(self):
        """Current hash-bound adapter; synthetic monitor, never engine evidence.

        Supersedes retired dynamic-policy integration. Preserve success,
        pre-import test rejection, incomplete evidence rejection, source drift
        rejection, and untrusted adapter provenance rejection.
        """
        for case in ('success', 'test-phase', 'retention-failure', 'source-drift', 'wrong-policy'):
            with self.subTest(case=case), tempfile.TemporaryDirectory() as td:
                work=Path(td); project=work/'project';project.mkdir()
                entries=dict(self.entries)
                for name in entries:
                    target=project/name;target.parent.mkdir(parents=True,exist_ok=True)
                    target.write_bytes((ROOT/'game'/name).read_bytes())
                # Descriptors are immutable source now, not allowed generated files.
                for kind in p.PAIRS:
                    target=project/(p.PREFIX+kind+'.gltf.import')
                    target.write_bytes(self.synthetic(kind));entries[target.relative_to(project).as_posix()]=p.digest(target)
                engine=work/'engine';engine.write_bytes(b'synthetic-never-launched')
                archive=work/'source.zip';archive.write_bytes(b'synthetic-not-opened')
                manifest=work/'manifest.json';manifest.write_text('{}')
                output=work/'evidence';xdg=work/'xdg';launches=[]
                package={'candidate':'synthetic-build','runtime_manifest':{'sha256':'a'*64}}
                argv=['guarded_manifest_ci.py','test' if case=='test-phase' else 'import',
                      '--project',str(project),'--archive',str(archive),'--manifest',str(manifest),
                      '--output',str(output),'--xdg',str(xdg),'--godot',str(engine),
                      '--archive-sha256',p.digest(archive),'--manifest-sha256',p.digest(manifest),
                      '--hosted-execution-approved']
                def monitor_run(prefix,command,**kwargs):
                    launches.append(prefix)
                    cache=project/'.godot/imported/synthetic.res';cache.parent.mkdir(parents=True);cache.write_bytes(b'SYNTHETIC NOT A GODOT RESOURCE')
                    self.assertEqual(prefix,output/'import');self.assertEqual(command[-1],'--import')
                    self.assertEqual(kwargs['expected_artifact_hashes']['adapter'],p.digest(Path(adapter.__file__)))
                    for name,digest in entries.items():
                        self.assertEqual(kwargs['expected_artifact_hashes']['source:'+name],digest)
                    request={'test_dependencies':False,'helper':{'load_sha256':adapter.MONITOR_SHA,'invocation_sha256':adapter.MONITOR_SHA},'fixture':'SYNTHETIC ONLY'}
                    ip=prefix.with_suffix('.invocation.json');ip.write_text(json.dumps(request))
                    log=prefix.with_suffix('.log');log.write_text('Synthetic; no Godot ran.')
                    receipt={'passed':True,'cleanup_complete':True,'child_started':True,'exit':0,
                             'log_sha256':p.digest(log),'invocation_sha256':p.digest(ip),
                             'post_run_binding_matches':{'fixture':True},'stop_reason':None,'seconds':0,'sampled_peak_rss_kib':0}
                    if case=='retention-failure':receipt['output_errors']=['synthetic evidence retention failure']
                    if case=='wrong-policy':request['helper']['invocation_sha256']='0'*64;ip.write_text(json.dumps(request));receipt['invocation_sha256']=p.digest(ip)
                    prefix.with_suffix('.json').write_text(json.dumps(receipt))
                    if case=='source-drift':(project/(p.PREFIX+'stable.bin')).write_bytes(b'drift')
                monitor=types.SimpleNamespace(Limits=lambda **kw:kw,run=monitor_run)
                with patch.object(adapter.sys,'argv',argv),patch.dict(adapter.os.environ,{'GITHUB_ACTIONS':'true','RUNNER_ENVIRONMENT':'github-hosted'}),patch.object(adapter,'ENGINE_SHA',p.digest(engine)),patch.object(adapter.shutil,'which',return_value=str(engine)),patch.object(adapter,'verify_source',return_value=(package,entries)),patch.object(adapter,'load_monitor',return_value=monitor):
                    status=adapter.main()
                self.assertEqual(status,0 if case=='success' else 1)
                self.assertEqual(len(launches),0 if case=='test-phase' else 1)
                summary=json.loads((output/'phase-summary.json').read_text())
                self.assertEqual(summary['passed'],case=='success')
                self.assertEqual((xdg/'import-complete.json').exists(),case=='success')
                self.assertFalse((output/'approval.json').exists())
                if case in ('success','source-drift'):
                    self.assertEqual(summary['commands'][0]['receipt'],'import.json')
                    self.assertEqual(summary['commands'][0]['name'],'import')
                    self.assertEqual(summary['commands'][0]['receipt_sha256'],p.digest(output/'import.json'))
                else:self.assertEqual(summary['commands'],[])
                if case!='success':
                    self.assertIn('error',summary)
                    expected={'test-phase':'Guarded import certificate required','retention-failure':'Incomplete/failed monitor evidence','source-drift':'Source inventory mutated: assets/advanced_buildings/stable.bin','wrong-policy':'Monitor provenance mismatch'}
                    self.assertEqual(summary['error']['message'],expected[case])
                if launches:
                    self.assertTrue((output/'import.json').exists())
                    self.assertTrue((output/'import.invocation.json').exists())
                    self.assertTrue((output/'import.log').exists())


if __name__ == '__main__':
    unittest.main()

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
        self.plant(); adapter.inventory(self.root, self.entries)
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
        self.assertEqual(p.digest(ROOT / 'ci/hardened_monitored_run.py'), '4c7802bcfb53a2f73f501635cdf483e1459d3d86eb881a7450dccd3bbd705d50')
        self.assertEqual(p.digest(ROOT / 'ci/official_download.py'), '3dc01d98dd01638960db2634e3c0c3efbf1b67626d1d43745ddc6f1169367d42')


    def test_full_main_mocked_orchestration(self):
        """Real main/inventory/finally, mocked engine; all evidence is synthetic."""
        for case in ('success', 'test-phase', 'retention-failure', 'source-drift', 'wrong-policy'):
            with self.subTest(case=case), tempfile.TemporaryDirectory(prefix='mocked-orchestration-') as td:
                work = Path(td); project = work / 'project'; project.mkdir()
                for name in self.entries:
                    target = project / name; target.parent.mkdir(parents=True, exist_ok=True)
                    target.write_bytes((ROOT / 'game' / name).read_bytes())
                old_root = self.root; self.root = project
                engine = work / 'engine'; engine.write_bytes(b'synthetic-engine-never-launched')
                archive = work / 'source.zip'; archive.write_bytes(b'synthetic-archive-not-opened')
                manifest = work / 'manifest.json'; manifest.write_text('{}\n')
                output = work / 'evidence'; xdg = work / 'xdg'
                package = {'candidate': 'synthetic-build', 'runtime_manifest': {'sha256': 'a' * 64}}
                argv = ['guarded_manifest_ci.py', 'test' if case == 'test-phase' else 'import',
                        '--project', str(project), '--archive', str(archive), '--manifest', str(manifest),
                        '--output', str(output), '--xdg', str(xdg), '--godot', str(engine),
                        '--archive-sha256', p.digest(archive), '--manifest-sha256', p.digest(manifest), '--hosted-execution-approved']
                launches = []

                def synthetic_monitor(prefix, command, **kwargs):
                    launches.append(prefix)
                    self.assertEqual(prefix, output / 'import')
                    self.assertEqual(command[-1], '--import')
                    self.assertEqual(kwargs['expected_artifact_hashes']['building-policy'], p.digest(Path(p.__file__)))
                    for kind in p.PAIRS: self.plant(kind)
                    invocation = {'test_dependencies': False, 'helper': {'load_sha256': adapter.MONITOR_SHA,
                                  'invocation_sha256': adapter.MONITOR_SHA}, 'fixture': 'SYNTHETIC ONLY'}
                    ipath = prefix.with_suffix('.invocation.json'); ipath.write_text(json.dumps(invocation))
                    log = prefix.with_suffix('.log'); log.write_text('Synthetic parser test. No Godot ran.\n')
                    result = {'passed': True, 'cleanup_complete': True, 'child_started': True, 'exit': 0,
                              'log_sha256': p.digest(log), 'invocation_sha256': p.digest(ipath),
                              'post_run_binding_matches': {'fixture': True}, 'stop_reason': None,
                              'seconds': 0, 'sampled_peak_rss_kib': 0, 'fixture': 'SYNTHETIC ONLY'}
                    prefix.with_suffix('.json').write_text(json.dumps(result))

                original_retain = p.retain_actual

                def mocked_retain(*args):
                    result = original_retain(*args)
                    if case == 'retention-failure':
                        result['errors'].append({'source': 'fixture', 'reason': 'synthetic retention failure'})
                    if case == 'source-drift':
                        (project / (p.PREFIX + 'stable.bin')).write_bytes(b'synthetic-drift')
                    return result

                monitor = types.SimpleNamespace(Limits=lambda **kwargs: kwargs, run=synthetic_monitor)
                env = {'GITHUB_ACTIONS': 'true', 'RUNNER_ENVIRONMENT': 'github-hosted',
                       'BUILDING_IMPORT_POLICY_SHA256': '0' * 64 if case == 'wrong-policy' else p.digest(Path(p.__file__))}
                with patch.object(adapter.sys, 'argv', argv), patch.dict(adapter.os.environ, env), \
                     patch.object(adapter, 'ENGINE_SHA', p.digest(engine)), \
                     patch.object(adapter.shutil, 'which', return_value=str(engine)), \
                     patch.object(adapter, 'verify_source', return_value=(package, self.entries)), \
                     patch.object(adapter, 'load_monitor', return_value=monitor), \
                     patch.object(p, 'retain_actual', side_effect=mocked_retain):
                    if case in ('test-phase', 'wrong-policy'):
                        with self.assertRaises(RuntimeError): adapter.main()
                        self.assertEqual(launches, [])
                        self.assertFalse(output.exists())
                    else:
                        status = adapter.main()
                        self.assertEqual(len(launches), 1)
                        self.assertEqual(status, 0 if case == 'success' else 1)
                        summary = json.loads((output / 'phase-summary.json').read_text())
                        self.assertEqual(summary['passed'], case == 'success')
                        self.assertEqual(summary['commands'][0]['receipt'], 'import.json')
                        self.assertEqual(summary['commands'][0]['name'], 'import')
                        self.assertTrue((xdg / 'import-complete.json').exists())
                        self.assertFalse((output / 'approval.json').exists())
                        self.assertEqual(summary['commands'][0]['receipt_sha256'], p.digest(output / 'import.json'))
                self.root = old_root


if __name__ == '__main__':
    unittest.main()

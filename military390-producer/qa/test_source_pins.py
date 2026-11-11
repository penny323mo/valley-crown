"""Pure negative tests for duplicated identity pins; no process launch."""
import ast
import copy
import hashlib
import json
from pathlib import Path
import re
import unittest
import guard_contract
import run_browser
import source_pins
from check_export_pins import validate_pins
import test_export_pins_preflight
HERE=Path(__file__).resolve().parent
class SourcePins(unittest.TestCase):
    def test_duplicate_source_constants_and_branch(self):
        self.assertEqual(guard_contract.BUILD,source_pins.BUILD)
        self.assertEqual(run_browser.SOURCE_COMMIT,source_pins.SOURCE_COMMIT)
        guard=(HERE/'run_browser.py').read_text()
        self.assertIn("lock.get('build') == "+repr(source_pins.BUILD),guard)
        self.assertIn("'refs/heads/"+source_pins.BRANCH+"'",(HERE/'prepare_browser_qa.py').read_text())
        for name in ['scenario-manifest.json','expected-export.json']:
            data=json.loads((HERE/name).read_text()); self.assertEqual(data['build'],source_pins.BUILD)
            self.assertEqual(data['game_source_sha256'],source_pins.GAME_SOURCE_SHA256)
            content=data.get('export_manifest',data)
            self.assertEqual(content['source_commit'],source_pins.SOURCE_COMMIT)
            self.assertEqual(content['game_tree'],source_pins.GAME_TREE)
    def test_actual_stream_literals_match_verified_export(self):
        expected=json.loads((HERE/'expected-export.json').read_text())
        for name in ['public_stream_cache_policy.mjs','test_public_stream_cache_policy.mjs']:
            text=(HERE/name).read_text()
            self.assertIn(repr(expected['build']),text)
            self.assertIn(repr(expected['export_manifest']['source_commit']),text)
            for resource in ['index.wasm','index.pck']:
                matches=re.findall(re.escape(repr(resource))+r"\s*:\s*'([0-9a-f]{64})'",text)
                self.assertEqual(matches,[expected['export_manifest']['files_sha256'][resource]])
    def test_all_executable_bundle_files_reject_previous_runtime_pins(self):
        for path in HERE.iterdir():
            if not path.is_file() or path.name.startswith('test_'):continue
            text=path.read_text()
            for stale in ['vc-542ddb524e45','422acc862d9fc56f1fe2c95440f411893ded5edf','f75ccbd9484f33676fc46c413d63711fd3144116c8c7dfbb56f2467b194b5fa5','13853296416','43016465017']:
                self.assertNotIn(stale,text,path.name)
    def test_disabled_unbound_bundle_cannot_be_admitted(self):
        expected=json.loads((HERE/'expected-export.json').read_text())
        scenario=json.loads((HERE/'scenario-manifest.json').read_text())
        if expected['reviewed'] or scenario['reviewed']:
            self.skipTest('Later bound receipt reviewed by parent; disabled-template test only')
        self.assertEqual(expected['files_sha256'],{})
        self.assertEqual(scenario['files_sha256'],{})
        for key in ['artifact_id','export_run_id','artifact_zip_sha256']:self.assertIsNone(expected[key])
        with self.assertRaises(ValueError):validate_pins(expected,scenario,'e'*64)
        expected['reviewed']=True;scenario['reviewed']=True
        with self.assertRaises(ValueError):validate_pins(expected,scenario,'e'*64)
    def test_stale_or_tampered_exact_source_pins_rejected(self):
        for target,key,value in [('expected','game_source_sha256','0'*64),('scenario','game_source_sha256','0'*64),('scenario','game_tree','0'*40),('export','game_tree','0'*40),('export','source_commit','0'*40)]:
            expected,scenario=test_export_pins_preflight.ExportPins().fixture()
            obj=expected if target=='expected' else scenario if target=='scenario' else expected['export_manifest']
            obj[key]=value
            with self.assertRaises(ValueError):validate_pins(expected,scenario,'e'*64)
    def test_no_bound_previous_export_bytes_or_ids(self):
        text='\n'.join((HERE/name).read_text() for name in ['expected-export.json','scenario-manifest.json','source_pins.py','run_browser.py','guard_contract.py','prepare_browser_qa.py'])
        for stale in ['vc-542ddb524e45','422acc862d9fc56f1fe2c95440f411893ded5edf','13853296416','43016465017','d7d5140ff5c8d17328438dcf60d806773cdef989']:
            self.assertNotIn(stale,text)
if __name__=='__main__':unittest.main()

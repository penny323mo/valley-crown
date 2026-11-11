"""Inert final-pin gate checks. Fake hashes are not runtime evidence."""
import copy
import json
from pathlib import Path
import unittest
from check_export_pins import validate_pins
from guard_contract import BUILD
from validate_construction_binding import PREPARED_SCENARIO, PREPARED_VIEWPORT
from run_browser import SOURCE_COMMIT


class ExportPins(unittest.TestCase):
    def fixture(self):
        files={name:'b'*64 for name in ('index.html','index.pck','index.wasm')}
        expected={'reviewed':True,'build':BUILD,'artifact_id':'1','export_run_id':'2','artifact_zip_sha256':'c'*64,
          'files_sha256':{'artifacts/clean-a/'+name:digest for name,digest in files.items()},
          'export_manifest':{'build':BUILD,'source_commit':SOURCE_COMMIT,'game_tree':'d'*40,'files_sha256':files}}
        scenario={'reviewed':True,'build':BUILD,'source_commit':SOURCE_COMMIT,'profile':'portrait','hud_schema':2,'scenario':PREPARED_SCENARIO,'viewport':PREPARED_VIEWPORT.copy(),'files_sha256':files}
        return expected,scenario
    def test_exact_fake_binding_passes(self):
        expected,scenario=self.fixture(); validate_pins(expected,scenario,'e'*64)
    def test_disabled_or_incomplete_pins_fail_before_preparation(self):
        expected,scenario=self.fixture(); expected['reviewed']=False
        with self.assertRaises(ValueError): validate_pins(expected,scenario,'e'*64)
        for key in ('artifact_id','export_run_id','artifact_zip_sha256','files_sha256'):
            expected,scenario=self.fixture(); expected.pop(key)
            with self.assertRaises(ValueError): validate_pins(expected,scenario,'e'*64)
    def test_changed_scenario_source_or_export_rejected(self):
        for key in ('build','source_commit','files_sha256'):
            expected,scenario=self.fixture(); scenario[key]='mismatch'
            with self.assertRaises((ValueError,TypeError)): validate_pins(expected,scenario,'e'*64)


if __name__ == '__main__': unittest.main()

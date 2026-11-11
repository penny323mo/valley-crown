"""Inert manifest/lock contract tests; fake pins are NOT runtime evidence."""
import copy
import unittest
from validate_construction_binding import validate


class Binding(unittest.TestCase):
    def fixture(self):
        manifest = {'reviewed':True,'build':'vc-123456789abc','source_commit':'a'*40,'profile':'portrait','hud_schema':1,
                    'files_sha256':{name:'b'*64 for name in ('index.html','index.pck','index.wasm')}}
        lock=copy.deepcopy(manifest); lock['qa_files_sha256']={'scenario-manifest.json':'c'*64}
        return manifest,lock
    def test_exact_binding(self):
        manifest,lock=self.fixture(); validate(manifest,lock,'c'*64)
    def test_changed_identity_or_unbound_manifest_fails(self):
        for field in ('build','source_commit','files_sha256'):
            manifest,lock=self.fixture(); lock[field]='different'
            with self.assertRaises(ValueError): validate(manifest,lock,'c'*64)
        manifest,lock=self.fixture()
        with self.assertRaises(ValueError): validate(manifest,lock,'d'*64)
    def test_disabled_manifest_fails(self):
        manifest,lock=self.fixture(); manifest['reviewed']=False
        with self.assertRaises(ValueError): validate(manifest,lock,'c'*64)


if __name__ == '__main__': unittest.main()

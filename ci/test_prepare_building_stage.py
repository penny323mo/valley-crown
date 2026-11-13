import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from unittest import mock
import prepare_web_release as prep
import run_export as product
import run_export_diagnostic as diagnostic

class PreparationTests(unittest.TestCase):
    def fake_git(self,*args):
        if args==('rev-parse','HEAD'):return 'a'*40
        if args[0]=='rev-parse':
            folder=args[1].split(':',1)[1]
            return next(v['tree'] for v in prep.SIDES.values() if v['directory']==folder)
        assert args[0]=='ls-tree'
        folder=args[-1].split(':',1)[1];root=prep.ROOT/folder
        rows=[]
        for path in sorted(root.rglob('*')):
            if path.is_file():
                data=path.read_bytes();digest=hashlib.sha1(b'blob '+str(len(data)).encode()+b'\0'+data).hexdigest()
                rows.append('100644 blob '+digest+'\t'+path.relative_to(root).as_posix())
        return '\n'.join(rows)

    def test_exact_two_preparations_without_engine(self):
        with tempfile.TemporaryDirectory() as tmp,mock.patch.object(prep,'git',self.fake_git):
            for side in ('product',):
                work=Path(tmp)/side;receipt=prep.prepare(side,work)
                lock=json.loads((work/'export-lock.json').read_text())
                runner=product if side=='product' else diagnostic
                runner.validate_lock(lock)
                self.assertFalse(receipt['engine_executed'])
                self.assertEqual(lock['diagnostic_only'],side=='diagnostic')
                self.assertEqual(len(lock['project_files']),prep.SIDES[side]['files'])
                self.assertEqual('scripts/building_art_review.gd.uid' in lock['allowed_generated_uid_files'],side=='diagnostic')
                self.assertEqual('building_harness_sha256' in lock,side=='product')
                self.assertEqual(set(x.name for x in work.iterdir()),{'project','source.zip','import-manifest.json','export-lock.json','pins.env','source-attestation.json'})
                manifest=json.loads((work/'import-manifest.json').read_text())
                self.assertFalse(manifest['execution_enabled'])
                self.assertEqual(manifest['runtime_manifest']['inputs'],prep.SIDES[side]['runtime'])

    def test_wrong_tree_rejects_before_copy(self):
        with tempfile.TemporaryDirectory() as tmp,mock.patch.object(prep,'git',return_value='0'*40):
            work=Path(tmp)/'target'
            with self.assertRaisesRegex(ValueError,'tree differs'):prep.prepare('product',work)
            self.assertFalse(work.exists())

    def test_wrong_public_blob_rejects_before_copy(self):
        def changed(*args):
            result=self.fake_git(*args)
            if args[0]=='ls-tree':result=result.replace('100644 blob ','100644 blob 0',1)
            return result
        with tempfile.TemporaryDirectory() as tmp,mock.patch.object(prep,'git',changed):
            work=Path(tmp)/'target'
            with self.assertRaisesRegex(ValueError,'bytes/count'):prep.prepare('product',work)
            self.assertFalse(work.exists())

    def test_existing_or_overlapping_work_rejected(self):
        with tempfile.TemporaryDirectory() as tmp,mock.patch.object(prep,'git',self.fake_git):
            with self.assertRaisesRegex(ValueError,'Fresh real'):prep.prepare('product',Path(tmp))
            with self.assertRaisesRegex(ValueError,'overlap'):prep.prepare('product',prep.ROOT/'nonexistent-test-work')

    def test_product_workflow_excludes_diagnostic(self):
        text=(prep.ROOT/'.github/workflows/building-runtime.yml').read_text()
        self.assertNotIn('--side diagnostic',text)
        self.assertNotIn('run_export_diagnostic.py',text)
        self.assertIn("BUILDING_RUNTIME_EXECUTION_APPROVED: 'true'",text)

    def test_export_guards_differ_only_three_identity_constants(self):
        a=Path(product.__file__).read_bytes();b=Path(diagnostic.__file__).read_bytes()
        for old,new in ((diagnostic.BUILD,product.BUILD),(diagnostic.GAME_TREE,product.GAME_TREE)):
            self.assertEqual(b.count(old.encode()),1);b=b.replace(old.encode(),new.encode())
        self.assertEqual(a,b)

    def test_host_admission_fails_closed(self):
        with mock.patch.dict(prep.os.environ,{},clear=True):
            with self.assertRaisesRegex(ValueError,'Fresh hosted'):prep.admitted()

if __name__=='__main__':unittest.main()

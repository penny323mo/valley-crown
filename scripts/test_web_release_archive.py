import hashlib, io, json, pathlib, stat, unittest, zipfile
import web_release_archive as archive

class ArchiveSafety(unittest.TestCase):
    def make(self, pairs):
        b=io.BytesIO()
        with zipfile.ZipFile(b,'w') as z:
            for name,value in pairs: z.writestr(name,value)
        return b.getvalue()
    def row(self):
        return {'build':'vc-test','files_sha256':{'index.html':archive.sha(b'ok')}}
    def test_exact_bytes(self):
        self.assertEqual(archive.verified_members(self.make([('index.html',b'ok')]),self.row()),{'index.html':b'ok'})
    def test_extra_file(self):
        with self.assertRaises(ValueError): archive.verified_members(self.make([('index.html',b'ok'),('extra',b'x')]),self.row())
    def test_changed_file(self):
        with self.assertRaises(ValueError): archive.verified_members(self.make([('index.html',b'changed')]),self.row())
    def test_traversal(self):
        for name in ['../x','/x','a/../x','a\\x','a//x','C:x']:
            with self.subTest(name=name),self.assertRaises(ValueError): archive.verified_members(self.make([(name,b'x')]),self.row())
    def test_symlink(self):
        i=zipfile.ZipInfo('index.html');i.external_attr=(stat.S_IFLNK|0o777)<<16
        with self.assertRaises(ValueError): archive.verified_members(self.make([(i,b'ok')]),self.row())
    def test_duplicates(self):
        with self.assertRaises(ValueError): archive.verified_members(self.make([('index.html',b'ok'),('index.html',b'ok')]),self.row())
    def test_metadata_pin(self):
        m=json.dumps({'build':'vc-test','side':'product','diagnostic_only':False,'files_sha256':{'index.html':archive.sha(b'ok')}}).encode()
        row={'build':'vc-test','metadata_sha256':archive.sha(m)}
        self.assertEqual(len(archive.verified_members(self.make([('index.html',b'ok'),('candidate-metadata.json',m)]),row)),2)
        row['metadata_sha256']='0'*64
        with self.assertRaises(ValueError):archive.verified_members(self.make([('index.html',b'ok'),('candidate-metadata.json',m)]),row)
    def test_inventory_has_trust_pins(self):
        workflow=pathlib.Path('.github/workflows/pages.yml')
        if not workflow.exists(): self.skipTest('requires checkout')
        rows=archive.inventory(workflow.read_text())
        self.assertTrue(rows)
        for r in rows:self.assertTrue(r.get('files_sha256') or r.get('metadata_sha256'))

if __name__=='__main__':unittest.main()

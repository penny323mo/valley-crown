"""Inert tests: synthetic ZIPs, source bindings, unchanged guards. No network/runtime."""
from pathlib import Path
from copy import deepcopy
import ast,hashlib,json,sys,tempfile,unittest,zipfile
import preflight_pair as p
from fetch_export import metadata_matches,safe_target,verify_extract
sys.path.insert(0,str(p.ROOT/'report'))
from gpu_identity import identity

class FinalPairTests(unittest.TestCase):
    def test_actual_small_evidence_bindings(self):
        for side in ('baseline','candidate'):
            expected,scenario=p.source_check(side)
            self.assertFalse(expected['full_compiled_zip_locally_verified'])
            self.assertEqual(len(expected['files_sha256']),29)
            self.assertEqual(scenario['overlay_sha256'],'a09462f7654cdd9faf58d263130f56d9c0ce44b1dddfb708ca1052bf4daa2f30')
        with self.assertRaises(ValueError):p.admitted({})

    def test_actual_pins_reject_negative_mutations(self):
        for side in ('baseline','candidate'):
            qa,gate,_=p.load(side);e,s=p.source_check(side);s=dict(s,execution_approved=True)
            changes=[lambda e,s:e.update(source_chain_verified=False),lambda e,s:e.update(artifact_id=''),lambda e,s:e.update(export_run_id=''),
                lambda e,s:e.update(source_chain_verification_sha256=''),lambda e,s:e.update(artifact_zip_sha256=''),
                lambda e,s:e['export_manifest'].update(product_source_commit='0'*40),lambda e,s:e['export_manifest'].update(diagnostic_export_run_attempt=True),
                lambda e,s:e['export_manifest']['diagnostic_overlay_sha256'].update({'diagnostic/visibility_paused.gd':'0'*64}),
                lambda e,s:e['files_sha256'].update({'artifacts/clean-b/index.pck':'0'*64}),lambda e,s:s.update(qa_inventory_sha256='0'*64),
                lambda e,s:s.update(viewport=[844,390]),lambda e,s:s.update(execution_approved=False),lambda e,s:s.update(source_archive_sha256='0'*64)]
            for i,change in enumerate(changes):
                expected,scenario=deepcopy(e),deepcopy(s);change(expected,scenario)
                with self.subTest(side=side,negative=i):
                    with self.assertRaises(ValueError):gate.validate_pins(expected,scenario,hashlib.sha256(json.dumps(scenario).encode()).hexdigest())

    def test_exact_metadata_and_redirect_negatives(self):
        e,_=p.source_check('baseline');good={'id':int(e['artifact_id']),'expired':False,'size_in_bytes':e['artifact_zip_size_bytes'],'digest':'sha256:'+e['artifact_zip_sha256'],'workflow_run':{'id':int(e['export_run_id']),'head_sha':e['export_manifest']['diagnostic_export_commit']}}
        metadata_matches(good,e)
        for key,value in [('id',1),('expired',True),('size_in_bytes',1),('digest','sha256:'+'0'*64),('workflow_run',{})]:
            bad=deepcopy(good);bad[key]=value
            with self.assertRaises(ValueError):metadata_matches(bad,e)
        self.assertEqual(safe_target('https://example.blob.core.windows.net/a?synthetic=1'),'https://example.blob.core.windows.net/a?synthetic=1')
        for url in ['http://example.blob.core.windows.net/a','https://example.com/a','https://evil.blob.core.windows.net.evil.test/a','https://user:pass@example.blob.core.windows.net/a']:
            with self.assertRaises(ValueError):safe_target(url)

    def synthetic_zip(self,root,extra=None):
        manifest={'synthetic_only':True};bodies={'diagnostic-export-manifest.json':json.dumps(manifest).encode(),'a.txt':b'synthetic'}
        if extra:bodies.update(extra)
        archive=root/'input.zip'
        with zipfile.ZipFile(archive,'w') as z:
            for name,body in bodies.items():z.writestr(name,body)
        expected={'artifact_zip_size_bytes':archive.stat().st_size,'artifact_zip_sha256':p.sha(archive),'files_sha256':{n:hashlib.sha256(v).hexdigest() for n,v in bodies.items()},'export_manifest':manifest}
        return archive,expected

    def test_strict_zip_extraction_negatives(self):
        with tempfile.TemporaryDirectory() as name:
            root=Path(name);archive,e=self.synthetic_zip(root);result=verify_extract(archive,root/'good',e);self.assertTrue(result['full_zip_verified'])
            for key,value in [('artifact_zip_size_bytes',1),('artifact_zip_sha256','0'*64),('export_manifest',{'wrong':True})]:
                bad=deepcopy(e);bad[key]=value
                with self.assertRaises(ValueError):verify_extract(archive,root/key,bad)
            bad=deepcopy(e);bad['files_sha256']['a.txt']='0'*64
            with self.assertRaises(ValueError):verify_extract(archive,root/'wrong-file',bad)
            bad=deepcopy(e);bad['files_sha256'].pop('a.txt')
            with self.assertRaises(ValueError):verify_extract(archive,root/'wrong-map',bad)
        with tempfile.TemporaryDirectory() as name:
            root=Path(name);archive,e=self.synthetic_zip(root,{'../escape.txt':b'no'})
            with self.assertRaises(ValueError):verify_extract(archive,root/'unsafe',e)

    def test_original_host_network_and_safety_functions(self):
        donor=json.loads((p.ROOT/'review/donor-files.json').read_text())
        for side in ('baseline','candidate'):
            qa=p.ROOT/side/'qa'
            for name in ('run_host_browser.py','host_main.mjs','network_diagnostics.mjs','server_diagnostics.mjs','package.json','package-lock.json'):
                self.assertEqual(p.sha(qa/name),donor[name]['sha256'])
            for name in ('run_browser.py','guard_contract.py'):
                source=p.ROOT/'review/original'/name;self.assertEqual(p.sha(source),donor[name]['sha256'])
                before={n.name:ast.dump(n) for n in ast.parse(source.read_text()).body if isinstance(n,ast.FunctionDef)}
                after={n.name:ast.dump(n) for n in ast.parse((qa/name).read_text()).body if isinstance(n,ast.FunctionDef)}
                for fn in before:
                    if name=='run_browser.py' and fn=='validate_inputs':continue
                    self.assertEqual(before[fn],after[fn])

    def test_gpu_volatile_subset_and_missing_fields(self):
        raw={'devices':[{'vendorId':1,'deviceId':2,'driverVendor':'synthetic','driverVersion':'1'}],'auxAttributes':{'glVendor':'synthetic','glRenderer':'synthetic','glVersion':'1'},'initializationTime':1}
        changed=deepcopy(raw);changed['initializationTime']=999;self.assertEqual(identity(raw),identity(changed))
        changed['devices'][0]['driverVersion']='2';self.assertNotEqual(identity(raw),identity(changed))
        del changed['auxAttributes']['glRenderer'];self.assertEqual(identity(changed)['status'],'unknown')

    def test_workflow_sequential_scope_and_cleanup_gate(self):
        text=(p.ROOT/'.github/workflows/paused-browser-pair.yml').read_text()
        self.assertNotIn('matrix:',text);self.assertEqual(text.count('runs-on: ubuntu-24.04'),1)
        self.assertLess(text.index('Run baseline original'),text.index('Verify baseline exact cleanup'))
        self.assertLess(text.index('Verify baseline exact cleanup'),text.index('Run candidate separate'))
        self.assertEqual(text.count('GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}'),2)
        self.assertIn('preflight_pair.py --previous-guard "$RTS_B/host-guard.json"',text)
        with self.assertRaises((ValueError,FileNotFoundError)):p.safe_next(Path('/nonexistent-synthetic-receipt'))

if __name__=='__main__':unittest.main(verbosity=2)

"""Local source and synthetic file fixtures only. No network/engine/workflow."""
from pathlib import Path
import hashlib,importlib.util,json,sys,tempfile,unittest,zipfile,os,shutil
from unittest import mock
ROOT=Path(__file__).resolve().parent
sys.path.insert(0,str(ROOT))
import stage_render as stage
import run_render_delivery as run
import delivery_helpers as common
class Tests(unittest.TestCase):
    def test_hosted_gate_before_process(self):
        c=json.loads((ROOT/'DELIVERY.json').read_text())
        self.assertIs(c['execution_enabled'],True)
        with mock.patch.dict(os.environ,{},clear=True):
            with self.assertRaises(ValueError):run.validate(c)
            with self.assertRaises(ValueError):common.validate_contract(ROOT/'DELIVERY.json',hosted=True)
    def test_rejects_binding_path_escape(self):
        c=json.loads((ROOT/'DELIVERY.json').read_text());c['execution_enabled']=True
        c['bindings']={'bad':{'path':'../private','sha256':'a'*64}}
        with mock.patch.dict(os.environ,{'GITHUB_ACTIONS':'true','RUNNER_ENVIRONMENT':'github-hosted'}):
            with self.assertRaises(ValueError):run.validate(c)
    def test_local_phase_never_spawns(self):
        with mock.patch.object(run.subprocess,'run') as spawn:
            with self.assertRaises(ValueError):run.run(ROOT/'DELIVERY.json','capture',None)
            spawn.assert_not_called()
    def test_child_environment_removes_tokens(self):
        with mock.patch.dict(os.environ,{'GITHUB_TOKEN':'fixture','GH_TOKEN':'fixture','ACTIONS_RUNTIME_TOKEN':'fixture','GITHUB_ACTIONS':'true','RUNNER_ENVIRONMENT':'github-hosted'}):
            env=run.child_environment()
            self.assertFalse(any('TOKEN' in key for key in env))
            self.assertEqual(env['GITHUB_ACTIONS'],'true')
    def test_exact_scenarios_and_workflow(self):
        self.assertEqual(run.SCENARIOS,(('studies',844,390,'capture_material_studies.gd'),('portrait',390,844,'capture_material_gameplay.gd'),('landscape',844,390,'capture_material_gameplay.gd')))
        text=(ROOT/'.github/workflows/material-render.yml').read_text()
        self.assertIn("if: ${{ github.event_name == 'push' && github.ref == 'refs/heads/ci/material-render-proof-v1' }}",text)
        self.assertNotIn('download-artifact',text);self.assertNotIn('always()',text);self.assertNotIn('matrix:',text)
        self.assertIn('path: safe-render/',text)
        self.assertEqual(text.count('delivery_helpers.py fetch'),4)
    def test_immutable_actions_exact_paths_and_concurrency(self):
        text=(ROOT/'.github/workflows/material-render.yml').read_text()
        self.assertIn('actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683',text)
        self.assertIn('actions/upload-artifact@ea165f8d65b6e75b540449e92b4886f43607fa02',text)
        self.assertNotIn('@v4',text)
        self.assertIn('group: material-render-proof-v1',text);self.assertIn('cancel-in-progress: false',text)
        self.assertIn("PYTHONDONTWRITEBYTECODE: '1'",text)
        lines=text.split('    paths:\n',1)[1].split('permissions:',1)[0].splitlines()
        paths=[line.strip()[3:-1] for line in lines if line.strip().startswith("- '")]
        manifest=json.loads((ROOT/'DELIVERY_FILES.json').read_text())['files_sha256']
        self.assertEqual(set(paths),set(manifest)|{'DELIVERY_FILES.json'})
        self.assertFalse(any('*' in name for name in paths))
        self.assertNotIn('run: python3',text)
    def test_known_baseline_and_source_bindings(self):
        contract=json.loads((ROOT/'DELIVERY.json').read_text())
        for key in ('old_licensed','old_native'):
            common.validate_artifact(key,contract['artifacts'][key])
        for row in contract['bindings'].values():
            if row['sha256'] is not None:self.assertEqual(stage.sha(ROOT/row['path']),row['sha256'])
        generated=contract['artifacts']['generated'];common.validate_artifact('generated',generated)
        review=json.loads((ROOT/'controls/GENERATION_REVIEW.json').read_text())
        source=json.loads((ROOT/'controls/MATERIAL_SOURCE_INPUTS.json').read_text())
        self.assertEqual(generated['run_id'],42447623186)
        self.assertEqual(generated['artifact_id'],13604855256)
        self.assertEqual(generated['members'],review['archive_inventory']['files_sha256'])
        self.assertEqual(len(generated['members']),19)
        self.assertEqual(generated['members'],source['generated_files'])
        self.assertEqual(stage.sha(ROOT/'controls/GENERATION_REVIEW.json'),source['generation_review_sha256'])
        self.assertEqual(stage.sha(ROOT/'tools/build_licensed_action_characters.py'),source['generator_sha256'])
        self.assertFalse(review['native_validation_passed'])
        self.assertFalse(review['rendered_pixel_acceptance'])
        native=contract['artifacts']['native_accepted'];common.validate_artifact('native_accepted',native)
        self.assertEqual(native['run_id'],42448936212)
        self.assertEqual(native['artifact_id'],13605245411)
        self.assertEqual(len(native['members']),39)
        acceptance=json.loads((ROOT/'controls/NATIVE_OUTPUT_REVIEW.json').read_text())
        self.assertIs(acceptance['passed'],True)
        self.assertEqual(native['archive_sha256'],acceptance['artifact_archive_sha256'])
    def test_actual_capture_locks_reviewed_but_unbound(self):
        helpers=ROOT/'source/render/ci'
        for name in ('studies','portrait','landscape'):
            lock=json.loads((ROOT/'controls'/(name+'.prepared.json')).read_text())
            review=json.loads((ROOT/'controls'/(name+'.review.json')).read_text())
            self.assertEqual(lock['build'],'vc-84a95dfec970')
            self.assertEqual(len(lock['project_files']),197)
            self.assertIs(lock['reviewed_for_execution'],True)
            self.assertIsNone(lock['import_certificate_sha256'])
            self.assertIs(review['peer_reviewed'],True)
            self.assertIs(lock['independent_review']['passed'],True)
            self.assertEqual(stage.sha(ROOT/'controls'/(name+'.review.json')),lock['independent_review']['report_sha256'])
            self.assertEqual(lock['source_archive_sha256'],'233850979155595d169a97a5c5fe570f7dedc6057899af83916ecf050c603944')
            self.assertEqual(lock['import_manifest_sha256'],'077e6b449e74ad97b9597692da9fe4e78a927a566fabdbc27b9aac4c61179e3e')
            for helper,digest in lock['support_files'].items():self.assertEqual(stage.sha(helpers/helper[3:]),digest)
            core=dict(lock);core.pop('independent_review');core['import_certificate_sha256']=None
            actual=hashlib.sha256(json.dumps(core,sort_keys=True,separators=(',',':'),allow_nan=False).encode()).hexdigest()
            self.assertEqual(review['render_contract_core_sha256'],actual)
            spec=importlib.util.spec_from_file_location('actual_material_contract',helpers/'material_contract.py')
            module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
            with self.assertRaises(ValueError):module.validate_lock(lock) # Real import certificate is still absent.
    def test_failure_diagnostics_are_separate_and_reviewed(self):
        text=(ROOT/'.github/workflows/material-render.yml').read_text()
        self.assertIn("failure() && steps.capture.outcome == 'failure'",text)
        self.assertIn("steps.collect_diagnostics.outputs.diagnostics_scanned == 'true'",text)
        self.assertIn('path: work/UNACCEPTED-render-diagnostics/',text)
        self.assertIn('path: safe-render/',text)
        review=json.loads((ROOT/'controls/FAILURE_COLLECTOR_REVIEW.json').read_text())
        self.assertIs(review['passed_source_review'],True)
        self.assertEqual(stage.sha(ROOT/'collect_render_failure.py'),review['collector_sha256'])
    def test_copied_frozen_helpers(self):
        frozen=ROOT.parents[1]
        for p in (ROOT/'source').rglob('*'):
            if p.is_file() and '__pycache__' not in p.parts:
                original=frozen/p.relative_to(ROOT/'source')
                self.assertEqual(p.read_bytes(),original.read_bytes(),str(p.relative_to(ROOT)))
    def test_final_public_tree_exact_and_extra_rejected(self):
        c=json.loads((ROOT/'DELIVERY.json').read_text());manifest=json.loads((ROOT/'DELIVERY_FILES.json').read_text())
        with tempfile.TemporaryDirectory() as tmp:
            destination=Path(tmp)
            for name in list(manifest['files_sha256'])+['DELIVERY_FILES.json']:
                target=destination/name;target.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(ROOT/name,target)
            common.manifest_files(destination,c,strict=True)
            (destination/'unreviewed.txt').write_text('extra')
            with self.assertRaises(ValueError):common.manifest_files(destination,c,strict=True)
    def test_baseline_closed35(self):
        chain=json.loads((ROOT/'BASELINE_CHAIN.json').read_text())
        files=chain['public_files'];self.assertEqual(len(files),35);self.assertEqual(len(chain['commands']),12)
        actual={p.relative_to(ROOT/'baseline-public').as_posix():stage.sha(p) for p in (ROOT/'baseline-public').rglob('*') if p.is_file()}
        self.assertEqual(actual,files)
    def fixture(self,root):
        evidence=root/'evidence';evidence.mkdir();imp=root/'import';imp.mkdir();locks=root/'locks';locks.mkdir()
        def write(path,value):path.write_text(json.dumps(value))
        invocation={'test_dependencies':False,'helper':{'load_sha256':stage.MONITOR_SHA,'invocation_sha256':stage.MONITOR_SHA},'artifacts':{k:{'sha256':v} for k,v in {'engine':stage.ENGINE_SHA,'monitor':stage.MONITOR_SHA,'adapter':'a'*64,'archive':'b'*64,'suite-manifest':'c'*64}.items()},'argv':['/engine','--headless','--editor','--path','/project','--import']}
        invocation['requested_argv']=invocation['argv'];write(imp/'import.invocation.json',invocation);(imp/'import.log').write_text('Synthetic successful import log, not engine evidence')
        receipt={'passed':True,'cleanup_complete':True,'child_started':True,'cleanup_errors':[],'exit':0,'log_sha256':stage.sha(imp/'import.log'),'invocation_sha256':stage.sha(imp/'import.invocation.json'),'post_run_binding_matches':{'fixture':True}}
        write(imp/'import.json',receipt)
        marker=root/'import-complete.json';certificate={'build':'vc-fixture-only','project':'/project','receipt':str(imp/'import.json'),'invocation':str(imp/'import.invocation.json'),'receipt_sha256':stage.sha(imp/'import.json'),'invocation_sha256':stage.sha(imp/'import.invocation.json'),'cache_sha256':{'.godot/imported/fixture':'d'*64},'archive_sha256':'b'*64,'manifest_sha256':'c'*64,'engine_sha256':stage.ENGINE_SHA,'adapter_sha256':'a'*64};write(marker,certificate)
        for scenario in stage.SCENARIOS:
            lock={'reviewed_for_execution':True,'import_certificate_sha256':stage.sha(marker),'build':'vc-fixture-only','project_files':{'fixture-'+str(i):'d'*64 for i in range(197)},'material_binding':{'fixture':True},'source_archive_sha256':'b'*64,'import_manifest_sha256':'c'*64,'godot_sha256':stage.ENGINE_SHA,'support_files':{'ci/guarded_manifest_ci.py':'a'*64}}
            lock_path=locks/(scenario+'.json');write(lock_path,lock)
            folder=evidence/scenario;folder.mkdir();files={}
            for name in stage.expected_files(scenario):
                p=folder/name;p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(b'synthetic staging fixture, not frame evidence')
            guard={'passed':True,'cleanup_complete':True,'capture_completed':True,'test_dependencies':False,'build':'vc-fixture-only','input_sha256':{k:stage.sha(v) for k,v in {'lock':lock_path,'import_marker':marker,'import_receipt':imp/'import.json','import_invocation':imp/'import.invocation.json','import_log':imp/'import.log'}.items()}}
            guard['input_sha256']['import_adapter']='a'*64;write(folder/'guard-receipt.json',guard)
            files={name:{'sha256':stage.sha(folder/name)} for name in stage.expected_files(scenario)}
            write(evidence/(scenario+'-scan.json'),{'passed':True,'findings':[],'files':files,'visual_findings':[{'kind':'human_material_pixel_review_required'}]})
        return evidence
    def admit(self,root,evidence):return stage.stage(evidence,root/'safe',root/'import-complete.json',root/'import',root/'locks')
    def test_closed_staging46(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);evidence=self.fixture(root);result=self.admit(root,evidence)
            self.assertEqual(result['files'],46);self.assertIs(result['visual_acceptance'],False)
            self.assertEqual(sum(p.is_file() for p in (root/'safe').rglob('*')),46)
    def test_modified_unscanned_bytes_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);evidence=self.fixture(root);(evidence/'portrait/godot.log').write_text('changed')
            with self.assertRaises(ValueError):self.admit(root,evidence)
            self.assertFalse((root/'safe').exists())
    def test_extra_file_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);evidence=self.fixture(root);(evidence/'landscape/private.txt').write_text('extra')
            with self.assertRaises(ValueError):self.admit(root,evidence)
    def test_no_pixel_review_omission(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);evidence=self.fixture(root);p=evidence/'studies-scan.json';r=json.loads(p.read_text());r['visual_findings']=[];p.write_text(json.dumps(r))
            with self.assertRaises(ValueError):self.admit(root,evidence)
    def test_symlink_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);evidence=self.fixture(root);p=evidence/'studies/godot.log';p.unlink();p.symlink_to(evidence/'portrait/godot.log')
            with self.assertRaises(ValueError):self.admit(root,evidence)
    def test_each_success_provenance_file_is_hash_bound(self):
        names=['import-complete.json','import/import.json','import/import.invocation.json','import/import.log','locks/studies.json','locks/portrait.json','locks/landscape.json']
        for name in names:
            with self.subTest(name=name),tempfile.TemporaryDirectory() as tmp:
                root=Path(tmp);evidence=self.fixture(root);p=root/name;p.write_bytes(p.read_bytes()+b'\n')
                with self.assertRaises(ValueError):self.admit(root,evidence)
                self.assertFalse((root/'safe').exists())
    def test_provenance_missing_lock_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);evidence=self.fixture(root);(root/'locks/landscape.json').unlink()
            with self.assertRaises(ValueError):self.admit(root,evidence)
    def test_provenance_secret_and_private_paths_rejected(self):
        for content in ('password=fixture-secret','/workspace/shared/fixture'):
            with tempfile.TemporaryDirectory() as tmp:
                root=Path(tmp);evidence=self.fixture(root);(root/'import/import.log').write_text(content)
                with self.assertRaises(ValueError):self.admit(root,evidence)
    def test_provenance_size_bound(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);evidence=self.fixture(root);(root/'import/import.log').write_bytes(b'x'*(4*1024*1024+1))
            with self.assertRaises(ValueError):self.admit(root,evidence)
    def test_provenance_guard_cross_binding_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);evidence=self.fixture(root);p=evidence/'portrait/guard-receipt.json';r=json.loads(p.read_text());r['input_sha256']['import_marker']='e'*64;p.write_text(json.dumps(r))
            scan=evidence/'portrait-scan.json';r=json.loads(scan.read_text());r['files']['guard-receipt.json']['sha256']=stage.sha(p);scan.write_text(json.dumps(r))
            with self.assertRaises(ValueError):self.admit(root,evidence)
    def test_provenance_symlink_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);evidence=self.fixture(root);p=root/'locks/studies.json';p.unlink();p.symlink_to(root/'locks/portrait.json')
            with self.assertRaises(ValueError):self.admit(root,evidence)
    def test_closed_zip_rejects_traversal(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);z=root/'bad.zip'
            with zipfile.ZipFile(z,'w') as archive:archive.writestr('../escape',b'x')
            with self.assertRaises(ValueError):common.safe_extract(z,{'../escape':hashlib.sha256(b'x').hexdigest()},root/'out')
            self.assertFalse((root/'escape').exists())
if __name__=='__main__':unittest.main()

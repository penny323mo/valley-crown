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
        # All source bytes remain pinned, with only the reviewed diagnostic pair revised.
        expected={'source/assemble_material_source.py': '732f1b634788bd15d5dad4211a1f876468ed76455e6be11cfdff7057d7be2487', 'source/bind_render_after_import.py': 'be7889a332b41d20018669b0c55809ce26dac530514d45a5b9f4cbc739d6ae7c', 'source/prepare_render_source.py': '7c61e3c57511c7d9da28f82d873a03c3cdb62d90b574a4852079ab684e005246', 'source/render/ci/baseline_192.json': '36e6441b6dac681d4194a6d21e14c18660b38ea7082c1cddc7d9e48e5b07a93c', 'source/render/ci/capture_material_base.gd': '98ded858e41488d56e5616c7cb3bcca65a954ec5613b1bbfd5acc37abb7c008a', 'source/render/ci/capture_material_gameplay.gd': '7958c90b2eb083b6bcdbb21d8d41c8844321bd8882cc7b255b711fdafb079a56', 'source/render/ci/capture_material_studies.gd': 'ad0f3ac4b17b0f9d1abdd8ac531979d8676a701eb99af34aa216019213656204', 'source/render/ci/guarded_manifest_ci.py': '1737dfca2778614730b6dd6d3803009460139a19dfe901b830e84120abce75e0', 'source/render/ci/hardened_monitored_run.py': '4c7802bcfb53a2f73f501635cdf483e1459d3d86eb881a7450dccd3bbd705d50', 'source/render/ci/material_contract.py': '751251aceccc72645dbbbb01bdf72a499c870258c69d5237a1912d7ef4c90c67', 'source/render/ci/material_gameplay-lock.disabled.json': '47bc5a2ad91dc2cafcc22e3156bae65c1009a8bb561c5976cabae0b7f7b8fe92', 'source/render/ci/material_studies-lock.disabled.json': 'fedb66186d72f232d7c74357089c49f71e409fd7e84d107f46cb84160471b56a', 'source/render/ci/run_native.py': '56704a1f789b9322e113fb8e3a50c0b2d836f2d755f1dc95672ac85c559b5698', 'source/render/ci/scan_evidence.py': '8cd57ac9f3f47a4060aaa36a7e972d0dd853eeaa822725a2d16b4d23fa40fb67', 'source/render/ci/xvfb_startup.py': '558daeca491842c43e1212cb39b636c7014fd5e33a6f35b8a05bbf5cbc78b546'}
        actual={p.relative_to(ROOT).as_posix():stage.sha(p) for p in (ROOT/'source').rglob('*') if p.is_file() and '__pycache__' not in p.parts}
        self.assertEqual(actual,expected)
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



# Synthetic in-memory dictionaries only, never capture artifacts.
import ast,contextlib,copy,io,struct,re
sys.path.insert(0,str(ROOT/'source/render/ci'))
import material_contract as c
import scan_evidence as scanner
"""Synthetic dictionaries only; never capture/provenance artifacts."""
import copy
import unittest
from pathlib import Path
H='a'*64

def fixture():
    light=dict(source='main.tscn runtime unmodified',ambient_energy=.36,sun_energy=.95,sun_shadow=True,ambient_color='b6bec5ff',sun_color='ffedceff',background_color='727967ff',tonemap=0,shadow_distance=80,sun_rotation_degrees=[-48,-32,0])
    files={'main.tscn':H,'scripts/action_character.gd':H}
    binding=dict(native_scene_sha256={},atlas_sha256={},atlas_rgba8_sha256={'art/action_characters/textures/'+k+'_atlas.png':H for k in c.KINDS})
    lock=dict(project_files=files,material_binding=binding,capture_contract=c.CONTRACTS[0],allowed_generated_uid_files=[])
    camera=dict(basis=[[1,0,0],[0,1,0],[0,0,1]],size=3.2)
    report=dict(mode='material_studies',failed=0,fixed_fps=20,source_sha256=files,lighting=light,opening_camera=camera,frames=[])
    for kind in c.KINDS:
        for view in ('front','rear'):
            report['frames'].append(dict(kind=kind,view=view,fixed_fps=20,main_scene_sha256=H,action_controller_sha256=H,material_binding=binding,process_frame=len(report['frames'])+1,rendering_method='gl_compatibility',rendering_driver='opengl3',unix_time=1,utc='2026-11-08T00:00:00',lighting=light,camera=camera,study_label=c.LABEL,framebuffer=[844,390],unit_state='controlled_paused_idle',clip='idle',overlay_disabled=True,camera_scope='detail framing, not gameplay',animation_poses=[dict(kind=kind,clip='idle',occlusion=dict(authorized=False))],materials=[dict(mesh='Body',surface=0,name='body',albedo='ffffffff',roughness=1,metallic=0,vertex_color=False,texture_path='res://atlas',texture_rgba8_sha256=H)]))
    return report,lock
class ScenarioTests(unittest.TestCase):
    def test_positive_structural_study_still_requires_pixel_review(self):
        report,lock=fixture();result=c.validate_report(report,lock,lambda p,l:None)
        self.assertEqual(result[0]['kind'],'human_material_pixel_review_required')
    def test_rejects_wrong_material_texture(self):
        report,lock=fixture();report['frames'][0]['materials'][0]['texture_rgba8_sha256']='b'*64
        with self.assertRaises(ValueError):c.validate_report(report,lock,lambda p,l:None)
    def test_rejects_coverage_or_overlay_or_label_or_renderer(self):
        for key,value in [('view','side'),('overlay_disabled',False),('study_label','rig study'),('rendering_method','dummy'),('process_frame',-1)]:
            report,lock=fixture();report['frames'][0][key]=value
            with self.assertRaises(ValueError):c.validate_report(report,lock,lambda p,l:None)
    def test_rejects_new_light_recipe(self):
        report,lock=fixture();report['lighting']['sun_energy']=1.5
        with self.assertRaises(ValueError):c.validate_report(report,lock,lambda p,l:None)
    def test_rejects_source_drift(self):
        report,lock=fixture();report['source_sha256']=dict(report['source_sha256']);report['source_sha256']['main.tscn']='b'*64
        with self.assertRaises(ValueError):c.validate_report(report,lock,lambda p,l:None)
    def test_rejects_missing_study(self):
        report,lock=fixture();report['frames'].pop()
        with self.assertRaises(ValueError):c.validate_report(report,lock,lambda p,l:None)



def game_fixture():
    report,lock=fixture();report['mode']='material_gameplay';lock['capture_contract']=c.CONTRACTS[1]
    lock['project_files']['assets/mature/shaders/observed_occlusion.gdshader']=H
    report['frames']=report['frames'][:2];report['worker_id']=3
    for i,f in enumerate(report['frames']):
        f.update(label=['opening','worker-walking'][i],test_mode=False,economy_audit_ok=True,selected=[3],worker_visible=True,
            own_units=[dict(id=3,state='move',pos=[i,0,0])],
            animation_poses=[dict(snapshot=dict(live={'3':dict(kind='villager',clip='walk')}))],
            visibility_probe=dict(clear=True,sample_count=3,blocker_count=0,samples=[dict(height=h,world=[0,h,0],screen=[50,50],ray_origin=[19,25,23]) for h in (.7,1.1,1.5)],projected_body_bounds=[40,40,20,30],overlay=dict(authorized=True,supported=True,overlay_meshes=1),
                overlay_nodes=[dict(visible=True,visible_in_tree=True,shader_sha256=H)],materials=f['materials']))
    report['inputs']=[dict(action=action,pressed=pressed,route='root.push_input InputEventScreenTouch',position=[100,100],touch_command_before=True,selected_before=[3]) for action in ('worker-select','command-enter','worker-move') for pressed in (True,False)]
    return report,lock

class GameplayTests(unittest.TestCase):
    def validate(self,report,lock):
        calls=[];result=c.validate_report(report,lock,lambda p,l:calls.append(p))
        return result,calls
    def test_positive_calls_pose_validator_and_requires_pixel_review(self):
        report,lock=game_fixture();result,calls=self.validate(report,lock)
        self.assertEqual(len(calls),1);self.assertEqual(result[0]['kind'],'human_material_pixel_review_required')
    def test_missing_command_enter(self):
        report,lock=game_fixture();report['inputs']=report['inputs'][:2]+report['inputs'][4:]
        with self.assertRaises(ValueError):self.validate(report,lock)
    def test_no_actual_move(self):
        report,lock=game_fixture();report['frames'][1]['own_units'][0]['pos']=[0,0,0]
        with self.assertRaises(ValueError):self.validate(report,lock)
    def test_camera_drift(self):
        report,lock=game_fixture();report['frames'][1]['camera']=dict(report['frames'][1]['camera'],size=5)
        with self.assertRaises(ValueError):self.validate(report,lock)
    def test_blocked_worker(self):
        report,lock=game_fixture();report['frames'][1]['visibility_probe']['blocker_count']=1
        with self.assertRaises(ValueError):self.validate(report,lock)
    def test_overlay_toggled(self):
        report,lock=game_fixture();report['frames'][1]['visibility_probe']['overlay']['authorized']=False
        with self.assertRaises(ValueError):self.validate(report,lock)
    def test_nonwalking_pose(self):
        report,lock=game_fixture();report['frames'][1]['animation_poses'][0]['snapshot']['live']['3']['clip']='idle'
        with self.assertRaises(ValueError):self.validate(report,lock)
    def test_no_normal_command_mode(self):
        report,lock=game_fixture();report['inputs'][4]['touch_command_before']=False
        with self.assertRaises(ValueError):self.validate(report,lock)
    def test_wrong_native_or_atlas_bindings(self):
        for key in ('native_scene_sha256','atlas_sha256','atlas_rgba8_sha256'):
            report,lock=game_fixture();report['frames'][1]['material_binding']=copy.deepcopy(report['frames'][1]['material_binding']);report['frames'][1]['material_binding'][key]={'wrong_class':'b'*64}
            with self.assertRaises(ValueError):self.validate(report,lock)
    def test_wrong_mode_and_malformed_frames(self):
        for key,value in [('mode','rig_studies'),('frames',{}),('frames',[]),('frames',[None,None])]:
            report,lock=game_fixture();report[key]=value
            with self.assertRaises(ValueError):self.validate(report,lock)
    def test_study_poses_all_validated(self):
        report,lock=fixture();result,calls=self.validate(report,lock)
        self.assertEqual(len(calls),8)


class DiagnosticTests(unittest.TestCase):
    def test_all_original_acceptance_predicates_and_order_unchanged(self):
        tree=ast.parse((ROOT/'source/render/ci/material_contract.py').read_text())
        tree.body=[n for n in tree.body if not (isinstance(n,ast.FunctionDef) and n.name=='need') and not (isinstance(n,ast.Assign) and any(isinstance(t,ast.Name) and t.id=='MATERIAL_ASSERTION_IDS' for t in n.targets))]
        codes=[]
        for node in ast.walk(tree):
            if isinstance(node,ast.Call) and isinstance(node.func,ast.Name) and node.func.id=='need':
                self.assertEqual(len(node.args),2);self.assertEqual(node.keywords,[])
                self.assertIsInstance(node.args[1],ast.Constant)
                self.assertIs(type(node.args[1].value),str)
                codes.append(node.args.pop().value)
        self.assertEqual(len(codes),72);self.assertEqual(len(set(codes)),72)
        self.assertEqual(set(codes),c.MATERIAL_ASSERTION_IDS)
        # Reconstruct the exact original bytes, avoiding Python-version AST formatting.
        source=(ROOT/'source/render/ci/material_contract.py').read_text()
        start=source.index('\n# Closed source-authored diagnostic identifiers.')
        end=source.index('\ndef need(',start)
        source=source[:start]+source[end:]
        source=source.replace("def need(ok, assertion_id):\n    if not ok: raise ValueError('Material contract rejected: '+assertion_id)","def need(ok):\n    if not ok: raise ValueError('Material contract rejected; details withheld')")
        source=re.sub(r", 'MC_(?:LOCK|MATERIAL|REPORT)_[0-9]{2}'\)",')',source)
        self.assertEqual(hashlib.sha256(source.encode()).hexdigest(),'0482828bd669fe7121bfb6339e13e6f80762067df5762becae99ca3810f5df29')
    def test_every_fixed_assertion_is_safely_reportable_and_still_rejects(self):
        for code in sorted(c.MATERIAL_ASSERTION_IDS):
            with self.subTest(code=code):
                self.assertIsNone(c.need(True,code))
                with self.assertRaises(ValueError) as raised:c.need(False,code)
                self.assertIs(type(raised.exception),ValueError)
                self.assertEqual(scanner.safe_scan_exception(raised.exception),{'type':'ValueError','reason':'Material contract rejected: '+code})
    def test_unknown_or_data_bearing_assertion_messages_are_withheld(self):
        base='Material contract rejected: MC_REPORT_23'
        for message in ('fixture-private-data-unique',base+' fixture-private-data-unique',base+'\n',base+'\x00','Material contract rejected: MC_REPORT_99','Material contract rejected; details withheld'):
            with self.subTest(message=message):
                self.assertEqual(scanner.safe_scan_exception(ValueError(message)),{'type':'ValueError','reason':'Unexpected scanner exception; details withheld'})
        self.assertEqual(scanner.safe_scan_exception(RuntimeError(base)),{'type':'RuntimeError','reason':'Unexpected scanner exception; details withheld'})
    def test_float32_hypothesis_remains_rejected_with_fixed_identifier(self):
        report,lock=fixture()
        self.assertEqual(c.validate_report(report,lock,lambda p,l:None)[0]['kind'],'human_material_pixel_review_required')
        rounded=struct.unpack('f',struct.pack('f',3.2))[0]
        self.assertEqual(rounded,3.200000047683716);self.assertNotEqual(rounded,3.2)
        for value in (rounded,3.199,3.201,True,float('nan'),float('inf')):
            report,lock=fixture();report['frames'][0]['camera']['size']=value
            with self.assertRaisesRegex(ValueError,'^Material contract rejected: MC_REPORT_23$'):
                c.validate_report(report,lock,lambda p,l:None)
    def test_other_study_predicates_keep_distinct_rejections(self):
        mutations=[('study_label','wrong','MC_REPORT_21'),('overlay_disabled',False,'MC_REPORT_22'),('camera_scope','wrong','MC_REPORT_23'),('rendering_method','dummy','MC_REPORT_11')]
        for field,value,code in mutations:
            report,lock=fixture();report['frames'][0][field]=value
            with self.subTest(field=field),self.assertRaisesRegex(ValueError,'^Material contract rejected: '+code+'$'):
                c.validate_report(report,lock,lambda p,l:None)
    def test_rejection_summary_is_bounded_and_never_admitted(self):
        for message in ('Material contract rejected: MC_REPORT_23','Material contract rejected: MC_REPORT_23 fixture-private-data-unique'):
            with tempfile.TemporaryDirectory() as tmp:
                root=Path(tmp);lock=root/'lock.json';lock.write_text('{}');out=root/'scan.json';printed=io.StringIO()
                with mock.patch.object(scanner,'scan',side_effect=ValueError(message)),contextlib.redirect_stdout(printed):
                    self.assertEqual(scanner.scan_to_report(root,lock,out),1)
                result=json.loads(out.read_text());self.assertIs(result['passed'],False)
                self.assertEqual(set(result),{'passed','error'})
                self.assertNotIn('fixture-private-data-unique',out.read_text()+printed.getvalue())
                self.assertEqual(json.loads(printed.getvalue().removeprefix('NATIVE_SCAN_RESULT ')),result)
                self.assertEqual({p.name for p in root.iterdir()},{'lock.json','scan.json'})

if __name__=='__main__':unittest.main()

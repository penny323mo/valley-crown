"""Metadata-only positive and negative diagnostic binding checks; no launch."""
from pathlib import Path
import copy,json,sys
import diagnostic_policy as d
import guarded_manifest_ci as imp
import run_export as ex
side=sys.argv[1];work=Path(sys.argv[2]);lock=json.loads((work/'export-lock.json').read_text())
assert side==lock['side'] and len(lock['project_files'])==235 and len(lock['allowed_generated_uid_files'])==32
assert d.tree(work/'project')==lock['project_files']
assert d.sha(work/'source.zip')==lock['source_archive_sha256']
assert d.sha(work/'import-manifest.json')==lock['import_manifest_sha256']
assert lock['source_archive_sha256']=={'baseline':'352d3b5bcf1fa5bdc50451c5da9f9435fa817403d5162c57e7f8f354928c0c04','candidate':'ab7fad065261281a30578087373e4684ac021849b35884358e373a1b0d7fadb7'}[side]
# Validate exact same generated lock and archive parser without executing a phase.
positive=copy.deepcopy(lock);positive.update(reviewed_for_execution=True,execution_approved=True,source_policy_extension_applied=True)
def verify(value):
 ex.validate_lock(value)
 files=value['project_files'];uids=[n+'.uid' for n in files if n.endswith('.gd') and n+'.uid' not in files]
 for name in ['assets/mature/shaders/building_damage_soot.gdshader.uid','assets/mature/menu/menu_backdrop.gdshader.uid']:
  if name[:-4] in files and name not in files:uids.append(name)
 assert value['allowed_generated_uid_files']==sorted(uids) and len(uids)==32
verify(positive)
imp.verify_source(work/'project',work/'source.zip',work/'import-manifest.json',lock['source_archive_sha256'],lock['import_manifest_sha256'])
mutations=[lambda x:x.update(reviewed_for_execution=False),lambda x:x.update(source_commit='0'*40),lambda x:x.update(game_tree='0'*40),lambda x:x.update(build='vc-000000000000'),lambda x:x.update(diagnostic_only=False),lambda x:x.update(release_artifact_identity_claim=True),lambda x:x['project_files'].update({'scripts/game.gd':'0'*64}),lambda x:x['project_files'].update({'project.godot':'0'*64}),lambda x:x['diagnostic_overlay_sha256'].update({'diagnostic/extra.gd':'0'*64}),lambda x:x['allowed_generated_uid_files'].pop(),lambda x:x['bound_files_sha256'].update(policy='0'*64)]
for number,change in enumerate(mutations):
 bad=copy.deepcopy(positive);change(bad)
 try:verify(bad)
 except (ValueError,RuntimeError,AssertionError):pass
 else:raise AssertionError('Invalid diagnostic lock accepted: '+str(number))
config=d.configuration();approval=json.loads((d.ROOT/'approval.json').read_text());env={'GITHUB_ACTIONS':'true','RUNNER_ENVIRONMENT':'github-hosted','GITHUB_REPOSITORY':'penny323mo/valley-crown','GITHUB_REF':approval['branch'],'GITHUB_RUN_ATTEMPT':'1','DIAGNOSTIC_EXECUTION_APPROVED':'true'}
d.validate_admission(config,approval,env,side)
for key,value in [('GITHUB_ACTIONS','false'),('RUNNER_ENVIRONMENT','self-hosted'),('GITHUB_REF','refs/heads/main'),('GITHUB_RUN_ATTEMPT','2'),('DIAGNOSTIC_EXECUTION_APPROVED','false')]:
 bad=dict(env);bad[key]=value
 try:d.validate_admission(config,approval,bad,side)
 except ValueError:pass
 else:raise AssertionError('Invalid host admission accepted')
print(json.dumps({'side':side,'prepared_source_files':235,'generated_uid_names':32,'source_archive_verified':True,'negative_binding_cases':len(mutations),'negative_admission_cases':5,'engine_executed':False}))

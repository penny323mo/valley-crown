"""Check actual prepared source/adapter pins before any engine launch."""
import copy,json,sys,hashlib
from pathlib import Path
import run_export as r
import prepare_public_capture as source
import validate_contracts as c
import validate_military as m
import run_faction as f
HERE=Path(__file__).resolve().parent
EXPECTED=('ce2ea3d2513bd79cf62cf5c651abe3c47aad8513','cadc77674b0b3184e7c3af9961f3e6ffdac507e9','vc-79ebcaef19e3')
def verify(lock):
 r.validate_lock(lock);f.validate_gate(lock)
 assert (r.SOURCE,r.GAME_TREE,r.BUILD)==(source.SOURCE_COMMIT,source.GAME_TREE,source.BUILD)==EXPECTED
 assert c.BUILD==m.BUILD==EXPECTED[2] and c.GAME_SHA==m.GAME_SHA
 assert lock['contracts_reviewed_for_execution'] and lock['contracts_stop_reviewed_for_execution'] and lock['contracts_consolidated_reviewed_for_execution'] and lock['military_reviewed_for_execution']
 assert len(lock['project_files'])==232
 required={'runner_sha256':'run_export.py','owned_process_sha256':'owned_process.py','import_adapter_sha256':'guarded_manifest_ci.py','contracts_runner_sha256':'run_contracts.py','contracts_supervisor_sha256':'run_logic.py','contracts_validator_sha256':'validate_contracts.py','contracts_names_sha256':'check_contract.json','military_runner_sha256':'run_military.py','military_supervisor_sha256':'run_logic.py','military_validator_sha256':'validate_military.py','military_names_sha256':'military_contract.json','faction_runner_sha256':'run_faction.py','faction_supervisor_sha256':'run_logic.py','faction_validator_sha256':'validate_faction.py'}
 for key,name in required.items():assert lock[key]==hashlib.sha256((HERE/name).read_bytes()).hexdigest(),key
 for name,digest in list(c.FIXTURES.values())+list(m.FIXTURES.values()):assert lock['project_files'][name]==digest,name
 assert lock['project_files']['scripts/game.gd']==c.GAME_SHA
 assert lock['project_files']['scripts/main_menu.gd']==c.MENU_SHA
 assert lock['project_files']['scripts/faction_view.gd']==f.v.CANDIDATE_SHA
 assert lock['project_files']['tests/faction_publish_reference.gd']==f.v.REFERENCE_SHA
 assert lock['project_files']['tests/faction_publish_contract.gd']==f.HARNESS_SHA==lock['faction_harness_sha256']
 files=lock['project_files'];uids=sorted(n+'.uid' for n in files if n.endswith('.gd') and n+'.uid' not in files)
 for n in ['assets/mature/shaders/building_damage_soot.gdshader.uid','assets/mature/menu/menu_backdrop.gdshader.uid']:
  if n[:-4] in files and n not in files:uids.append(n)
 assert lock['allowed_generated_uid_files']==sorted(uids)
def check(path):
 lock=json.loads(Path(path).read_text());verify(lock);rejected=0
 for key,badvalues in [('source_commit',['3e84f07b5984135572c089a70fd90392810b8017','0'*40]),('game_tree',['5047b4ffcd5b7fea49a668d7769f7fa80a909062','0'*40]),('build',['vc-10d6c6145978','vc-000000000000'])]:
  for value in badvalues:
   bad=copy.deepcopy(lock);bad[key]=value
   try:verify(bad)
   except (RuntimeError,AssertionError):rejected+=1
   else:raise AssertionError('Wrong pin accepted: '+key)
 for mutate in [lambda x:x['project_files'].__setitem__('scripts/game.gd','0'*64),lambda x:x['allowed_generated_uid_files'].pop(),lambda x:x.__setitem__('contracts_validator_sha256','0'*64),lambda x:x['project_files'].__setitem__('scripts/main_menu.gd','0'*64)]:
  bad=copy.deepcopy(lock);mutate(bad)
  try:verify(bad)
  except (RuntimeError,AssertionError):rejected+=1
  else:raise AssertionError('Wrong source/UID/support pin accepted')
 assert rejected==10
 return {'actual_prepared_lock_valid':True,'negative_pin_cases_rejected':rejected,'source_files':232,'engine_executed':False}
if __name__=='__main__':print(json.dumps(check(sys.argv[1])))

"""Inert actual-lock identity and fixture validation; no engine/process launch."""
import copy,json,sys
from pathlib import Path
import run_export as r
import run_full_match_270 as f

def check(path):
 lock=json.loads(Path(path).read_text());r.validate_lock(lock);f.validate_gate(lock)
 assert (r.SOURCE,r.GAME_TREE,r.BUILD)==('422acc862d9fc56f1fe2c95440f411893ded5edf','d7d5140ff5c8d17328438dcf60d806773cdef989','vc-542ddb524e45')
 count=0
 for key,values in [('source_commit',['0c15a901d054702b84ec28e66da089de37b36178','0'*40]),('game_tree',['3e1a0725642df930df2555cf989c2fef7a063f48','0'*40]),('build',['vc-f3d75a2138cc','vc-000000000000'])]:
  for value in values:
   bad=copy.deepcopy(lock);bad[key]=value
   try:r.validate_lock(bad)
   except RuntimeError:count+=1
   else:raise AssertionError('Wrong identity accepted')
 for key in ['full_match_270_reviewed_for_execution','full_match_270_harness_sha256','full_match_270_validator_sha256','full_match_270_supervisor_sha256']:
  bad=copy.deepcopy(lock);bad[key]=False
  try:f.validate_gate(bad)
  except RuntimeError:count+=1
  else:raise AssertionError('Unreviewed match accepted')
 assert count==10
 for key,name in [('full_match_270_runner_sha256','run_full_match_270.py'),('full_match_270_harness_sha256','full_match_270.gd'),('full_match_270_validator_sha256','validate_full_match_270.py'),('full_match_270_supervisor_sha256','run_logic_300.py'),('runner_sha256','run_export.py'),('owned_process_sha256','owned_process.py')]:r.checked(Path(__file__).with_name(name),lock[key])
 return {'actual_lock_passed':True,'negative_cases':count,'engine_executed':False}
if __name__=='__main__':print(json.dumps(check(sys.argv[1])))

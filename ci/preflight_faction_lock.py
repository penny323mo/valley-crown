"""Pure validation of an actual prepared lock; never launches an engine."""
import copy,json,sys
from pathlib import Path
import run_export as r
import run_faction as f

def check(path):
 lock=json.loads(Path(path).read_text());r.validate_lock(lock);f.validate_gate(lock)
 assert (r.SOURCE,r.GAME_TREE,r.BUILD)==('0c15a901d054702b84ec28e66da089de37b36178','3e1a0725642df930df2555cf989c2fef7a063f48','vc-f3d75a2138cc')
 rejected=0
 for key,values in [('source_commit',['bd04f892cd559573d9cce9ae9539d2627d43a9ab','0'*40]),('game_tree',['f0db2450c82106bb957d50a2e1ee05a2e3e95d0f','0'*40]),('build',['vc-65e548819ad3','vc-000000000000'])]:
  for value in values:
   bad=copy.deepcopy(lock);bad[key]=value
   try:r.validate_lock(bad)
   except RuntimeError:rejected+=1
   else:raise AssertionError('Wrong identity accepted: '+key)
 assert rejected==6
 return {'actual_prepared_lock_valid':True,'old_or_mismatched_pins_rejected':rejected,'engine_executed':False}
if __name__=='__main__':print(json.dumps(check(sys.argv[1])))

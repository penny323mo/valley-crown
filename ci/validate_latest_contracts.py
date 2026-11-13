"""Exact latest material and paid-training gates; no engine or invented row evidence."""
import re
from pathlib import Path
from validate_building_contracts import require,parse_json,validate_monitor,validate_identity,LIMITS
COUNTS={'material_contract':13,'continuous_training_contract':16,'resource_visual_contract':27}
SUITES=tuple(COUNTS)
EXTERNAL=()
REPORT='not-used.json'
TRAINING_NAMES=['repeat is off by default', 'ordinary opt-in accepted', 'worker producer excluded', 'proposal is not payment', 'one normal paid item', 'no early first birth', 'two paid births over two countdowns', 'normal repeated total cost', 'first receipt fulfilled', 'next item proposed not yet prepaid', 'disable accepted', 'stale automatic intent cannot charge', 'can re-enable through normal queue', 'exact cancellation succeeds', 'cancellation stops repeat without rebuy', 'ledger conservation']
def read_report(stage,suite):
 log=(Path(stage)/'godot.log').read_text()
 require(not re.search(r'(?im)^\s*(?:SCRIPT ERROR:|ERROR:|FATAL:|FAIL )',log),'Error in log')
 if suite=='resource_visual_contract':
  rows=[l for l in log.splitlines() if l.startswith('RESOURCE_CONTRACT_PASS ')]
  require(rows==['RESOURCE_CONTRACT_PASS 27'],'Wrong resource summary')
  metrics=[l for l in log.splitlines() if l.startswith('RESOURCE_METRIC ')]
  require(len(metrics)==3,'Missing/duplicate resource metrics')
  for line,kind,count in zip(metrics,('stone','iron','berry'),(945,1365,3174)):
   require(line.startswith('RESOURCE_METRIC '+kind+' vertices='+str(count)+' surfaces=1 bounds='),'Wrong resource geometry')
  return {'summary':rows[0],'assertions':27,'metrics':metrics}
 if suite=='material_contract':
  rows=[l for l in log.splitlines() if l.startswith('FOG_MATERIAL_CONTRACT ')]
  require(rows==['FOG_MATERIAL_CONTRACT checks=13 failures=0'],'Wrong material summary')
  return {'summary':rows[0],'assertions':13}
 require(suite=='continuous_training_contract','Unknown suite')
 rows=[l for l in log.splitlines() if l.startswith('{')];require(len(rows)==1,'Missing/duplicate training report')
 d=parse_json(rows[0]);require(d.get('suite')==suite and d.get('failed')==0,'Wrong/failed training report')
 from run_export import BUILD
 require(d.get('build')==BUILD,'Wrong training build')
 checks=d.get('checks');require(type(checks) is list and len(checks)==16,'Missing training checks')
 require([x.get('name') for x in checks]==TRAINING_NAMES and all(x.get('passed') is True for x in checks),'Wrong/failed training checks')
 return d

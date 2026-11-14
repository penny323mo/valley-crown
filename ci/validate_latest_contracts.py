"""Exact latest material and paid-training gates; no engine or invented row evidence."""
import re
from pathlib import Path
from validate_building_contracts import require,parse_json,validate_monitor,validate_identity,LIMITS
COUNTS={'material_contract':13,'continuous_training_contract':16,'resource_visual_contract':27,'compact_click_contract':19,'compact_move_runtime':4}
COUNTS.update({'hold_box_contract': 24, 'hold_box_phone': 26, 'contextual_routed_touch': 22, 'wide_click_contract': 19})
COUNTS['skirmish_policy_contract']=17
COUNTS.update({'resource_polish_contract':24,'normal_probe':3})
COUNTS.update({'army_composition_contract':19,'army_recruitment_integration':10})
SUITES=tuple(COUNTS)
EXTERNAL=()
REPORT='not-used.json'
TRAINING_NAMES=['repeat is off by default', 'ordinary opt-in accepted', 'worker producer excluded', 'proposal is not payment', 'one normal paid item', 'no early first birth', 'two paid births over two countdowns', 'normal repeated total cost', 'first receipt fulfilled', 'next item proposed not yet prepaid', 'disable accepted', 'stale automatic intent cannot charge', 'can re-enable through normal queue', 'exact cancellation succeeds', 'cancellation stops repeat without rebuy', 'ledger conservation']
INPUT_CONTRACTS={'compact_click_contract': {'prefix': 'COMPACT_CLICK_CONTRACT', 'names': ['primary click selects worker', 'worker building actions immediately visible', 'empty ground fixture', 'primary click queues move without command button', 'repeat primary click issues exactly one new order', 'paused primary click cannot order', 'selection change cancels held mouse press', 'mouse drag cannot leak contextual order', 'visible contextual fixture spearman', 'primary click contextual order spearman', 'primary click correct capability spearman', 'visible contextual fixture berry', 'primary click contextual order berry', 'primary click correct capability berry', 'visible contextual fixture farm', 'primary click contextual order farm', 'primary click correct capability farm', 'farm click carries gather intent', 'ended match cannot order']}, 'compact_move_runtime': {'prefix': 'COMPACT_MOVE_RUNTIME', 'names': ['visible empty destination', 'move queued with retained selection', 'simulation actually moves worker', 'no instruction mode required']}}
INPUT_CONTRACTS.update({'hold_box_contract': {'prefix': 'HOLD_BOX_CONTRACT', 'names': ['short stationary press remains contextual tap', 'long hold alone cannot issue movement', 'early single swipe cannot pan or arm later', 'hold shows rectangle (60.0, 50.0)', 'hold selects units without mode button (60.0, 50.0)', 'hold shows rectangle (-60.0, 50.0)', 'hold selects units without mode button (-60.0, 50.0)', 'hold shows rectangle (60.0, -50.0)', 'hold selects units without mode button (60.0, -50.0)', 'hold shows rectangle (-60.0, -50.0)', 'hold selects units without mode button (-60.0, -50.0)', 'small hold jitter keeps original box anchor', 'second finger cancels automatic rectangle', 'two fingers pan map', 'two to one stays inert until full release', 'HUD boundary cancels pending hold', 'canceled release cannot select or order', 'old cleanup preserves reused press hold', 'global cancellation clears hold and ignores late input', 'GUI owned press never arms world box', 'build preview retains one finger drag', 'hold preserves raw drag boundary samples', 'zero area hold preserves selection without order', 'hold completion restores input accumulation']}, 'hold_box_phone': {'prefix': 'HOLD_BOX_PHONE', 'names': ['visible worker group exists', 'box endpoints are battlefield', 'hold drag shows rectangle without menu', 'release selects actual boxed units', 'box gesture issues no movement and does not pan', 'box release clears transient ownership', 'selected group next tap moves once', 'quick single swipe neither pans nor orders', 'two finger drag pans', 'last pinch finger cannot pan or emit order', 'actual producer controls and worker are visible', 'ordinary train tap queues exactly one villager command', 'ordinary training command pays and reserves population', 'actual routed producer swipe scrolls the action strip', 'swipe emits no button or world command', 'swipe retires game-owned pointer state', 'first same-index world tap after swipe selects worker', 'first worker selection emits no command or economic change', 'tap without a preceding swipe selects worker', 'tap without swipe emits no command', 'canceled active swipe cannot activate old button or world order', 'first world tap after canceled swipe selects worker', 'canceled swipe and next tap leave no pointer ownership', 'repeated swipes return strip without any old button command', 'first world tap after repeated swipes selects worker', 'repeated gestures leave no pointer or command residue']}, 'contextual_routed_touch': {'prefix': 'CONTEXTUAL_ROUTED_TOUCH', 'names': ['touch selects worker', 'worker building actions immediately visible', 'empty ground fixture', 'touch queues move without command button', 'repeat touch issues exactly one new order', 'paused touch cannot order', 'selection change cancels held touch press', 'touch drag cannot leak contextual order', 'visible contextual fixture spearman', 'touch contextual order spearman', 'touch correct capability spearman', 'visible contextual fixture pine', 'touch contextual order pine', 'touch correct capability pine', 'visible contextual fixture berry', 'touch contextual order berry', 'touch correct capability berry', 'visible contextual fixture farm', 'touch contextual order farm', 'touch correct capability farm', 'farm click carries gather intent', 'ended match cannot order']}, 'wide_click_contract': {'prefix': 'WIDE_CLICK_CONTRACT', 'names': ['primary click selects worker', 'worker building actions immediately visible', 'empty ground fixture', 'primary click queues move without command button', 'repeat primary click issues exactly one new order', 'paused primary click cannot order', 'selection change cancels held mouse press', 'mouse drag cannot leak contextual order', 'visible contextual fixture spearman', 'primary click contextual order spearman', 'primary click correct capability spearman', 'visible contextual fixture berry', 'primary click contextual order berry', 'primary click correct capability berry', 'visible contextual fixture farm', 'primary click contextual order farm', 'primary click correct capability farm', 'farm click carries gather intent', 'ended match cannot order']}})
ARMY_CONTRACTS={'army_composition_contract': {'suite': 'army_composition', 'names': ['no observations preserves baseline tie order', 'counter cavalry', 'hidden old cavalry ignored', 'dead cavalry ignored', 'counter spearman', 'hidden old spearman ignored', 'dead spearman ignored', 'counter archer', 'hidden old archer ignored', 'dead archer ignored', 'counter demand bounded', 'input order cannot change decision', 'duplicate observation not doubled', 'already queued counter avoids duplicate overcommit', 'building cannot spoof unit', 'neutral cannot reveal enemy army', 'opening counters spear with available archer', 'opening never recommends locked cavalry', 'no mutation of input']}, 'army_recruitment_integration': {'suite': 'army_recruitment_integration', 'names': ['no enemy opening remains old tie', 'seen spear adapts opening to archer', 'lost sight cannot affect opening', 'worker floor precedes tactics', 'housing precedes tactics', 'no enemy late game preserves tie', 'seen archer late game recruits cavalry', 'queued counter already covers current deficit', 'technology gate precedes adaptive recruitment', 'no source mutation initial data']}}
def read_report(stage,suite):
 log=(Path(stage)/'godot.log').read_text()
 require(not re.search(r'(?im)^\s*(?:SCRIPT ERROR:|ERROR:|FATAL:|FAIL )',log),'Error in log')
 if suite in ARMY_CONTRACTS:
  spec=ARMY_CONTRACTS[suite];rows=[l for l in log.splitlines() if l.startswith('{')]
  require(len(rows)==1,'Missing/duplicate army report')
  d=parse_json(rows[0]);require(set(d)=={'suite','checks','failed'} and d['suite']==spec['suite'] and d['failed']==0,'Wrong army report identity')
  checks=d['checks'];require(type(checks) is list and len(checks)==COUNTS[suite],'Wrong army assertion count')
  require([x.get('name') for x in checks]==spec['names'],'Wrong army names/order')
  require(all(type(x) is dict and set(x)=={'name','passed'} and x['passed'] is True for x in checks),'Failed/malformed army assertion')
  return d
 if suite in INPUT_CONTRACTS:
  spec=INPUT_CONTRACTS[suite];prefix=spec['prefix']+' '
  rows=[l[len(prefix):] for l in log.splitlines() if l.startswith(prefix)]
  require(len(rows)==1,'Missing/duplicate input report')
  checks=parse_json(rows[0])
  require(type(checks) is list and len(checks)==COUNTS[suite],'Wrong input assertion count')
  require([x.get('name') for x in checks]==spec['names'],'Wrong input names/order')
  require(all(type(x) is dict and set(x)=={'name','passed'} and x['passed'] is True for x in checks),'Failed/malformed input assertion')
  return {'checks':checks,'assertions':len(checks)}
 if suite=='resource_visual_contract':
  rows=[l for l in log.splitlines() if l.startswith('RESOURCE_CONTRACT_PASS ')]
  require(rows==['RESOURCE_CONTRACT_PASS 27'],'Wrong resource summary')
  metrics=[l for l in log.splitlines() if l.startswith('RESOURCE_METRIC ')]
  require(len(metrics)==3,'Missing/duplicate resource metrics')
  for line,kind,count in zip(metrics,('stone','iron','berry'),(1344,1344,3378)):
   require(line.startswith('RESOURCE_METRIC '+kind+' vertices='+str(count)+' surfaces=1 bounds='),'Wrong resource geometry')
  return {'summary':rows[0],'assertions':27,'metrics':metrics}
 if suite=='skirmish_policy_contract':
  rows=[l for l in log.splitlines() if l.startswith('SKIRMISH ')]
  require(rows==['SKIRMISH 17/17'],'Wrong/failed skirmish summary')
  return {'summary':rows[0],'assertions':17}
 if suite in ('resource_polish_contract','normal_probe'):
  prefix='RESOURCE_POLISH_PASS ' if suite=='resource_polish_contract' else 'NORMALS_PASS '
  rows=[l for l in log.splitlines() if l.startswith(prefix)]
  require(rows==[prefix+str(COUNTS[suite])],'Wrong/failed geometry summary')
  return {'summary':rows[0],'assertions':COUNTS[suite]}
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

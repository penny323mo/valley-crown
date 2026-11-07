from pathlib import Path
import argparse, hashlib, json, re, math
p=argparse.ArgumentParser(); p.add_argument('--root',type=Path,required=True); p.add_argument('report',type=Path); a=p.parse_args()
errors=[]; build="unknown"
sha=lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
def require(ok,label):
 if not ok: errors.append(label)
names=['expected exact build', 'visible ground accepted without payment', 'invalid ground preserves prior point infinite', 'invalid ground preserves prior point nan', 'invalid ground preserves prior point outside', 'invalid ground preserves prior point hidden', 'invalid ground preserves prior point occupied', 'ineligible producer rejected house0', 'ineligible producer rejected barracks0', 'ineligible producer rejected town_center1', 'enemy cannot mutate owned rally', 'owned observation includes rally', 'enemy observation excludes rally', 'clear removes setting without payment', 'destroyed queued producer cannot receive rally', 'training pays unchanged fifty food', 'rally update does not restart training', 'newborn inherits latest ordinary move', 'full-duration exactly-once spawn', 'real movement reaches rally', 'reservation fulfilled with unchanged ledger', 'producer changes never overwrite existing manual order', 'manual stop is not rallied again', 'cancelled training cannot rally or spawn', 'cleared rally preserves baseline newborn idle', 'override fixture catches newborn before route search', 'manual stop supersedes newborn rally before movement', 'explicit rally action enters isolated touch mode', 'cancel emits no command', 'selection change cancels rally', 'pause cancels rally', 'box mode replaces rally', 'destroyed producer cancels targeting immediately']
try:
 require(a.report.stat().st_size<=131072,'bounded report')
 r=json.loads(a.report.read_text()); root=a.root
 fixture=Path(__file__).resolve().parent
 lock=json.loads((fixture/'source_lock.json').read_text())
 build=re.search(r'const BUILD_ID = "([^"]+)"',(root/'scripts/rules.gd').read_text())[1]
 require(build==lock['build']==r['build'],'build binding')
 actual={p.relative_to(root).as_posix() for p in root.rglob('*') if p.is_file() and '.godot' not in p.parts and '__pycache__' not in p.parts}
 require(len(lock['files'])==192 and len(lock['imported_extras'])==5,'expected source counts')
 require(not (set(lock['files']) & set(lock['imported_extras'])),'disjoint source sets')
 require(actual==set(lock['files'])|set(lock['imported_extras']),'exact imported source set')
 for path,digest in (lock['files']|lock['imported_extras']).items(): require(sha(root/path)==digest,'source hash '+path)
 require(r['game_sha256']==sha(root/'scripts/game.gd'),'game binding')
 require(r['manifest_sha256']==sha(root/'reports/build-manifest.json'),'manifest binding')
 require(r['contract_sha256']==sha(fixture/'contract.gd'),'contract binding')
 require(r['source_lock_sha256']==sha(fixture/'source_lock.json'),'lock binding')
 require([c['name'] for c in r['checks']]==names,'ordered exact checks')
 require(all(set(c)=={'name','pass'} and c['pass'] is True for c in r['checks']),'all strict true')
 require(r['completed'] is True and type(r['failed']) is int and r['failed']==0,'completion')
 require(type(r['passed']) is int and r['passed']==len(names),'passed count')
 require(r['engine']['major']==4 and r['engine']['minor']==6 and r['engine']['patch']==3,'engine version')
 require(r['schema']=='ground-rally-v1','report schema')
 prod=r['production'];trace=r['trace'];bank={'food':100000,'wood':200000}
 require(set(prod)=={'producer_id','first_target','train_tick','receipt_id','paid_bank','train_remaining','latest_target','rally_update_tick','newborn_id','birth_tick','birth_position','birth_destination','birth_mode','final_receipt','final_bank','audit','commits'},'exact production fields')
 require(prod['producer_id']==0 and type(prod['producer_id']) is int and prod['newborn_id']==2 and type(prod['newborn_id']) is int,'seeded producer/newborn identities')
 require(prod['first_target']==[-.5,0,.5] and prod['latest_target']==[-.5,0,-.5] and prod['birth_destination']==prod['latest_target'] and prod['birth_mode']=='MOVE','latest ordinary destination')
 require(prod['train_tick']==2 and prod['train_remaining']==299 and prod['rally_update_tick']==3 and prod['birth_tick']==301,'full native training timeline')
 require(type(prod['receipt_id']) is str and 0<len(prod['receipt_id'])<=80,'bounded receipt identity')
 require(prod['paid_bank']==prod['final_bank']==bank and prod['audit']=={'ok':True,'errors':[]},'single charge and audited bank')
 receipt=prod['final_receipt'];require(receipt['state']=='fulfilled' and receipt['team']==0 and receipt['cost_units']=={'food':50} and receipt['paid_milli']=={'food':50000,'wood':0} and receipt['refund_policy']=='started','fulfilled paid receipt')
 require(prod['commits']==[{'building':0,'queue':0,'tick':301}],'single birth commit')
 def position(v):return type(v) is list and len(v)==3 and all(type(x) in (int,float) and math.isfinite(x) and abs(x)<=40 for x in v)
 require(position(prod['birth_position']),'finite native birth position')
 require(type(trace) is list and len(trace)==14,'complete bounded movement trace')
 for row,tick in zip(trace,range(301,432,10)):
  require(set(row)=={'tick','position','state','path_status','bank'},'trace fields')
  require(type(row['tick']) is int and row['tick']==tick and position(row['position']) and row['bank']==bank,'trace identity conservation')
  require(row['state'] in ['move','idle'] and type(row['path_status']) is str and len(row['path_status'])<=64,'bounded ordinary motion state')
 require(trace[0]['position']==prod['birth_position'],'birth sample binding')
 require(math.dist(trace[-1]['position'],prod['latest_target'])<.2 and math.dist(trace[-1]['position'],prod['birth_position'])>1,'actual travel to rally')

except Exception as e: errors.append(type(e).__name__)
print(json.dumps({'status':'FAIL' if errors else 'PASS','build':build,'expected_checks':len(names),'errors':errors}))
raise SystemExit(bool(errors))

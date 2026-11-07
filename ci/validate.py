"""Bounded clean-only verifier. Never imports or executes the game/fixture."""
from pathlib import Path
import argparse, hashlib, json, math, re
p=argparse.ArgumentParser();p.add_argument('--root',type=Path,required=True);p.add_argument('report',type=Path);a=p.parse_args()
errors=[];build='unknown'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
def require(ok,label):
 if not ok: errors.append(label)
def integer(x): return type(x) is int or (type(x) is float and math.isfinite(x) and x.is_integer())
def vec(v): return type(v) is list and len(v)==3 and all(type(x) in (int,float) and math.isfinite(x) for x in v)
base=['reconstructed premise','ordinary paid training','blocked sixty ticks','ordinary tick bounds','untouched geometry and health','no overlaps every tick','conserved paid bank','one receipt only']
cn=['no move no fulfillment','retry budget retained'];mn=['ordinary move completed','one fulfillment and birth','original receipt queue committed','freed exit used safely','forty tick duplicate guard']
names=['expected unchanged build']+['control '+n for n in base+cn]+['move '+n for n in base+mn]
try:
 require(a.report.stat().st_size<=1000000,'bounded report size')
 if a.report.stat().st_size>1000000: raise ValueError('report too large')
 r=json.loads(a.report.read_text()); folder=Path(__file__).parent;lock_path=folder/'source_lock.json';lock=json.loads(lock_path.read_text())
 build=re.search(r'const BUILD_ID = "([^"]+)"',(a.root/'scripts/rules.gd').read_text())[1]
 require(build==lock['build']=='vc-c09af531eecf','exact c09 source')
 require(len(lock['files'])==192 and len(lock['imported_extras'])==5,'source inventory count')
 actual={p.relative_to(a.root).as_posix() for p in a.root.rglob('*') if p.is_file() and '.godot' not in p.parts and '__pycache__' not in p.parts}
 require(actual==set(lock['files'])|set(lock['imported_extras']),'exact imported source inventory')
 for part in ['files','imported_extras']:
  for path,digest in lock[part].items():require(sha(a.root/path)==digest,'source hash '+path)
 for field,path in [('game_sha256',a.root/'scripts/game.gd'),('manifest_sha256',a.root/'reports/build-manifest.json'),('contract_sha256',folder/'contract.gd'),('source_lock_sha256',lock_path)]: require(r[field]==sha(path),field)
 require(r['schema']=='production-exit-reconstruction-v1' and r['build']==build,'report identity')
 require(r['total_ticks_per_case']==221 and r['completed'] is True and type(r['failed']) is int and r['failed']==0,'completion')
 require([c['name'] for c in r['checks']]==names and all(c['pass'] is True for c in r['checks']),'exact ordered24 checks')
 require(r['engine']['major']==4 and r['engine']['minor']==6 and r['engine']['patch']==3 and r['engine']['status']=='stable','engine4.6.3')
 require(type(r['cases']) is list and [c['name'] for c in r['cases']]==['control','move'],'ordered cases')
 layout=json.loads(re.search(r'^const LAYOUT = (.*)$',(folder/'contract.gd').read_text(),re.M)[1]);id_map={str(row[0]):i for i,row in enumerate(layout)}
 require(len(layout)==36 and len(id_map)==36,'fixture layout count')
 for c in r['cases']:
  tag=c['name']; moving=tag=='move';initial=c['initial'];trace=c['trace'];receipt=c['receipt_id'];qid=c['queue_id'];producer=id_map['78'];mover=id_map['85']
  require(initial['entities']==37 and initial['live']==16 and initial['capacity']==20 and initial['bank']=={'food':150000,'wood':200000},tag+' initial population/bank')
  require(initial['id_map']==id_map and initial['producer']==producer and initial['mover']['id']==mover and initial['mover']['pos']==[-30.5,0,21.5],tag+' exact mapped identities')
  require(initial['free_exits']==[] and initial['clearance']['ok'] is True,tag+' blocked clear premise')
  require(c['acceleration']=={'tick':1,'before':359,'after':0},tag+' disclosed ready acceleration')
  require(receipt=='payment:1' and qid==0,tag+' sole receipt identity')
  train={'building':producer,'kind':'spearman','command_id':tag+'-train','type':'train','team':0,'sequence':1,'enqueue_tick':0}
  commands=[train]
  if moving: commands.append({'ids':[mover],'target':-1,'position':[-31.5,0,21.5],'command_id':'move-clear-exit','type':'order','team':0,'sequence':2,'enqueue_tick':61})
  require(c['commands']==commands,tag+' exact ordinary commands')
  require(type(trace) is list and len(trace)==220 and [t['tick'] for t in trace]==list(range(2,222)),tag+' contiguous bounded ticks')
  birth=c['birth_tick'];require(integer(birth) and (62<=birth<=181 if moving else birth==-1),tag+' bounded birth')
  last_pos=[-30.5,0,21.5];transitions=0;last_state='open';last_polls=0;last_checks=0;poll_ticks=[];newborn_id=None
  for t in trace:
   tick=t['tick'];born=moving and tick>=birth
   require(vec(t['mover']),tag+' finite mover')
   require(math.dist(t['mover'],last_pos)<=.1001,tag+' bounded physical movement'); last_pos=t['mover']
   if not moving or tick<=61: require(t['mover']==[-30.5,0,21.5],tag+' unmoved before boundary')
   require(t['geometry'] is True and type(t['minimum_unit_distance']) in (int,float) and math.isfinite(t['minimum_unit_distance']) and t['minimum_unit_distance']>=.7-1e-6,tag+' nonoverlap')
   require(t['reserved_population']==17 and t['live']==(17 if born else 16) and t['commits']==(1 if born else 0),tag+' population/commit sequence')
   expected='fulfilled' if born else 'open';require(t['receipt_state']==expected,tag+' receipt sequence')
   if t['receipt_state']!=last_state:transitions+=1;last_state=t['receipt_state']
   poll_delta=t['polls']-last_polls;check_delta=t['candidate_checks']-last_checks
   require(poll_delta in (0,1) and check_delta>=0,tag+' monotonic bounded poll')
   if poll_delta:
    poll_ticks.append(tick);require(check_delta==(1 if born else 16),tag+' bounded candidates')
   else:require(check_delta==0,tag+' no extra candidates')
   last_polls=t['polls'];last_checks=t['candidate_checks']
   if born:
    require(t['queue']==[],tag+' ready order removed')
    n=t['newborn'];require(n['kind']=='spearman' and n['team']==0 and n['alive'] is True and n['pos']==[-30.5,0,21.5],tag+' valid newborn at released exit')
    if newborn_id is None:newborn_id=n['id']
    require(n['id']==newborn_id==37,tag+' same sole newborn')
    require(math.dist(t['mover'],n['pos'])>=.7-1e-6,tag+' blocker newborn separation')
   else:
    require(t['newborn']=={} and len(t['queue'])==1,tag+' blocked queue retained')
    q=t['queue'][0];require(q['receipt_id']==receipt and q['queue_id']==qid and q['kind']=='spearman' and q['remaining_ticks']==0 and q['started'] is True and q['next_retry_tick']==poll_ticks[-1]+20,tag+' original queued item')
  require(poll_ticks==list(range(2,(birth if moving else 221)+1,20)),tag+' exact retry schedule')
  require(transitions==(1 if moving else 0),tag+' exact transition count')
  if moving: require(trace[-1]['mover']==[-31.5,0,21.5] and trace[-1]['mover_state']=='idle' and 221-birth>=40,tag+' settled duplicate guard')
  require(c['final_bank']=={'food':100000,'wood':180000} and c['final_audit']=={'ok':True,'errors':[]} and c['fixed_final_unchanged'] is True,tag+' conserved unchanged world')
  fr=c['final_receipt'];require(fr['state']==('fulfilled' if moving else 'open') and fr['paid_milli']=={'food':50000,'wood':20000} and fr['cost_units']=={'food':50,'wood':20} and fr['refund_policy']=='started',tag+' final receipt')
  require(c['final_commits']==([{'building':producer,'queue':qid,'tick':birth}] if moving else []),tag+' sole ordered commit')
  transactions=c['final_transactions'];require(set(transactions)==({'payment:1','fulfilled:payment:1'} if moving else {'payment:1'}),tag+' no second charge or closure')
  require(transactions['payment:1']['signature']==['pay',0,{'food':50,'wood':20},'unstarted','purchase'] and transactions['payment:1']['result']['applied'] is True and transactions['payment:1']['result']['ok'] is True,tag+' actual paid transaction')
  if moving: require(transactions['fulfilled:payment:1']['signature']==['close_cost','payment:1',0,'fulfilled'] and transactions['fulfilled:payment:1']['result']['applied'] is True and transactions['fulfilled:payment:1']['result']['ok'] is True,tag+' actual fulfilled transaction')
except Exception as e: errors.append(type(e).__name__)
print(json.dumps({'schema':'production-exit-verdict-v1','status':'FAIL' if errors else 'PASS','build':build,'expected_checks':len(names),'error_count':len(errors),'errors':[s[:120] for s in errors[:16]]}))
raise SystemExit(bool(errors))

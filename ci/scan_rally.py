"""Closed ordinary native ScreenTouch rally production proof; no physical-phone claim."""
from pathlib import Path
import argparse,json,math,re
import scan_evidence as base
BUILD='vc-fe500d2ea0b5'
SCENARIO='native_ground_rally_portrait_v1'
SCOPE='normal seeded simulation with routed synthetic native touch; not physical phone or measured frame rate'
CAPTURE={'mode':'ground_rally','kind':'native_controlled_ground_rally','frame_count':4}
LABELS=['rally_targeting','rally_set','rally_cancel_preserved','newborn_rally_move']
ACTIONS=['worker_select','producer_select','rally_enter','rally_target','rally_reenter','rally_cancel','train']
CHECKS=['normal seeded initial state','worker target exists','producer target exists','producer selected by touch','rally_enter reachable','explicit rally targeting','rally_targeting raw screenshot saved','visible empty ground exists','rally accepted normally','rally_set raw screenshot saved','rally_reenter reachable','rally_cancel reachable','cancel preserves previous rally','rally_cancel_preserved raw screenshot saved','train reachable','normal paid train queued','paid newborn observed','newborn ordinary move progresses','original paid receipt fulfilled','newborn_rally_move raw screenshot saved']
ERRORS={'Rally contract differs','Rally checks differ','Rally input differs','Rally state differs','Rally camera differs','Rally UI differs','Rally payment differs','Rally birth differs','Rally movement differs'}
def need(v,reason='Rally state differs'):base.require(v,reason)
def num(v):return type(v) in (int,float) and math.isfinite(v)
def integer(v,lo=0,hi=100000):return type(v) is int and lo<=v<=hi
def vec(v):return type(v) is list and len(v)==3 and all(num(x) and abs(x)<=100 for x in v)
def near(a,b,tol=3e-6):
 if type(b) is list:return type(a) is list and len(a)==len(b) and all(near(x,y,tol) for x,y in zip(a,b))
 return num(a) and num(b) and abs(a-b)<=tol
def distance(a,b):return math.sqrt(sum((x-y)**2 for x,y in zip(a,b)))
def rect(r):return type(r) is list and len(r)==4 and all(num(x) for x in r) and r[2]>=0 and r[3]>=0
def inside(r):return rect(r) and r[0]>=-1 and r[1]>=-1 and r[0]+r[2]<=391 and r[1]+r[3]<=845
def encloses(a,b):return rect(a) and rect(b) and a[0]<=b[0]+.01 and a[1]<=b[1]+.01 and a[0]+a[2]+.01>=b[0]+b[2] and a[1]+a[3]+.01>=b[1]+b[3]
def cross(a,b):return [a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0]]
def unit(v):n=math.sqrt(sum(x*x for x in v));return [x/n for x in v]
BACK=unit([19,25,23]);RIGHT=unit(cross([0,1,0],BACK));UP=cross(BACK,RIGHT)
CAMERA={'focus':[-25,0,24],'zoom':30,'projection':1,'keep_aspect':1,'size':30,'near':.1,'far':120,'transform':[RIGHT,UP,BACK,[-6,25,47]]}
BANK={'food':150000,'wood':200000};PAID={'food':100000,'wood':200000}
def state(v):
 need(set(v)=={'tick','selected','rally_building','touch_command','rally_point','bank','queue','commands'} and integer(v['tick']) and type(v['selected']) is list and type(v['touch_command']) is bool and type(v['queue']) is list and type(v['commands']) is list)
 need(v['rally_point'] is None or vec(v['rally_point']))
def units(rows):
 need(type(rows) is list and 6<=len(rows)<=7,'Rally birth differs')
 ids=[]
 for u in rows:
  need(set(u)=={'id','kind','pos','state','mode','target','dest','motion_tick','motion_position'} and integer(u['id']) and u['kind'] in ('villager','scout') and vec(u['pos']) and vec(u['dest']) and integer(u['motion_tick'],-1) and vec(u['motion_position']),'Rally birth differs');ids.append(u['id'])
 need(ids==sorted(set(ids)),'Rally birth differs');return {u['id']:u for u in rows}
def validate(report,lock):
 need(lock.get('capture_contract')==CAPTURE and lock.get('build')==BUILD and lock.get('fixed_fps')==20 and lock.get('rally_viewport')==[390,844],'Rally contract differs')
 need(report.get('scenario')==SCENARIO and report.get('scope')==SCOPE and report.get('fixed_fps')==20,'Rally contract differs')
 rows=report.get('checks',[]);need([r.get('name') for r in rows]==CHECKS and all(set(r)=={'name','pass'} and r['pass'] is True for r in rows) and report.get('failed')==0,'Rally checks differ')
 frames=report.get('frames',[]);need(len(frames)==4 and [f['label'] for f in frames]==LABELS,'Rally contract differs')
 sid=report.get('worker_id');pid=report.get('producer_id');nid=report.get('newborn_id');target=report.get('target')
 need(integer(sid,1,5) and pid==0 and integer(nid,78) and vec(target) and abs(target[1])<1e-6 and 4<=distance(target,[-25,0,24])<=7)
 need(all(abs((target[k]-.5)-round(target[k]-.5))<1e-6 for k in (0,2)))
 initial=report['initial'];state(initial['state']);initial_units=units(initial['units']);need(set(initial_units)==set(range(1,7)) and [initial_units[i]['kind'] for i in range(1,7)]==['villager']*5+['scout'])
 need(initial['state']['selected']==[0] and initial['state']['rally_building']==-1 and initial['state']['touch_command'] is False and initial['state']['rally_point'] is None and initial['state']['bank']==BANK and initial['state']['queue']==initial['state']['commands']==initial['spawn_commits']==[])
 events=report.get('inputs',[]);need(len(events)==14,'Rally input differs');prior=-1
 for i,name in enumerate(ACTIONS):
  a,b=events[2*i:2*i+2]
  for j,e in enumerate((a,b)):
   need(set(e)=={'action','pressed','position','tick','frame','target_rect'} and e['action']==name and e['pressed'] is (j==0) and integer(e['frame']) and e['frame']>prior and integer(e['tick']),'Rally input differs');prior=e['frame']
   need(type(e['position']) is list and len(e['position'])==2 and all(num(x) for x in e['position']) and 0<=e['position'][0]<390 and 0<=e['position'][1]<844,'Rally input differs')
  need(a['position']==b['position'] and a['target_rect']==b['target_rect'] and b['tick']>=a['tick'],'Rally input differs')
  if i in (2,4,5,6):
   rr=a['target_rect'];need(inside(rr) and rr[3]>=44 and near(a['position'],[rr[0]+rr[2]/2,rr[1]+rr[3]/2]),'Rally input differs')
  else:need(a['target_rect']==[],'Rally input differs')
 acts=report.get('actions',[]);need(len(acts)==7 and [a.get('action') for a in acts]==ACTIONS,'Rally input differs')
 for i,a in enumerate(acts):
  need(set(a)=={'action','before','after_release'},'Rally input differs');state(a['before']);state(a['after_release'])
  need(a['after_release']['tick']==events[2*i+1]['tick'] and a['before']['tick']==events[2*i]['tick'],'Rally input differs')
  need(a['before']['commands']==[] and a['before']['bank']==a['after_release']['bank']==BANK)
  if i not in (3,6):need(a['after_release']['commands']==[])
 need(acts[0]['before']['selected']==[0] and acts[0]['after_release']['selected']==[sid] and acts[1]['after_release']['selected']==[0])
 for i in (2,4):need(acts[i]['after_release']['rally_building']==0 and acts[i]['after_release']['touch_command'] is True)
 need(acts[3]['after_release']['rally_point'] is None and acts[3]['after_release']['rally_building']==-1 and acts[3]['after_release']['touch_command'] is False)
 for side in ['before','after_release']:need(near(acts[5][side]['rally_point'],target) and acts[5][side]['bank']==BANK)
 need(acts[5]['after_release']['rally_building']==-1 and acts[5]['after_release']['touch_command'] is False,'Rally state differs')
 rallycmds=acts[3]['after_release']['commands'];traincmds=acts[6]['after_release']['commands'];need(len(rallycmds)==len(traincmds)==1,'Rally input differs')
 rc,tc=rallycmds[0],traincmds[0]
 for cmd,kind in [(rc,'rally'),(tc,'train')]:need(cmd.get('type')==kind and cmd.get('team')==0 and cmd.get('building')==0 and integer(cmd.get('sequence'),1) and cmd.get('command_id')==str(cmd.get('sequence')) and integer(cmd.get('enqueue_tick')),'Rally input differs')
 need(tc['sequence']>rc['sequence'],'Rally input differs')
 need(set(rc)=={'type','team','building','position','sequence','command_id','enqueue_tick'} and vec(rc['position']) and distance(rc['position'],target)<.001 and rc['enqueue_tick']==acts[3]['after_release']['tick'],'Rally input differs')
 need(set(tc)=={'type','team','building','kind','sequence','command_id','enqueue_tick'} and tc['kind']=='villager' and tc['enqueue_tick']==acts[6]['after_release']['tick'],'Rally input differs')
 training=report['training'];q=training['queue'];receipt=training['paid_receipt'];finalreceipt=report['final_receipt']
 need(set(training)=={'observed_tick','queue','paid_receipt'} and integer(training['observed_tick']) and set(q)=={'receipt_id','queue_id','kind','remaining_ticks','started','next_retry_tick','candidate_cursor'},'Rally payment differs')
 need(type(q['receipt_id']) is str and re.fullmatch(r'payment:[1-9][0-9]{0,5}',q['receipt_id']) and integer(q['queue_id']) and q['kind']=='villager' and integer(q['remaining_ticks'],1,299) and q['started'] is True,'Rally payment differs')
 need(q['remaining_ticks']==300-(training['observed_tick']-tc['enqueue_tick']),'Rally payment differs')
 expected_receipt={'team':0,'cost_units':{'food':50},'paid_milli':{'food':50000,'wood':0},'refund_policy':'started','purpose':'purchase','state':'open'}
 need(receipt==expected_receipt and finalreceipt==dict(expected_receipt,state='fulfilled'),'Rally payment differs')
 birth=report['birth'];need(set(birth)=={'tick','unit','spawn_commits'} and integer(birth['tick']) and tc['enqueue_tick']+300<=birth['tick']<=tc['enqueue_tick']+360,'Rally birth differs')
 need(birth['spawn_commits']==[{'building':0,'queue':q['queue_id'],'tick':birth['tick']}],'Rally birth differs')
 bu=birth['unit'];need(bu['id']==nid and bu['kind']=='villager' and bu['state']=='move' and bu['mode']=='MOVE' and bu['target']==-1 and vec(bu['pos']) and near(bu['dest'],target),'Rally birth differs')
 movement=report['movement'];need(type(movement) is list and 1<=len(movement)<=30,'Rally movement differs');prev=birth['tick']
 for m in movement:
  need(set(m)=={'tick','pos','state','mode','dest','target','motion_tick','motion_position'} and integer(m['tick']) and m['tick']==prev+1 and vec(m['pos']) and near(m['dest'],target) and m['mode']=='MOVE' and m['state']=='move' and m['target']==-1 and integer(m['motion_tick'],-1) and vec(m['motion_position']),'Rally movement differs');prev=m['tick']
 need(distance(movement[-1]['pos'],bu['pos'])>=.5 and len({tuple(m['pos']) for m in movement})>=2,'Rally movement differs')
 final=report['final'];state(final);need(final['bank']==PAID and final['queue']==final['commands']==[] and near(final['rally_point'],target) and final['selected']==[0] and final['rally_building']==-1 and final['touch_command'] is False)
 finalunits=units(report['final_units']);need(set(finalunits)==set(initial_units)|{nid} and finalunits[nid]['state']=='move' and near(finalunits[nid]['dest'],target),'Rally birth differs')
 need(frames[0]['process_frame']<=events[6]['frame'] and frames[1]['process_frame']<=events[8]['frame'] and frames[2]['process_frame']<=events[12]['frame'] and frames[3]['ui_state']['tick']>=movement[-1]['tick'],'Rally input differs')
 findings=[];prior=-1
 for i,f in enumerate(frames):
  need(f.get('scenario')==SCENARIO and f['image']=='%03d-%s.png'%(i,LABELS[i].replace('_','-')) and f['fixed_fps']==20 and near(f['observed_process_delta_seconds'],.05,1e-8) and f['framebuffer']==f['logical_viewport']==[390,844] and f['content_scale_factor']==1 and f['test_mode'] is False,'Rally contract differs')
  need(integer(f['process_frame']) and f['process_frame']>prior,'Rally input differs');prior=f['process_frame'];need(f['input_count']==[6,8,12,14][i],'Rally input differs')
  c=f['camera'];need(set(c)==set(CAMERA) and all(near(c[k],CAMERA[k]) for k in CAMERA),'Rally camera differs')
  state(f['ui_state']);st=f['ui_state'];need(st['selected']==[0] and st['bank']==(PAID if i==3 else BANK) and st['queue']==st['commands']==[] and st['touch_command'] is (i==0) and st['rally_building']==(0 if i==0 else -1))
  need(st['rally_point'] is None if i==0 else near(st['rally_point'],target))
  snapshot=f['snapshot'];need(snapshot['build']==BUILD and snapshot['tick']==st['tick'] and snapshot['bank_milli']==st['bank'] and snapshot['selected']==[0] and snapshot['population']==(7 if i==3 else 6) and snapshot['capacity']==10 and snapshot['trained']==int(i==3) and snapshot['delivered']==0 and snapshot['own_pending_commands']==0 and snapshot['build_mode']=='' and snapshot['paused'] is False and snapshot['game_over'] is False)
  uu=units(f['own_units']);need(set(uu)==set(initial_units)|({nid} if i==3 else set()))
  poses=f['animation_poses'];need(len(poses)==1 and poses[0]['node']=='.');root=poses[0]['snapshot'];need(root['deaths']==[] and root['death_visual_cap']==16)
  for pose in root['live'].values():base.pose_identity(pose,lock)
  if i==3:need(str(nid) in root['live'] and root['live'][str(nid)]['kind']=='villager' and root['live'][str(nid)]['clip']=='walk','Rally movement differs')
  hud=f['hud'];need(set(hud)=={'title','detail','queue','toast','bottom_rect','actions','action_scroll_rect'},'Rally UI differs')
  for key in ['title','detail','queue','toast']:
   item=hud[key];need(set(item)=={'text','visible','rect','minimum_size','line_count'} and type(item['text']) is str and len(item['text'])<512 and type(item['visible']) is bool and rect(item['rect']) and type(item['minimum_size']) is list and len(item['minimum_size'])==2 and all(num(x) for x in item['minimum_size']) and integer(item['line_count'],0,20),'Rally UI differs')
   if item['visible'] and (not inside(item['rect']) or item['minimum_size'][1]>item['rect'][3]+1):findings.append({'kind':'possible_clipping','frame':LABELS[i],'control':key})
  need(hud['title']['text']=='主堡' and hud['queue']['text']=='','Rally UI differs')
  need(hud['detail']['text']=='點可見空地設定集合點；新單位自動移動。' if i==0 else '集合點已設定，新單位自動移動' in hud['detail']['text'],'Rally UI differs')
  if i==1:need(hud['toast']['visible'] is True and hud['toast']['text']=='集合點已設定；新單位自動移動。','Rally UI differs')
  aa=hud['actions'];need(type(aa) is list and len(aa)==(1 if i==0 else 3),'Rally UI differs')
  need([a['text'] for a in aa]==(['取消集合點'] if i==0 else ['集合點','取消集合點設定','訓練村民\n食 50 ']),'Rally UI differs')
  for a in aa:
   need(set(a)=={'text','rect','visible','disabled'} and a['visible'] is True and a['disabled'] is False and rect(a['rect']) and a['rect'][3]>=44,'Rally UI differs')
   if not inside(a['rect']) or not encloses(hud['action_scroll_rect'],a['rect']):findings.append({'kind':'action_not_fully_visible','frame':LABELS[i],'text':a['text']})
  if i==3:
   ns=f['newborn_screen'];need(type(ns) is list and len(ns)==2 and all(num(x) for x in ns) and 0<=ns[0]<390 and 90<=ns[1]<hud['bottom_rect'][1],'Rally movement differs')
  else:need(f['newborn_screen'] is None,'Rally contract differs')
  need(rect(hud['bottom_rect']) and rect(hud['action_scroll_rect']),'Rally UI differs')
  if not inside(hud['bottom_rect']):findings.append({'kind':'hud_outside_viewport','frame':LABELS[i]})
  marker=f['marker'];need(set(marker)=={'visible','position'} and type(marker['visible']) is bool and vec(marker['position']))
  if i>0:need(marker['visible'] is True and near(marker['position'],target),'Rally UI differs')
 return findings
original_scan=base.scan
def scan(directory,lock,digest):
 guard=json.loads((directory/'guard-receipt.json').read_text());need(guard.get('fixed_fps')==20,'Rally contract differs');return original_scan(directory,lock,digest)
base.scan=scan;base.validate_scenario=validate;base.SAFE_SCAN_REASONS=base.SAFE_SCAN_REASONS|ERRORS
if __name__=='__main__':
 p=argparse.ArgumentParser()
 for key in ('directory','lock','report'):p.add_argument('--'+key,type=Path,required=True)
 a=p.parse_args();raise SystemExit(base.scan_to_report(a.directory,a.lock,a.report))

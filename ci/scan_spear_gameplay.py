"""Closed four-event, real-scene controlled spear evidence admission.
Structural admission does not certify visual readability or authorize adoption.
"""
from pathlib import Path
import argparse,json,math
import scan_evidence as base
CAPTURE={'mode':'rts_spear','kind':'native_controlled_rts_spear','frame_count':4}
SCENARIO='native_controlled_rts_spear_v1'
LABELS=['idle','walk','attack-release','received-hit']
CLIPS=['idle','walk','attack','hit']
GAME='ea9f9927a9d593f0a7a2664763b6702e125d8588b8fdd8048e5af46792aefefc'
ERRORS={'Spear scenario differs','Spear camera differs','Spear authority differs','Spear pose differs','Spear fixture differs','Spear viewport differs','Spear pair differs','Spear pacing differs'}
def need(ok,reason='Spear scenario differs'):base.require(ok,reason)
def finite(x):return type(x) in (int,float) and math.isfinite(x)
def near(a,b,tol=3e-6):
 if type(b) is list:return type(a) is list and len(a)==len(b) and all(near(x,y,tol) for x,y in zip(a,b))
 return finite(a) and finite(b) and abs(a-b)<=tol
def distance(a,b):return math.sqrt(sum((x-y)**2 for x,y in zip(a,b)))
def cross(a,b):return [a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0]]
def normalized(x):n=math.sqrt(sum(t*t for t in x));return [t/n for t in x]
BACK=normalized([19,25,23]);RIGHT=normalized(cross([0,1,0],BACK));UP=cross(BACK,RIGHT)
CAMERA=[RIGHT,UP,BACK,[-6,25,47]]
IDENTITY=[[1,0,0],[0,1,0],[0,0,1],[0,0,0]]
def yaw_transform(yaw,position):
 c,s=math.cos(yaw),math.sin(yaw)
 return [[c,0,-s],[0,1,0],[s,0,c],position]
def transform(t):
 need(type(t) is list and len(t)==4 and all(type(x) is list and len(x)==3 and all(finite(v) for v in x) for x in t),'Spear pose differs')
 for axis in t[:3]:need(abs(sum(x*x for x in axis)-1)<1e-5,'Spear pose differs')
 for a,b in [(0,1),(1,2),(0,2)]:need(abs(sum(x*y for x,y in zip(t[a],t[b])))<1e-5,'Spear pose differs')
 need(near(cross(t[0],t[1]),t[2],1e-5),'Spear pose differs')
def frame_pose(frame,lock,subject):
 roots=frame.get('animation_poses');need(type(roots) is list and len(roots)==1 and roots[0].get('node')=='.','Spear pose differs')
 snap=roots[0].get('snapshot',{});need(snap.get('death_visual_cap')==16 and snap.get('deaths')==[],'Spear pose differs')
 live=snap.get('live',{});need(type(live) is dict and str(subject) in live,'Spear pose differs')
 for p in live.values():base.pose_identity(p,lock)
 return live[str(subject)]
def validate(report,lock):
 need(lock.get('capture_contract')==CAPTURE and lock.get('fixed_fps')==20 and lock['project_files'].get('scripts/game.gd')==GAME and lock.get('spear_viewport') in [[390,844],[844,390]])
 need(report.get('scenario')==SCENARIO and report.get('fixed_fps')==20 and report.get('scope')=='native_controlled_scene_combat')
 frames=report.get('frames',[]);need(len(frames)==4 and [f.get('label') for f in frames]==LABELS)
 mutations=report.get('fixture_mutations',[]);need(len(mutations)==2,'Spear fixture differs')
 first,second=mutations;sid=first.get('id');oid=second.get('id');spawn=report.get('opponent_spawn_tick')
 # Ordinary AI may create a paid building between the two fixture spawns.
 need(type(sid) is int and type(oid) is int and oid>sid>=0 and type(spawn) is int and spawn%20==1,'Spear fixture differs')
 need(first=={'operation':'controlled_spawn','kind':'spearman','team':0,'id':sid,'position':[-21.5,0,28.5],'tick':first.get('tick')} and type(first.get('tick')) is int and first['tick']>=12,'Spear fixture differs')
 need(second=={'operation':'controlled_spawn','kind':'spearman','team':1,'id':oid,'position':[-20.25,0,26.5],'tick':spawn,'initial_cooldown_ticks':10},'Spear fixture differs')
 commands=report.get('commands',[]);need(len(commands)==1,'Spear fixture differs')
 cmd=commands[0];need(set(cmd)=={'type','ids','target','position','team','tick','sequence','command_id'} and cmd['type']=='order' and cmd['ids']==[sid] and cmd['target']==-1 and cmd['position']==[-21.5,0,26.5] and cmd['team']==0 and cmd['tick']==frames[0]['game_tick'] and cmd['command_id']=='spear-fixture-0','Spear fixture differs')
 previous=-1;dimensions=None;hud_bounds=None
 for index,(f,clip) in enumerate(zip(frames,CLIPS)):
  need(f.get('scenario')==SCENARIO and f.get('image')=='%03d-%s.png'%(index,LABELS[index]))
  need(f.get('test_mode') is False and f.get('ai_enabled') is True and f.get('economy_audit_ok') is True and f.get('fixed_fps')==20 and near(f.get('observed_process_delta_seconds'),.05,1e-8),'Spear pacing differs')
  size=f.get('framebuffer');need(size==lock['spear_viewport'] and f.get('logical_viewport')==size and f.get('content_scale_factor')==1,'Spear viewport differs')
  if dimensions is None:dimensions=size
  need(size==dimensions,'Spear viewport differs')
  c=f.get('camera',{});need(set(c)=={'focus','zoom','projection','keep_aspect','size','near','far','transform'} and c['focus']==[-25,0,24] and c['zoom']==c['size']==30 and c['projection']==c['keep_aspect']==1 and near(c['near'],.1) and c['far']==120 and near(c['transform'],CAMERA),'Spear camera differs')
  tick=f.get('game_tick');need(type(tick) is int and tick>previous and near(f.get('game_seconds'),tick*.05) and type(f.get('game_frame_counter')) is int,'Spear authority differs');previous=tick
  snapshot=f.get('snapshot',{});need(snapshot.get('tick')==tick and near(snapshot.get('time'),tick*.05) and snapshot.get('build')==lock['build'] and snapshot.get('paused') is False and snapshot.get('game_over') is False and snapshot.get('selected')==f.get('selected')==[0],'Spear authority differs')
  s=f.get('subject',{});a=f.get('subject_authority',{});need(s.get('id')==a.get('id')==sid and s.get('kind')==a.get('kind')=='spearman' and s.get('owned') is True and s.get('alive') is True and a.get('alive') is True and s.get('team')==a.get('team')==0 and s.get('hp')==a.get('hp') and near(s.get('position'),a.get('position')),'Spear authority differs')
  pose=frame_pose(f,lock,sid);need(pose.get('clip')==clip and pose.get('kind')=='spearman' and pose.get('asset_sha256')==f.get('spear_asset_sha256')==lock['project_files']['assets/mature/models/spearman_action.scn'] and pose.get('dead_visual_only') is False,'Spear pose differs')
  player=f.get('player',{});need(player.get('assigned_clip')==clip and player.get('current_clip')=='' and player.get('paused') is True and near(player.get('actual_seconds'),player.get('controller_seconds'),1e-7) and near(player.get('controller_seconds'),pose.get('seek_seconds'),1e-7),'Spear pose differs')
  ts=f.get('production_transforms',{});need(set(ts)=={'unit','body','rig','skeleton','rig_local','skeleton_local'},'Spear pose differs')
  for t in ts.values():transform(t)
  need(near(ts['unit'][3],a['position']) and near(ts['body'][3],a['position']) and near(ts['rig'][3],a['position']) and near(ts['skeleton'][3],a['position']),'Spear pose differs')
  need(finite(a.get('body_yaw')) and near(ts['unit'],yaw_transform(0,a['position'])) and near(ts['body'],yaw_transform(a['body_yaw'],a['position'])) and near(ts['skeleton_local'],IDENTITY),'Spear pose differs')
  action_yaw=s.get('visual_action_yaw');need(finite(action_yaw),'Spear pose differs')
  wanted_yaw=a['body_yaw'] if clip in ('idle','walk') else action_yaw
  need(near(ts['rig'],yaw_transform(wanted_yaw,a['position'])) and near(ts['skeleton'],ts['rig']) and near(ts['rig_local'],yaw_transform(wanted_yaw-a['body_yaw'],[0,0,0])),'Spear pose differs')
  point=f.get('subject_screen');need(type(point) is list and len(point)==2 and all(finite(v) for v in point) and 0<=point[0]<size[0] and 0<=point[1]<size[1],'Spear viewport differs')
  delta=[a['position'][0]+25,a['position'][1]+.8,a['position'][2]-24]
  expected_screen=[size[0]/2+sum(x*y for x,y in zip(delta,RIGHT))*size[1]/30,size[1]/2-sum(x*y for x,y in zip(delta,UP))*size[1]/30]
  need(near(point,expected_screen,.001),'Spear viewport differs')
  hud=f.get('hud',{});bounds=[hud.get('top'),hud.get('bottom')]
  for b in bounds:
   need(type(b) is list and len(b)==4 and all(finite(v) for v in b),'Spear viewport differs')
   need(not(b[0]<=point[0]<=b[0]+b[2] and b[1]<=point[1]<=b[1]+b[3]),'Spear viewport differs')
  if hud_bounds is None:hud_bounds=bounds
  need(bounds==hud_bounds,'Spear viewport differs')
  if index<2:need(f.get('pair_events')==[] and a['hp']==60 and f.get('opponent')==f.get('opponent_authority')=={},'Spear authority differs')
  if index==0:need(a['state']=='idle' and near(a['position'],[-21.5,0,28.5]) and tick==first['tick']+4 and not s.get('visual_moving'),'Spear authority differs')
  if index==1:need(a['state']=='move' and s.get('visual_moving') is True and distance(a['position'],[-21.5,0,28.5])>=.4-1e-5,'Spear authority differs')
  if index>=2:
   o=f.get('opponent',{});oa=f.get('opponent_authority',{});need(o.get('id')==oa.get('id')==oid and o.get('kind')==oa.get('kind')=='spearman' and o.get('alive') is True and oa.get('alive') is True and o.get('team')==oa.get('team')==1 and o.get('hp')==oa.get('hp') and near(o.get('position'),oa.get('position')) and near(oa.get('position'),[-20.25,0,26.5]),'Spear authority differs')
   need(distance(a['position'],[-21.5,0,26.5])<=.2+1e-5 and distance(a['position'],oa['position'])<=1.45+1e-5 and spawn<tick<spawn+19,'Spear authority differs')
   e=report.get('attack_event' if index==2 else 'hit_event',{});expected=(sid,oid) if index==2 else (oid,sid)
   need(set(e)=={'attack_id','release_tick','attacker_id','target_id','damage','origin','endpoint'} and type(e['attack_id']) is int and e['attacker_id']==expected[0] and e['target_id']==expected[1] and e['damage']==5 and e['release_tick']==tick,'Spear authority differs')
   need(near(e['origin'],a['position'] if index==2 else oa['position']) and near(e['endpoint'],oa['position'] if index==2 else a['position']),'Spear authority differs')
   need(f.get('pair_events')==([e] if index==2 else [report['attack_event'],e]),'Spear authority differs')
   # Production observe() enters attack at impact.56*length1, then advances
   # the same normal fixed20 frame by.05; hit similarly enters0 then.05.
   if index==2:need(a['hp']==60 and oa['hp']==55 and pose['attack_release_tick']==tick and s['visual_attack_tick']==tick and tick==spawn+2 and near(player['actual_seconds'],.61,1e-7),'Spear authority differs')
   else:need(a['hp']==oa['hp']==55 and pose['hit_tick']==tick and s['visual_hit_tick']==tick and a['last_damage_tick']==tick and tick==spawn+10 and near(player['actual_seconds'],.05,1e-7),'Spear authority differs')
 return []

original_scan=base.scan
def scan_guard(directory,lock,digest):
 guard=json.loads((directory/'guard-receipt.json').read_text());need(guard.get('fixed_fps')==20,'Spear pacing differs')
 return original_scan(directory,lock,digest)
base.scan=scan_guard;base.validate_scenario=validate;base.SAFE_SCAN_REASONS=base.SAFE_SCAN_REASONS|ERRORS

def compare(baseline,candidate):
 """After each artifact passes its own scanner, compare intended match state.
 Mesh/native-file identity, build and rendered pixels may differ; all bone poses
 and presentation metadata must remain exact. Host timestamps may differ.
 """
 need(baseline['scenario']==candidate['scenario']==SCENARIO,'Spear pair differs')
 for key in ['commands','fixture_mutations','attack_event','hit_event','opponent_spawn_tick']:
  need(baseline[key]==candidate[key],'Spear pair differs')
 keys=['label','game_tick','game_seconds','game_frame_counter','fixed_fps','observed_process_delta_seconds','framebuffer','logical_viewport','content_scale_factor','test_mode','ai_enabled','selected','own_units','subject','opponent','subject_authority','opponent_authority','pair_events','camera','production_transforms','player','hud','subject_screen']
 for left,right in zip(baseline['frames'],candidate['frames']):
  for key in keys:need(left[key]==right[key],'Spear pair differs')
  ls=dict(left['snapshot']);rs=dict(right['snapshot']);ls.pop('build');rs.pop('build');need(ls==rs,'Spear pair differs')
 # Width-only comparison is against the af925 pose baseline, never original432766.
 need(baseline.get('build')=='vc-130723842165' and candidate.get('build')=='vc-8b74d2fbc5ef','Spear pair differs')
 for left,right in zip(baseline['frames'],candidate['frames']):
  need(left.get('spear_asset_sha256')=='af925f0f70fc14567796230dbc4d1543003e3a4bd52b3bc4554d4daea83c0038' and right.get('spear_asset_sha256')=='b530c245f0808896866e0261066d83492829bfb71b1ab168b39a8065dcaa1731','Spear pair differs')
  # Permit only the one reviewed SCN hash delta. All bones/poses/clip/visibility
  # fields, native paths, sample counters and unrelated actor hashes stay exact.
  normalized=json.loads(json.dumps(right['animation_poses']))
  for root in normalized:
   for pose in root['snapshot']['live'].values():
    if pose['kind']=='spearman':
     need(pose['asset_sha256']=='b530c245f0808896866e0261066d83492829bfb71b1ab168b39a8065dcaa1731','Spear pair differs')
     pose['asset_sha256']='af925f0f70fc14567796230dbc4d1543003e3a4bd52b3bc4554d4daea83c0038'
  need(left['animation_poses']==normalized,'Spear pair differs')
 return {'passed':True,'paired_frames':4,'scope':'exact control/state/time/camera/HUD match; pixels require independent visual review'}
if __name__=='__main__':
 p=argparse.ArgumentParser()
 for key in ['directory','lock','report']:p.add_argument('--'+key,type=Path,required=True)
 a=p.parse_args();raise SystemExit(base.scan_to_report(a.directory,a.lock,a.report))

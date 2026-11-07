"""Closed ScreenTouch preview/menu portrait evidence; image admission is not UI approval."""
from pathlib import Path
import argparse,json,math
import scan_evidence as base
CAPTURE={'mode':'selection_preview','kind':'native_controlled_selection_preview','frame_count':4}
BUILD='vc-f605f947768e'
SCENARIO='native_selection_preview_portrait_v1'
SCOPE='frozen normal seeded world; native ScreenTouch preview and menu selection, not paid construction or physical phone'
LABELS=['held_preview_before_army','army_actions_restored','held_preview_before_home','home_actions_restored']
ACTIONS=[p+'_'+a for p in ('army','home') for a in ('worker','house','plot','menu','target')]
CHECKS=['fixed portrait logical viewport','normal seeded targets']
for p,preview,restored in [('army',LABELS[0],LABELS[1]),('home',LABELS[2],LABELS[3])]:
 CHECKS += [p+' worker target',p+' worker selected',p+'_house reachable',p+' unheld preview',p+' guided plot reachable',p+' held legal preview',preview+' raw screenshot saved',p+'_menu reachable',p+' menu preserves preview',p+'_target reachable',p+' selected and closed',p+' preview fully retired',p+' actions restored',restored+' raw screenshot saved']
CHECKS += ['unchanged authority economy and frozen tick']
ERRORS={'Selection contract differs','Selection checks differ','Selection input differs','Selection state differs','Selection camera differs','Selection UI metadata differs','Selection pose differs'}
def need(value,reason='Selection state differs'):base.require(value,reason)
def finite(x):return type(x) in (int,float) and math.isfinite(x)
def near(a,b,tolerance=3e-6):
 if type(b) is list:return type(a) is list and len(a)==len(b) and all(near(x,y,tolerance) for x,y in zip(a,b))
 return finite(a) and finite(b) and abs(a-b)<=tolerance
def cross(a,b):return [a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0]]
def unit(x):n=math.sqrt(sum(v*v for v in x));return [v/n for v in x]
BACK=unit([19,25,23]);RIGHT=unit(cross([0,1,0],BACK));UP=cross(BACK,RIGHT)
def camera(focus):return [RIGHT,UP,BACK,[focus[0]+19,focus[1]+25,focus[2]+23]]
def rect(value):need(type(value) is list and len(value)==4 and all(finite(x) for x in value) and value[2]>=0 and value[3]>=0,'Selection UI metadata differs')
def inside(r):return r[0]>=-1 and r[1]>=-1 and r[0]+r[2]<=391 and r[1]+r[3]<=845
def validate(report,lock):
 need(lock.get('capture_contract')==CAPTURE and lock.get('fixed_fps')==20 and lock.get('selection_viewport')==[390,844] and lock.get('build')==BUILD,'Selection contract differs')
 need(report.get('scenario')==SCENARIO and report.get('fixed_fps')==20 and report.get('scope')==SCOPE,'Selection contract differs')
 rows=report.get('checks',[])
 need([r.get('name') for r in rows]==CHECKS and all(set(r)=={'name','pass'} and r['pass'] is True for r in rows) and report.get('failed')==0,'Selection checks differ')
 frames=report.get('frames',[]);need(len(frames)==4 and [f.get('label') for f in frames]==LABELS,'Selection contract differs')
 sid=report.get('worker_id');home=report.get('home_worker_id');need(type(sid) is int and sid in range(1,6) and type(home) is int and home in range(1,6) and report.get('army_ids')==[6])
 need(report.get('initial_tick')==report.get('final_tick')==0 and report.get('final_commands')==[])
 bank={'food':150000,'wood':200000};need(report.get('initial_bank')==report.get('final_bank')==bank)
 initial=report.get('initial_snapshot',{});need(initial.get('build')==BUILD and initial.get('tick')==0 and initial.get('selected')==[0] and initial.get('bank_milli')==bank and initial.get('population')==6 and initial.get('capacity')==10 and initial.get('own_pending_commands')==0 and initial.get('build_mode')=='' and initial.get('touch_mode') is False)
 inputs=report.get('inputs',[]);need(len(inputs)==20,'Selection input differs');previous=-1
 for i,action in enumerate(ACTIONS):
  press,release=inputs[i*2:i*2+2]
  for j,event in enumerate((press,release)):
   need(set(event)=={'x','y','pressed','tick','action','target_rect','frame'} and event['pressed'] is (j==0) and event['tick']==0 and event['action']==action,'Selection input differs')
   need(finite(event['x']) and finite(event['y']) and 0<=event['x']<390 and 0<=event['y']<844 and type(event['frame']) is int and event['frame']>previous,'Selection input differs');previous=event['frame']
  need(press['x']==release['x'] and press['y']==release['y'] and press['target_rect']==release['target_rect'],'Selection input differs')
  r=press['target_rect']
  if action.endswith(('_house','_menu','_target')):
   rect(r);need(inside(r) and r[2]>0 and r[3]>0 and near(press['x'],r[0]+r[2]/2) and near(press['y'],r[1]+r[3]/2),'Selection input differs')
  else:need(r==[],'Selection input differs')
 proofs=report.get('menu_proofs',[]);need(len(proofs)==2)
 for i,p in enumerate(proofs):need(p=={'action':['army','home'][i],'input_count':[8,18][i],'selected':[[sid],[home]][i],'build_mode':'house','held':True,'ghost_valid':True,'menu_visible':True,'tick':0})
 findings=[];previous=-1
 for i,f in enumerate(frames):
  preview=i in (0,2);current_worker=home if i>=2 else sid;selected=[current_worker] if preview else ([6] if i==1 else [0])
  need(f.get('scenario')==SCENARIO and f.get('image')=='%03d-%s.png'%(i,LABELS[i].replace('_','-')) and f.get('scope')==SCOPE,'Selection contract differs')
  need(f.get('fixed_fps')==20 and near(f.get('observed_process_delta_seconds'),.05,1e-8) and f.get('framebuffer')==f.get('logical_viewport')==[390,844] and f.get('content_scale_factor')==1,'Selection contract differs')
  need(f.get('test_mode') is True and f.get('game_tick')==0 and type(f.get('game_frame_counter')) is int and f['game_frame_counter']>previous);previous=f['game_frame_counter']
  need(type(f.get('process_frame')) is int and f['process_frame']>=inputs[[5,9,15,19][i]]['frame'],'Selection input differs')
  need(f.get('input_count')==[6,10,16,20][i] and f.get('selected')==selected and f.get('touch_command') is False and f.get('build_mode')==('house' if preview else ''))
  need(f.get('preview_held') is preview and f.get('ghost_valid') is preview and f.get('ghost_count')==int(preview) and f.get('build_confirm_valid') is preview)
  need(f.get('menu_visible') is False and f.get('menu_dismiss_visible') is False and f.get('pointer_counts')=={'all':0,'points':0,'gui':0,'epochs':0})
  need(type(f.get('pointer_world')) is list and len(f['pointer_world'])==3 and all(finite(x) for x in f['pointer_world']) and abs(f['pointer_world'][1])<1e-6)
  if preview:need(f.get('placement_ok') is True)
  need(f.get('bank')==bank and f.get('commands')==[] and f.get('producer_queue')==[])
  expected=initial.copy();expected.update(selected=selected,build_mode='house' if preview else '')
  need(f.get('snapshot')==expected)
  focus=[-21,0,22] if i in (1,2) else [-25,0,24]
  c=f.get('camera',{});need(set(c)=={'focus','zoom','projection','keep_aspect','size','near','far','transform'} and c['focus']==focus and c['zoom']==c['size']==30 and c['projection']==c['keep_aspect']==1 and near(c['near'],.1) and c['far']==120 and near(c['transform'],camera(focus)),'Selection camera differs')
  roots=f.get('animation_poses',[]);need(len(roots)==1 and roots[0].get('node')=='.','Selection pose differs');snap=roots[0].get('snapshot',{});live=snap.get('live',{})
  need(snap.get('death_visual_cap')==16 and snap.get('deaths')==[] and str(current_worker) in live and live[str(current_worker)].get('kind')=='villager','Selection pose differs')
  for pose in live.values():base.pose_identity(pose,lock)
  hud=f.get('hud',{});need(set(hud)=={'selection_title','detail','queue','toast','bottom_rect','top_rect','unit_tools_visible','command_visible','command_rect','actions','action_scroll_rect','action_scroll_horizontal'},'Selection UI metadata differs')
  for key in ('bottom_rect','top_rect','command_rect','action_scroll_rect'):rect(hud[key])
  need(type(hud['action_scroll_horizontal']) is int and hud['action_scroll_horizontal']>=0,'Selection UI metadata differs')
  actions=hud['actions'];need(type(actions) is list and len(actions)==(2 if i<3 else 1),'Selection UI metadata differs')
  for a in actions:
   need(set(a)=={'text','rect','visible','disabled'} and type(a['text']) is str and len(a['text'])<100 and a['visible'] is True and a['disabled'] is False,'Selection UI metadata differs');rect(a['rect'])
   r=a['rect'];scroll=hud['action_scroll_rect']
   if not inside(r) or r[0]<scroll[0]-1 or r[0]+r[2]>scroll[0]+scroll[2]+1:findings.append({'kind':'action_not_fully_visible','frame':LABELS[i],'index':actions.index(a)})
  texts=[a['text'] for a in actions]
  if preview:need(texts==['確認建造','取消建造'],'Selection UI metadata differs')
  elif i==1:need(texts==['停止','守備'],'Selection UI metadata differs')
  else:need(texts[0].startswith('訓練村民\n'),'Selection UI metadata differs')
  need(hud['unit_tools_visible'] is (i==1) and hud['command_visible'] is (i==1),'Selection UI metadata differs')
  for key in ('selection_title','detail','queue','toast'):
   item=hud[key];need(set(item)=={'text','rect','minimum_size','visible','line_count'} and type(item['text']) is str and len(item['text'])<512 and type(item['visible']) is bool and type(item['line_count']) is int and 0<=item['line_count']<=20,'Selection UI metadata differs');rect(item['rect'])
   need(type(item['minimum_size']) is list and len(item['minimum_size'])==2 and all(finite(x) and x>=0 for x in item['minimum_size']),'Selection UI metadata differs')
   if item['visible'] and (not inside(item['rect']) or item['minimum_size'][1]>item['rect'][3]+1):findings.append({'kind':'possible_ui_clipping','frame':LABELS[i],'control':key})
  if not inside(hud['bottom_rect']):findings.append({'kind':'hud_outside_viewport','frame':LABELS[i]})
  need(hud['selection_title']['text']==('建造 民居' if preview else ('斥候' if i==1 else '主堡')),'Selection UI metadata differs')
  need(hud['queue']['text']==('木材 50' if preview else '') and hud['queue']['visible'] is preview,'Selection UI metadata differs')
  if preview:need('位置已選，按確認建造' in hud['detail']['text'],'Selection UI metadata differs')
  elif i==1:need('按指令再點目標' in hud['detail']['text'] and inside(hud['command_rect']),'Selection UI metadata differs')
  else:need('新單位在出口待命' in hud['detail']['text'],'Selection UI metadata differs')
 return findings
original_scan=base.scan
def scan(directory,lock,digest):
 guard=json.loads((directory/'guard-receipt.json').read_text());need(guard.get('fixed_fps')==20,'Selection contract differs')
 return original_scan(directory,lock,digest)
base.scan=scan;base.validate_scenario=validate;base.SAFE_SCAN_REASONS=base.SAFE_SCAN_REASONS|ERRORS
if __name__=='__main__':
 p=argparse.ArgumentParser()
 for key in ('directory','lock','report'):p.add_argument('--'+key,type=Path,required=True)
 a=p.parse_args();raise SystemExit(base.scan_to_report(a.directory,a.lock,a.report))

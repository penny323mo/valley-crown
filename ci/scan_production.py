"""Closed portrait ScreenTouch/HUD evidence. Admission is not automatic layout approval."""
from pathlib import Path
import argparse,json,math
import scan_evidence as base
CAPTURE={'mode':'production_guidance','kind':'native_controlled_production_guidance','frame_count':4}
BUILD='vc-d99ac5d19247'
SCENARIO='native_production_guidance_portrait_v1'
LABELS=['producer_selected','producer_ground_hint','synthetic_blocked_queue','unit_move_submitted']
CHECKS=['fixed portrait logical viewport','initial worker target exists','initial routed touch changes keep selection to worker','producer touch target exists','routed touch selects producer','producer waiting guidance','no producer command controls','producer_selected raw screenshot saved','ground target exists','touch gives building-specific guidance','touch preserves selection and queued commands','no accidental recruitment or payment','producer_ground_hint raw screenshot saved','ready exit guidance actionable','synthetic_blocked_queue raw screenshot saved','visible worker touch target exists','routed touch selects worker','unit guidance retained without implicit order','unit command button visible and in viewport','routed command button enters targeting','routed ground tap submits one move','unit_move_submitted raw screenshot saved','test mode blocks all simulation ticks']
ERRORS={'Production contract differs','Production checks differ','Production input differs','Production state differs','Production camera differs','Production UI metadata differs','Production pose differs'}
def need(value,reason='Production state differs'):base.require(value,reason)
def finite(x):return type(x) in (int,float) and math.isfinite(x)
def near(a,b,tolerance=3e-6):
 if type(b) is list:return type(a) is list and len(a)==len(b) and all(near(x,y,tolerance) for x,y in zip(a,b))
 return finite(a) and finite(b) and abs(a-b)<=tolerance
def cross(a,b):return [a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0]]
def unit(x):n=math.sqrt(sum(v*v for v in x));return [v/n for v in x]
BACK=unit([19,25,23]);RIGHT=unit(cross([0,1,0],BACK));UP=cross(BACK,RIGHT)
CAMERA=[RIGHT,UP,BACK,[-6,25,47]]
def rect(value):need(type(value) is list and len(value)==4 and all(finite(x) for x in value) and value[2]>=0 and value[3]>=0,'Production UI metadata differs')
def inside(r):return r[0]>=-1 and r[1]>=-1 and r[0]+r[2]<=391 and r[1]+r[3]<=845
def validate(report,lock):
 need(lock.get('capture_contract')==CAPTURE and lock.get('fixed_fps')==20 and lock.get('production_viewport')==[390,844] and lock.get('build')==BUILD,'Production contract differs')
 need(report.get('scenario')==SCENARIO and report.get('fixed_fps')==20 and report.get('scope')=='frozen native ScreenTouch and synthetic queue UI; not production replay or physical phone','Production contract differs')
 checks=report.get('checks',[])
 need([r.get('name') for r in checks]==CHECKS and all(r.get('pass') is True and set(r)=={'name','pass'} for r in checks) and report.get('failed')==0,'Production checks differ')
 frames=report.get('frames',[]);need(len(frames)==4 and [r.get('label') for r in frames]==LABELS,'Production contract differs')
 sid=report.get('worker_id');keep=report.get('producer_id');tick=report.get('initial_tick')
 need(keep==0 and type(sid) is int and sid>0 and report.get('initial_worker_id')==sid and tick==report.get('final_tick')==0)
 bank=report.get('initial_bank');need(bank=={'food':150000,'wood':200000} and report.get('final_bank')==bank and report.get('final_queue')==[])
 initial=report.get('initial_snapshot',{});need(initial.get('build')==BUILD and initial.get('selected')==[keep] and initial.get('tick')==0 and initial.get('bank_milli')==bank and initial.get('own_pending_commands')==0 and initial.get('population')==6 and initial.get('capacity')==10)
 inputs=report.get('inputs',[]);need(len(inputs)==14,'Production input differs')
 for i in range(0,14,2):
  press,release=inputs[i:i+2]
  need(set(press)==set(release)=={'x','y','pressed','tick'} and press['pressed'] is True and release['pressed'] is False,'Production input differs')
  need(press['tick']==release['tick']==tick and press['x']==release['x'] and press['y']==release['y'] and finite(press['x']) and finite(press['y']) and 0<=press['x']<390 and 0<=press['y']<844,'Production input differs')
 for a,b in [(0,6),(4,8),(8,12)]:need(inputs[a]==inputs[b] and inputs[a+1]==inputs[b+1],'Production input differs')
 command=report.get('final_commands');need(type(command) is list and len(command)==1)
 cmd=command[0];need(set(cmd)=={'type','team','sequence','enqueue_tick','command_id','ids','position','target'} and cmd['type']=='order' and cmd['team']==0 and cmd['sequence']==1 and cmd['enqueue_tick']==0 and cmd['command_id']=='1' and cmd['ids']==[sid] and cmd['target']==-1)
 need(type(cmd['position']) is list and len(cmd['position'])==3 and all(finite(x) for x in cmd['position']) and abs(cmd['position'][1])<1e-5 and all(abs(x)<=40 for x in (cmd['position'][0],cmd['position'][2])))
 findings=[];previous=-1
 for i,f in enumerate(frames):
  need(f.get('scenario')==SCENARIO and f.get('image')=='%03d-%s.png'%(i,LABELS[i].replace('_','-')),'Production contract differs')
  need(f.get('fixed_fps')==20 and near(f.get('observed_process_delta_seconds'),.05,1e-8) and f.get('framebuffer')==f.get('logical_viewport')==[390,844] and f.get('content_scale_factor')==1,'Production contract differs')
  need(f.get('test_mode') is True and f.get('game_tick')==tick and type(f.get('game_frame_counter')) is int and f['game_frame_counter']>previous);previous=f['game_frame_counter']
  need(f.get('input_count')==[4,6,6,14][i] and f.get('touch_command') is False and f.get('selected')==([keep] if i<3 else [sid]))
  need(f.get('bank')==bank and f.get('commands')==([] if i<3 else command) and f.get('producer_queue')==([{'remaining_ticks':0}] if i==2 else []))
  expected=initial.copy();expected.update(selected=f['selected'],own_pending_commands=int(i==3),population=initial['population']+int(i==2))
  need(f.get('snapshot')==expected)
  c=f.get('camera',{});need(set(c)=={'focus','zoom','projection','keep_aspect','size','near','far','transform'} and c['focus']==[-25,0,24] and c['zoom']==c['size']==30 and c['projection']==c['keep_aspect']==1 and near(c['near'],.1) and c['far']==120 and near(c['transform'],CAMERA),'Production camera differs')
  roots=f.get('animation_poses',[]);need(len(roots)==1 and roots[0].get('node')=='.','Production pose differs');snap=roots[0].get('snapshot',{});live=snap.get('live',{})
  need(snap.get('death_visual_cap')==16 and snap.get('deaths')==[] and str(sid) in live and live[str(sid)].get('kind')=='villager','Production pose differs')
  for pose in live.values():base.pose_identity(pose,lock)
  hud=f.get('hud',{});need(set(hud)=={'selection_title','detail','queue','toast','bottom_rect','top_rect','unit_tools_visible','command_visible','command_rect','actions','action_scroll_rect','action_scroll_horizontal'},'Production UI metadata differs')
  for key in ('bottom_rect','top_rect','command_rect','action_scroll_rect'):rect(hud[key])
  need(type(hud['action_scroll_horizontal']) is int and hud['action_scroll_horizontal']>=0,'Production UI metadata differs')
  actions=hud['actions'];need(type(actions) is list and 1<=len(actions)<=6,'Production UI metadata differs')
  for action in actions:
   need(set(action)=={'text','rect','visible','disabled'} and type(action['text']) is str and len(action['text'])<100 and type(action['visible']) is bool and type(action['disabled']) is bool,'Production UI metadata differs');rect(action['rect'])
  if i<3:
   train=[a for a in actions if a['text'].startswith('訓練村民\n')]
   need(len(train)==1 and train[0]['visible'] is True and train[0]['disabled'] is False,'Production UI metadata differs')
   r=train[0]['rect'];scroll=hud['action_scroll_rect']
   if not inside(r) or r[0]<scroll[0]-1 or r[0]+r[2]>scroll[0]+scroll[2]+1:findings.append({'kind':'train_control_not_fully_visible','frame':LABELS[i]})
  need(hud['unit_tools_visible'] is (i==3) and hud['command_visible'] is (i==3),'Production UI metadata differs')
  for key in ('selection_title','detail','queue','toast'):
   item=hud[key];need(set(item)=={'text','rect','minimum_size','visible','line_count'} and type(item['text']) is str and len(item['text'])<512 and type(item['visible']) is bool and type(item['line_count']) is int and 0<=item['line_count']<=20,'Production UI metadata differs');rect(item['rect'])
   need(type(item['minimum_size']) is list and len(item['minimum_size'])==2 and all(finite(x) and x>=0 for x in item['minimum_size']),'Production UI metadata differs')
   if item['visible'] and (not inside(item['rect']) or item['minimum_size'][1]>item['rect'][3]+1):findings.append({'kind':'possible_ui_clipping','frame':LABELS[i],'control':key})
  if not inside(hud['bottom_rect']):findings.append({'kind':'hud_outside_viewport','frame':LABELS[i]})
  if i<3:need(hud['selection_title']['text']=='主堡' and '新單位在出口待命，選取後按指令移動' in hud['detail']['text'],'Production UI metadata differs')
  if i==1:need(hud['toast']['visible'] is True and hud['toast']['text']=='已選取建築。先點選自己的單位，再按指令移動。','Production UI metadata differs')
  need(hud['queue']['text']==('訓練完成，出口受阻；選取門口單位，再按指令移開' if i==2 else '') and hud['queue']['visible'] is (i==2),'Production UI metadata differs')
  if i==3:
   need(hud['selection_title']['text']=='村民' and '按指令再點目標' in hud['detail']['text'] and inside(hud['command_rect']),'Production UI metadata differs')
   r=hud['command_rect'];need(near(inputs[10]['x'],r[0]+r[2]/2) and near(inputs[10]['y'],r[1]+r[3]/2),'Production input differs')
 return findings
original_scan=base.scan
def scan(directory,lock,digest):
 guard=json.loads((directory/'guard-receipt.json').read_text());need(guard.get('fixed_fps')==20,'Production contract differs')
 return original_scan(directory,lock,digest)
base.scan=scan;base.validate_scenario=validate;base.SAFE_SCAN_REASONS=base.SAFE_SCAN_REASONS|ERRORS
if __name__=='__main__':
 p=argparse.ArgumentParser()
 for key in ('directory','lock','report'):p.add_argument('--'+key,type=Path,required=True)
 a=p.parse_args();raise SystemExit(base.scan_to_report(a.directory,a.lock,a.report))

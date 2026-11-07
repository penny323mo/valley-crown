"""Strict four-frame controlled terminal/restart evidence; not a natural phone match."""
from pathlib import Path
import argparse,json,math
import scan_evidence as base
import check_restart
CAPTURE={'mode':'match_restart','kind':'native_controlled_match_restart','frame_count':4}
SCENARIO='native_match_restart_portrait_v1'
SCOPE='native controlled portrait ScreenTouch; synthetic victory fixture, actual UI surrender defeat, genuine scene reload; not natural phone match or physical device'
ERRORS={'Restart contract differs','Restart behavior contract failed','Restart state differs','Restart camera differs','Restart pose differs','Restart input boundary differs'}
def need(value,reason='Restart state differs'):base.require(value,reason)
def finite(x):return type(x) in (int,float) and math.isfinite(x)
def near(a,b,tol=3e-6):
 if type(b) is list:return type(a) is list and len(a)==len(b) and all(near(x,y,tol) for x,y in zip(a,b))
 return finite(a) and finite(b) and abs(a-b)<=tol
def cross(a,b):return [a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0]]
def unit(a):n=math.sqrt(sum(x*x for x in a));return [x/n for x in a]
BACK=unit([19,25,23]);RIGHT=unit(cross([0,1,0],BACK));UP=cross(BACK,RIGHT)
CAMERA=[RIGHT,UP,BACK,[-6,25,47]]
def validate(report,lock):
 need(lock.get('capture_contract')==CAPTURE and lock.get('build')=='vc-d99ac5d19247' and lock.get('fixed_fps')==20 and lock.get('restart_viewport')==[390,844],'Restart contract differs')
 need(report.get('scenario')==SCENARIO and report.get('fixed_fps')==20 and report.get('scope')==SCOPE and report.get('harness_sha256')==lock['harness_sha256'],'Restart contract differs')
 try:check_restart.validate(report)
 except ValueError:raise ValueError('Restart behavior contract failed') from None
 initial=report['initial'];snap=initial['snapshot']
 need(snap.get('build')==lock['build'] and snap.get('time')==0 and snap.get('population')==6 and snap.get('capacity')==10 and snap.get('own_pending_commands')==0 and snap.get('selected')==[0] and snap.get('bank_milli')==initial['bank']=={'food':150000,'wood':200000})
 need(initial.get('ai') is True and initial.get('over') is False and initial.get('actions_empty') is True and initial.get('corpses_empty') is True and initial.get('queue')=='')
 inputs=report['inputs'];previous=-1
 for i,e in enumerate(inputs):
  need(set(e)=={'x','y','pressed','canceled','double_tap','viewport','tick','reloads','frame'} and type(e['double_tap']) is bool,'Restart input boundary differs')
  need(e['tick']==(1 if i in (6,7) else 0) and e['reloads']==int(i>=8),'Restart input boundary differs')
  need(type(e['frame']) is int and e['frame']>previous,'Restart input boundary differs');previous=e['frame']
 frames=report['frames'];previous=-1
 for i,f in enumerate(frames):
  need(f.get('scenario')==SCENARIO and f.get('image')=='%03d-%s.png'%(i,check_restart.LABELS[i].replace('_','-')),'Restart contract differs')
  need(f.get('fixed_fps')==20 and near(f.get('observed_process_delta_seconds'),.05,1e-8) and f.get('framebuffer')==f.get('logical_viewport')==f.get('viewport')==[390,844] and f.get('content_scale_factor')==1 and f.get('test_mode') is True,'Restart contract differs')
  need(f.get('source_sha256')==f.get('game_sha256')==lock['project_files']['scripts/game.gd'],'Restart contract differs')
  need(type(f.get('frame')) is int and f['frame']==f.get('process_frame') and f['frame']>previous);previous=f['frame']
  need(f.get('input_count')==[0,6,8,16][i] and f.get('tick')==[0,1,0,0][i])
  st=f['state'];ss=st['snapshot']
  need(ss.get('build')==lock['build'] and ss.get('tick')==f['tick'] and near(ss.get('time'),f['tick']*.05) and ss.get('outcome')==['victory','defeat','',''][i] and ss.get('game_over') is (i<2) and st['ai'] is True and ss.get('bank_milli')==st['bank']==initial['bank'])
  need(st.get('actions_empty') is True and st.get('corpses_empty') is True)
  if i<3:need(st['commands']==[])
  c=f.get('camera',{});need(set(c)=={'focus','zoom','projection','keep_aspect','size','near','far','transform'} and c['focus']==[-25,0,24] and c['zoom']==c['size']==30 and c['projection']==c['keep_aspect']==1 and near(c['near'],.1) and c['far']==120 and near(c['transform'],CAMERA),'Restart camera differs')
  roots=f.get('animation_poses',[]);need(len(roots)==1 and roots[0].get('node')=='.','Restart pose differs');poses=roots[0].get('snapshot',{});live=poses.get('live',{})
  need(poses.get('death_visual_cap')==16 and poses.get('deaths')==[] and type(live) is dict and 1<=len(live)<=128,'Restart pose differs')
  for pose in live.values():base.pose_identity(pose,lock)
  if i==0:need(f['frame']<inputs[0]['frame'],'Restart input boundary differs')
  else:need(f['frame']>inputs[[0,5,7,15][i]]['frame'],'Restart input boundary differs')
  if i in (1,2):need(f['frame']<inputs[[0,6,8,0][i]]['frame'],'Restart input boundary differs')
 # The held press/release is on the actual visible end-panel button center.
 rect=frames[1]['restart']['rect']
 need(near(inputs[6]['x'],rect[0]+rect[2]/2) and near(inputs[6]['y'],rect[1]+rect[3]/2),'Restart input boundary differs')
 need(inputs[8]['x']==inputs[6]['x'] and inputs[8]['y']==inputs[6]['y'],'Restart input boundary differs')
 command=frames[3]['state']['commands'][0]
 need(command.get('team')==0 and command.get('sequence')==1 and command.get('enqueue_tick')==0 and command.get('command_id')=='1')
 need(frames[3]['state']['command_sequence']==1 and frames[3]['state']['snapshot'].get('own_pending_commands')==1 and frames[3]['state']['touch_command'] is False)
 return []
original_scan=base.scan
def scan(directory,lock,digest):
 guard=json.loads((directory/'guard-receipt.json').read_text());need(guard.get('fixed_fps')==20,'Restart contract differs')
 return original_scan(directory,lock,digest)
base.scan=scan;base.validate_scenario=validate;base.SAFE_SCAN_REASONS=base.SAFE_SCAN_REASONS|ERRORS
if __name__=='__main__':
 p=argparse.ArgumentParser()
 for key in ('directory','lock','report'):p.add_argument('--'+key,type=Path,required=True)
 a=p.parse_args();raise SystemExit(base.scan_to_report(a.directory,a.lock,a.report))

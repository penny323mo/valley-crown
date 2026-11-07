#!/usr/bin/env python3
"""Admit only matched-time normal opening evidence; never automatic art approval."""
from pathlib import Path
import argparse,json,math
import scan_evidence as base
SCENARIO='native_original_ground_opening_v1'
LABELS=['opening-%02d'%i for i in range(10)]
ERRORS={'Opening contract differs','Opening normal state differs','Opening frame timing differs','Opening public scene differs','Opening pose differs','Opening renderer telemetry differs'}
def need(ok,why):base.require(ok,why)
def num(x):return type(x) in (int,float) and math.isfinite(x)
def contract(viewport):return {'scenario':SCENARIO,'viewport':viewport,'fixed_fps':20,'ticks':list(range(12,22)),'input':'none','camera':'unchanged opening','frames':LABELS}
def validate(report,lock):
 c=lock.get('opening_contract',{});viewport=c.get('viewport')
 need(viewport in ([390,844],[844,390]) and c==contract(viewport) and lock.get('fixed_fps')==20 and type(lock['fixed_fps']) is int and
      lock['capture_contract']=={'mode':'gameplay','kind':'genuine_native_game_viewport','frame_count':10} and report.get('scenario')==SCENARIO and
      report.get('fixed_fps')==20 and report.get('commands')==[] and report.get('input_events')==[],'Opening contract differs')
 frames=report['frames'];need([f.get('label') for f in frames]==LABELS,'Opening contract differs')
 for i,f in enumerate(frames):
  need(f.get('scenario')==SCENARIO and f.get('fixed_fps')==20 and f.get('framebuffer')==f.get('logical_viewport')==viewport and f.get('content_scale_factor')==1 and
       f.get('ground_sha256')==lock['project_files']['assets/mature/terrain/ground.gdshader'] and f.get('camera_focus')==[-25,0,24] and f.get('camera_zoom')==30,
       'Opening contract differs')
  need(f.get('test_mode') is False and f.get('ai_enabled') is True and f.get('selected')==[0],'Opening normal state differs')
  need(f.get('game_tick')==12+i and f.get('game_frame_counter')==12+i and type(f.get('process_frame')) is int and
       (i==0 or f['process_frame']==frames[i-1]['process_frame']+1) and num(f.get('game_seconds')) and math.isclose(f['game_seconds'],(12+i)*.05,rel_tol=0,abs_tol=1e-6) and
       num(f.get('observed_process_delta_seconds')) and math.isclose(f['observed_process_delta_seconds'],.05,rel_tol=0,abs_tol=1e-8),'Opening frame timing differs')
  s=f.get('snapshot',{})
  expected={'bank_milli':{'food':150000,'wood':200000},'build':lock['build'],'build_mode':'','built':0,'capacity':10,'delivered':0.,'economy_scale':1000,'game_over':False,'outcome':'','own_pending_commands':0,'paused':False,'population':6,'selected':[0],'tick':12+i,'touch_mode':False,'trained':0}
  need(all(s.get(k)==v for k,v in expected.items()),'Opening normal state differs')
  units=f.get('own_units',[])
  need(len(units)==6 and sorted((u.get('id'),u.get('kind')) for u in units)==[(1,'villager'),(2,'villager'),(3,'villager'),(4,'villager'),(5,'villager'),(6,'scout')] and
       all(u.get('state')=='idle' and u.get('carry')==0 and u.get('path_points')==0 for u in units),'Opening public scene differs')
  need(i==0 or units==frames[0]['own_units'],'Opening public scene differs')
  roots=f.get('animation_poses');need(type(roots) is list and len(roots)==1 and roots[0].get('node')=='.','Opening pose differs')
  snap=roots[0]['snapshot'];live=snap.get('live',{})
  need(set(live)=={str(n) for n in range(1,7)} and snap.get('deaths')==[],'Opening pose differs')
  for n,p in live.items():
   need(p.get('kind')==('scout' if n=='6' else 'villager') and p.get('clip')=='idle' and p.get('dead_visual_only') is False,'Opening pose differs');base.pose_identity(p,lock)
  need(all(type(f.get(k)) is int and f[k]>0 for k in ('visible_draw_calls','visible_primitives')),'Opening renderer telemetry differs')
 return []
original_scan=base.scan
def scan_guard(directory,lock,digest):
 guard=json.loads((directory/'guard-receipt.json').read_text())
 need(type(guard.get('fixed_fps')) is int and guard['fixed_fps']==20,'Opening frame timing differs')
 return original_scan(directory,lock,digest)
base.scan=scan_guard;base.validate_scenario=validate;base.SAFE_SCAN_REASONS=base.SAFE_SCAN_REASONS|ERRORS
if __name__=='__main__':
 p=argparse.ArgumentParser()
 for key in ('directory','lock','report'):p.add_argument('--'+key,type=Path,required=True)
 a=p.parse_args();raise SystemExit(base.scan_to_report(a.directory,a.lock,a.report))

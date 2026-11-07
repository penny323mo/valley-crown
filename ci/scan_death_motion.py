#!/usr/bin/env python3
"""Admit31 real native clip samples, not synthetic frames or real-time performance."""
from pathlib import Path
import argparse,json,math
import scan_evidence as base
CONTRACT_PATH=Path(__file__).with_name('death-motion-contract.json')
CONTRACT=json.loads(CONTRACT_PATH.read_text())
CAPTURE={'mode':'death_motion','kind':'native_controlled_death_motion','frame_count':31}
ERRORS={'Motion contract differs','Motion samples differ','Motion fixture differs','Motion pose differs','Motion result differs','Motion pacing differs','Motion native output differs','Motion frame sequence differs'}
def need(ok,why):base.require(ok,why)
def numeric(x):return type(x) in (int,float) and math.isfinite(x)
def near(a,b):
 if numeric(b):return numeric(a) and math.isclose(a,b,rel_tol=0,abs_tol=1e-6)
 if type(b) is list:return type(a) is list and len(a)==len(b) and all(near(x,y) for x,y in zip(a,b))
 if type(b) is dict:return type(a) is dict and set(a)==set(b) and all(near(a[k],b[k]) for k in b)
 return type(a) is type(b) and a==b

def validate(report,lock):
 need(lock.get('death_motion_contract')==CONTRACT and lock.get('support_files',{}).get('ci/death-motion-contract.json')==base.sha(CONTRACT_PATH) and
      lock.get('capture_contract')==CAPTURE and type(lock.get('fixed_fps')) is int and lock['fixed_fps']==20,'Motion contract differs')
 need(report.get('scenario')==CONTRACT['scenario'] and report.get('mode')=='death_motion' and type(report.get('fixed_fps')) is int and report['fixed_fps']==20 and
      type(report.get('actor_pose_count')) is int and report['actor_pose_count']==93 and type(report.get('failed')) is int and report['failed']==0 and
      type(report.get('sample_hz')) is int and report['sample_hz']==20,'Motion result differs')
 frames=report.get('frames',[]);labels=['death-motion-%02d'%i for i in range(31)]
 need(len(frames)==31 and all(type(c.get('pass')) is bool for c in report.get('checks',[])) and
      report.get('checks')==[{'name':label+' framebuffer saved','pass':True} for label in labels],'Motion result differs')
 for kind,digest in CONTRACT['output_scn_sha256'].items():
  need(lock['project_files'].get('assets/mature/models/'+kind+'_action.scn')==digest,'Motion native output differs')
 hashes={k:set() for k in CONTRACT['kinds']}
 for index,(frame,seconds) in enumerate(zip(frames,CONTRACT['sample_seconds'])):
  need(frame.get('label')==labels[index] and frame.get('image')=='%03d-%s.png'%(index,labels[index]) and
       frame.get('kinds')==CONTRACT['kinds'] and frame.get('clip')=='death' and frame.get('scenario')==CONTRACT['scenario'] and
       type(frame.get('sample_index')) is int and frame['sample_index']==index and near(frame.get('sample_seconds'),seconds) and
       frame.get('props')==CONTRACT['props'] and near(frame.get('clip_length_seconds'),1.5),'Motion samples differ')
  need(frame.get('original_fixture_sha256')==CONTRACT['original_fixture_sha256'] and frame.get('framebuffer')==[844,390] and
       frame.get('unit_state')=='controlled_paused_death_motion_sample' and near(frame.get('camera'),CONTRACT['camera']) and
       near(frame.get('floor'),CONTRACT['floor']) and near(frame.get('body_positions'),CONTRACT['body_positions']),'Motion fixture differs')
  need(type(frame.get('fixed_fps')) is int and frame['fixed_fps']==20 and type(frame.get('sample_hz')) is int and frame['sample_hz']==20,'Motion pacing differs')
  need(frame.get('sample_players_paused')==[True,True,True] and all(type(x) is bool for x in frame['sample_players_paused']) and
       near(frame.get('player_position_seconds'),[seconds]*3),'Motion pose differs')
  need(type(frame.get('process_frame')) is int and (index==0 or frame['process_frame']>frames[index-1]['process_frame']),'Motion frame sequence differs')
  poses=frame.get('animation_poses',[])
  need(type(poses) is list and len(poses)==3,'Motion pose differs')
  for pose,kind in zip(poses,CONTRACT['kinds']):
   need(pose.get('kind')==kind and pose.get('clip')=='death' and near(pose.get('seek_seconds'),seconds) and
        pose.get('dead_visual_only') is False and pose.get('occlusion',{}).get('authorized') is False,'Motion pose differs')
   digest=base.pose_identity(pose,lock);hashes[kind].add(digest)
   need(set(CONTRACT['props'][kind]).issubset({b['bone'] for b in pose['poses']}),'Motion pose differs')
 need(all(len(v)>=3 for v in hashes.values()),'Motion pose differs')
 need(len({f.get('image_sha256') for f in frames})==31,'Motion frame sequence differs')
 return []
original_scan=base.scan
def scan_guard(directory,lock,digest):
 guard=json.loads((directory/'guard-receipt.json').read_text())
 need(type(guard.get('fixed_fps')) is int and guard['fixed_fps']==20,'Motion pacing differs')
 return original_scan(directory,lock,digest)
base.scan=scan_guard;base.validate_scenario=validate;base.SAFE_SCAN_REASONS=base.SAFE_SCAN_REASONS|ERRORS
if __name__=='__main__':
 p=argparse.ArgumentParser()
 for key in ('directory','lock','report'):p.add_argument('--'+key,type=Path,required=True)
 a=p.parse_args();raise SystemExit(base.scan_to_report(a.directory,a.lock,a.report))

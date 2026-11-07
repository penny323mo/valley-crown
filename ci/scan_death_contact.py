#!/usr/bin/env python3
"""Admit raw paused death milestones, never automatic contact/art acceptance."""
from pathlib import Path
import argparse, json, math
import scan_evidence as base
CONTRACT_PATH=Path(__file__).with_name('death-contact-contract.json')
CONTRACT=json.loads(CONTRACT_PATH.read_text())
CAPTURE={'mode':'death_contact','kind':'native_controlled_death_contact','frame_count':7}
ERRORS={'Death contract differs','Death milestones differ','Death fixture differs','Death pose differs','Death result differs','Death pacing differs','Death native output differs'}

def need(ok,why):base.require(ok,why)
def numeric(x):return type(x) in (int,float) and math.isfinite(x)
def near(a,b):
 if numeric(b):return numeric(a) and math.isclose(a,b,rel_tol=0,abs_tol=1e-6)
 if type(b) is list:return type(a) is list and len(a)==len(b) and all(near(x,y) for x,y in zip(a,b))
 if type(b) is dict:return type(a) is dict and set(a)==set(b) and all(near(a[k],b[k]) for k in b)
 return type(a) is type(b) and a==b

def validate(report,lock):
 need(lock.get('death_contact_contract')==CONTRACT and lock.get('support_files',{}).get('ci/death-contact-contract.json')==base.sha(CONTRACT_PATH) and
      lock.get('capture_contract')==CAPTURE and type(lock.get('fixed_fps')) is int and lock['fixed_fps']==20,'Death contract differs')
 need(report.get('scenario')==CONTRACT['scenario'] and report.get('mode')=='death_contact' and type(report.get('fixed_fps')) is int and report['fixed_fps']==20 and
      type(report.get('distinct_class_time_samples')) is int and report['distinct_class_time_samples']==17 and type(report.get('failed')) is int and report['failed']==0,'Death result differs')
 frames=report.get('frames',[]);studies=CONTRACT['studies']
 need(len(frames)==7 and all(type(c.get('pass')) is bool for c in report.get('checks',[])) and report.get('checks')==[{'name':s['label']+' framebuffer saved','pass':True} for s in studies],'Death result differs')
 for kind,digest in CONTRACT['output_scn_sha256'].items():
  need(lock['project_files'].get('assets/mature/models/'+kind+'_action.scn')==digest,'Death native output differs')
 hashes={k:set() for k in CONTRACT['output_scn_sha256']}
 seen={}
 for index,(frame,study) in enumerate(zip(frames,studies)):
  need(frame.get('label')==study['label'] and frame.get('image')=='%03d-%s.png'%(index,study['label']) and
       frame.get('kind')==study['kind'] and frame.get('clip')=='death' and frame.get('scenario')==CONTRACT['scenario'] and
       frame.get('sample_labels')==study['sample_labels'] and frame.get('props')==study['props'] and
       near(frame.get('sample_seconds'),study['seconds']) and near(frame.get('clip_length_seconds'),1.5),'Death milestones differ')
  need(frame.get('original_fixture_sha256')==CONTRACT['original_fixture_sha256'] and frame.get('framebuffer')==[844,390] and
       frame.get('unit_state')=='controlled_paused_death_milestones' and near(frame.get('camera'),CONTRACT['camera']) and
       near(frame.get('floor'),CONTRACT['floor']) and near(frame.get('body_positions'),CONTRACT['body_positions']),'Death fixture differs')
  need(type(frame.get('fixed_fps')) is int and frame['fixed_fps']==20,'Death pacing differs')
  need(frame.get('sample_players_paused')==[True,True,True] and all(type(x) is bool for x in frame['sample_players_paused']),'Death pose differs')
  poses=frame.get('animation_poses',[])
  need(type(poses) is list and len(poses)==3,'Death pose differs')
  for pose,seconds in zip(poses,study['seconds']):
   need(pose.get('kind')==study['kind'] and pose.get('clip')=='death' and near(pose.get('seek_seconds'),seconds) and
        pose.get('dead_visual_only') is False and pose.get('occlusion',{}).get('authorized') is False,'Death pose differs')
   digest=base.pose_identity(pose,lock);hashes[study['kind']].add(digest)
   need(set(study['props']).issubset({b['bone'] for b in pose['poses']}),'Death pose differs')
   key=(study['kind'],seconds)
   need(key not in seen or seen[key]==digest,'Death pose differs');seen[key]=digest
 need(len(seen)==17 and all(len(v)>=3 for v in hashes.values()),'Death pose differs')
 return []

original_scan=base.scan
def scan_guard(directory,lock,digest):
 guard=json.loads((directory/'guard-receipt.json').read_text())
 need(type(guard.get('fixed_fps')) is int and guard['fixed_fps']==20,'Death pacing differs')
 return original_scan(directory,lock,digest)
base.scan=scan_guard;base.validate_scenario=validate;base.SAFE_SCAN_REASONS=base.SAFE_SCAN_REASONS|ERRORS
if __name__=='__main__':
 p=argparse.ArgumentParser()
 for key in ('directory','lock','report'):p.add_argument('--'+key,type=Path,required=True)
 a=p.parse_args();raise SystemExit(base.scan_to_report(a.directory,a.lock,a.report))

#!/usr/bin/env python3
"""Admit exactly four controlled held-spear triptychs; no death/art acceptance."""
from pathlib import Path
import argparse,json,math
import scan_evidence as base
CONTRACT_PATH=Path(__file__).with_name('held-contract.json')
CONTRACT=json.loads(CONTRACT_PATH.read_text())
CAPTURE={'mode':'held_spear_studies','kind':'native_controlled_held_spear_study','frame_count':4}
ERRORS={'Held contract differs','Held samples differ','Held pose differs','Held result differs','Held pacing differs','Held native output differs','Held caption differs','Held study binding differs'}
def need(ok,why):base.require(ok,why)
def num(x):return type(x) in (int,float) and math.isfinite(x)
def near(a,b):
 if num(b):return num(a) and math.isclose(a,b,rel_tol=0,abs_tol=1e-7)
 if type(b) is list:return type(a) is list and len(a)==len(b) and all(near(x,y) for x,y in zip(a,b))
 return type(a) is type(b) and a==b

def check_names():
 names=[]
 for clip in CONTRACT['clips']:
  names += ['spearman '+clip+' sample '+str(i)+' bound reviewed native rig' for i in range(3)]
  names += ['spearman '+clip+' sample '+str(i)+' exact paused native seek' for i in range(3)]
  names += ['spearman '+clip+' framebuffer saved','spearman '+clip+' bone poses change']
 return names+['exactly four held spear clips captured']
def request_times(clip):
 length=CONTRACT['clip_lengths'][clip]
 return [min(length*f,length-1e-6) if clip in ('idle','walk') else length*f for f in CONTRACT['fractions'][clip]]
def captions(clip,build):
 t=request_times(clip);middle=56 if clip=='attack' else 35;qualifier=' (clamped)' if clip in ('idle','walk') else ''
 return ('HELD SPEAR '+clip+' | '+build+' | SCN'+CONTRACT['native_output_sha256'][:12]+' | NOT GAMEPLAY',
         '0%%: %.3fs | %d%%: %.3fs | 100%%: %.3fs%s | paused native poses'%(t[0],middle,t[1],t[2],qualifier))
def validate(report,lock):
 need(lock.get('held_contract')==CONTRACT and lock['support_files'].get('ci/held-contract.json')==base.sha(CONTRACT_PATH) and lock.get('capture_contract')==CAPTURE and type(lock.get('fixed_fps')) is int and lock['fixed_fps']==20,'Held contract differs')
 asset='assets/mature/models/spearman_action.scn'
 need(lock['project_files'].get(asset)==CONTRACT['native_output_sha256']==report.get('validated_native_sha256'),'Held native output differs')
 need(report.get('mode')=='held_spear_studies' and type(report.get('failed')) is int and report['failed']==0,'Held result differs')
 checks=report.get('checks',[])
 need([c.get('name') for c in checks]==check_names() and all(c.get('pass') is True for c in checks),'Held result differs')
 frames=report.get('frames',[]);studies=report.get('studies',[])
 need(len(frames)==len(studies)==4,'Held result differs')
 for index,(f,s,clip) in enumerate(zip(frames,studies,CONTRACT['clips'])):
  times=request_times(clip);caption,samples=captions(clip,lock['build'])
  need(f.get('label')=='spearman-'+clip and f.get('image')=='%03d-spearman-%s.png'%(index,clip) and f.get('kind')=='spearman' and f.get('clip')==clip and f.get('fractions')==CONTRACT['fractions'][clip] and near(f.get('clip_length_seconds'),CONTRACT['clip_lengths'][clip]) and f.get('unit_state')=='controlled_paused_clip_samples' and f.get('framebuffer')==[844,390],'Held samples differ')
  need(near(f.get('requested_times'),times) and near(f.get('actual_positions'),times) and f.get('assigned_clips')==[clip]*3 and f.get('paused_states')==[True]*3 and all(type(x) is bool for x in f['paused_states']) and f.get('loop_endpoint_policy')==CONTRACT['endpoint_policy'],'Held pose differs')
  need(f.get('caption_text')==caption and f.get('samples_text')==samples,'Held caption differs')
  poses=f.get('animation_poses',[])
  need(type(poses) is list and len(poses)==3,'Held pose differs')
  hashes=[]
  for p,t in zip(poses,times):
   need(p.get('kind')=='spearman' and p.get('clip')==clip and near(p.get('seek_seconds'),t) and p.get('dead_visual_only') is False and p.get('occlusion',{}).get('authorized') is False,'Held pose differs')
   hashes.append(base.pose_identity(p,lock));need('prop_spear' in {b['bone'] for b in p['poses']},'Held pose differs')
  need(len(set(hashes))>=2,'Held pose differs')
  expected={'kind':'spearman','clip':clip,'fractions':f['fractions'],'png':f['image'],'png_sha256':f['image_sha256'],'size':[844,390],'poses':poses,'caption_text':caption,'samples_text':samples,'requested_times':f['requested_times'],'actual_positions':f['actual_positions'],'assigned_clips':f['assigned_clips'],'paused_states':f['paused_states']}
  need(s==expected,'Held study binding differs')
 return []
original_scan=base.scan
def scan_guard(directory,lock,digest):
 guard=json.loads((directory/'guard-receipt.json').read_text());need(type(guard.get('fixed_fps')) is int and guard['fixed_fps']==20,'Held pacing differs')
 return original_scan(directory,lock,digest)
base.scan=scan_guard;base.validate_scenario=validate;base.SAFE_SCAN_REASONS=base.SAFE_SCAN_REASONS|ERRORS
if __name__=='__main__':
 p=argparse.ArgumentParser()
 for key in ('directory','lock','report'):p.add_argument('--'+key,type=Path,required=True)
 a=p.parse_args();raise SystemExit(base.scan_to_report(a.directory,a.lock,a.report))

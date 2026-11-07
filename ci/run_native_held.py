"""One bounded hosted native child; preserve exact accepted source and import cache."""
from pathlib import Path
import json,os,shutil,stat,re
import guarded_manifest_ci as g
HERE=Path(__file__).resolve().parent
PACKAGE='069473af06b2519fb4fff01c774533e76ac07eb77d89b7d918064ad1e7f92bb4'
ARCHIVE='a4740d4e00862128d06dea1030dfd0efea6c9c0e8bc0e89f3a0396b5314d8f98'
ADAPTER='1737dfca2778614730b6dd6d3803009460139a19dfe901b830e84120abce75e0'
BUILD='vc-43276605e0fb'
SCENES={'spearman_action.scn'}
def read(p):return json.loads(p.read_text(),parse_constant=lambda _:(_ for _ in ()).throw(ValueError('Nonfinite JSON')))
def snapshot(root):
 result={}
 for p in root.rglob('*'):
  mode=p.lstat().st_mode;g.require(not stat.S_ISLNK(mode),'Symlink rejected')
  if stat.S_ISDIR(mode):continue
  g.require(stat.S_ISREG(mode),'Special file rejected');result[p.relative_to(root).as_posix()]=g.sha(p)
 return result
def strict_guard(prefix):
 r=g.guard_receipt(prefix.with_suffix('.json'),prefix.with_suffix('.invocation.json'))
 text=re.sub(r'\x1b\[[0-9;]*[A-Za-z]','',prefix.with_suffix('.log').read_text(encoding='utf-8'))
 g.require(re.search(r'(?im)(?:SCRIPT ERROR|PARSE ERROR|ASSERTION FAILED|Fontconfig error|(?:^|\s)(?:ERROR|WARNING):)',text) is None,'Engine diagnostic rejected')
 g.require(type(r['system_before']['oom_kill']) is int and r['system_before']['oom_kill']==r['system_after']['oom_kill'],'OOM changed');return r

def main():
 g.require_hosted_approval(True,os.environ);g.checked(HERE/'guarded_manifest_ci.py',ADAPTER)
 project=Path('project').resolve();archive=Path('construction-source.zip').resolve();manifest=Path('CONSTRUCTION_SOURCE_PACKAGE.json').resolve();xdg=Path('private/import').resolve();out=Path('held-evidence').resolve()
 g.require(not out.exists() and not out.is_symlink(),'Fresh evidence required');out.mkdir()
 summary={'base_build':BUILD,'passed':False,'held_attempts':0}
 try:
  package,entries=g.verify_source(project,archive,manifest,ARCHIVE,PACKAGE);g.require(len(entries)==192 and package['candidate']==BUILD,'Wrong base source')
  engine=g.checked(os.environ['GODOT'],g.ENGINE_SHA);pins=read(HERE/'HELD_INPUTS.json')
  g.require(set(pins)=={'apply_held_spear.gd','scene_preservation.gd','spear-held-key-proposal.json','validate_held.gd'},'Unexpected proposal inventory')
  files={k:g.checked(HERE/'held_validation'/k,v) for k,v in pins.items()}
  marker=xdg/'import-complete.json';cert=read(marker)
  for k,v in {'build':BUILD,'project':str(project),'archive_sha256':ARCHIVE,'manifest_sha256':PACKAGE,'engine_sha256':g.ENGINE_SHA,'adapter_sha256':ADAPTER}.items():g.require(cert.get(k)==v,'Import identity mismatch')
  receipt=g.checked(cert['receipt'],cert['receipt_sha256']);invocation=g.checked(cert['invocation'],cert['invocation_sha256']);strict_guard(receipt.with_suffix(''))
  g.require(g.import_cache(project,entries)==cert['cache_sha256'],'Import cache changed')
  initial=snapshot(project);proposal=project/'held_validation';destination=project/'held_validation_output'
  g.require(not proposal.exists() and not destination.exists(),'Fresh proposal/output required');proposal.mkdir()
  for k,p in files.items():shutil.copyfile(p,proposal/k)
  immutable=snapshot(project)
  def check_source(allowed):
   current=snapshot(project);extra={k:v for k,v in current.items() if k not in immutable}
   g.require({k:current.get(k) for k in immutable}==immutable,'Source/cache/proposal changed')
   g.require(set(extra)=={'held_validation_output/'+n for n in allowed},'Unexpected output inventory')
   return extra
  artifacts={'engine':engine,'archive':archive,'manifest':manifest,'adapter':HERE/'guarded_manifest_ci.py','runner':Path(__file__).resolve(),'monitor':HERE/'hardened_monitored_run.py','pins':HERE/'HELD_INPUTS.json','public-inputs':Path('PUBLIC_INPUTS.json').resolve(),'evaluator':HERE/'evaluate_held_tracks.py','applied-evaluator':HERE/'evaluate_applied_held.py','marker':marker,'import-receipt':receipt,'import-invocation':invocation}
  artifacts.update({'input:'+k:project/k for k in immutable});expected={k:g.sha(v) for k,v in artifacts.items()}
  monitor=g.load_monitor();env=g.isolated_environment(xdg);env['PYTHONDONTWRITEBYTECODE']='1'
  limits=monitor.Limits(timeout_s=300,sample_target_s=.05,terminate_grace_s=5,kill_reap_grace_s=5,launch_min_available_kib=4194304,runtime_min_available_kib=1048576,max_rss_kib=2097152)
  summary['held_attempts']=1
  monitor.run(out/'held',[str(engine),'--headless','--path',str(project),'--script','res://held_validation/validate_held.gd'],env=env,limits=limits,artifacts=artifacts,expected_artifact_hashes=expected)
  strict_guard(out/'held');final=check_source(SCENES|{'validation-report.json'})
  validate_report(read(destination/'validation-report.json'),destination,pins)
  shutil.copyfile(destination/'validation-report.json',out/'validation-report.json')
  summary.update(passed=True,original_files_unchanged=True,output_files=final,base_files=entries,proposal_files=pins,import_snapshot=initial)
 except BaseException as exc:
  summary['error_type']=type(exc).__name__
 finally:
  summary['files']={p.name:g.sha(p) for p in out.iterdir() if p.is_file() and not p.is_symlink() and p.name!='summary.json'}
  (out/'summary.json').write_text(json.dumps(summary,indent=2)+'\n');print(json.dumps({k:v for k,v in summary.items() if k not in {'files','base_files','proposal_files','import_snapshot','output_files'}},sort_keys=True))
 return 0 if summary['passed'] else 1

def validate_report(report,destination,pins):
 import math
 require=g.require
 fields={'schema','passed','source_sha256','proposal_sha256','output_sha256','changed_tracks','verified_selected_keys','full_scene_storage_preserved','untouched_source_preserved','exact_reload_verified','sampling_grid','local_pose_tolerance','time_tolerance','finite_sample_count','samples','limits','changed_interpolation_tracks','event_sample_count','event_samples','margin_sample_count','margin_samples'}
 require(set(report)==fields,'Report fields mismatch')
 require(report['schema']=='held-native-readability-validation-v2' and report['passed'] is True,'Held verdict failed')
 proposal=HERE/'held_validation/spear-held-key-proposal.json'
 g.checked(proposal,pins['spear-held-key-proposal.json']);plan=read(proposal)
 require(report['source_sha256']==plan['source_native_sha256']=='a3c93a0cdf95d6bf049140c384841ecd59c7fc5933ebd53fd9619f16ca9bab89','Source native mismatch')
 require(report['proposal_sha256']==pins['spear-held-key-proposal.json'] and report['output_sha256']==g.sha(destination/'spearman_action.scn'),'Held output binding failed')
 for k,v in {'changed_tracks':8,'verified_selected_keys':290,'finite_sample_count':612,'changed_interpolation_tracks':4,'event_sample_count':4,'margin_sample_count':8}.items():require(type(report[k]) is int and report[k]==v,'Wrong count')
 for k in ('full_scene_storage_preserved','untouched_source_preserved','exact_reload_verified'):require(report[k] is True,'Preservation failed')
 require(report['sampling_grid']=='153 uniform nominal times per clip; loop endpoint clamped length-1e-6; distinct from prior offline612 grid','Wrong grid')
 require(report['local_pose_tolerance']==1e-6 and report['time_tolerance']==1e-7,'Wrong tolerances')
 require(report['limits']==['Finite sampled bone transforms only; not mesh clearance or visual acceptance','Death unchanged and not accepted','No gameplay, device, material or camera acceptance'],'Wrong scope')
 g.checked(HERE/'evaluate_held_tracks.py','73f726a3e19fe4c67f30826503f34d5e492a64f326e3a92d689110bb5f6c7399')
 g.checked(HERE/'evaluate_applied_held.py','6fd81b68726e41ebfb0c1575356281dcab8a72d6af26ff3e81f469be2ff47860')
 import evaluate_held_tracks as evaluator
 import evaluate_applied_held as applied_evaluator
 samples=report['samples'];require(type(samples) is list and len(samples)==612,'Wrong samples')
 keys={'clip','nominal_time','requested_time','actual_clip','actual_time','paused','actual_position','expected_position','actual_rotation','expected_rotation','track_rotation','actual_scale','expected_scale','bones'}
 def number(x):return type(x) in (int,float) and math.isfinite(x)
 def vector(x,n):require(type(x) is list and len(x)==n and all(number(v) for v in x),'Invalid vector')
 bone_names='root,pelvis,spine_01,spine_02,spine_03,neck_01,Head,clavicle_l,upperarm_l,lowerarm_l,hand_l,prop_shield,clavicle_r,upperarm_r,lowerarm_r,hand_r,prop_spear,thigh_l,calf_l,foot_l,ball_l,thigh_r,calf_r,foot_r,ball_r'.split(',')
 event_times={'idle':[],'walk':[],'attack':[.56,.61],'hit':[0.,.05]}
 margin_times={'idle':[1.833353373069763,1.8666466746139527],'walk':[.5333133611488342,.4666866686534882],'attack':[.19998000298023225,.300020011920929],'hit':[0.,.3333533432674408]}
 require(type(report['event_samples']) is list and len(report['event_samples'])==4,'Wrong event rows')
 require(type(report['margin_samples']) is list and len(report['margin_samples'])==8,'Wrong margin rows')
 work=[]
 for ci,name in enumerate(('idle','walk','attack','hit')):
  length=plan['clips'][name]['length_unchanged']
  work.extend((name,length*j/152,row) for j,row in enumerate(samples[ci*153:(ci+1)*153]))
 for field,grid in [('event_samples',event_times),('margin_samples',margin_times)]:
  expected=[(name,t) for name in ('idle','walk','attack','hit') for t in grid[name]]
  work.extend((name,t,row) for (name,t),row in zip(expected,report[field]))
 require(len(work)==624,'Wrong total rows')
 for name,nominal,row in work:
   length=plan['clips'][name]['length_unchanged']
   require(set(row)==keys and row['clip']==row['actual_clip']==name and row['paused'] is True,'Wrong sample identity')
   requested=min(nominal,length-1e-6) if name in ('idle','walk') else nominal
   for k,v in [('nominal_time',nominal),('requested_time',requested),('actual_time',requested)]:require(number(row[k]) and abs(row[k]-v)<=1e-7,'Wrong sample time')
   vector(row['track_rotation'],4)
   raw=evaluator.reference(plan,name,'rotation',requested)
   require(math.dist(row['track_rotation'],raw)<=1e-6,'Raw track rotation differs from source proposal')
   for prop,n in [('position',3),('rotation',4),('scale',3)]:
    a=row['actual_'+prop];b=row['expected_'+prop];vector(a,n);vector(b,n)
    error=math.dist(a,b)
    if prop=='rotation':error=min(error,math.sqrt(sum((x+y)**2 for x,y in zip(a,b))))
    require(error<=1e-6,'Local evaluated pose mismatch')
    ref=applied_evaluator.applied_reference(plan,name,prop,requested) if prop!='scale' else [1,1,1]
    ref_error=math.dist(b,ref)
    if prop=='rotation':
     ref_error=min(ref_error,math.sqrt(sum((x+y)**2 for x,y in zip(b,ref))))
     require(abs(math.sqrt(sum(x*x for x in b))-1)<=1e-6,'Nonunit rotation')
    require(ref_error<=1e-6,'Expected pose differs from source proposal')
   bones=row['bones'];require(type(bones) is list and len(bones)==25,'Invalid bone count')
   names=[]
   for bone in bones:
    require(type(bone) is list and len(bone)==5 and type(bone[0]) is str and re.fullmatch(r'[A-Za-z0-9_]{1,64}',bone[0]),'Invalid bone row')
    names.append(bone[0])
    for v in bone[1:]:vector(v,3)
    cols=bone[1:4]
    require(all(.5<=math.sqrt(sum(x*x for x in c))<=2 for c in cols),'Degenerate bone basis')
    det=(cols[0][0]*(cols[1][1]*cols[2][2]-cols[1][2]*cols[2][1])-cols[1][0]*(cols[0][1]*cols[2][2]-cols[0][2]*cols[2][1])+cols[2][0]*(cols[0][1]*cols[1][2]-cols[0][2]*cols[1][1]))
    require(.1<det<8,'Invalid bone determinant')
   require(len(names)==len(set(names)) and 'prop_spear' in names,'Invalid skeleton names')
   require(names==bone_names,'Skeleton order changed')
   parent=bones[15];prop=bones[16];x,y,z,w=row['actual_rotation'];scale=row['actual_scale']
   local=[[1-2*(y*y+z*z),2*(x*y-z*w),2*(x*z+y*w)],[2*(x*y+z*w),1-2*(x*x+z*z),2*(y*z-x*w)],[2*(x*z-y*w),2*(y*z+x*w),1-2*(x*x+y*y)]]
   def transform(v):return [sum(parent[c+1][r]*v[c] for c in range(3)) for r in range(3)]
   for col in range(3):
    expected=transform([local[r][col]*scale[col] for r in range(3)])
    require(math.dist(expected,prop[col+1])<=1e-5,'Global spear basis inconsistent with native local pose')
   pos=transform(row['actual_position']);expected=[pos[r]+parent[4][r] for r in range(3)]
   require(math.dist(expected,prop[4])<=1e-5,'Global spear origin inconsistent with parent/local pose')
if __name__=='__main__':raise SystemExit(main())

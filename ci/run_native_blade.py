"""One bounded hosted native child; preserve exact accepted source and import cache."""
from pathlib import Path
import json,os,shutil,stat,re
import guarded_manifest_ci as g
HERE=Path(__file__).resolve().parent
PACKAGE='f7e900121ac2d2d5baf83d7d1db2033ea8fcf2c017907782a0a8f1aa2c3abe5a'
ARCHIVE='69994f5d4e7476adc012590d0c5b9e537c5b821d5d17984bf21c990a27cc65a1'
ADAPTER='1737dfca2778614730b6dd6d3803009460139a19dfe901b830e84120abce75e0'
BUILD='vc-130723842165'
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
 project=Path('project').resolve();archive=Path('held-source.zip').resolve();manifest=Path('HELD_SOURCE_PACKAGE.json').resolve();xdg=Path('private/import').resolve();out=Path('blade-evidence').resolve()
 g.require(not out.exists() and not out.is_symlink(),'Fresh evidence required');out.mkdir()
 summary={'base_build':BUILD,'passed':False,'blade_attempts':0}
 try:
  package,entries=g.verify_source(project,archive,manifest,ARCHIVE,PACKAGE);g.require(len(entries)==192 and package['candidate']==BUILD,'Wrong base source')
  engine=g.checked(os.environ['GODOT'],g.ENGINE_SHA);pins=read(HERE/'BLADE_INPUTS.json')
  g.require(set(pins)=={'expected_vertex_data.bin', 'scene_preservation.gd', 'apply_blade_stream.gd', 'SELECTED_PROPOSAL.json', 'validate_blade.gd'},'Unexpected proposal inventory')
  files={k:g.checked(HERE/'blade_validation'/k,v) for k,v in pins.items()}
  marker=xdg/'import-complete.json';cert=read(marker)
  for k,v in {'build':BUILD,'project':str(project),'archive_sha256':ARCHIVE,'manifest_sha256':PACKAGE,'engine_sha256':g.ENGINE_SHA,'adapter_sha256':ADAPTER}.items():g.require(cert.get(k)==v,'Import identity mismatch')
  receipt=g.checked(cert['receipt'],cert['receipt_sha256']);invocation=g.checked(cert['invocation'],cert['invocation_sha256']);strict_guard(receipt.with_suffix(''))
  g.require(g.import_cache(project,entries)==cert['cache_sha256'],'Import cache changed')
  initial=snapshot(project);proposal=project/'blade_validation';destination=project/'blade_validation_output'
  g.require(not proposal.exists() and not destination.exists(),'Fresh proposal/output required');proposal.mkdir()
  for k,p in files.items():shutil.copyfile(p,proposal/k)
  immutable=snapshot(project)
  def check_source(allowed):
   current=snapshot(project);extra={k:v for k,v in current.items() if k not in immutable}
   g.require({k:current.get(k) for k in immutable}==immutable,'Source/cache/proposal changed')
   g.require(set(extra)=={'blade_validation_output/'+n for n in allowed},'Unexpected output inventory')
   return extra
  artifacts={'engine':engine,'archive':archive,'manifest':manifest,'adapter':HERE/'guarded_manifest_ci.py','runner':Path(__file__).resolve(),'monitor':HERE/'hardened_monitored_run.py','pins':HERE/'BLADE_INPUTS.json','public-inputs':Path('PUBLIC_INPUTS.json').resolve(),'marker':marker,'import-receipt':receipt,'import-invocation':invocation}
  artifacts.update({'input:'+k:project/k for k in immutable});expected={k:g.sha(v) for k,v in artifacts.items()}
  monitor=g.load_monitor();env=g.isolated_environment(xdg);env['PYTHONDONTWRITEBYTECODE']='1'
  limits=monitor.Limits(timeout_s=300,sample_target_s=.05,terminate_grace_s=5,kill_reap_grace_s=5,launch_min_available_kib=4194304,runtime_min_available_kib=1048576,max_rss_kib=2097152)
  summary['blade_attempts']=1
  monitor.run(out/'blade',[str(engine),'--headless','--path',str(project),'--script','res://blade_validation/validate_blade.gd'],env=env,limits=limits,artifacts=artifacts,expected_artifact_hashes=expected)
  strict_guard(out/'blade');final=check_source(SCENES|{'validation-report.json'})
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
 import math,struct
 require=g.require
 f32=lambda x:struct.unpack("<f",struct.pack("<f",x))[0]
 fields={'schema','completed','source_sha256','proposal_sha256','output_sha256','vertex_stream_sha256','selected_vertices','allowed_bytes','preservation','reload','surface_aabb','bone16_aabb','selected_bounds_contained','changed_bytes','unaffected_vertex_bytes','unaffected_vertex_sha256','source_file_unchanged','limits'}
 require(set(report)==fields,'Report fields mismatch')
 proposal=g.checked(HERE/'blade_validation/SELECTED_PROPOSAL.json',pins['SELECTED_PROPOSAL.json']);plan=read(proposal)
 g.checked(HERE/'blade_validation/expected_vertex_data.bin',pins['expected_vertex_data.bin'])
 require(plan['schema']=='native-blade-geometry-proposal-v1' and plan['selected_cross_section_scale']==[2.0,1.0,1.0],'Wrong width-only proposal')
 require(report['schema']=='blade-stream-validation-v1','Wrong schema')
 for k in ('completed','preservation','reload','selected_bounds_contained','source_file_unchanged'):require(report[k] is True,'Preservation failed')
 for k,v in {'selected_vertices':96,'allowed_bytes':1920,'changed_bytes':877,'unaffected_vertex_bytes':80120}.items():require(type(report[k]) is int and report[k]==v,'Wrong count')
 require(report['source_sha256']==plan['base_native_sha256']=='af925f0f70fc14567796230dbc4d1543003e3a4bd52b3bc4554d4daea83c0038','Wrong source')
 require(report['proposal_sha256']==pins['SELECTED_PROPOSAL.json'],'Wrong proposal')
 require(report['vertex_stream_sha256']==pins['expected_vertex_data.bin']=='0c2c3ebd8733af7567777635391992417a83e8989b321567aaa3094025fe803e','Wrong stream')
 require(report['unaffected_vertex_sha256']=='0e465bc5163d64b768d3d73279f963cea2298ed40e680e0b8945809f8d543f37','Wrong unchanged stream')
 require(report['output_sha256']==g.sha(destination/'spearman_action.scn'),'Output hash mismatch')
 require(report['limits']=='No new pose, continuous clearance, or visual acceptance.','Wrong scope')
 points=plan['plan']['replacement_mesh_positions'];require(len(points)==96,'Wrong selected points')
 expected_bounds={'surface_aabb':[-.8997926712036133,-.003679136512801051,-.18564818799495697,1.7995855808258057,3.0541791915893555,.3533816933631897],'bone16_aabb':[-.7482000589370728,1.075500249862671,-.08290013670921326,.13000011444091797,1.9749999046325684,.034999996423721313]}
 for name in ('surface_aabb','bone16_aabb'):
  b=report[name];require(type(b) is list and len(b)==6 and all(type(v) in (int,float) and math.isfinite(v) for v in b) and all(v>=0 for v in b[3:]),'Invalid bounds')
  require([f32(v) for v in b]==expected_bounds[name],'Unexpected native bounds')
  for v in points:
   require(all(f32(b[j])<=f32(v[j])<=f32(f32(b[j])+f32(b[j+3])) for j in range(3)),'Selected point outside bounds')
if __name__=='__main__':raise SystemExit(main())

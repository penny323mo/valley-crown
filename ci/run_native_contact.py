"""Two bounded hosted native children; preserve exact accepted source and import cache."""
from pathlib import Path
import json,os,shutil,stat,re
import guarded_manifest_ci as g
HERE=Path(__file__).resolve().parent
PACKAGE='51b142986a9563804f266887b3fe4718e892dd12ae67d919acd8250369cfb2ae'
ARCHIVE='cd9a1bf3c35130c591174b4600a336d3dcdc69a5bee6b91d327f4950912681f5'
ADAPTER='1737dfca2778614730b6dd6d3803009460139a19dfe901b830e84120abce75e0'
BUILD='vc-f6a2f9514b4d'
SCENES={k+'_action.scn' for k in ('spearman','archer','scout')}
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
 project=Path('project').resolve();archive=Path('ground-source.zip').resolve();manifest=Path('GROUND_SOURCE_PACKAGE.json').resolve();xdg=Path('private/import').resolve();out=Path('contact-evidence').resolve()
 g.require(not out.exists() and not out.is_symlink(),'Fresh evidence required');out.mkdir()
 summary={'base_build':BUILD,'passed':False,'patch_attempts':0,'probe_attempts':0}
 try:
  package,entries=g.verify_source(project,archive,manifest,ARCHIVE,PACKAGE);g.require(len(entries)==192 and package['candidate']==BUILD,'Wrong base source')
  engine=g.checked(os.environ['GODOT'],g.ENGINE_SHA);pins=read(HERE/'CONTACT_INPUTS.json')
  g.require(set(pins)=={'patch_native_scenes.gd','validate_native_contact.gd','probe_native_contact.gd','apply_native_contact.gd','scene_preservation.gd','input-lock.json','spearman.json','archer.json','scout.json'},'Unexpected proposal inventory')
  files={k:g.checked(HERE/'native_contact'/k,v) for k,v in pins.items()}
  marker=xdg/'import-complete.json';cert=read(marker)
  for k,v in {'build':BUILD,'project':str(project),'archive_sha256':ARCHIVE,'manifest_sha256':PACKAGE,'engine_sha256':g.ENGINE_SHA,'adapter_sha256':ADAPTER}.items():g.require(cert.get(k)==v,'Import identity mismatch')
  receipt=g.checked(cert['receipt'],cert['receipt_sha256']);invocation=g.checked(cert['invocation'],cert['invocation_sha256']);strict_guard(receipt.with_suffix(''))
  g.require(g.import_cache(project,entries)==cert['cache_sha256'],'Import cache changed')
  initial=snapshot(project);proposal=project/'native_contact';destination=project/'native_contact_output'
  g.require(not proposal.exists() and not destination.exists(),'Fresh proposal/output required');proposal.mkdir()
  for k,p in files.items():shutil.copyfile(p,proposal/k)
  immutable=snapshot(project)
  def check_source(allowed):
   current=snapshot(project);extra={k:v for k,v in current.items() if k not in immutable}
   g.require({k:current.get(k) for k in immutable}==immutable,'Source/cache/proposal changed')
   g.require(set(extra)=={'native_contact_output/'+n for n in allowed},'Unexpected output inventory')
   return extra
  artifacts={'engine':engine,'archive':archive,'manifest':manifest,'adapter':HERE/'guarded_manifest_ci.py','runner':Path(__file__).resolve(),'monitor':HERE/'hardened_monitored_run.py','pins':HERE/'CONTACT_INPUTS.json','public-inputs':Path('PUBLIC_INPUTS.json').resolve(),'marker':marker,'import-receipt':receipt,'import-invocation':invocation}
  artifacts.update({'input:'+k:project/k for k in immutable});expected={k:g.sha(v) for k,v in artifacts.items()}
  monitor=g.load_monitor();env=g.isolated_environment(xdg);env['PYTHONDONTWRITEBYTECODE']='1'
  limits=monitor.Limits(timeout_s=300,sample_target_s=.05,terminate_grace_s=5,kill_reap_grace_s=5,launch_min_available_kib=4194304,runtime_min_available_kib=1048576,max_rss_kib=2097152)
  summary['patch_attempts']=1
  monitor.run(out/'patch',[str(engine),'--headless','--path',str(project),'--script','res://native_contact/patch_native_scenes.gd'],env=env,limits=limits,artifacts=artifacts,expected_artifact_hashes=expected)
  strict_guard(out/'patch');patch_outputs=check_source(SCENES|{'patch-report.json'})
  patch=read(destination/'patch-report.json');validate_patch(patch,destination,pins)
  shutil.copyfile(destination/'patch-report.json',out/'patch-report.json')
  artifacts.update({'output:'+k:project/k for k in patch_outputs});expected.update({k:g.sha(v) for k,v in artifacts.items()})
  summary['probe_attempts']=1
  monitor.run(out/'probe',[str(engine),'--headless','--path',str(project),'--script','res://native_contact/validate_native_contact.gd'],env=env,limits=limits,artifacts=artifacts,expected_artifact_hashes=expected)
  strict_guard(out/'probe');final=check_source(SCENES|{'patch-report.json','native-probe-report.json'})
  for k,v in patch_outputs.items():g.require(final.get(k)==v,'Probe mutated packed output')
  probe=read(destination/'native-probe-report.json')
  validate_probe(probe,destination,pins)
  shutil.copyfile(destination/'native-probe-report.json',out/'native-probe-report.json')
  summary.update(passed=True,original_files_unchanged=True,output_files=final,base_files=entries,proposal_files=pins,import_snapshot=initial)
 except BaseException as exc:
  summary['error_type']=type(exc).__name__
 finally:
  summary['files']={p.name:g.sha(p) for p in out.iterdir() if p.is_file() and not p.is_symlink() and p.name!='summary.json'}
  (out/'summary.json').write_text(json.dumps(summary,indent=2)+'\n');print(json.dumps({k:v for k,v in summary.items() if k not in {'files','base_files','proposal_files','import_snapshot','output_files'}},sort_keys=True))
 return 0 if summary['passed'] else 1

def validate_patch(patch,destination,pins):
 names={'spearman':{'prop_spear','prop_shield'},'archer':{'prop_bow'},'scout':{'prop_sword'}}
 g.require(set(patch)==set(names),'Wrong patch classes')
 for kind,row in patch.items():
  data=read(HERE/'native_contact'/(kind+'.json'))
  g.require(row.get('output_sha256')==g.sha(destination/(kind+'_action.scn')) and row.get('sidecar_sha256')==pins[kind+'.json'] and row.get('unchanged_other_track_bytes') is True and row.get('reloaded_other_track_snapshot_equal') is True and row.get('reloaded_other_scene_storage_equal') is True,'Patch preservation failed')
  g.require(set(row['props'])==names[kind],'Wrong corrected prop set')
  for name,spec in data['props'].items():
   result=row['props'][name]
   g.require(set(result)=={'keys_per_track','release_seconds','contact_seconds','settled_seconds'} and type(result['keys_per_track']) is int and result['keys_per_track']==len(spec['samples']),'Wrong corrected key count')
   for key in ('release_seconds','contact_seconds','settled_seconds'):g.require(type(result[key]) in (int,float) and abs(result[key]-spec[key])<1e-7,'Wrong event time')

def validate_probe(probe,destination,pins):
 units={'spearman':{'prop_spear','prop_shield'},'archer':{'prop_bow'},'scout':{'prop_sword'}}
 g.require(probe.get('schema')=='native-contact-engine-probe-v1' and probe.get('status')=='PASS' and probe.get('continuous_clearance_certified') is False and probe.get('visual_acceptance') is False,'Probe schema/scope failed')
 g.require(probe.get('input_lock_sha256')==pins['input-lock.json'] and probe.get('patch_report_sha256')==g.sha(destination/'patch-report.json') and set(probe['units'])==set(units),'Probe bindings failed')
 original=read(HERE/'native_contact/input-lock.json')
 metrics={'vertex_count','probe_count','min_y_m','min_y_time','max_world_path_error_m','max_held_error_m','release_error_m','max_settled_drift_m','terminal_min_y_m','terminal_vertices_within_2_1mm'}
 import math
 for kind,names in units.items():
  u=probe['units'][kind];g.require(u.get('status')=='PASS' and u.get('continuous_clearance_certified') is False and u.get('visual_acceptance') is False and set(u['props'])==names,'Wrong probe unit')
  g.require(u['source_native_sha256']==original[kind]['native_sha256'] and u['data_sha256']==pins[kind+'.json'] and u['output_native_sha256']==g.sha(destination/(kind+'_action.scn')),'Probe resource binding failed')
  for r in u['props'].values():
   g.require(set(r)==metrics and all(type(v) in (int,float) and math.isfinite(v) for v in r.values()),'Invalid probe metrics')
   g.require(all(type(r[k]) is int for k in ['vertex_count','probe_count','terminal_vertices_within_2_1mm']),'Invalid integer metric')
   g.require(r['vertex_count']>=4 and r['probe_count']>=1449 and 0<=r['min_y_time']<=1.5,'Insufficient probes')
   g.require(r['min_y_m']>=.001 and 0<=r['max_world_path_error_m']<.01 and 0<=r['max_held_error_m']<.00002 and 0<=r['release_error_m']<.00002 and 0<=r['max_settled_drift_m']<.001 and .001<=r['terminal_min_y_m']<=.003 and r['terminal_vertices_within_2_1mm']>=3,'Native contact metric failed')
if __name__=='__main__':raise SystemExit(main())

"""One hosted direct-child replay on immutable accepted source; retain incomplete results."""
from pathlib import Path
import hashlib,json,os,sys
import guarded_manifest_ci as g
HERE=Path(__file__).resolve().parent
PACKAGE='8c7c4bde61bbebf1d661f751d791beb9be76bfe562f7138b84dae4fc1eb915de'
ARCHIVE='c63c2f79f4ce650b704da040691d1a4b1ac45a6adba05e9228947fa40513be1e'
ADAPTER='1737dfca2778614730b6dd6d3803009460139a19dfe901b830e84120abce75e0'
def ordinary_clean_exit(r):
 return (type(r.get('exit')) is int and r['exit'] in (0,1) and r.get('child_started') is True and r.get('cleanup_complete') is True
  and not any(r.get(k) for k in ('stop_reason','exception','cleanup_errors','output_errors'))
  and bool(r.get('post_run_binding_matches')) and all(v is True for v in r['post_run_binding_matches'].values())
  and type(r.get('system_before',{}).get('oom_kill')) is int and r['system_before']['oom_kill']==r.get('system_after',{}).get('oom_kill'))
def main():
 g.require_hosted_approval(True,os.environ)
 g.checked(HERE/'guarded_manifest_ci.py',ADAPTER)
 project=Path('project').resolve();archive=Path('ground-rally-source.zip').resolve();manifest=Path('GROUND_RALLY_SOURCE_PACKAGE.json').resolve();xdg=Path('private/import').resolve();out=Path('replay-evidence').resolve()
 g.require(not out.exists() and not out.is_symlink(),'Fresh evidence required');out.mkdir()
 summary={'build':'vc-c9aad346e872','passed':False,'replay_attempts':0,'report_present':False}
 try:
  package,entries=g.verify_source(project,archive,manifest,ARCHIVE,PACKAGE);g.require(len(entries)==192,'Wrong source inventory')
  engine=g.checked(os.environ['GODOT'],g.ENGINE_SHA);pins=json.loads((HERE/'REPLAY_INPUTS.json').read_text())
  g.require(set(pins)=={'contract.gd','validate.py','source_lock.json'},'Unexpected replay input set')
  files={k:g.checked(HERE/k,v) for k,v in pins.items()}
  marker=xdg/'import-complete.json';certificate=json.loads(marker.read_text())
  for k,v in {'build':package['candidate'],'project':str(project),'archive_sha256':ARCHIVE,'manifest_sha256':PACKAGE,'engine_sha256':g.ENGINE_SHA,'adapter_sha256':ADAPTER}.items():g.require(certificate.get(k)==v,'Import identity mismatch')
  receipt=g.checked(certificate['receipt'],certificate['receipt_sha256']);invocation=g.checked(certificate['invocation'],certificate['invocation_sha256']);g.guard_receipt(receipt,invocation)
  before=g.inventory(project,entries);g.require(g.import_cache(project,entries)==certificate['cache_sha256'],'Import cache mismatch')
  artifacts={'engine':engine,'archive':archive,'manifest':manifest,'adapter':HERE/'guarded_manifest_ci.py','runner':Path(__file__).resolve(),'monitor':HERE/'hardened_monitored_run.py','pins':HERE/'REPLAY_INPUTS.json','marker':marker,'import-receipt':receipt,'import-invocation':invocation,**files}
  artifacts.update({'source:'+k:project/k for k in entries});artifacts.update({'cache:'+k:project/k for k in before})
  expected={k:g.sha(v) for k,v in artifacts.items()};monitor=g.load_monitor();env=g.isolated_environment(xdg);env['PYTHONDONTWRITEBYTECODE']='1'
  limits=monitor.Limits(timeout_s=300,sample_target_s=.05,terminate_grace_s=5,kill_reap_grace_s=5,launch_min_available_kib=4194304,runtime_min_available_kib=1048576,max_rss_kib=2097152)
  report=out/'ground-rally-contract.json';summary['replay_attempts']=1
  monitor.run(out/'replay',[str(engine),'--headless','--path',str(project),'--script',str(files['contract.gd']),'--',str(report)],env=env,limits=limits,artifacts=artifacts,expected_artifact_hashes=expected)
  summary['source_preserved']=g.inventory(project,entries)==before and g.import_cache(project,entries)==certificate['cache_sha256']
  r=json.loads((out/'replay.json').read_text());summary.update(replay_exit=r.get('exit'),cleanup_complete=r.get('cleanup_complete'),guard_passed=r.get('passed'),report_present=report.is_file() and not report.is_symlink())
  if summary['report_present'] and summary['source_preserved'] and ordinary_clean_exit(r):
   artifacts['report']=report;expected['report']=g.sha(report)
   monitor.run(out/'checker',[sys.executable,str(files['validate.py']),'--root',str(project),str(report)],env=env,limits=monitor.Limits(timeout_s=60,sample_target_s=.05,terminate_grace_s=5,kill_reap_grace_s=5,launch_min_available_kib=4194304,runtime_min_available_kib=1048576,max_rss_kib=2097152),artifacts=artifacts,expected_artifact_hashes=expected)
   c=json.loads((out/'checker.json').read_text());summary['checker_exit']=c.get('exit');summary['checker_passed']=c.get('passed') is True and c.get('cleanup_complete') is True and c.get('exit')==0
  summary['source_preserved']=summary.get('source_preserved') and g.inventory(project,entries)==before
  summary['passed']=summary.get('source_preserved') is True and r.get('passed') is True and r.get('cleanup_complete') is True and r.get('exit')==0 and summary.get('checker_passed') is True
 except BaseException as exc:
  summary['error_type']=type(exc).__name__
 finally:
  summary['files']={p.name:g.sha(p) for p in out.iterdir() if p.is_file() and not p.is_symlink() and p.name!='summary.json'}
  (out/'summary.json').write_text(json.dumps(summary,indent=2)+'\n');print(json.dumps({k:v for k,v in summary.items() if k!='files'},sort_keys=True))
 return 0 if summary['passed'] else 1
if __name__=='__main__':raise SystemExit(main())

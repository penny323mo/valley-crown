"""Admit bounded safe failure evidence; stage native outputs only after exact success reconciliation."""
from pathlib import Path
import hashlib,json,re,shutil,stat,sys
import run_native_held as runner
SOURCE=Path('held-evidence');DEST=Path('safe-held-evidence');OUTPUT=Path('safe-held-output')
ALLOWED={'summary.json','validation-report.json','held.json','held.invocation.json','held.log'}
PATTERNS=[rb'gh[pousr]_[A-Za-z0-9]{20,255}',rb'github_pat_[A-Za-z0-9_]{20,255}',rb'AKIA[0-9A-Z]{16}',rb'xox[baprs]-[A-Za-z0-9-]{20,255}',rb'-----BEGIN (?:RSA |EC |DSA |OPENSSH |ENCRYPTED )?PRIVATE KEY-----',rb'/(?:home/agent|workspace/scratch|workspace/shared|agent_notes|user_notes)/',rb'sk-(?:proj-)?[A-Za-z0-9_-]{24,}',rb'(?i)(?:password|client_secret|access_token|refresh_token)\s*[=:]\s*["\x27]?[A-Za-z0-9_./+\-=]{12,}']
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def safe(p,text=True):
 assert stat.S_ISREG(p.lstat().st_mode) and not p.is_symlink() and p.stat().st_size<=32*1024*1024
 b=p.read_bytes();assert not any(re.search(pattern,b) for pattern in PATTERNS)
 if text:b.decode('utf-8',errors='strict')
 if p.suffix=='.json':runner.read(p)
def main():
 assert SOURCE.is_dir() and not SOURCE.is_symlink() and not DEST.exists() and not OUTPUT.exists()
 files=list(SOURCE.iterdir());assert {p.name for p in files}<=ALLOWED and (SOURCE/'summary.json').is_file()
 assert sum(p.lstat().st_size for p in files)<=128*1024*1024
 for p in files:safe(p)
 s=runner.read(SOURCE/'summary.json');assert s['base_build']==runner.BUILD and type(s['passed']) is bool
 assert all(type(s[k]) is int and s[k] in (0,1) for k in ('held_attempts',))
 assert s['files']=={p.name:sha(p) for p in files if p.name!='summary.json'}
 for phase in ('held',):
  if not (SOURCE/(phase+'.json')).exists():continue
  r=runner.read(SOURCE/(phase+'.json'));i=runner.read(SOURCE/(phase+'.invocation.json'))
  assert r['log_sha256']==sha(SOURCE/(phase+'.log')) and r['invocation_sha256']==sha(SOURCE/(phase+'.invocation.json'))
  assert i['test_dependencies'] is False and i['helper']['load_sha256']==i['helper']['invocation_sha256']==runner.g.MONITOR_SHA
 passed=False;output_files={}
 if s['passed']:
  assert s['original_files_unchanged'] is True and s['held_attempts']==1 and {p.name for p in files}==ALLOWED
  project=Path('project').resolve();destination=project/'held_validation_output';pins=runner.read(Path(__file__).parent/'HELD_INPUTS.json')
  package=Path('CONSTRUCTION_SOURCE_PACKAGE.json');assert sha(package)==runner.PACKAGE
  entries={r['file']:r['sha256'] for r in runner.read(package)['files']};assert len(entries)==192 and s['base_files']==entries and s['proposal_files']==pins
  expected={'engine':runner.g.ENGINE_SHA,'archive':runner.ARCHIVE,'manifest':runner.PACKAGE,'adapter':runner.ADAPTER,'monitor':runner.g.MONITOR_SHA,'runner':sha(Path(runner.__file__)),'pins':sha(Path(__file__).parent/'HELD_INPUTS.json')}
  expected.update({'input:'+k:v for k,v in s['import_snapshot'].items()});expected.update({'input:held_validation/'+k:v for k,v in pins.items()})
  assert all(s['import_snapshot'].get(k)==v for k,v in entries.items())
  for phase,script in [('held','validate_held.gd')]:
   runner.strict_guard(SOURCE/phase);i=runner.read(SOURCE/(phase+'.invocation.json'));r=runner.read(SOURCE/(phase+'.json'))
   for k,h in expected.items():assert i['artifacts'][k]['sha256']==h and r['post_run_binding_matches']['artifact:'+k] is True
   assert i['argv']==[i['artifacts']['engine']['path'],'--headless','--path',str(project),'--script','res://held_validation/'+script] and i['requested_argv']==i['argv']
   assert i['executable']['sha256']==runner.g.ENGINE_SHA
   assert i['limits']=={'timeout_s':300,'sample_target_s':.05,'terminate_grace_s':5,'kill_reap_grace_s':5,'launch_min_available_kib':4194304,'runtime_min_available_kib':1048576,'max_rss_kib':2097152}
  assert runner.snapshot(destination).keys()==runner.SCENES|{'validation-report.json'}
  for p in destination.iterdir():safe(p,text=p.suffix=='.json');output_files[p.name]=sha(p)
  assert s['output_files']=={'held_validation_output/'+k:v for k,v in output_files.items()}
  for n in ('validation-report.json',):assert output_files[n]==sha(SOURCE/n)
  runner.validate_report(runner.read(SOURCE/'validation-report.json'),destination,pins)
  current=runner.snapshot(project);expected_source=dict(s['import_snapshot']);expected_source.update({'held_validation/'+k:v for k,v in pins.items()});expected_source.update(s['output_files']);assert current==expected_source
  passed=True
 DEST.mkdir()
 for p in files:shutil.copyfile(p,DEST/p.name)
 (DEST/'admission.json').write_text(json.dumps({'safe_evidence':True,'held_validation_passed':passed,'files':{p.name:sha(p) for p in files}},indent=2)+'\n')
 if passed:
  OUTPUT.mkdir()
  for n in output_files:shutil.copyfile(Path('project/held_validation_output')/n,OUTPUT/n)
  (OUTPUT/'provenance.json').write_text(json.dumps({'base_build':runner.BUILD,'held_validation_passed':True,'continuous_clearance_certified':False,'visual_acceptance':False,'outputs':output_files,'source_files':s['base_files'],'proposal_files':pins,'evidence_admission_sha256':sha(DEST/'admission.json')},indent=2)+'\n')
 print(json.dumps({'safe_evidence':True,'held_validation_passed':passed,'file_count':len(files)}))

def admit_import():
 source=Path('import-evidence');dest=Path('safe-import-evidence')
 assert source.is_dir() and not source.is_symlink() and not dest.exists() and not dest.is_symlink()
 files=list(source.iterdir());names={p.name for p in files}
 assert names and names<={'import.json','import.invocation.json','import.log','phase-summary.json'} and 'phase-summary.json' in names
 assert sum(p.lstat().st_size for p in files)<=64*1024*1024
 for p in files:safe(p)
 summary=runner.read(source/'phase-summary.json')
 assert summary.get('build')==runner.BUILD and summary.get('phase')=='import' and type(summary.get('passed')) is bool
 assert summary.get('manifest_sha256')==runner.PACKAGE and summary.get('archive_sha256')==runner.ARCHIVE
 if 'import.json' in names:
  assert {'import.invocation.json','import.log'}<=names
  receipt=runner.read(source/'import.json');inv=runner.read(source/'import.invocation.json')
  assert receipt['log_sha256']==sha(source/'import.log') and receipt['invocation_sha256']==sha(source/'import.invocation.json')
  assert inv['test_dependencies'] is False and inv['helper']['load_sha256']==inv['helper']['invocation_sha256']==runner.g.MONITOR_SHA
  package=Path('CONSTRUCTION_SOURCE_PACKAGE.json');assert sha(package)==runner.PACKAGE
  expected={'adapter':runner.ADAPTER,'monitor':runner.g.MONITOR_SHA,'engine':runner.g.ENGINE_SHA,'archive':runner.ARCHIVE,'suite-manifest':runner.PACKAGE}
  expected.update({'source:'+row['file']:row['sha256'] for row in runner.read(package)['files']});assert len(expected)==197
  for name,digest in expected.items():assert inv['artifacts'][name]['sha256']==digest
  engine=inv['artifacts']['engine']['path'];project=inv['artifacts']['source:main.tscn']['path'].removesuffix('/main.tscn')
  assert inv['argv']==inv['requested_argv']==[engine,'--headless','--editor','--path',project,'--import']
  assert inv['executable']=={'path':engine,'sha256':runner.g.ENGINE_SHA}
 elif names!={'phase-summary.json'}:
  assert names<={'phase-summary.json','import.invocation.json','import.log'}
 dest.mkdir()
 for p in files:shutil.copyfile(p,dest/p.name)
 (dest/'admission.json').write_text(json.dumps({'safe_evidence':True,'evidence_only':True,'held_acceptance':False,'files':{p.name:sha(p) for p in files}},indent=2)+'\n')
 print(json.dumps({'safe_import_evidence':True,'evidence_only':True,'file_count':len(files)}))
if __name__=='__main__':
 try:
  if sys.argv[1:]==['--import-only']:admit_import()
  else:
   assert not sys.argv[1:];main()
 except BaseException:print('NATIVE_HELD_ADMISSION_FAILED');raise SystemExit(1)

"""Admit bounded safe failure evidence; stage native outputs only after exact success reconciliation."""
from pathlib import Path
import hashlib,json,re,shutil,stat
import run_native_contact as runner
SOURCE=Path('contact-evidence');DEST=Path('safe-contact-evidence');OUTPUT=Path('safe-contact-output')
ALLOWED={'summary.json','patch-report.json','native-probe-report.json'}|{n+s for n in ('patch','probe') for s in ('.json','.invocation.json','.log')}
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
 assert all(type(s[k]) is int and s[k] in (0,1) for k in ('patch_attempts','probe_attempts'))
 assert s['files']=={p.name:sha(p) for p in files if p.name!='summary.json'}
 for phase in ('patch','probe'):
  if not (SOURCE/(phase+'.json')).exists():continue
  r=runner.read(SOURCE/(phase+'.json'));i=runner.read(SOURCE/(phase+'.invocation.json'))
  assert r['log_sha256']==sha(SOURCE/(phase+'.log')) and r['invocation_sha256']==sha(SOURCE/(phase+'.invocation.json'))
  assert i['test_dependencies'] is False and i['helper']['load_sha256']==i['helper']['invocation_sha256']==runner.g.MONITOR_SHA
 passed=False;output_files={}
 if s['passed']:
  assert s['original_files_unchanged'] is True and s['patch_attempts']==s['probe_attempts']==1 and {p.name for p in files}==ALLOWED
  project=Path('project').resolve();destination=project/'native_contact_output';pins=runner.read(Path(__file__).parent/'CONTACT_INPUTS.json')
  package=Path('GROUND_SOURCE_PACKAGE.json');assert sha(package)==runner.PACKAGE
  entries={r['file']:r['sha256'] for r in runner.read(package)['files']};assert len(entries)==192 and s['base_files']==entries and s['proposal_files']==pins
  expected={'engine':runner.g.ENGINE_SHA,'archive':runner.ARCHIVE,'manifest':runner.PACKAGE,'adapter':runner.ADAPTER,'monitor':runner.g.MONITOR_SHA,'runner':sha(Path(runner.__file__)),'pins':sha(Path(__file__).parent/'CONTACT_INPUTS.json')}
  expected.update({'input:'+k:v for k,v in s['import_snapshot'].items()});expected.update({'input:native_contact/'+k:v for k,v in pins.items()})
  assert all(s['import_snapshot'].get(k)==v for k,v in entries.items())
  for phase,script in [('patch','patch_native_scenes.gd'),('probe','validate_native_contact.gd')]:
   runner.strict_guard(SOURCE/phase);i=runner.read(SOURCE/(phase+'.invocation.json'));r=runner.read(SOURCE/(phase+'.json'))
   for k,h in expected.items():assert i['artifacts'][k]['sha256']==h and r['post_run_binding_matches']['artifact:'+k] is True
   assert i['argv']==[i['artifacts']['engine']['path'],'--headless','--path',str(project),'--script','res://native_contact/'+script] and i['requested_argv']==i['argv']
   assert i['executable']['sha256']==runner.g.ENGINE_SHA
   assert i['limits']=={'timeout_s':300,'sample_target_s':.05,'terminate_grace_s':5,'kill_reap_grace_s':5,'launch_min_available_kib':4194304,'runtime_min_available_kib':1048576,'max_rss_kib':2097152}
  assert runner.snapshot(destination).keys()==runner.SCENES|{'patch-report.json','native-probe-report.json'}
  for p in destination.iterdir():safe(p,text=p.suffix=='.json');output_files[p.name]=sha(p)
  assert s['output_files']=={'native_contact_output/'+k:v for k,v in output_files.items()}
  for n in ('patch-report.json','native-probe-report.json'):assert output_files[n]==sha(SOURCE/n)
  probe_inv=runner.read(SOURCE/'probe.invocation.json');probe_receipt=runner.read(SOURCE/'probe.json')
  for n in runner.SCENES|{'patch-report.json'}:
   key='output:native_contact_output/'+n;assert probe_inv['artifacts'][key]['sha256']==output_files[n] and probe_receipt['post_run_binding_matches']['artifact:'+key] is True
  runner.validate_patch(runner.read(SOURCE/'patch-report.json'),destination,pins)
  runner.validate_probe(runner.read(SOURCE/'native-probe-report.json'),destination,pins)
  current=runner.snapshot(project);expected_source=dict(s['import_snapshot']);expected_source.update({'native_contact/'+k:v for k,v in pins.items()});expected_source.update(s['output_files']);assert current==expected_source
  passed=True
 DEST.mkdir()
 for p in files:shutil.copyfile(p,DEST/p.name)
 (DEST/'admission.json').write_text(json.dumps({'safe_evidence':True,'native_probe_passed':passed,'files':{p.name:sha(p) for p in files}},indent=2)+'\n')
 if passed:
  OUTPUT.mkdir()
  for n in output_files:shutil.copyfile(Path('project/native_contact_output')/n,OUTPUT/n)
  (OUTPUT/'provenance.json').write_text(json.dumps({'base_build':runner.BUILD,'native_probe_passed':True,'continuous_clearance_certified':False,'visual_acceptance':False,'outputs':output_files,'source_files':s['base_files'],'proposal_files':pins,'evidence_admission_sha256':sha(DEST/'admission.json')},indent=2)+'\n')
 print(json.dumps({'safe_evidence':True,'native_probe_passed':passed,'file_count':len(files)}))
if __name__=='__main__':
 try:main()
 except BaseException:print('NATIVE_CONTACT_ADMISSION_FAILED');raise SystemExit(1)

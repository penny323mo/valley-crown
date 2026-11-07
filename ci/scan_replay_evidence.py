"""File-only bounded admission of complete or incomplete replay evidence."""
from pathlib import Path
import hashlib,json,re,shutil,stat
import run_ordinary_replay as runner
SOURCE=Path('replay-evidence');DEST=Path('safe-replay-evidence')
ALLOWED={'summary.json','ordinary-map80-replay.json','replay.json','replay.log','replay.invocation.json','checker.json','checker.log','checker.invocation.json'}
PATTERNS=[rb'gh[pousr]_[A-Za-z0-9]{20,255}',rb'github_pat_[A-Za-z0-9_]{20,255}',rb'AKIA[0-9A-Z]{16}',rb'xox[baprs]-[A-Za-z0-9-]{20,255}',rb'-----BEGIN (?:RSA |EC |DSA |OPENSSH |ENCRYPTED )?PRIVATE KEY-----',rb'/(?:home/agent|workspace/scratch|workspace/shared|agent_notes|user_notes)/',rb'sk-(?:proj-)?[A-Za-z0-9_-]{24,}',rb'(?i)(?:password|client_secret|access_token|refresh_token)\s*[=:]\s*["\x27]?[A-Za-z0-9_./+\-=]{12,}']
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
 assert SOURCE.is_dir() and not SOURCE.is_symlink() and not DEST.exists() and not DEST.is_symlink()
 files=list(SOURCE.iterdir());assert {p.name for p in files}<=ALLOWED and (SOURCE/'summary.json').is_file()
 total=0
 for p in files:
  assert stat.S_ISREG(p.lstat().st_mode) and not p.is_symlink()
  cap=64*1024*1024 if p.name=='ordinary-map80-replay.json' else 16*1024*1024
  assert p.stat().st_size<=cap;total+=p.stat().st_size;assert total<=128*1024*1024
  data=p.read_bytes();data.decode('utf-8',errors='strict');assert not any(re.search(pattern,data) for pattern in PATTERNS)
  if p.suffix=='.json':json.loads(data,parse_constant=lambda _:(_ for _ in ()).throw(ValueError()))
 summary=json.loads((SOURCE/'summary.json').read_text());assert summary['build']=='vc-c7211e1083c8' and type(summary['passed']) is bool and type(summary['replay_attempts']) is int and summary['replay_attempts'] in [0,1]
 assert summary['files']=={p.name:sha(p) for p in files if p.name!='summary.json'}
 for name in ['replay','checker']:
  receipt=SOURCE/(name+'.json')
  if receipt.exists():
   r=json.loads(receipt.read_text());assert r['log_sha256']==sha(SOURCE/(name+'.log')) and r['invocation_sha256']==sha(SOURCE/(name+'.invocation.json'))
   if summary['passed']:assert runner.ordinary_clean_exit(r) and r.get('passed') is True and r['exit']==0
   i=json.loads((SOURCE/(name+'.invocation.json')).read_text());assert i['test_dependencies'] is False and i['helper']['load_sha256']==i['helper']['invocation_sha256']=='4c7802bcfb53a2f73f501635cdf483e1459d3d86eb881a7450dccd3bbd705d50'
 verified_pass=False
 if summary['passed']:
  assert summary.get('source_preserved') is True and summary['replay_attempts']==1
  package_path=Path('OCCLUSION_SOURCE_PACKAGE.json');assert sha(package_path)==runner.PACKAGE
  package=json.loads(package_path.read_text());pins=json.loads((Path(__file__).parent/'REPLAY_INPUTS.json').read_text())
  assert pins['ordinary_map80_replay.gd']=='775d10759cceaad7452817777d84d085de0a4517758d298ec5c56a3b36a3f18d'
  assert pins['check_replay.py']=='9d7011b727bb600e44c934e3653b93930d9173939aff681c6ccce37d9cb4487f'
  expected={'engine':runner.g.ENGINE_SHA,'archive':runner.ARCHIVE,'manifest':runner.PACKAGE,'adapter':runner.ADAPTER,'monitor':runner.g.MONITOR_SHA,**pins}
  expected.update({'source:'+row['file']:row['sha256'] for row in package['files']})
  assert len(package['files'])==188 and package['candidate']==summary['build']
  for name in ['replay','checker']:
   r=json.loads((SOURCE/(name+'.json')).read_text());i=json.loads((SOURCE/(name+'.invocation.json')).read_text())
   assert runner.ordinary_clean_exit(r) and r['passed'] is True and r['exit']==0
   for k,h in expected.items():assert i['artifacts'][k]['sha256']==h and r['post_run_binding_matches']['artifact:'+k] is True
   a=i['argv'];assert a[0]==i['executable']['path'] and a[1:]==i['requested_argv'][1:];project=i['artifacts']['source:main.tscn']['path'].removesuffix('/main.tscn');report=str((SOURCE/'ordinary-map80-replay.json').resolve())
   if name=='replay':assert a==[i['artifacts']['engine']['path'],'--headless','--path',project,'--script',i['artifacts']['ordinary_map80_replay.gd']['path'],'--',report]
   else:
    assert a[1:]==[i['artifacts']['check_replay.py']['path'],'--root',project,'--report',report]
    assert i['artifacts']['report']['sha256']==sha(SOURCE/'ordinary-map80-replay.json') and r['post_run_binding_matches']['artifact:report'] is True
  verdict=json.loads((SOURCE/'checker.log').read_text());assert verdict['failed']==0 and verdict['passed']>0 and all(x['pass'] is True for x in verdict['checks'])
  verified_pass=True
 DEST.mkdir()
 for p in files:shutil.copyfile(p,DEST/p.name)
 (DEST/'admission.json').write_text(json.dumps({'safe_evidence':True,'replay_passed':verified_pass,'files':{p.name:sha(p) for p in files}},indent=2)+'\n')
 print(json.dumps({'safe_evidence':True,'replay_passed':verified_pass,'files':len(files)}))
if __name__=='__main__':
 try:main()
 except BaseException:print('REPLAY_EVIDENCE_ADMISSION_FAILED');raise SystemExit(1)

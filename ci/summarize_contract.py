"""Emit bounded scalar-only diagnostics; never raw logs, rows, paths or environment."""
import hashlib,json,re
from pathlib import Path
BUILD='vc-c7211e1083c8'
PACKAGE='52711be56c32b5f1a8b861ff4578843cebd3e16a1501b78466a5ac0492ad05aa'
SCRIPT='f1531ef60c4911a4ec7d105f29d65d3c28de2ce0a1a1c949139464d2f51cb413'
MONITOR='4c7802bcfb53a2f73f501635cdf483e1459d3d86eb881a7450dccd3bbd705d50'
ROOT=Path('contract-evidence')
def digest(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def read(p,limit=16000000):
 assert p.is_file() and not p.is_symlink() and p.stat().st_size<=limit
 return json.loads(p.read_text(),parse_constant=lambda _:(_ for _ in ()).throw(ValueError()))
def integer(x): assert type(x) is int and -255<=x<=1000000000;return x
def boolean(x): assert type(x) is bool;return x
def main():
 package=Path('OCCLUSION_SOURCE_PACKAGE.json');assert digest(package)==PACKAGE
 script=Path('project/tests/occlusion_stencil_contract.gd');assert digest(script)==SCRIPT
 p=read(package);suite=p['suites'][0];assert len(p['suites'])==1 and suite['script_sha256']==SCRIPT
 s=read(ROOT/'phase-summary.json');assert s['build']==BUILD and s['phase']=='test' and s['manifest_sha256']==PACKAGE and s['archive_sha256']==p['source_archive_sha256'] and s['runtime_manifest_sha256']==p['runtime_manifest']['sha256']
 out={'build':BUILD,'package_sha256':PACKAGE,'suite_sha256':SCRIPT,'runtime_manifest_sha256':p['runtime_manifest']['sha256'],'phase_passed':boolean(s['passed']),'phase_sha256':digest(ROOT/'phase-summary.json')}
 receipt=ROOT/'occlusion_stencil_contract.json';invocation=ROOT/'occlusion_stencil_contract.invocation.json';log=ROOT/'occlusion_stencil_contract.log';report=ROOT/'occlusion-stencil-contract.json'
 if receipt.exists():
  r=read(receipt);i=read(invocation);assert i['test_dependencies'] is False and i['helper']['load_sha256']==i['helper']['invocation_sha256']==MONITOR
  assert r['invocation_sha256']==digest(invocation) and r['log_sha256']==digest(log)
  out.update(receipt_sha256=digest(receipt),guard_passed=boolean(r['passed']),cleanup_complete=boolean(r['cleanup_complete']),exit=integer(r['exit']) if r['exit'] is not None else None,oom_before=integer(r['system_before']['oom_kill']),oom_after=integer(r['system_after']['oom_kill']),peak_rss_kib=integer(r['sampled_peak_rss_kib']))
  assert log.stat().st_size<=16000000
  text=log.read_text(errors='replace')
  out['diagnostic_categories']=[label for label,pattern in [('parse','Parse Error'),('shader','Shader Error|SHADER ERROR'),('script','SCRIPT ERROR'),('assertion','Assertion failed|failed=[1-9]')] if re.search(pattern,text)][:4]
 if report.exists():
  q=read(report);assert q['build']==BUILD
  rows=q['checks'];assert type(rows) is list and len(rows)<=512
  passed=integer(q['passed']);failed=integer(q['failed']);assert passed>=0 and failed>=0 and passed+failed==len(rows)
  assert sum(boolean(x['pass']) for x in rows)==passed
  source=script.read_text();suffixes=re.findall(r'check\(kind\+"([^"]+)"',source);fixed=re.findall(r'check\("([^"]+)"',source)
  known={k+v for k in ['villager','spearman','archer','scout'] for v in suffixes}|set(fixed)|{'unmatched winding fails closed '+str(k) for k in [0,1]}
  names=[]
  for row in rows:
   assert type(row['name']) is str and row['name'] in known
   if not row['pass']:names.append(row['name'])
  out.update(passed=passed,failed=failed,report_sha256=digest(report),failed_test_ids=sorted(set(names))[:64])
 if s['passed']:
  assert out['guard_passed'] and out['cleanup_complete'] and out['exit']==0 and out['oom_before']==out['oom_after'] and out['failed']==0
  assert len(s['commands'])==1;cmd=s['commands'][0];assert cmd['receipt_sha256']==out['receipt_sha256'] and cmd['report']['sha256']==out['report_sha256'] and cmd['report']['suite_sha256']==SCRIPT
 print('NATIVE_CONTRACT_SUMMARY '+json.dumps(out,sort_keys=True))
if __name__=='__main__':
 try:main()
 except BaseException:
  print('NATIVE_CONTRACT_SUMMARY_INVALID');raise SystemExit(1)

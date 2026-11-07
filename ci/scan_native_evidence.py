#!/usr/bin/env python3
"""Scan only declared text evidence; never emit matching sensitive contents."""
import hashlib,json,pathlib,re,stat,sys
root=pathlib.Path('evidence'); manifest=pathlib.Path('CONSTRUCTION_REGRESSION_PACKAGE.json')
assert hashlib.sha256(manifest.read_bytes()).hexdigest()=='f9473eac11baf62982d67df333ed9cb74f43c8e826e22e200907f0e9c99355bd'
suites=json.loads(manifest.read_text())['suites']
allowed=set()
for phase in ['source-import','source-tests']:allowed.add(phase+'/phase-summary.json')
for name in ['import']:
 for suffix in ['.json','.invocation.json','.log']:allowed.add('source-import/'+name+suffix)
for suite in suites:
 for suffix in ['.json','.invocation.json','.log']:allowed.add('source-tests/'+suite['name']+suffix)
 report=suite['report'].removeprefix('OUTPUT/') if suite['report'].startswith('OUTPUT/') else suite['name']+'.report.json'
 allowed.add('source-tests/'+suite['name']+'.report.json');allowed.add('source-tests/'+report);allowed.add('source-tests/'+report+'.progress.jsonl')
patterns=[rb'/workspace/scratch/',rb'/workspace/shared/',rb'/agent_notes/',rb'/user_notes/',rb'/home/agent/',rb'gh[pousr]_[A-Za-z0-9]{20,}',rb'github_pat_[A-Za-z0-9_]{20,}',rb'AKIA[0-9A-Z]{16}',rb'sk-[A-Za-z0-9_-]{24,}',rb'xox[baprs]-[A-Za-z0-9-]{16,}',rb'-----BEGIN (?:RSA |EC |DSA |OPENSSH |ENCRYPTED )?PRIVATE KEY-----']
assert root.is_dir() and not root.is_symlink(),'Evidence root absent or unsafe'
entries={};total=0
for f in root.rglob('*'):
 mode=f.lstat().st_mode;assert not stat.S_ISLNK(mode),'Evidence symlink rejected'
 if stat.S_ISDIR(mode):continue
 assert stat.S_ISREG(mode),'Evidence special file rejected'
 name=f.relative_to(root).as_posix();assert name in allowed,'Unexpected evidence filename'
 assert f.stat().st_size<=32*1024*1024,'Evidence file exceeds bound'
 b=f.read_bytes();total+=len(b);assert total<=128*1024*1024,'Evidence total exceeds bound'
 b.decode('utf-8');assert not any(re.search(p,b) for p in patterns),'Evidence privacy scan failed'
 if f.suffix=='.json':json.loads(b)
 entries[name]=hashlib.sha256(b).hexdigest()
assert entries,'No evidence'
pathlib.Path('evidence-scan.json').write_text(json.dumps({'passed':True,'files_sha256':entries,'total_bytes':total},indent=2)+'\n')
print('Evidence allowlist, file-type, size and privacy scan passed')

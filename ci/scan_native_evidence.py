#!/usr/bin/env python3
"""Fail-closed allowlist scan and staging of public native CI results."""
import hashlib,json,pathlib,re,shutil,stat,sys,zipfile
root=pathlib.Path('native-evidence'); mode=sys.argv[1]
assert mode in ('evidence','runtime')
phases=('import','native-pack','reload-diagnostic','stamp','reload-final')
allowed={'summary.json'} | {n+s for n in phases for s in ('.before.json','.json','.invocation.json','.log')}
allowed |= {n+'.report.json' for n in phases if n!='import'}
runtime={'accepted-runtime/'+n for n in ('runtime-delta.zip','final-source-lock.json','receipt.json')}
patterns=[rb'/workspace/scratch/',rb'/workspace/shared/',rb'/agent_notes/',rb'/user_notes/',rb'/home/agent/',rb'gh[pousr]_[A-Za-z0-9]{20,}',rb'github_pat_[A-Za-z0-9_]{20,}',rb'AKIA[0-9A-Z]{16}',rb'sk-[A-Za-z0-9_-]{24,}',rb'xox[baprs]-[A-Za-z0-9-]{16,}',rb'-----BEGIN (?:RSA |EC |DSA |OPENSSH |ENCRYPTED )?PRIVATE KEY-----']
def scan(b,text=True):
 assert not any(re.search(p,b) for p in patterns),'Privacy scan failed'
 if text:b.decode('utf-8')
def digest(b):return hashlib.sha256(b).hexdigest()
def parse(b):return json.loads(b,parse_constant=lambda x:(_ for _ in ()).throw(ValueError('Nonfinite JSON')))
assert root.is_dir() and not root.is_symlink(),'Missing or unsafe evidence'
entries={};total=0
for f in root.rglob('*'):
 m=f.lstat().st_mode
 assert not stat.S_ISLNK(m),'Symlink rejected'
 if stat.S_ISDIR(m):
  assert f.relative_to(root).as_posix()=='accepted-runtime','Unknown directory'
  continue
 assert stat.S_ISREG(m),'Special file rejected'
 n=f.relative_to(root).as_posix();assert n in allowed|runtime,'Unknown evidence file'
 assert f.stat().st_size<=64*1024*1024,'File too large'
 total+=f.stat().st_size;assert total<=192*1024*1024,'Evidence too large'
 if n in allowed:
  b=f.read_bytes();scan(b)
  if f.suffix=='.json':parse(b)
  entries[n]=digest(b)
assert entries,'Empty evidence'
dest=pathlib.Path('safe-native-'+mode);assert not dest.exists(),'Staging must be fresh'
if mode=='runtime':
 summary=parse((root/'summary.json').read_bytes());assert summary.get('passed') is True,'Runtime not accepted'
 assert len(summary['commands'])==5 and [x['name'] for x in summary['commands']]==list(phases)
 assert all(x['passed'] is True and x['exit']==0 and x['cleanup_complete'] is True for x in summary['commands'])
 receipt=parse((root/'accepted-runtime/receipt.json').read_bytes())
 lock_bytes=(root/'accepted-runtime/final-source-lock.json').read_bytes();scan(lock_bytes);lock=parse(lock_bytes)
 scan((root/'accepted-runtime/receipt.json').read_bytes())
 assert digest(lock_bytes)==receipt['final_source_lock_sha256']
 archive=root/'accepted-runtime/runtime-delta.zip'
 assert digest(archive.read_bytes())==receipt['archive_sha256'] and archive.stat().st_size==receipt['archive_bytes']
 assert receipt['build']==lock['build']==summary['runtime_build']
 members=receipt['member_sha256'];full={r['file']:r['sha256'] for r in lock['files']}
 assert len(full)==len(lock['files'])
 input_bytes=pathlib.Path('ACTION_FIX_SOURCE_LOCK.json').read_bytes()
 assert digest(input_bytes)=='70466a5bef3078de2722d08fd14ff4912061c88191ea2b474e9a8c60345e63b7'
 initial={r['file']:r['sha256'] for r in parse(input_bytes)['files']};assert len(initial)==158
 uid_names={n+'.uid' for n in initial if n.endswith(('.gd','.gdshader')) and n+'.uid' not in initial}
 assert set(full)==set(initial)|set(members)
 assert all(full[n]==h for n,h in initial.items() if n!='scripts/rules.gd')
 source=pathlib.Path('map80-actions-thin-source-v2.zip')
 assert digest(source.read_bytes())=='203852e82ca33d5e5b550e1d8ef07ef989734fd24b1cf54c6d8318307d43d6d8'
 with zipfile.ZipFile(source) as src:original_rules=src.read('scripts/rules.gd')
 assert digest(original_rules)==initial['scripts/rules.gd']
 required={f'assets/mature/models/{k}_action.scn' for k in ('villager','spearman','archer','scout')}|{'scripts/rules.gd','reports/build-manifest.json'}
 with zipfile.ZipFile(archive) as z:
  assert z.testzip() is None and len(z.namelist())==len(set(z.namelist())) and set(z.namelist())==set(members)
  assert required<=set(members) and sum(i.file_size for i in z.infolist())<=128*1024*1024
  for i in z.infolist():
   n=i.filename;p=pathlib.PurePosixPath(n)
   assert not p.is_absolute() and all(x not in ('','.','..') for x in n.split('/')) and '\\' not in n
   assert stat.S_IFMT(i.external_attr>>16) in (0,stat.S_IFREG)
   assert n in required|uid_names
   b=z.read(i);scan(b,False);assert digest(b)==members[n]==full[n]
   if n=='scripts/rules.gd':
    pattern=rb'const BUILD_ID = "[^"\n]*"'
    assert len(re.findall(pattern,original_rules))==len(re.findall(pattern,b))==1
    assert re.sub(pattern,b'const BUILD_ID = "normalized"',b)==re.sub(pattern,b'const BUILD_ID = "normalized"',original_rules)
    assert ('const BUILD_ID = "'+receipt['build']+'"').encode() in b
 entries={n:digest((root/n).read_bytes()) for n in runtime}
dest.mkdir()
for n in entries:
 target=dest/n;target.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(root/n,target)
(dest/'scan.json').write_text(json.dumps({'passed':True,'files_sha256':entries},indent=2)+'\n')
print('Exact evidence scan and staging passed: '+mode)

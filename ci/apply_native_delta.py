#!/usr/bin/env python3
"""Reassemble the exact accepted native runtime before any test overlay."""
from pathlib import Path,PurePosixPath
import hashlib,json,stat,zipfile
INPUT_LOCK='1d94d4f2feb0618c50a0be4b7bc056d79403c28cd85246dd3115decf63d020af'
FINAL_LOCK='2626317df74d113cc5397a8e9f9daf3a7b2190bcaea8b028359ef6d20fac9e94'
DELTA='7e9f184b20556d80baf79c334b7cab0ead971700617c24080f6004d120955716'
RECEIPT='ddc5d519e9c5214a03494040da2828bd6280fb2df13a2001331513115ac23b1c'
def require(ok,msg):
 if not ok:raise RuntimeError(msg)
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def inventory(root):
 require(root.is_dir() and not root.is_symlink(),'Missing or linked root')
 files={}
 for p in root.rglob('*'):
  mode=p.lstat().st_mode;require(not stat.S_ISLNK(mode),'Symlink rejected')
  if stat.S_ISDIR(mode):continue
  require(stat.S_ISREG(mode),'Special file rejected');files[p.relative_to(root).as_posix()]=sha(p)
 return files
source=Path('SOURCE_INPUT_LOCK.json');require(sha(source)==INPUT_LOCK,'Initial lock mismatch')
initial={r['file']:r['sha256'] for r in json.loads(source.read_text())['files']}
root=Path('project');require(inventory(root)==initial,'Initial158 source mismatch')
artifact=Path('native-artifact');received=inventory(artifact)
expected={'accepted-runtime/final-source-lock.json':FINAL_LOCK,'accepted-runtime/runtime-delta.zip':DELTA,'accepted-runtime/receipt.json':RECEIPT}
require(set(received)==set(expected)|{'scan.json'} and all(received[n]==h for n,h in expected.items()),'Runtime artifact mismatch')
scan=json.loads((artifact/'scan.json').read_text());require(scan.get('passed') is True and scan.get('files_sha256')==expected,'Runtime scan bindings mismatch')
accepted=artifact/'accepted-runtime';receipt=json.loads((accepted/'receipt.json').read_text());lock=json.loads((accepted/'final-source-lock.json').read_text())
require(receipt['build']==lock['build']=='vc-f659b53824e3','Wrong native build')
final={r['file']:r['sha256'] for r in lock['files']};require(len(final)==len(lock['files'])==181,'Final inventory count mismatch')
with zipfile.ZipFile(accepted/'runtime-delta.zip') as z:
 require(z.testzip() is None and len(z.namelist())==len(set(z.namelist())) and set(z.namelist())==set(receipt['member_sha256']),'Delta inventory mismatch')
 for i in z.infolist():
  n=i.filename;p=PurePosixPath(n);require(not p.is_absolute() and all(x not in ('','.','..') for x in n.split('/')) and '\\' not in n,'Unsafe member')
  require(stat.S_IFMT(i.external_attr>>16) in (0,stat.S_IFREG),'Special delta member')
  data=z.read(i);require(hashlib.sha256(data).hexdigest()==receipt['member_sha256'][n]==final[n],'Delta hash mismatch')
  target=root/n;target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(data)
require(inventory(root)==final,'Final181 source mismatch')
require((root/'art/.gdignore').read_bytes()==b'','Editable art must stay ignored')
print('Reassembled accepted native runtime vc-f659b53824e3, exact181 files')

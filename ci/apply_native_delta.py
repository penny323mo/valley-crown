#!/usr/bin/env python3
"""Reassemble the exact accepted native runtime before any test overlay."""
from pathlib import Path,PurePosixPath
import hashlib,json,stat,zipfile
INPUT_LOCK='70466a5bef3078de2722d08fd14ff4912061c88191ea2b474e9a8c60345e63b7'
FINAL_LOCK='abec3ae826afc37a3773dae3817128cd761816e50c2392025b112c231b01ea00'
DELTA='3612c8c77603e89d4148f1692f6f37c9605c1b713748abb36f04bd55043c6c12'
RECEIPT='4eba9836f91487faf485e1e957dffdd11dd34f6d2e21c87c4646eeaee4c41c27'
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
source=Path('ACTION_FIX_SOURCE_LOCK.json');require(sha(source)==INPUT_LOCK,'Initial lock mismatch')
initial={r['file']:r['sha256'] for r in json.loads(source.read_text())['files']}
root=Path('project');require(inventory(root)==initial,'Initial158 source mismatch')
artifact=Path('native-artifact');received=inventory(artifact)
expected={'accepted-runtime/final-source-lock.json':FINAL_LOCK,'accepted-runtime/runtime-delta.zip':DELTA,'accepted-runtime/receipt.json':RECEIPT}
require(set(received)==set(expected)|{'scan.json'} and all(received[n]==h for n,h in expected.items()),'Runtime artifact mismatch')
scan=json.loads((artifact/'scan.json').read_text());require(scan.get('passed') is True and scan.get('files_sha256')==expected,'Runtime scan bindings mismatch')
accepted=artifact/'accepted-runtime';receipt=json.loads((accepted/'receipt.json').read_text());lock=json.loads((accepted/'final-source-lock.json').read_text())
require(receipt['build']==lock['build']=='vc-6f4dddc33ec2','Wrong native build')
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
print('Reassembled accepted native runtime vc-6f4dddc33ec2, exact181 files')

#!/usr/bin/env python3
"""Assemble only frozen thin game source and exact previously reviewed art bytes."""
from pathlib import Path
import hashlib,json,shutil,zipfile
THIN='203852e82ca33d5e5b550e1d8ef07ef989734fd24b1cf54c6d8318307d43d6d8'
LOCK='1d94d4f2feb0618c50a0be4b7bc056d79403c28cd85246dd3115decf63d020af'
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def require(ok,message):
 if not ok:raise RuntimeError(message)
lock=Path('SOURCE_INPUT_LOCK.json');require(sha(lock)==LOCK,'Full source lock mismatch')
entries={r['file']:r['sha256'] for r in json.loads(lock.read_text())['files']};require(len(entries)==158,'Source count mismatch')
source=Path('map80-actions-thin-source-v2.zip');require(sha(source)==THIN,'Thin ZIP mismatch')
root=Path('project');require(not root.exists(),'Fresh source root required')
upstream=Path('licensed-artifact');require(upstream.is_dir() and not upstream.is_symlink(),'Missing art artifact')
require(not any(p.is_symlink() for p in upstream.rglob('*')),'Art symlink rejected')
actual={p.relative_to(upstream).as_posix():sha(p) for p in upstream.rglob('*') if p.is_file()}
require(len(actual)==19 and all(entries.get(n)==h for n,h in actual.items()),'Art artifact identity mismatch')
with zipfile.ZipFile(source) as z:
 require(z.testzip() is None and len(z.infolist())==139,'Thin source inventory mismatch')
 for i in z.infolist():
  n=Path(i.filename);require(not n.is_absolute() and '..' not in n.parts and i.external_attr>>16&0o170000!=0o120000,'Unsafe thin member')
  require(i.filename in entries and i.filename not in actual,'Thin/art overlap or unexpected file')
  z.extract(i,root)
for n in actual:
 p=root/n;p.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(upstream/n,p)
require({p.relative_to(root).as_posix():sha(p) for p in root.rglob('*') if p.is_file()}==entries,'Assembled full source differs')
require((root/'art/.gdignore').read_bytes()==b'','Source art must remain ignored')
print('Assembled exact158-file candidate; runtime stamp and engine validation still pending')

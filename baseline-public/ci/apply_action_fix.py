#!/usr/bin/env python3
"""Apply exactly three reviewed source fixes to exact pre-native158-file assembly."""
from pathlib import Path,PurePosixPath
import argparse,hashlib,json,zipfile
BASE_LOCK_SHA='1d94d4f2feb0618c50a0be4b7bc056d79403c28cd85246dd3115decf63d020af'
FIX_LOCK_SHA='70466a5bef3078de2722d08fd14ff4912061c88191ea2b474e9a8c60345e63b7'
OVERLAY_SHA='5cf6910c2866f7e9d90033786ac0f2432277545bf621acfd56d4eabcd4ba70e5'
CHANGED={'scripts/action_character.gd','tests/action_characters.gd','tools/import_action_characters.gd'}
def require(ok,message):
    if not ok:raise RuntimeError(message)
def sha(path):
    with Path(path).open('rb') as f:return hashlib.file_digest(f,'sha256').hexdigest()
def clean(path):
    path=Path(path).absolute();require(not any(p.is_symlink() for p in [path,*path.parents]),'Symlink path rejected');return path.resolve()
def entries(path):
    data=json.loads(path.read_text());rows=data['files'];out={}
    require(data['execution_enabled'] is False and len(rows)==158,'Closed disabled158-source lock required')
    for row in rows:
        n=row['file'];p=PurePosixPath(n)
        require(n and not p.is_absolute() and '\\' not in n and all(x not in ('','.','..') for x in n.split('/')),'Unsafe path')
        require(n not in out,'Duplicate path');out[n]=row['sha256']
    return out
def inventory(root):
    result={}
    for p in root.rglob('*'):
        require(not p.is_symlink() and (p.is_file() or p.is_dir()),'Nonregular source entry')
        if p.is_file():result[p.relative_to(root).as_posix()]=sha(p)
    return result
def main():
    parser=argparse.ArgumentParser(description=__doc__)
    for name in ('project','base-lock','fix-lock','overlay','receipt'):parser.add_argument('--'+name,type=Path,required=True)
    a=parser.parse_args();root=clean(a.project);require(root.is_dir(),'Missing source assembly')
    for path,pin in [(a.base_lock,BASE_LOCK_SHA),(a.fix_lock,FIX_LOCK_SHA),(a.overlay,OVERLAY_SHA)]:require(sha(clean(path))==pin,'Bound input mismatch')
    before,after=entries(a.base_lock),entries(a.fix_lock)
    require(set(before)==set(after) and {n for n in before if before[n]!=after[n]}==CHANGED,'Unexpected patch scope')
    require(inventory(root)==before,'Starting source is not exact original158 assembly')
    receipt=clean(a.receipt);require(not receipt.exists() and not receipt.is_relative_to(root),'Fresh external receipt required')
    with zipfile.ZipFile(a.overlay) as z:
        require(len(z.infolist())==3 and set(z.namelist())==CHANGED and z.testzip() is None,'Wrong overlay inventory/CRC')
        data={}
        for info in z.infolist():
            require(not info.is_dir() and (info.external_attr>>16)&0o170000!=0o120000,'Overlay symlink/directory')
            b=z.read(info);require(hashlib.sha256(b).hexdigest()==after[info.filename],'Overlay hash differs');data[info.filename]=b
    for n,b in data.items():(root/n).write_bytes(b)
    require(inventory(root)==after and (root/'art/.gdignore').read_bytes()==b'','Final patch assembly differs')
    with receipt.open('x') as f:json.dump({'passed':True,'files':158,'changed':sorted(CHANGED),'base_lock_sha256':BASE_LOCK_SHA,'fix_lock_sha256':FIX_LOCK_SHA,'overlay_sha256':OVERLAY_SHA,'scope':'File-only exact source correction, no engine or acceptance'},f,indent=2);f.write('\n')
if __name__=='__main__':main()

#!/usr/bin/env python3
"""Pure file assembly: exact accepted181 files plus one reviewed test, no engine."""
from pathlib import Path, PurePosixPath
import argparse
import hashlib
import json
import zipfile

PACKAGE_SHA = 'a2c7780e2ad3fbeda13646c06bf8edf5cca9795a6cca3b3512ef80b10ef21c7d'
ACCEPTED_LOCK_SHA = '2626317df74d113cc5397a8e9f9daf3a7b2190bcaea8b028359ef6d20fac9e94'
OVERLAY_SHA = '46c6816047f29392bd62242638b26a1e12ee7353a0506489ee0852730ab79fb7'
TEST = 'tests/action_game_events.gd'


def require(ok, message):
    if not ok: raise RuntimeError(message)


def sha(path):
    with Path(path).open('rb') as f: return hashlib.file_digest(f,'sha256').hexdigest()


def clean(path):
    path=Path(path).absolute()
    require(not any(p.is_symlink() for p in [path,*path.parents]),'Symlink path rejected')
    return path.resolve()


def entries(lock):
    result={}
    for row in lock['files']:
        name=row['file']; p=PurePosixPath(name)
        require(name and not p.is_absolute() and '\\' not in name and all(x not in ('','.','..') for x in name.split('/')),'Unsafe entry')
        require(name not in result,'Duplicate entry');result[name]=row['sha256']
    return result


def inventory(root):
    result={}
    for p in root.rglob('*'):
        require(not p.is_symlink() and (p.is_dir() or p.is_file()),'Nonregular project entry')
        if p.is_file():result[p.relative_to(root).as_posix()]=sha(p)
    return result


def store_archive(root, expected, archive):
    require(inventory(root)==expected,'Source bytes/inventory changed before archive')
    with zipfile.ZipFile(archive,'x',compression=zipfile.ZIP_STORED) as z:
        for name in sorted(expected):
            info=zipfile.ZipInfo(name,date_time=(2026,1,1,0,0,0));info.create_system=3
            info.compress_type=zipfile.ZIP_STORED;info.external_attr=0o100644<<16
            z.writestr(info,(root/name).read_bytes())
    with zipfile.ZipFile(archive) as z:
        require(z.testzip() is None and set(z.namelist())==set(expected),'Stored source archive malformed')
        require(all(hashlib.sha256(z.read(n)).hexdigest()==h for n,h in expected.items()),'Stored source member differs')


def main():
    p=argparse.ArgumentParser(description=__doc__)
    for name in ('project','package','accepted-lock','overlay','archive','receipt'):p.add_argument('--'+name,type=Path,required=True)
    a=p.parse_args();root=clean(a.project)
    require(root.is_dir(),'Missing assembled native project')
    for path,pin in [(a.package,PACKAGE_SHA),(a.accepted_lock,ACCEPTED_LOCK_SHA),(a.overlay,OVERLAY_SHA)]:
        path=clean(path);require(path.is_file() and sha(path)==pin,'Bound assembly input mismatch')
    package=json.loads(a.package.read_text());accepted=json.loads(a.accepted_lock.read_text())
    before=entries(accepted);expected=entries(package)
    require(len(before)==181 and len(expected)==182 and set(expected)-set(before)=={TEST},'Wrong assembly coverage')
    require(all(expected[n]==h for n,h in before.items()),'Overlay changes accepted source')
    require(package['candidate']==accepted['build']=='vc-f659b53824e3','Wrong accepted runtime')
    require(inventory(root)==before,'Starting source not exact accepted181-file tree')
    require((root/'art/.gdignore').read_bytes()==b'','Art ignore missing')
    archive,receipt=clean(a.archive),clean(a.receipt)
    require(not archive.exists() and not receipt.exists() and not archive.is_relative_to(root) and not receipt.is_relative_to(root),'Fresh external outputs required')
    with zipfile.ZipFile(a.overlay) as z:
        require(z.namelist()==[TEST] and z.testzip() is None,'Wrong overlay inventory')
        info=z.infolist()[0]
        require(not info.is_dir() and (info.external_attr>>16)&0o170000!=0o120000,'Overlay symlink rejected')
        data=z.read(TEST);require(hashlib.sha256(data).hexdigest()==expected[TEST],'Overlay bytes changed')
    with (root/TEST).open('xb') as f:f.write(data)
    store_archive(root,expected,archive)
    report={'build':package['candidate'],'files':182,'accepted181_files_unchanged':True,
            'package_sha256':PACKAGE_SHA,'overlay_sha256':OVERLAY_SHA,'archive_sha256':sha(archive),
            'archive_bytes':archive.stat().st_size,'scope':'File-only assembly, no engine or test acceptance'}
    with receipt.open('x') as f:json.dump(report,f,indent=2);f.write('\n')
    print(json.dumps(report))


if __name__=='__main__':main()

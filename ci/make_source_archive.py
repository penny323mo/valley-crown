#!/usr/bin/env python3
"""File-only, deterministic archive of the exact accepted181 reassembly."""
from pathlib import Path
import argparse
import hashlib
import json
import stat
import zipfile

def sha(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream,'sha256').hexdigest()

def make(project,manifest,output,expected_sha):
    project=project.resolve()
    assert project.is_dir() and not output.exists() and not output.is_relative_to(project)
    package=json.loads(manifest.read_text())
    expected={row['file']:row['sha256'] for row in package['files']}
    assert package['candidate']=='vc-6f4dddc33ec2' and len(expected)==len(package['files'])==181
    actual={}
    for path in project.rglob('*'):
        mode=path.lstat().st_mode
        assert not stat.S_ISLNK(mode)
        if stat.S_ISDIR(mode):continue
        assert stat.S_ISREG(mode)
        actual[path.relative_to(project).as_posix()]=sha(path)
    assert actual==expected
    with zipfile.ZipFile(output,'x',compression=zipfile.ZIP_STORED) as archive:
        for name in sorted(expected):
            info=zipfile.ZipInfo(name,date_time=(2026,1,1,0,0,0))
            info.create_system=3;info.external_attr=0o100644<<16;info.compress_type=zipfile.ZIP_STORED
            archive.writestr(info,(project/name).read_bytes())
    assert sha(output)==expected_sha
    print('Frozen181 archive verified: '+expected_sha)

if __name__=='__main__':
    parser=argparse.ArgumentParser()
    for name in ('project','manifest','output'):parser.add_argument('--'+name,type=Path,required=True)
    parser.add_argument('--expected-sha256',required=True)
    args=parser.parse_args();make(args.project,args.manifest,args.output.resolve(),args.expected_sha256)

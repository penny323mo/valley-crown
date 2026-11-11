#!/usr/bin/env python3
"""Extract only exact checksum-verified official archive; never launches Blender.
Caller obtains archive from fixed HTTPS URL. No arbitrary URL or executable.
Official in-archive library links are materialized as regular bytes, never links.
"""
import argparse, json, tarfile, posixpath, shutil
from pathlib import Path
from run_authoring import ARCHIVE_SHA, ARCHIVE_URL, checked, safe_path, p
PREFIX='blender-4.3.2-linux-x64'
def prepare(archive,destination):
    archive=checked(archive,ARCHIVE_SHA,512<<20);destination=safe_path(destination)
    p.require(not destination.exists(),'Fresh tool destination required')
    with tarfile.open(archive,'r:xz') as tar:
        members=tar.getmembers();p.require(len(members)<=50000,'Archive entry count')
        names=[m.name.rstrip('/') for m in members];p.require(len(names)==len(set(names)),'Duplicate archive path')
        entries=dict(zip(names,members))
        for name,m in entries.items():
            p.require(name==PREFIX or name.startswith(PREFIX+'/'),'Unexpected archive root')
            p.require(all(x not in ('','.','..') for x in name.split('/')) and '\\' not in name,'Unsafe archive path')
            p.require(m.isdir() or m.isfile() or m.issym() or m.islnk(),'Special archive member')
            p.require(m.size<=512<<20,'Archive member bound')
        def resolve(name,seen=None):
            seen=set() if seen is None else seen
            p.require(name in entries and name not in seen,'Broken/cyclic archive link');seen.add(name);m=entries[name]
            if m.isfile():return m
            p.require(m.issym() or m.islnk(),'Archive link target must be file')
            target=posixpath.normpath(posixpath.join(posixpath.dirname(name),m.linkname)) if m.issym() else posixpath.normpath(m.linkname)
            p.require(not m.linkname.startswith('/') and target.startswith(PREFIX+'/'),'Escaping archive link')
            return resolve(target,seen)
        resolved={name:resolve(name) for name,m in entries.items() if not m.isdir()}
        p.require(sum(m.size for m in resolved.values())<=3<<30,'Expanded archive bound')
        # Complete validation before writing; symlink entries are copied from verified target.
        destination.mkdir(mode=0o700)
        for name,m in resolved.items():
            out=destination/name.removeprefix(PREFIX+'/');out.parent.mkdir(parents=True,exist_ok=True)
            with tar.extractfile(m) as source,out.open('xb') as sink:shutil.copyfileobj(source,sink,1<<20)
            out.chmod(0o755 if m.mode&0o111 else 0o644)
    files=p.tree(destination)
    p.require('blender' in files,'Missing official executable')
    return {'schema':'vc-official-blender-extraction-v1','extraction_helper_sha256':p.digest(Path(__file__)),'archive_url':ARCHIVE_URL,'archive_sha256':ARCHIVE_SHA,'tool_files':files,'blender_sha256':files['blender'],'reviewed_for_execution':False}
if __name__=='__main__':
    parser=argparse.ArgumentParser(allow_abbrev=False);parser.add_argument('--archive',required=True,type=Path);parser.add_argument('--destination',required=True,type=Path);parser.add_argument('--receipt',required=True,type=Path);a=parser.parse_args()
    receipt=safe_path(a.receipt);p.require(not receipt.exists(),'Fresh receipt required');result=prepare(a.archive,a.destination);receipt.write_text(json.dumps(result,indent=2)+'\n')

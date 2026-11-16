#!/usr/bin/env python3
"""Reviewed delivery admission and bounded official downloads. No engine launch."""
from pathlib import Path, PurePosixPath
import argparse, hashlib, json, os, re, stat, urllib.error, urllib.parse, urllib.request, zipfile
REPO='penny323mo/valley-crown'
ENGINE_URL='https://github.com/godotengine/godot/releases/download/4.6.3-stable/Godot_v4.6.3-stable_linux.x86_64.zip'
ENGINE_NAME='Godot_v4.6.3-stable_linux.x86_64'
ENGINE_SHA='f64d4ed19fc9df9440321653fcc80df8c6e365ba7b6de0a29e2cfa9fa71bfeb3'
def need(v,reason):
    if not v:raise ValueError(reason)
def sha(path):return hashlib.sha256(Path(path).read_bytes()).hexdigest()
def digest(value):need(type(value) is str and re.fullmatch('[a-f0-9]{64}',value),'Missing actual digest');return value
def relative(name):
    need(type(name) is str and name and '\\' not in name,'Unsafe relative path')
    need(not PurePosixPath(name).is_absolute() and all(p not in ('','.','..') for p in name.split('/')),'Unsafe relative path');return name

def safe_extract(archive,expected,dest,max_total=192*1024*1024,max_member=64*1024*1024):
    archive=Path(archive);dest=Path(dest).absolute()
    need(archive.is_file() and not archive.is_symlink() and archive.stat().st_size<=192*1024*1024,'Bad archive')
    need(not dest.exists() and not any(p.is_symlink() for p in dest.parents),'Extraction must be fresh')
    with zipfile.ZipFile(archive) as z:
        infos=z.infolist();names=[i.filename for i in infos]
        need(len(infos)==len(expected) and len(names)==len(set(names)) and set(names)==set(expected),'Archive inventory mismatch')
        need(sum(i.file_size for i in infos)<=max_total,'Archive expands beyond bound')
        contents={}
        for i in infos:
            n=relative(i.filename);need(stat.S_IFMT(i.external_attr>>16) in (0,stat.S_IFREG) and not i.is_dir() and not i.flag_bits&1,'Special or encrypted ZIP member')
            need(i.file_size<=max_member,'Archive member too large');data=z.read(i)
            need(hashlib.sha256(data).hexdigest()==digest(expected[n]),'Archive member digest mismatch');contents[n]=data
        need(z.testzip() is None,'Archive CRC mismatch')
    dest.mkdir(parents=True)
    for n,data in contents.items():p=dest/n;p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(data)
    return len(contents)

class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self,req,fp,code,msg,headers,newurl):return None

def allowed_url(url,api=False):
    p=urllib.parse.urlsplit(url);need(p.scheme=='https' and not p.username and not p.password and p.port in (None,443) and not p.fragment,'Unsafe download URL')
    host=p.hostname or ''
    if api:need(host=='api.github.com' and p.path.startswith('/repos/'+REPO+'/actions/'),'Wrong authenticated API target')
    else:need(host in ('github.com','api.github.com','release-assets.githubusercontent.com','objects.githubusercontent.com') or host.endswith('.blob.core.windows.net') or host.endswith('.actions.githubusercontent.com') or host.endswith('.s3.amazonaws.com') or re.fullmatch(r'.+\.s3\.[a-z0-9-]+\.amazonaws\.com',host),'Unreviewed official download redirect')
    return url

def open_once(url,token=None):
    allowed_url(url,api=token is not None)
    headers={'Accept':'application/vnd.github+json','User-Agent':'valley-crown-material-proof','X-GitHub-Api-Version':'2022-11-28'}
    if token is not None:headers['Authorization']='Bearer '+token
    return urllib.request.build_opener(NoRedirect()).open(urllib.request.Request(url,headers=headers),timeout=45)

def api_json(path,token):
    with open_once('https://api.github.com/repos/'+REPO+'/actions/'+path,token) as response:
        need(response.status==200,'GitHub API did not return success');data=response.read(2*1024*1024+1);need(len(data)<=2*1024*1024,'API response too large');return json.loads(data)

def download(url,out,token=None,maximum=192*1024*1024):
    out=Path(out).absolute();need(not out.exists() and not any(p.is_symlink() for p in out.parents),'Download path must be fresh')
    current=url
    for attempt in range(5):
        try:
            response=open_once(current,token if attempt==0 else None)
        except urllib.error.HTTPError as error:
            need(error.code in (301,302,303,307,308),'Official download rejected')
            target=error.headers.get('Location');need(type(target) is str,'Missing official redirect')
            current=urllib.parse.urljoin(current,target);allowed_url(current);continue
        with response:
            need(response.status==200,'Download failed')
            size=response.headers.get('Content-Length')
            if size:need(int(size)<=maximum,'Download too large')
            out.parent.mkdir(parents=True,exist_ok=True);total=0
            with out.open('xb') as stream:
                while True:
                    chunk=response.read(1024*1024)
                    if not chunk:break
                    total+=len(chunk);need(total<=maximum,'Download exceeds bound');stream.write(chunk)
            return total
    raise ValueError('Too many official redirects')


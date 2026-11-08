#!/usr/bin/env python3
"""Reviewed delivery admission and bounded official downloads. No engine launch."""
from pathlib import Path, PurePosixPath
import argparse, hashlib, json, os, re, stat, urllib.error, urllib.parse, urllib.request, zipfile
REPO='penny323mo/valley-crown'
ENGINE_URL='https://github.com/godotengine/godot/releases/download/4.6.3-stable/Godot_v4.6.3-stable_linux.x86_64.zip'
ENGINE_NAME='Godot_v4.6.3-stable_linux.x86_64'
ENGINE_SHA='f64d4ed19fc9df9440321653fcc80df8c6e365ba7b6de0a29e2cfa9fa71bfeb3'
OLD={'old_licensed':(42339730042,13560214428,'ac7a345f5bc7cec62c43238725888cf85321dd3d','eee098a2dc3300f15879cdaac0b1ee1dcfac22c6da725f8e6ddb2ce4525e0f94'),'old_native':(42345297400,13563191390,'30c1452ae40791f07d0848eeb89c590a89c4100c','efbe9d3296d7c8d91b69c925dfb33e6e3b08889dec96d99a8a399953ec8ab418')}

def need(v,reason):
    if not v:raise ValueError(reason)
def sha(path):return hashlib.sha256(Path(path).read_bytes()).hexdigest()
def digest(value):need(type(value) is str and re.fullmatch('[a-f0-9]{64}',value),'Missing actual digest');return value
def relative(name):
    need(type(name) is str and name and '\\' not in name,'Unsafe relative path')
    need(not PurePosixPath(name).is_absolute() and all(p not in ('','.','..') for p in name.split('/')),'Unsafe relative path');return name

def path_at(root,name,exists=True):
    p=(root/relative(name)).absolute();need(p.is_relative_to(root),'Path outside checkout')
    need(not any(x.is_symlink() for x in (p,*p.parents)),'Symlink path')
    if exists:need(p.is_file(),'Missing regular file')
    return p

def read_json(path):
    need(Path(path).stat().st_size<=2*1024*1024,'Oversized JSON')
    def bad(_):raise ValueError('Nonfinite JSON')
    def pairs(rows):
        d={}
        for k,v in rows:need(k not in d,'Duplicate JSON key');d[k]=v
        return d
    return json.loads(Path(path).read_text(),parse_constant=bad,object_pairs_hook=pairs)

def core_hash(c):
    value=dict(c);value.pop('review',None)
    return hashlib.sha256(json.dumps(value,sort_keys=True,separators=(',',':'),allow_nan=False).encode()).hexdigest()

def manifest_files(root,c,strict):
    manifest_name=relative(c['public_manifest']);m=read_json(path_at(root,manifest_name));files=m['files_sha256']
    need(type(files) is dict and 10<=len(files)<=160 and manifest_name not in files,'Bad public file manifest')
    for name,h in files.items():need(sha(path_at(root,name))==digest(h),'Public input byte drift')
    if strict:
        actual=set()
        for p in root.rglob('*'):
            rel=p.relative_to(root)
            if rel.parts[0]=='.git':continue
            need(not p.is_symlink() and (p.is_file() or p.is_dir()),'Special checkout entry')
            if p.is_file():actual.add(rel.as_posix())
        need(actual==set(files)|{manifest_name},'Unexpected public checkout files')
    return files

def validate_artifact(key,item):
    need(type(item) is dict and set(item)=={'run_id','artifact_id','head_sha','archive_sha256','members','archive_path','destination'},'Artifact descriptor differs')
    need(type(item['run_id']) is int and item['run_id']>0 and type(item['artifact_id']) is int and item['artifact_id']>0,'Missing actual run/artifact')
    need(type(item['head_sha']) is str and re.fullmatch('[a-f0-9]{40}',item['head_sha']),'Missing actual source commit')
    digest(item['archive_sha256']);relative(item['archive_path']);relative(item['destination'])
    need(item['archive_path'].startswith('downloads/') and item['archive_path'].endswith('.zip'),'Unreviewed download location')
    need(type(item['members']) is dict and 1<=len(item['members'])<=512,'Missing exact artifact members')
    for n,h in item['members'].items():relative(n);digest(h)
    if key in OLD:need(tuple(item[n] for n in ('run_id','artifact_id','head_sha','archive_sha256'))==OLD[key],'Accepted baseline artifact changed')
    if key in ('old_licensed','generated'):need(len(item['members'])==19 and all(n.startswith(('art/action_characters/','reports/asset_manifest.json')) for n in item['members']),'Wrong accepted character artifact scope')
    if key=='old_native':need(set(item['members'])=={'scan.json','accepted-runtime/runtime-delta.zip','accepted-runtime/final-source-lock.json','accepted-runtime/receipt.json'},'Wrong accepted old native scope')
    if key=='native_accepted':need(len(item['members'])==39 and 'scan.json' in item['members'] and 'accepted-runtime/runtime-delta.zip' in item['members'],'Wrong accepted material native scope')
    need(not any(n.startswith('files/') or 'STATUS' in n or 'rejected' in n.lower() or 'unvalidated' in n.lower() for n in item['members']),'Diagnostic material inputs forbidden')

def validate_contract(contract,strict=False,hosted=True):
    contract=Path(contract).absolute();root=contract.parent
    need(not any(x.is_symlink() for x in (contract,*contract.parents)),'Symlink contract')
    c=read_json(contract)
    need(c.get('schema')=='material-delivery-v1' and c.get('mode') in ('native','render'),'Unknown delivery schema')
    need(c.get('execution_enabled') is True,'Delivery remains disabled')
    if hosted:need(os.environ.get('GITHUB_ACTIONS')=='true' and os.environ.get('RUNNER_ENVIRONMENT')=='github-hosted','Hosted runner only')
    need(set(c)=={'schema','mode','execution_enabled','public_manifest','review','artifacts','engine','bindings','workflow'},'Unexpected delivery fields')
    files=manifest_files(root,c,strict)
    need(contract.name in files,'Delivery contract not in frozen files')
    review_info=c['review'];need(type(review_info) is dict and set(review_info)=={'path','sha256'},'Review descriptor differs')
    review_path=path_at(root,review_info['path']);need(sha(review_path)==digest(review_info['sha256']),'Delivery review drift');review=read_json(review_path)
    need(review.get('peer_reviewed') is True and review.get('delivery_core_sha256')==core_hash(c),'Delivery core not independently reviewed')
    need(review.get('helper_sha256')==sha(__file__),'Delivery helper not reviewed')
    wf=c['workflow'];need(type(wf) is dict and set(wf)=={'path','sha256'},'Workflow descriptor differs')
    need(wf['path'] in ('.github/workflows/material-native.yml','.github/workflows/material-render.yml'),'Unreviewed workflow path')
    need(sha(path_at(root,wf['path']))==digest(wf['sha256'])==review.get('workflow_sha256'),'Workflow bytes differ')
    expected={'old_licensed','old_native','generated'}|({'native_accepted'} if c['mode']=='render' else set())
    need(type(c['artifacts']) is dict and set(c['artifacts'])==expected,'Unexpected artifact source set')
    locations=[]
    for key,item in c['artifacts'].items():
        validate_artifact(key,item);locations.extend([item['archive_path'],item['destination']])
    engine=c['engine'];need(engine=={'url':ENGINE_URL,'member':ENGINE_NAME,'executable_sha256':ENGINE_SHA,'archive_path':'downloads/godot.zip','destination':'engine'},'Official engine descriptor differs')
    locations.extend([engine['archive_path'],engine['destination']])
    need(len(locations)==len(set(locations)) and not any(a!=b and b.startswith(a+'/') for a in locations for b in locations),'Overlapping download targets')
    for name in locations:
        need(name not in files and not any(n.startswith(name+'/') for n in files),'Download would replace source')
    need(type(c['bindings']) is dict and bool(c['bindings']),'Missing final delivery bindings')
    for name,row in c['bindings'].items():
        need(type(name) is str and type(row) is dict and set(row)=={'path','sha256'},'Binding descriptor differs')
        need(sha(path_at(root,row['path']))==digest(row['sha256']),'Final binding byte drift')
    if not strict:
        allowed=set(files)|{c['public_manifest']}
        for item in c['artifacts'].values():
            allowed.add(item['archive_path'])
            allowed.update(item['destination']+'/'+n for n in item['members'])
            archive=path_at(root,item['archive_path'],False)
            if archive.exists():need(sha(archive)==item['archive_sha256'],'Previously fetched archive drift')
            for n,h in item['members'].items():
                output=path_at(root,item['destination']+'/'+n,False)
                if output.exists():need(output.is_file() and sha(output)==h,'Previously extracted member drift')
        allowed.update({engine['archive_path'],engine['destination']+'/'+engine['member']})
        binary=path_at(root,engine['destination']+'/'+engine['member'],False)
        if binary.exists():need(binary.is_file() and sha(binary)==engine['executable_sha256'],'Prepared engine drift')
        for entry in root.rglob('*'):
            rel=entry.relative_to(root)
            if rel.parts[0]=='.git':continue
            need(not entry.is_symlink() and (entry.is_file() or entry.is_dir()),'Special delivery entry')
            if entry.is_file():need(rel.as_posix() in allowed,'Undeclared delivery output')
    return root,c

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

def fetch(contract,key):
    root,c=validate_contract(contract);need(key in c['artifacts'],'Unknown artifact');item=c['artifacts'][key]
    token=os.environ.get('GITHUB_TOKEN');need(type(token) is str and bool(token),'Read-only GitHub job token required')
    metadata=api_json('artifacts/'+str(item['artifact_id']),token);run=api_json('runs/'+str(item['run_id']),token)
    need(metadata.get('id')==item['artifact_id'] and metadata.get('expired') is False,'Wrong/expired artifact')
    need(metadata.get('digest')=='sha256:'+item['archive_sha256'] and metadata.get('workflow_run',{}).get('id')==item['run_id'] and metadata['workflow_run'].get('head_sha')==item['head_sha'],'Artifact provenance mismatch')
    need(run.get('id')==item['run_id'] and run.get('head_sha')==item['head_sha'] and run.get('status')=='completed' and run.get('conclusion')=='success','Upstream run not accepted')
    if key=='generated':need(metadata.get('name')=='licensed-material-prototypes-'+item['head_sha'],'Failed/diagnostic generation cannot be consumed')
    archive=path_at(root,item['archive_path'],False);dest=path_at(root,item['destination'],False)
    need(not archive.exists() and not dest.exists(),'Artifact output already exists')
    download('https://api.github.com/repos/'+REPO+'/actions/artifacts/'+str(item['artifact_id'])+'/zip',archive,token)
    need(sha(archive)==item['archive_sha256'],'Outer artifact ZIP hash mismatch');count=safe_extract(archive,item['members'],dest)
    return {'fetched':True,'key':key,'run_id':item['run_id'],'artifact_id':item['artifact_id'],'head_sha':item['head_sha'],'archive_sha256':sha(archive),'members':count}

def engine(contract):
    root,c=validate_contract(contract);e=c['engine'];archive=path_at(root,e['archive_path'],False);dest=path_at(root,e['destination'],False)
    download(e['url'],archive);safe_extract(archive,{e['member']:e['executable_sha256']},dest,max_total=256*1024*1024,max_member=256*1024*1024)
    binary=dest/e['member'];binary.chmod(0o755)
    return {'official_engine_prepared':True,'executable_sha256':sha(binary),'archive_sha256':sha(archive),'engine_executed':False}

def main():
    p=argparse.ArgumentParser(description=__doc__);sub=p.add_subparsers(dest='command',required=True)
    for cmd in ('preflight','fetch','engine'):
        q=sub.add_parser(cmd);q.add_argument('--contract',type=Path,required=True)
        if cmd=='preflight':q.add_argument('--mode',choices=('native','render'),required=True)
        if cmd=='fetch':q.add_argument('--key',required=True)
    a=p.parse_args()
    try:
        if a.command=='preflight':root,c=validate_contract(a.contract,strict=True);need(c['mode']==a.mode,'Wrong job mode');result={'preflight':True,'mode':c['mode'],'delivery_core_sha256':core_hash(c)}
        elif a.command=='fetch':result=fetch(a.contract,a.key)
        else:result=engine(a.contract)
        print(json.dumps(result,sort_keys=True));return 0
    except Exception as error:
        print(json.dumps({'passed':False,'reason':'Delivery input or official retrieval rejected','error_type':type(error).__name__}));return 1
if __name__=='__main__':raise SystemExit(main())

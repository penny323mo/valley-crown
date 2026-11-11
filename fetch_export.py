"""Hosted-only exact official Actions artifact ZIP reader; no runtime launch."""
from pathlib import Path,PurePosixPath
import argparse,hashlib,json,os,stat,urllib.error,urllib.parse,urllib.request,zipfile
from preflight_pair import admitted,source_check,need

MAX_EXPANDED=256*1024*1024
class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self,*args,**kwargs):return None

def api_request(path,token):
    return urllib.request.Request('https://api.github.com/repos/penny323mo/valley-crown/'+path,
        headers={'Authorization':'Bearer '+token,'Accept':'application/vnd.github+json','X-GitHub-Api-Version':'2022-11-28','User-Agent':'valley-crown-verified-artifact-reader'})

def metadata_matches(meta,expected):
    need(str(meta.get('id'))==expected['artifact_id'] and meta.get('expired') is False,'Artifact ID/expiry differs')
    need(meta.get('size_in_bytes')==expected['artifact_zip_size_bytes'] and meta.get('digest')=='sha256:'+expected['artifact_zip_sha256'],'Artifact metadata size/digest differs')
    run=meta.get('workflow_run',{})
    need(str(run.get('id'))==expected['export_run_id'] and run.get('head_sha')==expected['export_manifest']['diagnostic_export_commit'],'Artifact workflow identity differs')

def safe_target(url):
    u=urllib.parse.urlsplit(url);host=u.hostname or ''
    need(u.scheme=='https' and u.username is None and u.password is None and u.port in (None,443),'Unsafe artifact redirect')
    need(host.endswith('.blob.core.windows.net') or host.endswith('.actions.githubusercontent.com'),'Unrecognized official artifact storage host')
    return url

def verify_extract(archive,destination,expected):
    need(archive.stat().st_size==expected['artifact_zip_size_bytes'],'Actual ZIP byte count differs')
    with archive.open('rb') as stream:observed=hashlib.file_digest(stream,'sha256').hexdigest()
    need(observed==expected['artifact_zip_sha256'],'Actual full ZIP digest differs')
    need(not destination.exists(),'Fresh extraction directory required')
    with zipfile.ZipFile(archive) as z:
        rows=z.infolist();need(len(rows)<=2048 and len({x.filename for x in rows})==len(rows),'Oversized/duplicate archive inventory')
        need(sum(x.file_size for x in rows)<=MAX_EXPANDED,'Archive expansion exceeds bound')
        regular=[]
        for info in rows:
            raw=info.filename[:-1] if info.is_dir() else info.filename;parts=raw.split('/')
            need(raw and not PurePosixPath(raw).is_absolute() and '\\' not in raw and all(x not in ('','.','..') for x in parts),'Unsafe artifact path')
            kind=stat.S_IFMT(info.external_attr>>16)
            need(not info.flag_bits&1 and kind in (0,stat.S_IFREG,stat.S_IFDIR),'Encrypted/special artifact member')
            if info.is_dir():need(any(n.startswith(raw+'/') for n in expected['files_sha256']),'Unbound directory member')
            else:
                need(kind in (0,stat.S_IFREG) and info.file_size<=MAX_EXPANDED,'Invalid regular artifact member');regular.append(info)
        need({x.filename for x in regular}==set(expected['files_sha256']),'Actual ZIP member map differs')
        destination.mkdir();files={}
        for info in regular:
            target=destination/info.filename;target.parent.mkdir(parents=True,exist_ok=True);h=hashlib.sha256();count=0
            with z.open(info) as source,target.open('xb') as output:
                while chunk:=source.read(1024*1024):
                    count+=len(chunk);need(count<=info.file_size,'Member length differs');h.update(chunk);output.write(chunk)
            need(count==info.file_size and h.hexdigest()==expected['files_sha256'][info.filename],'Actual unpacked file digest differs')
            files[info.filename]=h.hexdigest()
    need(json.loads((destination/'diagnostic-export-manifest.json').read_text())==expected['export_manifest'],'Actual unpacked diagnostic manifest differs from reviewed object')
    return {'full_zip_verified':True,'zip_sha256':observed,'zip_bytes':archive.stat().st_size,'files_sha256':files}

def fetch(side,work):
    admitted();expected,_=source_check(side,True);work=work.absolute()
    need(not work.exists() and not any(x.is_symlink() for x in [work,*work.parents]),'Fresh nonsymlink download root required')
    work.mkdir();receipt={'side':side,'passed':False,'full_zip_verified':False,'phase':'metadata'}
    try:
        token=os.environ.get('GITHUB_TOKEN','');need(bool(token),'Read-only ephemeral GitHub token missing')
        need(type(expected.get('artifact_zip_size_bytes')) is int and 0<expected['artifact_zip_size_bytes']<=64*1024*1024,'Exact ZIP size pin invalid')
        opener=urllib.request.build_opener(NoRedirect());path='actions/artifacts/'+expected['artifact_id']
        with opener.open(api_request(path,token),timeout=30) as response:
            body=response.read(1024*1024+1);need(len(body)<=1024*1024,'Artifact metadata oversized');metadata_matches(json.loads(body),expected)
        receipt['phase']='official-redirect'
        try:
            with opener.open(api_request(path+'/zip',token),timeout=30):raise ValueError('Expected official artifact redirect')
        except urllib.error.HTTPError as error:
            need(error.code==302,'Unexpected artifact endpoint status');url=safe_target(error.headers.get('Location',''));error.close()
        receipt['phase']='zip-download';archive=work/'artifact.zip';count=0
        # No Authorization header is sent to storage. Signed URL is never logged.
        with opener.open(urllib.request.Request(url,headers={'User-Agent':'valley-crown-verified-artifact-reader'}),timeout=60) as response,archive.open('xb') as target:
            need(response.status==200,'Artifact body response differs')
            while chunk:=response.read(1024*1024):
                count+=len(chunk);need(count<=expected['artifact_zip_size_bytes'],'Artifact ZIP exceeds exact size');target.write(chunk)
        receipt['phase']='strict-extraction';receipt.update(verify_extract(archive,work/'candidate',expected))
        receipt.update(passed=True,phase='completed',artifact_id=expected['artifact_id'],export_run_id=expected['export_run_id'],source_chain_verification_sha256=expected['source_chain_verification_sha256'])
    except BaseException as error:
        receipt['failure_type']=type(error).__name__  # Never print token, signed URL, headers or arbitrary remote error text.
        if isinstance(error,urllib.error.HTTPError):receipt['http_status']=error.code
    finally:(work/'artifact-download.json').write_text(json.dumps(receipt,indent=2,sort_keys=True)+'\n')
    return 0 if receipt['passed'] else 1

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--side',choices=['baseline','candidate'],required=True);p.add_argument('--work',type=Path,required=True);a=p.parse_args();raise SystemExit(fetch(a.side,a.work))

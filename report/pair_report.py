"""Offline evidence comparison only. No launch, promotion or host sampling."""
from pathlib import Path
import argparse,hashlib,json,os,struct
from validate_comparison import compare,need
ROOT=Path(__file__).resolve().parents[1]

def read(path):return json.loads(path.read_text())
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()

def arm(side,work,download):
    expected=read(ROOT/side/'qa/expected-export.json');manifest=read(ROOT/side/'qa/scenario-manifest.json')
    received=read(download/'artifact-download.json')
    need(received.get('passed') is True and received.get('full_zip_verified') is True,'Hosted full ZIP verification missing: '+side)
    need(received.get('zip_sha256')==expected['artifact_zip_sha256'] and received.get('zip_bytes')==expected['artifact_zip_size_bytes'] and received.get('files_sha256')==expected['files_sha256'],'Hosted ZIP/output map differs: '+side)
    evidence=read(work/'evidence/browser-evidence.json');host=read(work/'host-guard.json')
    need(host.get('host_oom_unchanged_after_cleanup') is True,'Post-cleanup OOM verification missing: '+side)
    for screenshot in evidence.get('screenshots',[]):
        name=screenshot['name'];need(name=='paused-startup.png','Unexpected screenshot filename')
        path=work/'evidence'/name;data=path.read_bytes();need(hashlib.sha256(data).hexdigest()==screenshot['sha256'],'PNG bytes differ')
        need(data[:8]==b'\x89PNG\r\n\x1a\n' and struct.unpack('>II',data[16:24])==(390,844),'PNG signature/dimensions differ')
    journal=work/'evidence/host-unit.log'
    cpu={'scope':'Whole original service: Node/server/browser startup, load, warmup, measurement, screenshot and cleanup; not measurement-window CPU',
         'journal_status':'retained' if journal.is_file() else 'unknown','journal_sha256':sha(journal) if journal.is_file() else None}
    return evidence,host,manifest,cpu

def main(args):
    result={'status':'inconclusive','automatic_promotion':False,'normal_gameplay_fps':False}
    try:
        a,ha,ma,ca=arm('baseline',args.baseline,args.baseline_download);b,hb,mb,cb=arm('candidate',args.candidate,args.candidate_download)
        need(ha.get('unit')!=hb.get('unit') and ha.get('owner')!=hb.get('owner'),'Pair reused owned service scope')
        result=compare(a,b,ha,hb,ma,mb);result['whole_service_cpu_evidence']={'baseline':ca,'candidate':cb}
    except (OSError,ValueError,KeyError,TypeError,struct.error) as error:result['reason']=str(error)
    result['workflow_scope']={'run_id':os.environ.get('GITHUB_RUN_ID'),'attempt':os.environ.get('GITHUB_RUN_ATTEMPT'),'job':os.environ.get('GITHUB_JOB'),'commit':os.environ.get('GITHUB_SHA'),'layout':'One fresh hosted job; baseline cleanup verified before separate candidate service; no concurrent legs'}
    args.output.parent.mkdir(parents=True,exist_ok=True);args.output.write_text(json.dumps(result,indent=2,sort_keys=True)+'\n')
    return 0 if result['status']=='descriptive_pair_only' else 1

if __name__=='__main__':
    p=argparse.ArgumentParser()
    for key in ('baseline','candidate','baseline-download','candidate-download','output'):p.add_argument('--'+key,type=Path,required=True)
    raise SystemExit(main(p.parse_args()))

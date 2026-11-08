#!/usr/bin/env python3
"""Bounded failure-only diagnostics; never accepts captures or reads frame payloads."""
from pathlib import Path
import argparse,hashlib,json,math,os,re,stat
SCENARIOS=('studies','portrait','landscape')
IMPORT_NAMES={'import.log','import.json','import.invocation.json'}
RENDER_NAMES={'godot.log','xvfb.log','guard-receipt.json'}
ENGINE_SHA='f64d4ed19fc9df9440321653fcc80df8c6e365ba7b6de0a29e2cfa9fa71bfeb3'
MONITOR_SHA='4c7802bcfb53a2f73f501635cdf483e1459d3d86eb881a7450dccd3bbd705d50'
PRIVATE=(rb'/workspace/(?:scratch|shared)/',rb'/home/agent/',rb'/(?:agent_notes|user_notes)/',rb'gh[pousr]_[A-Za-z0-9]{20,}',rb'github_pat_[A-Za-z0-9_]{20,}',rb'AKIA[0-9A-Z]{16}',rb'sk-[A-Za-z0-9_-]{24,}',rb'xox[baprs]-[A-Za-z0-9-]{16,}',rb'-----BEGIN (?:RSA |EC |DSA |OPENSSH |ENCRYPTED )?PRIVATE KEY-----',rb'(?i)(?:authorization\s*:\s*bearer|password\s*[=:]|MIT-MAGIC-COOKIE)')
MAX_LOG=4*1024*1024
MAX_JSON=16*1024*1024
MAX_TOTAL=64*1024*1024

def need(value,message):
    if not value:raise ValueError(message)
def digest(data):return hashlib.sha256(data).hexdigest()
def strict_json(data):
    def pairs(rows):
        result={}
        for key,value in rows:need(key not in result,'Duplicate JSON key');result[key]=value
        return result
    def invalid(_):raise ValueError('Nonfinite JSON')
    def finite(value):
        parsed=float(value);need(math.isfinite(parsed),'Nonfinite JSON numeric overflow');return parsed
    return json.loads(data,object_pairs_hook=pairs,parse_constant=invalid,parse_float=finite)
def clean(path):
    p=Path(path).absolute();need(not any(x.is_symlink() for x in (p,*p.parents)),'Unsafe symlink path');return p

def regular(path):
    clean(path)
    need(stat.S_ISREG(path.lstat().st_mode),'Nonregular diagnostic file')
def directory_entries(root,files,dirs=()):
    need(root.is_dir() and not root.is_symlink(),'Unsafe evidence directory');found=set()
    for p in root.iterdir():
        mode=p.lstat().st_mode
        need(not stat.S_ISLNK(mode),'Symlink evidence entry')
        if p.name in dirs:need(stat.S_ISDIR(mode),'Invalid excluded directory')
        else:need(p.name in files and stat.S_ISREG(mode),'Unknown/special evidence entry');found.add(p.name)
    return found

def validate_import(receipt,invocation,log_bytes,invocation_bytes):
    need(type(receipt) is dict and receipt.get('cleanup_complete') is True and receipt.get('child_started') is True and not receipt.get('cleanup_errors'),'Import owned child cleanup incomplete')
    need(type(receipt.get('exit')) is int,'Import exit unconfirmed')
    need(receipt.get('log_sha256')==digest(log_bytes) and receipt.get('invocation_sha256')==digest(invocation_bytes),'Import log/invocation binding mismatch')
    need(invocation.get('test_dependencies') is False,'Injected import evidence')
    helper=invocation.get('helper',{})
    need(helper.get('load_sha256')==helper.get('invocation_sha256')==MONITOR_SHA,'Import monitor provenance differs')
    need(invocation.get('artifacts',{}).get('engine',{}).get('sha256')==ENGINE_SHA,'Import engine differs')
    argv=invocation.get('argv')
    need(type(argv) is list and len(argv)==6 and argv==invocation.get('requested_argv') and argv[1:4]==['--headless','--editor','--path'] and argv[5]=='--import','Unexpected import command')

def validate_render(guard,logs):
    need(type(guard) is dict and guard.get('cleanup_complete') is True and guard.get('test_dependencies') is False,'Render cleanup/injection gate failed')
    need(not guard.get('unexpected_descendants') and not guard.get('readiness_cleanup_errors') and not guard.get('signal_restore_errors') and 'private_cleanup_error' not in guard,'Render readiness/ownership cleanup incomplete')
    children=guard.get('children');cleanup=guard.get('cleanup')
    need(type(children) is dict and bool(children) and set(children)<={'godot','xvfb'} and 'xvfb' in children,'No owned render process')
    need(type(cleanup) is dict and set(cleanup)==set(children) and logs=={name+'.log' for name in children},'Owned child/log/cleanup coverage differs')
    inputs=guard.get('input_sha256',{});need(inputs.get('godot')==ENGINE_SHA,'Render engine identity differs')
    pids=set()
    for name,child in children.items():
        need(type(child.get('pid')) is int and child['pid']>0 and child['pid'] not in pids,'Invalid/duplicate owned PID');pids.add(child['pid'])
        need(re.fullmatch('[a-f0-9]{64}',str(inputs.get(name))) is not None and child.get('executable_sha256')==inputs[name],'Owned executable binding differs')
        item=cleanup[name]
        need(item.get('complete') is True and type(item.get('exit')) is int and item.get('errors')==[],'Owned process was not cleanly reaped')
        need(type(item.get('signals')) is list and all(s in ('SIGTERM','SIGKILL') for s in item['signals']),'Unexpected cleanup signals')
    startup=guard.get('startup',{})
    need(type(startup.get('complete')) is bool and type(startup.get('detected')) is bool,'Missing readiness state')
    need(not startup['detected'] or startup['complete'],'Unresolved detected startup lifetime')
    need('godot' not in children or startup['complete'],'Godot started before completed readiness')
    helpers=startup.get('helpers');descendants=guard.get('observed_descendant_cleanup')
    need(type(helpers) is list and len(helpers)<=2 and type(descendants) is list and len(descendants)==len(helpers),'Startup ownership coverage differs')
    need(not helpers or (startup['complete'] and startup['detected'] and len(helpers)==2 and {h.get('role') for h in helpers}=={'dash','xkbcomp'}),'Startup helper pair incomplete')
    observed=set()
    for row in descendants:
        identity=(row.get('pid'),row.get('starttime_ticks'))
        need(all(type(v) is int and v>0 for v in identity) and identity not in observed,'Invalid/duplicate descendant lifetime')
        need(row.get('exited') is True and row.get('pidfd_closed') is True and row.get('status')!='cleanup_unconfirmed' and 'error_type' not in row,'Descendant cleanup unconfirmed');observed.add(identity)
    expected=set()
    for h in helpers:
        identity=h.get('identity',{});key=(identity.get('pid'),identity.get('starttime_ticks'));expected.add(key)
        need(h.get('exit_confirmed_before_engine') is True,'Startup helper exit unconfirmed before engine')
        need(all(type(h.get(k)) is int and 0<=h[k]<=limit for k,limit in [('sampled_peak_rss_kib',131072),('sampled_peak_hwm_kib',131072),('sampled_peak_threads',4)]),'Startup helper bounds differ')
        need(h.get('executable_sha256')==startup.get('distribution',{}).get(h.get('role'),{}).get('sha256') and re.fullmatch('[a-f0-9]{64}',str(h.get('executable_sha256'))) is not None,'Startup helper executable differs')
    need(expected==observed,'Startup helper pidfd lifetime mismatch')
    if helpers:
        by_role={h['role']:h for h in helpers}
        need(by_role['dash']['identity'].get('ppid')==children['xvfb']['pid'] and by_role['xkbcomp']['identity'].get('ppid')==by_role['dash']['identity']['pid'],'Startup helper parent ownership differs')
    need(startup.get('distribution',{}).get('xvfb',{}).get('sha256')==inputs.get('xvfb'),'Distribution Xvfb binding differs')

def collect(import_evidence,render_evidence,destination,failure_confirmed):
    need(failure_confirmed,'Explicit workflow failure context required')
    imp,render,dest=map(clean,(import_evidence,render_evidence,destination))
    need(not dest.exists() and all(not a.is_relative_to(b) and not b.is_relative_to(a) for a,b in ((imp,render),(imp,dest),(render,dest))),'Fresh disjoint diagnostic roots required')
    selected={};sources={};total=0
    def read(path,name):
        nonlocal total
        regular(path);limit=MAX_LOG if path.suffix=='.log' else MAX_JSON
        need(path.stat().st_size<=limit,'Diagnostic member oversized');data=path.read_bytes();need(len(data)<=limit,'Diagnostic grew beyond limit')
        total+=len(data);need(total<=MAX_TOTAL,'Diagnostic bundle oversized');data.decode('utf-8')
        need(not any(re.search(pattern,data) for pattern in PRIVATE),'Diagnostic privacy rejection')
        if path.suffix=='.json':strict_json(data)
        selected[name]=data;sources[name]=path;return data
    if imp.exists():
        names=directory_entries(imp,IMPORT_NAMES|{'phase-summary.json'})
        need(IMPORT_NAMES<=names,'No complete owned import diagnostic receipt')
        data={n:read(imp/n,'import/'+n) for n in sorted(IMPORT_NAMES)}
        validate_import(strict_json(data['import.json']),strict_json(data['import.invocation.json']),data['import.log'],data['import.invocation.json'])
    if render.exists():
        need(imp.exists() and 'import/import.json' in selected,'Render diagnostics require owned import receipt')
        directory_entries(render,{name+'-scan.json' for name in SCENARIOS},SCENARIOS)
        for scenario in SCENARIOS:
            folder=render/scenario
            if not folder.exists():continue
            names=directory_entries(folder,RENDER_NAMES,{'frames'})
            need('guard-receipt.json' in names,'Missing owned render receipt')
            data={n:read(folder/n,scenario+'/'+n) for n in sorted(names)}
            validate_render(strict_json(data['guard-receipt.json']),names-{'guard-receipt.json'})
    need(selected and any(n.endswith('.log') for n in selected),'No safe owned engine diagnostic evidence')
    # Check stable originals once more after complete ownership/privacy admission.
    for name,path in sources.items():regular(path);need(path.read_bytes()==selected[name],'Diagnostic source changed while collecting')
    dest.mkdir();hashes={}
    for name,data in sorted(selected.items()):
        target=dest/name;target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(data);hashes[name]=digest(data)
    index={'classification':'UNACCEPTED_DIAGNOSTIC_RENDER_FAILURE','diagnostic_only':True,'not_render_or_runtime_acceptance':True,'scope':'Bounded owned engine logs and cleanup receipts only; all frame payloads excluded','files_sha256':hashes,'file_count':len(hashes),'total_bytes':total}
    (dest/'UNACCEPTED_DIAGNOSTICS.json').write_text(json.dumps(index,indent=2)+'\n');return len(hashes)+1

def main():
    p=argparse.ArgumentParser(description=__doc__)
    for n in ('import-evidence','render-evidence','destination'):p.add_argument('--'+n,type=Path,required=True)
    p.add_argument('--failure-confirmed',action='store_true');a=p.parse_args()
    try:
        count=collect(a.import_evidence,a.render_evidence,a.destination,a.failure_confirmed)
        with Path(os.environ['GITHUB_OUTPUT']).open('a') as f:f.write('diagnostics_scanned=true\n')
        print('UNACCEPTED_DIAGNOSTIC_RENDER_FAILURE: '+str(count)+' bounded files');return 0
    except Exception as error:
        print('UNACCEPTED render diagnostics withheld: '+type(error).__name__);return 1
if __name__=='__main__':raise SystemExit(main())

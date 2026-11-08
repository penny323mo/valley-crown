#!/usr/bin/env python3
"""Failure-only bounded diagnostic copy. Never accepts or packages runtime assets."""
from pathlib import Path
import argparse,hashlib,json,os,re,stat
PHASES=('import','material-baseline','native-pack','reload-diagnostic','material-proof','stamp','reload-final')
SELECTED={'summary.json'}|{p+s for p in PHASES for s in ('.log','.json','.invocation.json')}
KNOWN=SELECTED|{p+'.before.json' for p in PHASES}|{p+'.report.json' for p in PHASES if p!='import'}|{'accepted-runtime/'+n for n in ('runtime-delta.zip','final-source-lock.json','receipt.json')}
PRIVATE=(rb'/workspace/(?:scratch|shared)/',rb'/home/agent/',rb'/(?:agent_notes|user_notes)/',rb'gh[pousr]_[A-Za-z0-9]{20,}',rb'github_pat_[A-Za-z0-9_]{20,}',rb'AKIA[0-9A-Z]{16}',rb'sk-[A-Za-z0-9_-]{24,}',rb'xox[baprs]-[A-Za-z0-9-]{16,}',rb'-----BEGIN (?:RSA |EC |DSA |OPENSSH |ENCRYPTED )?PRIVATE KEY-----')
def need(ok,reason):
    if not ok:raise ValueError(reason)
def clean(path):
    p=Path(path).absolute();need(not any(x.is_symlink() for x in (p,*p.parents)),'Unsafe path');return p

def read_json(data):
    def pairs(rows):
        value={}
        for key,item in rows:
            need(key not in value,"Duplicate diagnostic JSON key");value[key]=item
        return value
    def invalid(_):raise ValueError("Nonfinite diagnostic JSON")
    return json.loads(data,object_pairs_hook=pairs,parse_constant=invalid)

def collect(source,destination,failure_confirmed):
    need(failure_confirmed,'Failure context required')
    source=clean(source);destination=clean(destination)
    need(source.is_dir() and not destination.exists() and not destination.is_relative_to(source) and not source.is_relative_to(destination),'Fresh disjoint diagnostic destination required')
    selected={};total=0
    for p in source.rglob('*'):
        name=p.relative_to(source).as_posix();mode=p.lstat().st_mode
        need(not stat.S_ISLNK(mode),'Symlink rejected')
        if stat.S_ISDIR(mode):need(name=='accepted-runtime','Unknown evidence directory');continue
        need(stat.S_ISREG(mode) and name in KNOWN,'Unknown/special evidence entry')
        if name not in SELECTED:continue  # No runtime bytes, inventories or rendered/semantic reports.
        limit=4*1024*1024 if name.endswith('.log') else 16*1024*1024
        need(p.stat().st_size<=limit,'Oversized diagnostic member')
        total+=p.stat().st_size;need(total<=48*1024*1024,'Oversized diagnostic bundle')
        data=p.read_bytes();data.decode('utf-8')
        need(not any(re.search(pattern,data) for pattern in PRIVATE),'Diagnostic privacy scan failed')
        if name.endswith('.json'):read_json(data)
        selected[name]=data
    need('summary.json' in selected and any(n.endswith('.log') for n in selected),'No native engine failure logs available')
    summary=read_json(selected['summary.json']);need(type(summary) is dict and type(summary.get('passed')) is bool,'Malformed native summary')
    for phase in PHASES:
        trio={phase+'.log',phase+'.json',phase+'.invocation.json'}
        if not (trio & set(selected)):continue
        need(trio <= set(selected),'Incomplete owned-process diagnostic receipt')
        receipt=read_json(selected[phase+'.json'])
        need(receipt.get('cleanup_complete') is True and receipt.get('child_started') is True and not receipt.get('cleanup_errors'),'Owned engine cleanup not confirmed')
        need(receipt.get('log_sha256')==hashlib.sha256(selected[phase+'.log']).hexdigest() and receipt.get('invocation_sha256')==hashlib.sha256(selected[phase+'.invocation.json']).hexdigest(),'Diagnostic receipt content binding differs')
    destination.mkdir()
    hashes={}
    for name,data in sorted(selected.items()):
        (destination/name).write_bytes(data);hashes[name]=hashlib.sha256(data).hexdigest()
    index={'classification':'UNACCEPTED_DIAGNOSTIC_NATIVE_FAILURE','diagnostic_only':True,'not_native_or_render_acceptance':True,'scope':'Bounded raw phase stdout/stderr and process receipts only; no assets or runtime delivery','files_sha256':hashes,'file_count':len(hashes),'total_bytes':total}
    (destination/'UNVALIDATED_DIAGNOSTICS.json').write_text(json.dumps(index,indent=2)+'\n')
    return len(hashes)+1

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--source',type=Path,required=True);p.add_argument('--destination',type=Path,required=True);p.add_argument('--failure-confirmed',action='store_true');a=p.parse_args()
    try:
        count=collect(a.source,a.destination,a.failure_confirmed)
        with Path(os.environ['GITHUB_OUTPUT']).open('a') as f:f.write('diagnostics_scanned=true\n')
        print('UNVALIDATED native failure diagnostics: '+str(count)+' bounded files');return 0
    except Exception as error:
        print('UNVALIDATED diagnostics withheld: '+type(error).__name__);return 1
if __name__=='__main__':raise SystemExit(main())

#!/usr/bin/python3
"""Stage three scanned captures and seven cross-bound import/lock provenance files."""
from pathlib import Path, PurePosixPath
import argparse, hashlib, json, math, re, shutil
from collect_render_failure import PRIVATE, ENGINE_SHA, MONITOR_SHA, validate_import
SCENARIOS=('studies','portrait','landscape')
def need(ok):
    if not ok: raise ValueError('Render delivery rejected; details withheld')
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def regular(p):
    p=Path(p).absolute();need(not any(q.is_symlink() for q in (p,*p.parents)) and p.is_file());return p
def read(p):
    p=regular(p);need(p.stat().st_size<=16*1024*1024)
    def pairs(rows):
        out={}
        for k,v in rows:need(k not in out);out[k]=v
        return out
    def bad(v):raise ValueError('Render delivery rejected; details withheld')
    def finite(value):
        number=float(value);need(math.isfinite(number));return number
    return json.loads(p.read_text(),object_pairs_hook=pairs,parse_constant=bad,parse_float=finite)
def expected_files(name):
    labels=[k+'-'+v for k in ('villager','spearman','archer','scout') for v in ('front','rear')] if name=='studies' else ['opening','worker-walking']
    result={'guard-receipt.json','godot.log','xvfb.log','frames/capture-report.json'}
    for i,label in enumerate(labels):
        base='frames/%03d-%s.png'%(i,label);result.update((base,base+'.json'))
    return result

def provenance(evidence,marker,import_evidence,final_locks):
    marker=regular(marker);imp=Path(import_evidence).absolute();locks=Path(final_locks).absolute()
    need(marker.name=='import-complete.json' and imp.is_dir() and locks.is_dir())
    need({p.name for p in locks.iterdir()}=={n+'.json' for n in SCENARIOS})
    need({p.name for p in imp.iterdir()}<={'import.json','import.invocation.json','import.log','phase-summary.json'})
    receipt=regular(imp/'import.json');invocation=regular(imp/'import.invocation.json');log=regular(imp/'import.log')
    files={'provenance/import-complete.json':marker,'provenance/import.json':receipt,
           'provenance/import.invocation.json':invocation,'provenance/import.log':log}
    for name in SCENARIOS:files['provenance/'+name+'-lock.json']=regular(locks/(name+'.json'))
    pinned={name:sha(path) for name,path in files.items()}
    total=0
    for path in files.values():
        limit=4*1024*1024 if path.suffix=='.log' else 16*1024*1024
        need(path.stat().st_size<=limit);data=path.read_bytes();need(len(data)<=limit);total+=len(data)
        need(total<=64*1024*1024 and not any(re.search(pattern,data) for pattern in PRIVATE));data.decode('utf-8')
        if path.suffix=='.json':
            decoded=json.dumps(read(path),ensure_ascii=False).encode()
            need(not any(re.search(pattern,decoded) for pattern in PRIVATE))
    certificate=read(marker);result=read(receipt);request=read(invocation)
    validate_import(result,request,log.read_bytes(),invocation.read_bytes())
    need(result.get('passed') is True and result.get('exit')==0 and not result.get('exception') and not result.get('stop_reason') and not result.get('output_errors'))
    need(type(result.get('post_run_binding_matches')) is dict and bool(result['post_run_binding_matches']) and all(v is True for v in result['post_run_binding_matches'].values()))
    need(certificate.get('receipt')==str(receipt) and certificate.get('invocation')==str(invocation))
    need(certificate.get('receipt_sha256')==sha(receipt) and certificate.get('invocation_sha256')==sha(invocation))
    need(type(certificate.get('cache_sha256')) is dict and bool(certificate['cache_sha256']))
    need(all(re.fullmatch('[0-9a-f]{64}',h) is not None for h in certificate['cache_sha256'].values()))
    argv=request.get('argv');need(argv==request.get('requested_argv') and argv[4]==certificate.get('project'))
    shared=None
    for name in SCENARIOS:
        lock_path=locks/(name+'.json');lock=read(lock_path);guard=read(Path(evidence)/name/'guard-receipt.json')
        need(guard.get('passed') is True and guard.get('cleanup_complete') is True and guard.get('capture_completed') is True and guard.get('test_dependencies') is False)
        need(lock.get('reviewed_for_execution') is True and lock.get('import_certificate_sha256')==sha(marker))
        need(lock.get('build')==certificate.get('build')==guard.get('build'))
        identity=(lock.get('project_files'),lock.get('material_binding'),lock.get('source_archive_sha256'),lock.get('import_manifest_sha256'))
        if shared is None:shared=identity
        else:need(identity==shared)
        need(type(lock.get('project_files')) is dict and len(lock['project_files'])==197)
        need(certificate.get('archive_sha256')==lock['source_archive_sha256'] and certificate.get('manifest_sha256')==lock['import_manifest_sha256'])
        need(certificate.get('engine_sha256')==lock.get('godot_sha256')==ENGINE_SHA)
        need(certificate.get('adapter_sha256')==lock['support_files']['ci/guarded_manifest_ci.py'])
        bindings=guard.get('input_sha256',{})
        expected={'lock':sha(lock_path),'import_marker':sha(marker),'import_receipt':sha(receipt),'import_invocation':sha(invocation),'import_log':sha(log)}
        need(all(bindings.get(k)==v for k,v in expected.items()))
        need(bindings.get('import_adapter')==certificate['adapter_sha256'])
        for key,want in {'adapter':certificate['adapter_sha256'],'monitor':MONITOR_SHA,'engine':ENGINE_SHA,'archive':lock['source_archive_sha256'],'suite-manifest':lock['import_manifest_sha256']}.items():
            need(request.get('artifacts',{}).get(key,{}).get('sha256')==want)
    need(all(sha(path)==pinned[name] for name,path in files.items()))
    return files,pinned


def stage(evidence,destination,import_marker,import_evidence,final_locks):
    evidence=Path(evidence).absolute();destination=Path(destination).absolute()
    need(evidence.is_dir() and not evidence.is_symlink() and not destination.exists() and not destination.is_relative_to(evidence) and not evidence.is_relative_to(destination))
    need(not any(p.is_symlink() for p in destination.parents))
    for source in (Path(import_evidence).absolute(),Path(final_locks).absolute()):
        need(not destination.is_relative_to(source) and not source.is_relative_to(destination))
    all_files={}
    for name in SCENARIOS:
        folder=evidence/name;report_path=evidence/(name+'-scan.json');scan=read(report_path)
        need(scan.get('passed') is True and scan.get('findings')==[] and type(scan.get('files')) is dict and len(scan['files'])==len(expected_files(name)))
        need(type(scan.get('visual_findings')) is list and any(row.get('kind')=='human_material_pixel_review_required' for row in scan['visual_findings']))
        need(set(scan['files'])==expected_files(name))
        actual={}
        need(folder.is_dir() and not folder.is_symlink())
        for p in folder.rglob('*'):
            need(not p.is_symlink() and (p.is_file() or p.is_dir()))
            if p.is_file():regular(p);actual[p.relative_to(folder).as_posix()]=p
        need(set(actual)==set(scan['files']))
        for key,p in actual.items():
            need(not PurePosixPath(key).is_absolute() and '..' not in key.split('/') and '\\' not in key)
            need(re.fullmatch('[0-9a-f]{64}',scan['files'][key].get('sha256','')) is not None and sha(p)==scan['files'][key]['sha256'])
            all_files[name+'/'+key]=p
        all_files[name+'-scan.json']=report_path
    extra,provenance_pins=provenance(evidence,import_marker,import_evidence,final_locks)
    need(len(extra)==7);all_files.update(extra)
    expected_total=sum(len(expected_files(name))+1 for name in SCENARIOS)+7
    need(len(all_files)==expected_total)
    original_hashes={name:sha(path) for name,path in all_files.items()}
    need(all(original_hashes[name]==digest for name,digest in provenance_pins.items()))
    destination.mkdir()
    for name,p in sorted(all_files.items()):
        target=destination/name;target.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(p,target);need(sha(target)==sha(p)==original_hashes[name])
    return {'passed':True,'files':len(all_files),'visual_acceptance':False}
if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--evidence',type=Path,required=True);p.add_argument('--destination',type=Path,required=True)
    for name in ('import-marker','import-evidence','final-locks'):p.add_argument('--'+name,type=Path,required=True)
    a=p.parse_args()
    try:result=stage(a.evidence,a.destination,a.import_marker,a.import_evidence,a.final_locks)
    except Exception:print(json.dumps({'passed':False,'reason':'Render delivery rejected; details withheld'}));raise SystemExit(1)
    print(json.dumps(result))

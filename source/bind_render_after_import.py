#!/usr/bin/env python3
"""Bind one actual successful clean-import certificate. No engine/process/network."""
from pathlib import Path
import argparse, hashlib, importlib.util, json, os, sys
ASSEMBLY_HELPER_SHA = '732f1b634788bd15d5dad4211a1f876468ed76455e6be11cfdff7057d7be2487'
_HELPER = Path(__file__).with_name('assemble_material_source.py').absolute()
if any(p.is_symlink() for p in (_HELPER,*_HELPER.parents)) or not _HELPER.is_file() or hashlib.sha256(_HELPER.read_bytes()).hexdigest()!=ASSEMBLY_HELPER_SHA:
    raise RuntimeError('Bound assembly helper differs')
from assemble_material_source import need,sha,regular,json_file,digest,write_json

def core_hash(lock):
    core=dict(lock);core.pop('independent_review',None);core['import_certificate_sha256']=None
    return hashlib.sha256(json.dumps(core,sort_keys=True,separators=(',',':'),allow_nan=False).encode()).hexdigest()

def bind(a):
    need(os.environ.get('GITHUB_ACTIONS')=='true' and os.environ.get('RUNNER_ENVIRONMENT')=='github-hosted','Post-import binding is hosted only')
    prepared=regular(a.prepared_lock);need(sha(prepared)==digest(a.prepared_lock_sha256),'Prepared lock pin mismatch');lock=json_file(prepared)
    need(lock.get('reviewed_for_execution') is True and lock.get('import_certificate_sha256') is None,'Not an approved unbound render template')
    need(lock.get('independent_review',{}).get('passed') is True and sha(regular(a.review))==lock['independent_review']['report_sha256'],'Actual render review not bound')
    review=json_file(a.review)
    need(review.get('peer_reviewed') is True and review.get('render_contract_core_sha256')==core_hash(lock),'Review does not bind exact prepared capture contract')
    need(review.get('binder_sha256')==sha(__file__) and review.get('assembly_helper_sha256')==ASSEMBLY_HELPER_SHA,'Binder/dependency not independently reviewed')
    helper_root=Path(a.helpers).absolute();need(helper_root.is_dir() and not helper_root.is_symlink(),'Bad helper directory')
    for name,expected in lock['support_files'].items():
        need(name.startswith('ci/') and '/' not in name[3:] and '\\' not in name,'Unreviewed helper path')
        need(sha(regular(helper_root/name[3:]))==expected,'Helper drift')
    # Import only pinned locally authored guard definitions. No module launches an engine on import.
    sys.path.insert(0,str(helper_root))
    import guarded_manifest_ci as guard
    import material_contract
    import run_native
    marker=regular(a.import_marker);certificate=json_file(marker)
    lock=dict(lock);lock['import_certificate_sha256']=sha(marker)
    material_contract.validate_lock(lock)
    project=Path(a.project).resolve();engine=regular(a.godot).resolve();need(sha(engine)==lock['godot_sha256']==guard.ENGINE_SHA,'Wrong official engine')
    package,entries=guard.verify_source(project,regular(a.archive),regular(a.manifest),lock['source_archive_sha256'],lock['import_manifest_sha256'])
    need(entries==lock['project_files'] and package['candidate']==lock['build'],'Source package/lock differs')
    source,uids=run_native.source_inventory(project,lock);cache=run_native.cache_inputs(project)
    expected={'build':lock['build'],'project':str(project),'archive_sha256':lock['source_archive_sha256'],'manifest_sha256':lock['import_manifest_sha256'],'engine_sha256':guard.ENGINE_SHA,'adapter_sha256':lock['support_files']['ci/guarded_manifest_ci.py']}
    for k,v in expected.items():need(certificate.get(k)==v,'Fresh import identity differs')
    need(certificate.get('cache_sha256')==cache|uids and bool(cache),'Cache differs from actual clean import')
    receipt=regular(certificate['receipt']);invocation=regular(certificate['invocation'])
    need(sha(receipt)==certificate['receipt_sha256'] and sha(invocation)==certificate['invocation_sha256'],'Import receipt/invocation drift')
    guard.guard_receipt(receipt,invocation)
    request=json_file(invocation);argv=[str(engine),'--headless','--editor','--path',str(project),'--import']
    need(request.get('argv')==request.get('requested_argv')==argv,'Unexpected import command')
    for key,expected_sha in {'adapter':lock['support_files']['ci/guarded_manifest_ci.py'],'monitor':guard.MONITOR_SHA,'engine':guard.ENGINE_SHA,'archive':lock['source_archive_sha256'],'suite-manifest':lock['import_manifest_sha256']}.items():need(request['artifacts'][key]['sha256']==expected_sha,'Import control mismatch')
    output=Path(a.output).absolute();need(not output.exists() and not output.is_relative_to(project),'Lock output must be fresh and outside source');need(not any(p.is_symlink() for p in output.parents),'Lock output ancestor symlink')
    write_json(output,lock)
    return {'bound':True,'build':lock['build'],'prepared_lock_sha256':sha(prepared),'final_lock_sha256':sha(output),'import_certificate_sha256':sha(marker),'engine_executed_by_binder':False,'changed_fields':['import_certificate_sha256']}

def main():
    p=argparse.ArgumentParser(description=__doc__)
    for name in ('prepared-lock','review','helpers','import-marker','project','godot','archive','manifest','output'):p.add_argument('--'+name,type=Path,required=True)
    p.add_argument('--prepared-lock-sha256',required=True);print(json.dumps(bind(p.parse_args()),indent=2))
if __name__=='__main__':main()

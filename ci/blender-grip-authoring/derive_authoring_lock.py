#!/usr/bin/env python3
"""Reviewed deterministic tool derivation only. Never launches Blender."""
import argparse,importlib.util,json,os,re
from pathlib import Path
import run_authoring as r
p=r.p
CODE={'correct_public_grips.py':'3dfd3babe8fbe2f7ed183b87df1844cffc8e22832a82ed5eaf13c4e0e197d1cb','equipment_geometry.py':'958db50349dcb52f4523a75aa5476fbd14b33387822820820f0a79d6a05c4c45'}
CALIBRATION='7976d9c1247f6dae1e44e0c8558b3bef0e44753e401fb9aa5714460169216be3'
HELPERS={'run_authoring.py','owned_process.py','prepare_official_tool.py','download_official_archive.py','derive_authoring_lock.py'}

def validate_admission(admission):
    p.require(type(admission) is dict and set(admission)=={'schema','reviewed_for_derivation','files','code_files','calibration_sha256','archive_sha256'},'Wrong derivation admission keys')
    p.require(admission['schema']=='vc-fixed-blender-derivation-v1' and admission['reviewed_for_derivation'] is True,'Derivation not reviewed')
    p.require(admission['code_files']==CODE and admission['calibration_sha256']==CALIBRATION and admission['archive_sha256']==r.ARCHIVE_SHA,'Wrong product/archive binding')
    p.require(type(admission['files']) is dict and set(admission['files'])==HELPERS,'Wrong helper inventory')
    for h in admission['files'].values():r.digest_value(h)

def derive(args):
    admission_path=r.safe_path(args.admission);p.regular(admission_path);p.require(admission_path.stat().st_size<=64<<10,'Oversize admission')
    admission=json.loads(admission_path.read_text());validate_admission(admission)
    p.require(os.environ.get('GITHUB_ACTIONS')=='true' and os.environ.get('RUNNER_ENVIRONMENT')=='github-hosted','Fresh hosted runner required')
    p.require('VERSION_ID="24.04"' in Path('/etc/os-release').read_text(),'Ubuntu 24.04 required')
    commit=os.environ.get('GITHUB_SHA','');p.require(re.fullmatch('[a-f0-9]{40}',commit) is not None,'Missing exact dispatched commit')
    root=Path(__file__).absolute().parent
    archive=r.checked(args.archive,r.ARCHIVE_SHA,512<<20)
    code,source,calibration,tool,receipt,lockpath=map(r.safe_path,(args.code_root,args.input_root,args.calibration,args.tool_root,args.extraction_receipt,args.lock))
    p.require(not tool.exists() and not receipt.exists() and not lockpath.exists(),'Fresh derivation outputs required')
    roots=[root,code,source,tool]
    p.require(len(set(roots))==len(roots) and all(not a.is_relative_to(b) for a in roots for b in roots if a!=b),'Overlapping derivation roots')
    p.require(all(not x.is_relative_to(y) for x in (calibration,archive,receipt,lockpath) for y in (code,source,tool)),'Derivation path overlap')
    p.require(len({archive,calibration,receipt,lockpath,admission_path})==5,'Colliding derivation files')
    bindings={str(admission_path):p.digest(admission_path),str(archive):r.ARCHIVE_SHA,str(calibration):CALIBRATION}
    for name,h in admission['files'].items():r.checked(root/name,h,1<<20);bindings[str(root/name)]=h
    def recheck():
        for name,h in bindings.items():r.checked(name,h,512<<20)
        r.inventory(code,CODE,1<<20);r.inventory(source,r.SOURCE_FILES,16<<20)
    recheck()
    spec=importlib.util.spec_from_file_location('reviewed_official_extractor',root/'prepare_official_tool.py');module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
    # The inventory cannot be supplied by a caller: create it only by extracting
    # the exact verified official archive with the exact reviewed helper.
    extracted=module.prepare(archive,tool)
    lock={'schema':r.SCHEMA,'reviewed_for_execution':False,'source_commit':commit,'archive_url':r.ARCHIVE_URL,'archive_sha256':r.ARCHIVE_SHA,'runner_sha256':admission['files']['run_authoring.py'],'owned_process_sha256':admission['files']['owned_process.py'],'tool_files':extracted['tool_files'],'code_files':CODE,'source_files':r.SOURCE_FILES,'calibration_sha256':CALIBRATION,'extraction_receipt_sha256':None,'extraction_helper_sha256':admission['files']['prepare_official_tool.py']}
    r.validate_extraction_receipt(extracted,lock)
    # Preserve false/unaccepted extraction evidence if subsequent admission fails.
    with receipt.open('x') as stream:stream.write(json.dumps(extracted,indent=2)+'\n')
    empty_sha=r.hashlib.sha256(b'').hexdigest()
    empty_names=sorted(name for name,h in extracted['tool_files'].items() if h==empty_sha)
    print('OFFICIAL_TOOL_EMPTY_MEMBERS '+json.dumps({'count':len(empty_names),'paths':empty_names[:128],'truncated':len(empty_names)>128}),flush=True)
    r.tool_inventory(tool,lock['tool_files']);recheck()
    lock['extraction_receipt_sha256']=p.digest(receipt)
    # This transition is permitted only by the already-reviewed exact derivation
    # admission after extraction and every resulting binding has been verified.
    lock['reviewed_for_execution']=True;r.validate_lock(lock);recheck()
    with lockpath.open('x') as stream:stream.write(json.dumps(lock,indent=2)+'\n')
    return lock

if __name__=='__main__':
    parser=argparse.ArgumentParser(allow_abbrev=False)
    for name in ('admission','archive','code-root','input-root','calibration','tool-root','extraction-receipt','lock'):parser.add_argument('--'+name,required=True,type=Path)
    derive(parser.parse_args())

"""Source-only preparation; always disabled. No engine/download/runtime mode."""
from pathlib import Path
import argparse,json,os,shutil,zipfile
import diagnostic_policy as d

ROOT=d.ROOT
ENGINE_SHA='f64d4ed19fc9df9440321653fcc80df8c6e365ba7b6de0a29e2cfa9fa71bfeb3'
TEMPLATE_SHA='1446f79dc12f60ce5d244c39fb6628ec298337ca5c4f91a16491feea72aa1bc9'
OUTPUT_FILES=sorted(['index.html','index.js','index.wasm','index.pck','index.png','index.icon.png','index.apple-touch-icon.png','index.audio.worklet.js','index.audio.position.worklet.js'])
admitted=d.admitted
tree=d.tree

def dump(path,value):path.write_text(json.dumps(value,indent=2,sort_keys=True)+'\n')

def prepare(side,work):
    base=d.baseline(side);d.need(base['source_directory']=='game','Exact source directory required');project=ROOT/'game';work=Path(work).absolute()
    d.need(not any(p.is_symlink() for p in [work,*work.parents]),'Symlink work path')
    d.need(work.parent==ROOT/'prepared' and not work.exists(),'Fresh isolated prepared directory required')
    d.verify_product(project,base)
    overlay={'diagnostic/'+p.name:d.sha(p) for p in (ROOT/'overlay').iterdir() if p.is_file()}
    d.need(overlay==d.configuration()['overlay_files_sha256'] and set(overlay)==d.NAMES,'Exact two observer inputs required')
    work.mkdir();dest=work/'project';shutil.copytree(project,dest)
    for name in sorted(d.NAMES):
        target=dest/name;target.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(ROOT/'overlay'/Path(name).name,target)
    (dest/'project.godot').write_bytes(d.override(base['original_project_text']))
    files=d.tree(dest);d.verify(side,files,overlay)
    archive=work/'source.zip'
    with zipfile.ZipFile(archive,'x',compression=zipfile.ZIP_STORED) as z:
        for name in sorted(files):
            info=zipfile.ZipInfo(name,date_time=(2026,1,1,0,0,0));info.create_system=3;info.external_attr=0o100644<<16
            with (dest/name).open('rb') as source,z.open(info,'w') as target:shutil.copyfileobj(source,target,1024*1024)
    descriptor={'inputs':len(base['runtime']['source_sha256']),'sha256':d.canonical(base['runtime'])}
    # Structural descriptor only. No suite execution is included in this task.
    suite='tests/map80_contract.gd';report='OUTPUT/not-invoked.json';suite_sha=files[suite]
    bound={k:d.sha(p) for k,p in d.binding_inputs(side).items()}
    manifest=dict(candidate=base['build'],engine_expected=base['runtime']['engine'],execution_enabled=False,
        files=[dict(file=n,size=(dest/n).stat().st_size,sha256=h) for n,h in sorted(files.items())],
        runtime_manifest=descriptor,public_runtime_descriptor=base['runtime'],
        diagnostic_binding=dict(side=side,bound_files_sha256=bound,overlay_sha256=overlay),
        suites=[dict(name='unused_map_descriptor',script=suite,script_sha256=suite_sha,
            argv=['GODOT','--headless','--path','PROJECT','--script','res://'+suite,'--',report],report=report,
            report_contract=dict(format='JSON object',must_be_new_file_from_this_run=True,process_exit_code=0,minimum_rows=1,rows_field='checks',
                row_verdict=dict(key='pass',equals=True,type='boolean'),count_equations=['passed == len(checks)','failed == 0'],
                required_integer_fields=dict(passed=dict(minimum=1),failed=dict(equals=0)),required_external_receipt=dict(candidate_build=base['build'],runtime_manifest_sha256=descriptor['sha256'],suite_sha256=suite_sha,require_process_and_output_hash_binding=True)))])
    dump(work/'import-manifest.json',manifest)
    generated=sorted(n+'.uid' for n in files if n.endswith(('.gd','.gdshader')) and n+'.uid' not in files)
    lock=dict(schema='vc-diagnostic-web-export-v1',reviewed_for_execution=False,execution_approved=False,
        side=side,diagnostic_only=True,artifact_kind='paused-visibility-diagnostic-web',release_artifact_identity_claim=False,
        source_commit=base['source_commit'],game_tree=base['game_tree'],build=base['build'],bound_files_sha256=bound,
        diagnostic_overlay_sha256=overlay,godot_sha256=ENGINE_SHA,web_release_sha256=TEMPLATE_SHA,
        runner_sha256=d.sha(ROOT/'ci/run_export.py'),owned_process_sha256=d.sha(ROOT/'ci/owned_process.py'),
        source_archive_sha256=d.sha(archive),import_manifest_sha256=d.sha(work/'import-manifest.json'),
        import_adapter_sha256=d.sha(ROOT/'ci/guarded_manifest_ci.py'),project_files=files,
        allowed_generated_uid_files=generated,output_files=OUTPUT_FILES,source_policy_extension_applied=False)
    if os.environ.get('DIAGNOSTIC_EXECUTION_APPROVED')=='true':
        d.admitted(side);lock.update(reviewed_for_execution=True,execution_approved=True,source_policy_extension_applied=True)
    dump(work/'export-lock.json',lock)
    dump(work/'source-policy-lock.json',dict(side=side,diagnostic_only=True,release_artifact_identity_claim=False,
        execution_approved=False,product_source_commit=base['source_commit'],product_game_tree=base['game_tree'],product_build=base['build'],
        original_runtime_inputs=descriptor['inputs'],original_source_files=len(base['project_files']),diagnostic_source_files=len(files),
        original_generated_uid_names=len(base['expected_generated_uid_names']),diagnostic_generated_uid_names=len(generated),
        overlay_sha256=overlay,project_override_sha256=files['project.godot'],bound_files_sha256=bound))
    (work/'pins.env').write_text('ARCHIVE_SHA='+lock['source_archive_sha256']+'\nMANIFEST_SHA='+lock['import_manifest_sha256']+'\n')
    return lock

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--side',choices=['baseline','candidate'],required=True);parser.add_argument('--work',type=Path,required=True)
    args=parser.parse_args();prepare(args.side,args.work);print('Separate disabled diagnostic source prepared; no runtime executed.')

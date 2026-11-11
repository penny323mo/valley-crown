"""Prepare separate diagnostic files/locks. Pure prepare is allowed locally; engine is gated."""
from pathlib import Path
import argparse,hashlib,json,os,shutil,zipfile
import diagnostic_policy as d
ROOT=Path(__file__).resolve().parents[1]
ENGINE_SHA='f64d4ed19fc9df9440321653fcc80df8c6e365ba7b6de0a29e2cfa9fa71bfeb3'
TEMPLATE_SHA='1446f79dc12f60ce5d244c39fb6628ec298337ca5c4f91a16491feea72aa1bc9'
def dump(path,value):path.write_text(json.dumps(value,indent=2,sort_keys=True)+'\n')
def canonical(value):return hashlib.sha256(json.dumps(value,sort_keys=True,separators=(',',':')).encode()).hexdigest()
def admitted():
    d.need(os.environ.get('GITHUB_ACTIONS')=='true' and os.environ.get('RUNNER_ENVIRONMENT')=='github-hosted','Fresh hosted runner required')
    d.need(os.environ.get('GITHUB_REPOSITORY')=='penny323mo/valley-crown' and os.environ.get('GITHUB_REF')==d.BRANCH and os.environ.get('GITHUB_RUN_ATTEMPT')=='1','Wrong repository/branch/attempt')
    d.need(os.environ.get('DIAGNOSTIC_EXECUTION_APPROVED')=='true','Diagnostic execution review remains pending')
def tree(root):
    d.need(root.is_dir() and not any(p.is_symlink() for p in [root,*root.parents]),'Nonregular root')
    result={}
    for p in sorted(root.rglob('*')):
        d.need(not p.is_symlink(),'Symlink')
        if p.is_dir():continue
        d.need(p.is_file(),'Special file');result[p.relative_to(root).as_posix()]=d.sha(p)
    return result
def overlay_paths(root):
    files=tree(root)
    if set(files)==d.NAMES:return {name:root/name for name in d.NAMES}
    names={Path(name).name for name in d.NAMES}
    d.need(names <= set(files) <= names | {'OVERLAY.json'},'Overlay must contain only driver, scene, and optional metadata')
    return {name:root/Path(name).name for name in d.NAMES}
def overlay_inventory(root):return {name:d.sha(path) for name,path in overlay_paths(root).items()}
def prepare(project,overlay,work):
    base=d.baseline();project=project.resolve();overlay=overlay.resolve();work=work.absolute()
    d.need(not any(p.is_symlink() for p in [work,*work.parents]),'Symlink work path')
    d.need(not work.exists() and all(not work.is_relative_to(p) and not p.is_relative_to(work) for p in [project,overlay]),'Fresh separate work required')
    d.need(tree(project)==base['project_files'],'Immutable product source differs')
    pins=json.loads((ROOT/'overlay-binding.json').read_text())
    d.need(pins.get('bound') is True and pins.get('execution_approved') is False,'Overlay binding incomplete or approval mixed into source data')
    overlay_files=overlay_inventory(overlay);d.need(overlay_files==pins['files'] and set(overlay_files)==d.NAMES,'Overlay bytes differ')
    work.mkdir(parents=True);dest=work/'project';shutil.copytree(project,dest)
    for name in sorted(d.NAMES):
        out=dest/name;out.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(overlay_paths(overlay)[name],out)
    (dest/'project.godot').write_bytes(d.override(base['original_project_text']))
    files=tree(dest);d.verify(files,overlay_files)
    archive=work/'source.zip'
    with zipfile.ZipFile(archive,'x',compression=zipfile.ZIP_STORED) as z:
        for name in sorted(files):
            info=zipfile.ZipInfo(name,date_time=(2026,1,1,0,0,0));info.create_system=3;info.external_attr=0o100644<<16
            with (dest/name).open('rb') as src,z.open(info,'w') as out:shutil.copyfileobj(src,out,1024*1024)
    descriptor={'inputs':140,'sha256':canonical(base['runtime'])}
    # Uninvoked suite descriptor is retained only to satisfy the unchanged import manifest grammar.
    suite='tests/map80_contract.gd';suite_sha=files[suite];report='OUTPUT/not-invoked.json'
    manifest=dict(candidate=base['build'],engine_expected=base['runtime']['engine'],execution_enabled=False,
      files=[dict(file=n,size=(dest/n).stat().st_size,sha256=h) for n,h in sorted(files.items())],
      runtime_manifest=descriptor,public_runtime_descriptor=base['runtime'],
      diagnostic_binding=dict(baseline_sha256=d.BASELINE_SHA,policy_sha256=d.sha(d.__file__),overlay_sha256=overlay_files),
      suites=[dict(name='unused_map_descriptor',script=suite,script_sha256=suite_sha,
        argv=['GODOT','--headless','--path','PROJECT','--script','res://'+suite,'--',report],report=report,
        report_contract=dict(format='JSON object',must_be_new_file_from_this_run=True,process_exit_code=0,minimum_rows=1,rows_field='checks',
        row_verdict=dict(key='pass',equals=True,type='boolean'),count_equations=['passed == len(checks)','failed == 0'],
        required_integer_fields=dict(passed=dict(minimum=1),failed=dict(equals=0)),required_external_receipt=dict(candidate_build=base['build'],runtime_manifest_sha256=descriptor['sha256'],suite_sha256=suite_sha,require_process_and_output_hash_binding=True)))])
    dump(work/'import-manifest.json',manifest)
    generated=sorted(n+'.uid' for n in files if (n.endswith('.gd') or n.endswith('.gdshader')) and n+'.uid' not in files)
    from run_export import ALLOWED_OUTPUTS
    lock=dict(schema='vc-diagnostic-web-export-v1',reviewed_for_execution=False,diagnostic_only=True,
      artifact_kind='rendered-match-diagnostic-web',release_artifact_identity_claim=False,source_commit=base['source_commit'],game_tree=base['game_tree'],build=base['build'],
      baseline_sha256=d.BASELINE_SHA,diagnostic_policy_sha256=d.sha(d.__file__),diagnostic_overlay_sha256=overlay_files,
      godot_sha256=ENGINE_SHA,web_release_sha256=TEMPLATE_SHA,runner_sha256=d.sha(ROOT/'ci/run_export.py'),owned_process_sha256=d.sha(ROOT/'ci/owned_process.py'),
      source_archive_sha256=d.sha(archive),import_manifest_sha256=d.sha(work/'import-manifest.json'),import_adapter_sha256=d.sha(ROOT/'ci/guarded_manifest_ci.py'),
      project_files=files,allowed_generated_uid_files=generated,output_files=sorted(ALLOWED_OUTPUTS))
    # Approval is possible only in the reviewed hosted workflow, never from a local prepare.
    if os.environ.get('DIAGNOSTIC_EXECUTION_APPROVED')=='true':admitted();lock['reviewed_for_execution']=True
    dump(work/'export-lock.json',lock)
    dump(work/'source-policy-lock.json',dict(product_source=base['source_commit'],product_tree=base['game_tree'],baseline_sha256=d.BASELINE_SHA,original_runtime_inputs=140,original_source_files=232,diagnostic_source_files=234,overlay_sha256=overlay_files,project_override_sha256=files['project.godot'],release_artifact_identity_claim=False))
    (work/'pins.env').write_text('ARCHIVE_SHA='+lock['source_archive_sha256']+'\nMANIFEST_SHA='+lock['import_manifest_sha256']+'\n')
    return lock
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('phase',choices=['prepare','engine']);p.add_argument('--work',required=True,type=Path);p.add_argument('--project',type=Path,default=ROOT/'game');p.add_argument('--overlay',type=Path,default=ROOT/'overlay');a=p.parse_args()
    if a.phase=='prepare':
        prepare(a.project,a.overlay,a.work);print('Separate diagnostic source/import/export locks prepared; no engine launch')
    else:
        admitted();import official_download as download
        d.need((a.work/'export-lock.json').is_file(),'Preparation missing')
        download.download(download.ENGINE_URL,a.work/'engine.zip');download.safe_extract(a.work/'engine.zip',{download.ENGINE_NAME:ENGINE_SHA},a.work/'engine',max_total=256*1024*1024,max_member=256*1024*1024)
        (a.work/'engine'/download.ENGINE_NAME).chmod(0o755)

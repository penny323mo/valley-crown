#!/usr/bin/env python3
"""Exact product/controlled-diagnostic preparation; no engine in prepare phase."""
from pathlib import Path
import argparse
import hashlib
import importlib.util
import json
import os
import re
import shutil
import subprocess
import zipfile

ROOT = Path(__file__).resolve().parents[1]
BRANCH = 'refs/heads/main'
SOURCE = '406c000ec1c400cfd3e0097127bb5de00d984b62'
ENGINE = '4.6.3.stable.official.7d41c59c4'
ENGINE_SHA = 'f64d4ed19fc9df9440321653fcc80df8c6e365ba7b6de0a29e2cfa9fa71bfeb3'
TEMPLATE_SHA = '1446f79dc12f60ce5d244c39fb6628ec298337ca5c4f91a16491feea72aa1bc9'
SIDES = {
    'product': {'directory':'game', 'build':'vc-a60fa4203779', 'tree':'706ad359511d9257e68bedb74f3c7d78aacba237', 'files':356, 'runtime':179, 'runner':'run_export.py'},
    'diagnostic': {'directory':'diagnostic-game', 'build':'vc-09c394aef6d8', 'tree':'5d478c5414ba732f41b109515e90d45495406a1b', 'files':258, 'runtime':155, 'runner':'run_export_diagnostic.py'},
}
OUTPUT_FILES = sorted(['index.html','index.js','index.wasm','index.pck','index.png','index.icon.png','index.apple-touch-icon.png','index.audio.worklet.js','index.audio.position.worklet.js'])


def need(value, message):
    if not value: raise ValueError(message)


def sha(path):
    with Path(path).open('rb') as stream: return hashlib.file_digest(stream,'sha256').hexdigest()


def dump(path, value):
    with path.open('x') as stream:
        json.dump(value,stream,indent=2,sort_keys=True);stream.write('\n')


def admitted():
    need(os.environ.get('GITHUB_ACTIONS')=='true' and os.environ.get('RUNNER_ENVIRONMENT')=='github-hosted','Fresh hosted runner required')
    need(os.environ.get('GITHUB_REPOSITORY')=='penny323mo/valley-crown' and os.environ.get('GITHUB_REF')==BRANCH and os.environ.get('GITHUB_RUN_ATTEMPT')=='1','Wrong repository/branch/attempt')
    need(os.environ.get('BUILDING_RUNTIME_EXECUTION_APPROVED')=='true','Second-stage execution not reviewed')
    need('VERSION_ID="24.04"' in Path('/etc/os-release').read_text(),'Ubuntu24.04 required')
    need(re.fullmatch('[a-f0-9]{40}',SOURCE),'Unbound product source commit')
    need(os.environ.get('BUILDING_RUNTIME_SOURCE_COMMIT')==SOURCE,'Workflow source pin differs')


def git(*args):
    return subprocess.check_output(['git','-C',str(ROOT),*args],text=True,timeout=8).strip()


def prepare(side, work):
    identity=SIDES[side];project=ROOT/identity['directory'];work=work.absolute()
    need(git('rev-parse','HEAD:'+identity['directory'])==identity['tree'],'Public source tree differs')
    need(git('rev-parse',SOURCE+':'+identity['directory'])==identity['tree'],'Pinned source commit tree differs')
    need(not work.exists() and not any(p.is_symlink() for p in [work,*work.parents]),'Fresh real work root required')
    need(not work.is_relative_to(ROOT) and not ROOT.is_relative_to(work),'Source/work overlap')
    public={}
    for line in git('ls-tree','-r','HEAD:'+identity['directory']).splitlines():
        meta,name=line.split('\t',1);mode,kind,digest=meta.split()
        need(mode=='100644' and kind=='blob','Nonregular public source');public[name]=digest
    files={};actual={}
    for path in sorted(project.rglob('*')):
        need(not path.is_symlink(),'Source symlink')
        if path.is_dir():continue
        need(path.is_file(),'Special source');name=path.relative_to(project).as_posix();data=path.read_bytes()
        actual[name]=hashlib.sha1(b'blob '+str(len(data)).encode()+b'\0'+data).hexdigest()
        files[name]={'file':name,'size':len(data),'sha256':hashlib.sha256(data).hexdigest()}
    need(actual==public and len(actual)==identity['files'],'Exact public source bytes/count differ')
    spec=importlib.util.spec_from_file_location('bound_runtime',project/'tools/runtime_manifest.py');module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
    module.verify_mature_export_exclusions(project);paths=module.runtime_paths(project)
    need(len(paths)==identity['runtime'],'Runtime count differs')
    runtime={'build':identity['build'],'engine':ENGINE,'source_sha256':{p.relative_to(project).as_posix():sha(p) for p in paths}}
    digest=hashlib.sha256()
    for name in sorted(runtime['source_sha256']):
        data=(project/name).read_bytes()
        if name=='scripts/rules.gd':
            need(re.findall(rb'const BUILD_ID = "([^"]*)"',data)==[identity['build'].encode()],'Rules identity differs')
            data=re.sub(rb'const BUILD_ID = "[^"]*"',b'const BUILD_ID = "normalized"',data)
        digest.update(name.encode());digest.update(b'\0');digest.update(data)
    need('vc-'+digest.hexdigest()[:12]==identity['build'],'Derived runtime identity differs')
    work.mkdir(mode=0o700);dest=work/'project';shutil.copytree(project,dest)
    archive=work/'source.zip'
    with zipfile.ZipFile(archive,'x',compression=zipfile.ZIP_STORED) as z:
        for name in sorted(files):
            info=zipfile.ZipInfo(name,date_time=(2026,1,1,0,0,0));info.create_system=3;info.external_attr=0o100644<<16
            with (dest/name).open('rb') as source,z.open(info,'w') as target:shutil.copyfileobj(source,target,1024*1024)
    runtime_sha=hashlib.sha256(json.dumps(runtime,sort_keys=True,separators=(',',':')).encode()).hexdigest()
    suite='tests/map80_contract.gd';suite_sha=files[suite]['sha256'];report='OUTPUT/not-invoked.json'
    contract=dict(format='JSON object',must_be_new_file_from_this_run=True,process_exit_code=0,minimum_rows=1,rows_field='checks',row_verdict=dict(key='pass',equals=True,type='boolean'),count_equations=['passed == len(checks)','failed == 0'],required_integer_fields=dict(passed=dict(minimum=1),failed=dict(equals=0)),required_external_receipt=dict(candidate_build=identity['build'],runtime_manifest_sha256=runtime_sha,suite_sha256=suite_sha,require_process_and_output_hash_binding=True))
    manifest=dict(candidate=identity['build'],engine_expected=ENGINE,execution_enabled=False,files=list(files.values()),runtime_manifest=dict(inputs=len(paths),sha256=runtime_sha),public_runtime_descriptor=runtime,suites=[dict(name='unused_map_descriptor',script=suite,script_sha256=suite_sha,argv=['GODOT','--headless','--path','PROJECT','--script','res://'+suite,'--',report],report=report,report_contract=contract)])
    dump(work/'import-manifest.json',manifest)
    project_files={n:v['sha256'] for n,v in files.items()}
    generated=sorted(n+'.uid' for n in files if n.endswith('.gd') and n+'.uid' not in files)
    for shader in ('assets/mature/shaders/building_damage_soot.gdshader','assets/mature/menu/menu_backdrop.gdshader'):
        if shader in files and shader+'.uid' not in files:generated.append(shader+'.uid')
    lock=dict(schema='vc-web-export-v1',reviewed_for_execution=True,source_commit=SOURCE,game_tree=identity['tree'],build=identity['build'],godot_sha256=ENGINE_SHA,web_release_sha256=TEMPLATE_SHA,runner_sha256=sha(ROOT/'ci'/identity['runner']),owned_process_sha256=sha(ROOT/'ci/owned_process.py'),source_archive_sha256=sha(archive),import_manifest_sha256=sha(work/'import-manifest.json'),import_adapter_sha256=sha(ROOT/'ci/guarded_manifest_ci.py'),project_files=project_files,allowed_generated_uid_files=sorted(generated),output_files=OUTPUT_FILES,diagnostic_only=side=='diagnostic',artifact_kind='controlled-building-visual-review' if side=='diagnostic' else 'tested-building-product-candidate')
    if side=='product':
        lock['startup_identity_sha256']=sha(ROOT/'ci/startup_identity.py')
        lock.update(contracts_reviewed_for_execution=True,contracts_stop_reviewed_for_execution=True,contracts_consolidated_reviewed_for_execution=True,military_reviewed_for_execution=True,faction_reviewed_for_execution=True,building_reviewed_for_execution=True)
        for prefix,roles in {
            'contracts':{'runner':'run_contracts.py','supervisor':'run_logic.py','validator':'validate_contracts.py','names':'check_contract.json'},
            'military':{'runner':'run_military.py','supervisor':'run_logic.py','validator':'validate_military.py','names':'military_contract.json'},
            'faction':{'runner':'run_faction.py','supervisor':'run_logic.py','validator':'validate_faction.py'},
            'building':{'runner':'run_building_contracts.py','supervisor':'run_logic.py','validator':'validate_building_contracts.py'},
        }.items():
            for role,name in roles.items():lock[prefix+'_'+role+'_sha256']=sha(ROOT/'ci'/name)
        lock['faction_harness_sha256']=sha(project/'tests/faction_publish_contract.gd')
        lock['building_harness_sha256']={name:sha(ROOT/'ci/building-fixtures'/(name+'.gd') if name.startswith('building_damage_') else project/'tests'/(name+'.gd')) for name in ('advanced_building_visuals','advanced_building_observation','construction_visual','building_damage_component','building_damage_projection','map80_sparse_memory')}
    if side=='product':
        lock['latest_runner_sha256']=sha(ROOT/'ci/run_latest_contracts.py')
        lock['latest_validator_sha256']=sha(ROOT/'ci/validate_latest_contracts.py')
        lock['latest_harness_sha256']={n:sha(project/'tests'/(n+'.gd')) for n in ('material_contract','continuous_training_contract','resource_visual_contract','compact_click_contract','compact_move_runtime','hold_box_contract','hold_box_phone','contextual_routed_touch','wide_click_contract','skirmish_policy_contract','resource_polish_contract','normal_probe','army_composition_contract','army_recruitment_integration','army_formation_contract','army_formation_integration','home_defense_contract','home_defense_integration','military_technology_contract','military_tech_worker_recovery_contract','military_tech_lifecycle_contract','worker_safety_contract','worker_safety_cargo_contract','control_point_contract','control_point_menu_contract','rest_recovery_contract','field_manual_contract','scout_frontier_contract','resolved_attack_goal_contract','placement_sight_contract','idle_army_contract','workforce_contract','production_overview_contract','repair_dispatch_contract','construction_dispatch_contract','repair_layout_contract','unit_type_selection_contract','retry_gather_contract','context_manual_contract','training_batch_contract','desktop_stop_scroll_contract')}
    dump(work/'export-lock.json',lock)
    (work/'pins.env').write_text('ARCHIVE_SHA='+lock['source_archive_sha256']+'\nMANIFEST_SHA='+lock['import_manifest_sha256']+'\n')
    dump(work/'source-attestation.json',dict(side=side,build=identity['build'],game_tree=identity['tree'],source_commit=SOURCE,workflow_commit=git('rev-parse','HEAD'),source_files=len(files),runtime_inputs=len(paths),source_archive_sha256=sha(archive),import_manifest_sha256=sha(work/'import-manifest.json'),diagnostic_only=side=='diagnostic',engine_executed=False))
    return {'side':side,'build':identity['build'],'game_tree':identity['tree'],'source_files':len(files),'engine_executed':False}


def main():
    parser=argparse.ArgumentParser();parser.add_argument('phase',choices=['prepare','engine']);parser.add_argument('--side',choices=SIDES,default='product');parser.add_argument('--work',type=Path,required=True);args=parser.parse_args();admitted()
    if args.phase=='prepare':print(json.dumps(prepare(args.side,args.work)))
    else:
        import official_download as download
        need(args.side=='product' and (args.work/'export-lock.json').is_file(),'Product source preparation required')
        download.download(download.ENGINE_URL,args.work/'engine.zip');download.safe_extract(args.work/'engine.zip',{download.ENGINE_NAME:ENGINE_SHA},args.work/'engine',max_total=256*1024*1024,max_member=256*1024*1024)
        (args.work/'engine'/download.ENGINE_NAME).chmod(0o755)
        print('Pinned official engine prepared without launch')


if __name__=='__main__':main()

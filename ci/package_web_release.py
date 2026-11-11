#!/usr/bin/env python3
"""Package separately identified, independently guarded candidates. Never deploy."""
import argparse
import json
import os
from pathlib import Path
import shutil
import prepare_web_release as prep
import owned_process as p
import validate_building_contracts as b

NOTICES=['GODOT-LICENSES.txt','THIRD_PARTY_NOTICES.txt','assets/fonts/NOTO-LICENSE.txt','assets/fonts/DEJAVU-LICENSE.txt','assets/fonts/MENU-TITLE-LICENSE.txt']+[
 'art/action_characters/licenses/'+n for n in ['quaternius-outfits.txt','kaykit-animations.txt','quaternius-ual.txt','quaternius-ual2.txt','quaternius-base.txt']]+['art/advanced_buildings/upstream/QUATERNIUS-LICENSE.txt']
RELEASE=['construction_status','construction_status_hud','mobile_stop_control_contract','mobile_stop_control_phone','stance_target_cancel_phone','contextual_touch_contract','contextual_touch_phone','main_menu_flow_contract']
MILITARY=('military_progression_contract','military_runtime_edges')
need=prep.need
sha=prep.sha

def read(path):
    p.regular(path);need(0<path.stat().st_size<=16*1024*1024,'Empty/oversize evidence')
    return b.parse_json(path.read_text())

def identity(receipt,lock,post=True):
    need(receipt.get('passed') is True and all(receipt.get(k)==lock[k] for k in ('build','source_commit','game_tree')),'Failed or wrong receipt identity')
    if post:need(receipt.get('post_run_binding_matches') is True,'Source post-binding failed')
    need(not receipt.get('error') and not receipt.get('binding_error'),'Receipt carries failure')
    bindings=receipt.get('input_sha256')
    need(type(bindings) is dict and bindings,'Missing input bindings')
    for name,digest in bindings.items():
        path=Path(name);need(not any(x.is_symlink() for x in [path,*path.parents]),'Bound input symlink')
        need(sha(p.regular(path))==digest,'Bound input drift')

def monitor(stage,result,timeout):
    need(result.get('passed') is True and result.get('cleanup_complete') is True and result.get('test_dependencies') is False and result.get('unexpected_descendants')==[],'Monitor incomplete/mocked')
    need(type(result.get('exit')) is int and result['exit']==0,'Nonzero/unknown exit')
    limits=dict(b.LIMITS,timeout_seconds=timeout)
    need(result.get('limits')==limits and result.get('samples') and type(result.get('pid')) is int,'Wrong monitor limits/evidence')
    need(not result.get('error') and not result.get('final_error'),'Monitor failure')
    stored=dict(result)
    if timeout==300:stored.pop('output_sha256',None)
    need(read(stage/'receipt.json')==stored,'Monitor receipt differs')
    need(sha(p.regular(stage/'godot.log'))==result.get('log_sha256'),'Monitor log drift')

def validate_suites(work,lock):
    import validate_contracts as c
    import validate_military as m
    import run_faction as f
    b.validate_identity(lock)
    for directory,filename,suites in [('building-contracts','building-contracts-receipt.json',b.SUITES),('construction-contracts','construction-contracts-receipt.json',RELEASE),('military-contracts','military-contracts-receipt.json',MILITARY)]:
        root=work/directory;receipt=read(root/filename);identity(receipt,lock)
        need([row.get('suite') for row in receipt.get('suites',[])]==list(suites),'Missing/duplicate/reordered suites')
        for row in receipt['suites']:
            suite=row['suite'];stage=root/suite;monitor(stage,row['monitor'],120)
            need(sha(stage/'receipt.json')==row.get('receipt_sha256') and sha(stage/'godot.log')==row.get('log_sha256'),'Suite evidence drift')
            if directory=='building-contracts':
                parsed=b.read_report(stage,suite);b.validate_monitor(row['monitor']);count=b.COUNTS[suite]
                if suite=='construction_visual':need(sha(stage/b.REPORT)==row.get('report_sha256'),'Construction report drift')
            else:
                validator=c if directory=='construction-contracts' else m
                contract=validator.parse_json((Path(__file__).with_name('check_contract.json' if validator is c else 'military_contract.json')).read_text())
                if validator is c and suite==c.FILE_SUITE:
                    parsed=c.read_file_report(stage,suite,lock,contract)
                    need(sha(stage/c.FILE_REPORT)==row.get('report_sha256'),'Release file report drift')
                else:parsed=validator.read_log(stage/'godot.log',suite,lock,contract)
                count=len(parsed if type(parsed) is list else parsed['checks'])
            need(parsed==row.get('report') and row.get('assertions_executed')==count,'Suite report/count differs')
        need(receipt.get('assertions_executed')==sum(row['assertions_executed'] for row in receipt['suites']),'Suite total differs')
    root=work/'faction-contracts';receipt=read(root/'faction-publication-receipt.json');identity(receipt,lock)
    stage=root/'faction-publication';monitor(stage,receipt['monitor'],120)
    need(sha(stage/'receipt.json')==receipt.get('monitor_receipt_sha256') and sha(stage/'godot.log')==receipt.get('log_sha256') and sha(stage/f.REPORT)==receipt.get('report_sha256'),'Faction evidence drift')
    report=f.read_report(stage/f.REPORT,lock)
    need(f.v.validate(report,lock['build'])==receipt.get('validation'),'Faction validation differs')

def package(work,side):
    work=work.absolute();need(not any(x.is_symlink() for x in [work,*work.parents]),'Work symlink')
    lock=read(work/'export-lock.json');expected=prep.SIDES[side]
    need((lock.get('build'),lock.get('game_tree'),lock.get('source_commit'))==(expected['build'],expected['tree'],prep.SOURCE),'Wrong side identity')
    need(lock.get('diagnostic_only') is (side=='diagnostic'),'Wrong diagnostic classification')
    if side=='product':
        import run_export as runner
        validate_suites(work,lock)
    else:
        import run_export_diagnostic as runner
        need(lock.get('artifact_kind')=='controlled-building-visual-review','Wrong diagnostic artifact scope')
    runner.validate_lock(lock)
    source,uids=p.source_inventory(work/'project',lock);cache=p.cache_inputs(work/'project')
    need(cache,'Missing real import cache')
    runner.validate_import(work/'project',lock,work/'private/import/import-complete.json',cache,uids)
    receipt=read(work/'exports/web-export-receipt.json');identity(receipt,lock,post=False)
    exports=receipt.get('exports');need(type(exports) is list and len(exports)==2,'Two real exports required')
    need(exports[0].get('output_sha256')==exports[1].get('output_sha256') and sorted(exports[0]['output_sha256'])==prep.OUTPUT_FILES,'Wrong/repeat-mismatched nine export files')
    for i,result in enumerate(exports,1):
        stage=work/'exports'/('export-'+str(i));monitor(stage,result,300)
        need(result.get('export_completed') is True,'Export did not complete')
        need(p.tree(stage/'web')==result['output_sha256'],'Export files drift')
    for name in NOTICES:
        path=work/'project'/name
        need(sha(p.regular(path))==lock['project_files'].get(name),'Exact authorized notice missing/changed')
    candidate=work/'candidate';need(not candidate.exists(),'Candidate already exists')
    candidate.mkdir()
    for i,label in [(1,'clean-a'),(2,'clean-b')]:
        shutil.copytree(work/'exports'/('export-'+str(i))/'web',candidate/'artifacts'/label)
    for name in NOTICES:
        dest=candidate/'notices'/name;dest.parent.mkdir(parents=True,exist_ok=True)
        shutil.copyfile(work/'project'/name,dest)
    scope=('Controlled component building-art review only. Not match, observation, gameplay or performance evidence.' if side=='diagnostic' else 'Six building, eight release, two military and one faction suite passed; two byte-identical Web exports. Browser and visual acceptance remain untested.')
    manifest={'build':lock['build'],'game_tree':lock['game_tree'],'source_commit':lock['source_commit'],'side':side,'diagnostic_only':side=='diagnostic','scope':scope,'not_yet_deployed':True,'export_run':'https://github.com/penny323mo/valley-crown/actions/runs/'+os.environ['GITHUB_RUN_ID'],'export_files_sha256':exports[0]['output_sha256'],'files_sha256':p.tree(candidate),'export_receipt_sha256':sha(work/'exports/web-export-receipt.json')}
    if side=='diagnostic':
        diagnostic={'schema':'vc-building-art-web-artifact-v1','diagnostic_only':True,'release_artifact_identity_claim':False,
          'diagnostic_build':lock['build'],'diagnostic_source_commit':lock['source_commit'],'diagnostic_game_tree':lock['game_tree'],
          'product_build':prep.SIDES['product']['build'],'product_game_tree':prep.SIDES['product']['tree'],'side':'diagnostic-component',
          'diagnostic_export_run_id':os.environ['GITHUB_RUN_ID'],'diagnostic_export_run_attempt':int(os.environ['GITHUB_RUN_ATTEMPT']),
          'diagnostic_export_commit':os.environ['GITHUB_SHA'],'diagnostic_overlay_sha256':{n:lock['project_files'][n] for n in ('scripts/building_art_review.gd','main.tscn')},
          'source_archive_sha256':lock['source_archive_sha256'],'import_manifest_sha256':lock['import_manifest_sha256'],
          'export_lock_sha256':sha(work/'export-lock.json'),'guard_receipt_sha256':sha(work/'exports/web-export-receipt.json'),
          'files_sha256':exports[0]['output_sha256'],'scope':scope}
        (candidate/'diagnostic-export-manifest.json').write_text(json.dumps(diagnostic,indent=2)+'\n')
    (candidate/'candidate-metadata.json').write_text(json.dumps(manifest,indent=2)+'\n')
    (work/'release-summary.json').write_text(json.dumps(manifest,indent=2)+'\n')
    need(p.source_inventory(work/'project',lock,uids)[0]==source and p.cache_inputs(work/'project')==cache,'Post-package source/import drift')
    identity(receipt,lock,post=False)
    return manifest

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--work',type=Path,required=True);parser.add_argument('--side',choices=['product','diagnostic'],required=True);args=parser.parse_args()
    prep.admitted();print(json.dumps(package(args.work,args.side)))

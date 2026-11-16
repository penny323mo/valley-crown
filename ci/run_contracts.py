#!/usr/bin/env python3
"""PREPARED ONLY: consolidated exact suites under unchanged 120-second logic monitor.

Requires final-source export lock and construction/Stop/consolidated review flags.
Run only after one genuine guarded import on a fresh hosted Ubuntu 24.04 VM.
"""
import argparse
import json
import os
from pathlib import Path
import run_export as r
import run_logic as logic
import validate_contracts as v
p=r.p
SUITES=('construction_status','construction_status_hud','mobile_stop_control_contract',
        'mobile_stop_control_phone','stance_target_cancel_phone',
        'contextual_touch_contract','contextual_touch_phone','main_menu_flow_contract')
LOGIC_SHA='2800e75273335ce8ffefccb1db6128b54f09850b50dc243cf73e7065ff107607'

def argv(godot, project, suite, stage=None):
    p.require(suite in SUITES, 'Unsupported suite')
    command=[str(godot),'--headless','--path',str(project),'--audio-driver','Dummy',
            '--resolution','390x844','--fixed-fps','30','--script','res://'+v.FIXTURES[suite][0]]
    if suite==v.FILE_SUITE:
        p.require(type(stage) is Path or isinstance(stage,Path), 'Fixed output directory required')
        command+=['--',str(stage/v.FILE_REPORT)]
    else: p.require(stage is None, 'Unexpected output argument')
    return command

def run(args):
    lockpath=r.path_checked(args.lock); lock=json.loads(p.regular(lockpath).read_text())
    p.require(lock.get('contracts_reviewed_for_execution') is True, 'Construction adapter not reviewed')
    p.require(lock.get('contracts_stop_reviewed_for_execution') is True, 'Stop adapter not reviewed')
    p.require(lock.get('contracts_consolidated_reviewed_for_execution') is True, 'Consolidated adapter not reviewed')
    r.validate_lock(lock)
    p.require(lock.get('contracts_supervisor_sha256')==LOGIC_SHA, 'Unreviewed logic supervisor')
    p.require(os.environ.get('GITHUB_ACTIONS')=='true' and os.environ.get('RUNNER_ENVIRONMENT')=='github-hosted', 'Hosted VM required')
    p.require('VERSION_ID="24.04"' in Path('/etc/os-release').read_text(), 'Ubuntu 24.04 required')
    project,output,private=map(r.path_checked,(args.project,args.output,args.private))
    paths=[project,output,private]
    p.require(project.is_dir() and not output.exists() and not private.exists(), 'Fresh output/private required')
    p.require(len(set(paths))==3 and all(not a.is_relative_to(b) for a in paths for b in paths if a!=b), 'Overlapping paths')
    godot=r.checked(args.godot,r.ENGINE_SHA)
    required={'runner_sha256':r.__file__, 'owned_process_sha256':p.__file__,
              'contracts_runner_sha256':__file__, 'contracts_supervisor_sha256':logic.__file__, 'contracts_validator_sha256':v.__file__,
              'contracts_names_sha256':Path(__file__).with_name('check_contract.json')}
    bound=[lockpath,godot]
    for key,path in required.items(): bound.append(r.checked(path,lock[key]))
    for suite,(name,hashvalue) in v.FIXTURES.items():
        p.require(lock['project_files'].get(name)==hashvalue, 'Unreviewed contract suite bytes')
    p.require(lock['project_files']['scripts/construction_status.gd']==v.STATUS_SHA, 'Unreviewed status logic')
    p.require(lock['project_files']['scripts/game.gd']==v.GAME_SHA, 'Unreviewed Stop logic')
    p.require(lock['project_files'].get('scripts/main_menu.gd')==v.MENU_SHA, 'Unreviewed menu logic')
    contract=v.parse_json(Path(required['contracts_names_sha256']).read_text())
    source,uids=p.source_inventory(project,lock); cache=p.cache_inputs(project)
    p.require(cache,'Guarded import required')
    marker=r.path_checked(args.import_marker);bound.append(marker)
    bound+=r.validate_import(project,lock,marker,cache,uids)
    bindings={str(x):p.digest(x) for x in bound}
    output.mkdir(parents=True);private.mkdir(parents=True,mode=0o700)
    receipt={'passed':False,'build':lock['build'],'source_commit':lock['source_commit'],'game_tree':lock['game_tree'],
             'scope':'Value-only, synthetic control fixtures and controlled native HUD/input; no browser pixels, natural-play or physical-device proof',
             'input_sha256':bindings,'generated_uid_sha256':uids,'suites':[]}
    def unchanged():
        p.require(p.source_inventory(project,lock,uids)[0]==source and p.cache_inputs(project)==cache,'Source/UID/import cache drift')
        p.require(all(p.digest(path)==sha for path,sha in bindings.items()),'Bound input drift')
    try:
        for suite in SUITES:
            unchanged()
            work=private/suite;work.mkdir(mode=0o700)
            env={'PATH':'/usr/bin:/bin','LANG':'C.UTF-8','TZ':'UTC','GODOT_SILENCE_ROOT_WARNING':'1','OMP_NUM_THREADS':'1'}
            for key,name in [('HOME','home'),('TMPDIR','tmp'),('XDG_DATA_HOME','data'),('XDG_CONFIG_HOME','config'),('XDG_CACHE_HOME','cache')]:
                path=work/name;path.mkdir(mode=0o700);env[key]=str(path)
            stage=output/suite;stage.mkdir()
            result=logic.supervise(argv(godot,project,suite,stage if suite==v.FILE_SUITE else None),env,stage,p.metrics())
            row={'suite':suite,'monitor':result};receipt['suites'].append(row)
            p.require(result['passed'] and result['cleanup_complete'] and not result['test_dependencies'] and not result['unexpected_descendants'], 'Failed/unknown suite; no next process')
            unchanged()
            expected={'receipt.json','godot.log'} | ({v.FILE_REPORT} if suite==v.FILE_SUITE else set())
            p.require(set(p.tree(stage))==expected,'Unexpected suite files')
            if suite==v.FILE_SUITE:
                row['report']=v.read_file_report(stage,suite,lock,contract)
                row['report_sha256']=p.digest(stage/v.FILE_REPORT)
            else: row['report']=v.read_log(stage/'godot.log',suite,lock,contract)
            row['assertions_executed']=len(row['report'] if type(row['report']) is list else row['report']['checks'])
            row['receipt_sha256']=p.digest(stage/'receipt.json');row['log_sha256']=p.digest(stage/'godot.log')
            p.require(row['log_sha256']==result['log_sha256'],'Log drift')
        receipt['assertions_executed']=sum(row['assertions_executed'] for row in receipt['suites'])
        receipt['passed']=True
    except BaseException as exc:
        receipt['error']={'type':type(exc).__name__,'message':p.safe_diagnostic_text(exc)}
    finally:
        try:
            unchanged()
            receipt['post_run_binding_matches']=True
        except BaseException as exc:
            receipt['passed']=False
            receipt['post_run_binding_matches']=False
            receipt['binding_error']={'type':type(exc).__name__,'message':p.safe_diagnostic_text(exc)}
        (output/'construction-contracts-receipt.json').write_text(json.dumps(receipt,indent=2)+'\n')
        print(json.dumps({'passed':receipt['passed'],'scope':receipt['scope'],'error':receipt.get('error')}))
    return 0 if receipt['passed'] else 1

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    for key in ('lock','project','output','private','godot','import-marker'):parser.add_argument('--'+key,type=Path,required=True)
    raise SystemExit(run(parser.parse_args()))

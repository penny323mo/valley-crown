#!/usr/bin/env python3
"""PREPARED ONLY: exact two construction suites under unchanged 120-second logic monitor.

Requires separately reviewed export lock AND contracts_reviewed_for_execution.
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
SUITES=('construction_status','construction_status_hud')
LOGIC_SHA='04b8be583b5db6a4bb210adb55af4dde80e51f260579767daff41ee769b7bef1'

def argv(godot, project, suite):
    p.require(suite in SUITES, 'Unsupported suite')
    return [str(godot),'--headless','--path',str(project),'--audio-driver','Dummy',
            '--resolution','390x844','--fixed-fps','30','--script','res://'+v.FIXTURES[suite][0]]

def run(args):
    lockpath=r.path_checked(args.lock); lock=json.loads(p.regular(lockpath).read_text())
    p.require(lock.get('contracts_reviewed_for_execution') is True, 'Construction adapter not reviewed')
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
        p.require(lock['project_files'].get(name)==hashvalue, 'Unreviewed construction suite bytes')
    p.require(lock['project_files']['scripts/construction_status.gd']==v.STATUS_SHA, 'Unreviewed status logic')
    contract=v.parse_json(Path(required['contracts_names_sha256']).read_text())
    source,uids=p.source_inventory(project,lock); cache=p.cache_inputs(project)
    p.require(cache,'Guarded import required')
    marker=r.path_checked(args.import_marker);bound.append(marker)
    bound+=r.validate_import(project,lock,marker,cache,uids)
    bindings={str(x):p.digest(x) for x in bound}
    output.mkdir(parents=True);private.mkdir(parents=True,mode=0o700)
    receipt={'passed':False,'build':lock['build'],'source_commit':lock['source_commit'],'game_tree':lock['game_tree'],
             'scope':'Value-only and synthetic controlled HUD logic; no rendered/natural-play proof',
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
            result=logic.supervise(argv(godot,project,suite),env,stage,p.metrics())
            row={'suite':suite,'monitor':result};receipt['suites'].append(row)
            p.require(result['passed'] and result['cleanup_complete'] and not result['test_dependencies'] and not result['unexpected_descendants'], 'Failed/unknown suite; no next process')
            unchanged()
            p.require(set(p.tree(stage))=={'receipt.json','godot.log'},'Unexpected suite files')
            row['report']=v.read_log(stage/'godot.log',suite,lock,contract)
            row['receipt_sha256']=p.digest(stage/'receipt.json');row['log_sha256']=p.digest(stage/'godot.log')
            p.require(row['log_sha256']==result['log_sha256'],'Log drift')
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

#!/usr/bin/env python3
"""One exact faction publication component measurement; inert until reviewed."""
import argparse
import json
import os
from pathlib import Path
import run_export as r
import run_logic as logic
import validate_faction as v
p=r.p
LOGIC_SHA='2800e75273335ce8ffefccb1db6128b54f09850b50dc243cf73e7065ff107607'
HARNESS_SHA='0d83d9f9fe1f1878ab43c9cca1984c7bb194e6bf95629c97fbde0a57959f4f0c'
VALIDATOR_SHA='f7604feb2bcff0adca86d07831f37db8a0e5bbd6513afa981e320afb65f6dfdb'
REPORT='faction-publication-report.json'

def validate_gate(lock):
    p.require(lock.get('faction_reviewed_for_execution') is True,'Faction publication not reviewed')
    for key,want in [('faction_supervisor_sha256',LOGIC_SHA),('faction_harness_sha256',HARNESS_SHA),('faction_validator_sha256',VALIDATOR_SHA)]:
        p.require(lock.get(key)==want,'Unreviewed faction-publication input: '+key)

def argv(godot,project,harness,stage,build):
    p.require(harness.name=='faction_publish_contract.gd','Unsupported harness')
    return [str(godot),'--headless','--path',str(project),'--audio-driver','Dummy','--resolution','390x844',
            '--fixed-fps','30','--script',str(harness),'--',str(stage/REPORT),build]

def read_report(path,lock):
    report=v.read(path)
    p.require(report.get('schema')=='vc-faction-publication-v1','Wrong report schema')
    p.require(report.get('build')==lock['build'],'Report build mismatch')
    p.require(report.get('reference_sha256')==v.REFERENCE_SHA and report.get('candidate_sha256')==v.CANDIDATE_SHA,'Wrong component bytes')
    return report

def run(args):
    lockpath=r.path_checked(args.lock);lock=json.loads(p.regular(lockpath).read_text())
    validate_gate(lock);r.validate_lock(lock)
    p.require(os.environ.get('GITHUB_ACTIONS')=='true' and os.environ.get('RUNNER_ENVIRONMENT')=='github-hosted','Hosted VM required')
    p.require('VERSION_ID="24.04"' in Path('/etc/os-release').read_text(),'Ubuntu 24.04 required')
    project,output,private=map(r.path_checked,(args.project,args.output,args.private))
    paths=[project,output,private]
    p.require(project.is_dir() and not output.exists() and not private.exists(),'Fresh output/private required')
    p.require(len(set(paths))==3 and all(not a.is_relative_to(b) for a in paths for b in paths if a!=b),'Overlapping paths')
    godot=r.checked(args.godot,r.ENGINE_SHA)
    harness=r.path_checked(project/'tests/faction_publish_contract.gd')
    p.require(lock['project_files'].get('scripts/faction_view.gd')==v.CANDIDATE_SHA and lock['project_files'].get('tests/faction_publish_reference.gd')==v.REFERENCE_SHA,'Wrong component/reference binding')
    required={'runner_sha256':r.__file__,'owned_process_sha256':p.__file__,'faction_runner_sha256':__file__,
              'faction_supervisor_sha256':logic.__file__,'faction_validator_sha256':v.__file__,'faction_harness_sha256':harness}
    bound=[lockpath,godot]
    for key,path in required.items(): bound.append(r.checked(path,lock[key]))
    source,uids=p.source_inventory(project,lock);cache=p.cache_inputs(project)
    p.require(cache,'Guarded import required')
    marker=r.path_checked(args.import_marker);bound.append(marker)
    bound+=r.validate_import(project,lock,marker,cache,uids)
    bindings={str(x):p.digest(x) for x in bound}
    output.mkdir(parents=True);private.mkdir(parents=True,mode=0o700)
    receipt={'passed':False,'build':lock['build'],'source_commit':lock['source_commit'],'game_tree':lock['game_tree'],
             'scope':'Synthetic faction publication semantics and microbenchmark; not whole-game, mobile, render or normal-match proof',
             'input_sha256':bindings,'source_inventory_before':source,'generated_uid_sha256_before':uids,'cache_sha256_before':cache,
             'retry_permitted':False,'next_process_permitted':False}
    def unchanged():
        after_source,after_uids=p.source_inventory(project,lock,uids);after_cache=p.cache_inputs(project)
        receipt.update(source_inventory_after=after_source,generated_uid_sha256_after=after_uids,cache_sha256_after=after_cache)
        p.require(after_source==source and after_uids==uids and after_cache==cache,'Source/UID/import cache drift')
        p.require(all(p.digest(path)==sha for path,sha in bindings.items()),'Bound input drift')
    try:
        unchanged()
        env={'PATH':'/usr/bin:/bin','LANG':'C.UTF-8','TZ':'UTC','GODOT_SILENCE_ROOT_WARNING':'1','OMP_NUM_THREADS':'1'}
        for key,name in [('HOME','home'),('TMPDIR','tmp'),('XDG_DATA_HOME','data'),('XDG_CONFIG_HOME','config'),('XDG_CACHE_HOME','cache')]:
            path=private/name;path.mkdir(mode=0o700);env[key]=str(path)
        stage=output/'faction-publication';stage.mkdir()
        result=logic.supervise(argv(godot,project,harness,stage,lock['build']),env,stage,p.metrics())
        receipt['monitor']=result
        # Parse bounded partial evidence even after nonzero exit. This is data-only,
        # never permits another child, and can never change a failed monitor to pass.
        unchanged()
        p.require(set(p.tree(stage)) <= {'receipt.json','godot.log',REPORT},'Unexpected output files')
        for name,key in [('receipt.json','monitor_receipt_sha256'),('godot.log','log_sha256')]:
            if (stage/name).exists(): receipt[key]=p.digest(p.regular(stage/name))
        if (stage/REPORT).exists():
            report=read_report(stage/REPORT,lock)
            receipt['report_sha256']=p.digest(stage/REPORT)
            receipt['partial_summary']={'passed':report.get('passed'),'timed_out':report.get('timed_out'),'checks':len(report.get('checks',[])),'benchmarks':len(report.get('benchmarks',[]))}
        else: raise ValueError('No faction-publication report; retain monitor/log evidence')
        p.require(result['passed'] and result['cleanup_complete'] and not result['test_dependencies'] and not result['unexpected_descendants'],'Failed monitor or incomplete cleanup; no next process')
        p.require(receipt['log_sha256']==result['log_sha256'],'Log drift')
        receipt['validation']=v.validate(report,lock['build'])
        receipt['passed']=True
    except BaseException as exc:
        receipt['error']={'type':type(exc).__name__,'message':p.safe_diagnostic_text(exc)}
    finally:
        try:
            unchanged();receipt['post_run_binding_matches']=True
        except BaseException as exc:
            receipt['passed']=False;receipt['post_run_binding_matches']=False
            receipt['binding_error']={'type':type(exc).__name__,'message':p.safe_diagnostic_text(exc)}
        (output/'faction-publication-receipt.json').write_text(json.dumps(receipt,indent=2)+'\n')
        print(json.dumps({'passed':receipt['passed'],'scope':receipt['scope'],'partial':receipt.get('partial_summary'),'error':receipt.get('error')}))
    return 0 if receipt['passed'] else 1

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    for key in ('lock','project','output','private','godot','import-marker'): parser.add_argument('--'+key,type=Path,required=True)
    raise SystemExit(run(parser.parse_args()))

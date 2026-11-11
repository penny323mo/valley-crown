#!/usr/bin/env python3
"""One exact external natural-match fixture; inert until separately reviewed."""
import argparse
import json
import math
import os
from pathlib import Path
import run_export as r
import run_logic as logic
import validate_full_match as v
p=r.p
LOGIC_SHA='04b8be583b5db6a4bb210adb55af4dde80e51f260579767daff41ee769b7bef1'
HARNESS_SHA='a2670260f233e3771e1fe5142fb06581fad9795344f2108394d9a5a7580f6351'
VALIDATOR_SHA='050816a25144408a43cf25568034c5d3bdb1d35ebeeb4888b0ead1e71e6c80c8'
REPORT='full-match-report.json'

def validate_gate(lock):
    p.require(lock.get('full_match_reviewed_for_execution') is True,'Full match not reviewed')
    for key,want in [('full_match_supervisor_sha256',LOGIC_SHA),('full_match_harness_sha256',HARNESS_SHA),('full_match_validator_sha256',VALIDATOR_SHA)]:
        p.require(lock.get(key)==want,'Unreviewed full-match input: '+key)

def argv(godot,project,harness,stage,build):
    p.require(harness.name=='full_match.gd','Unsupported harness')
    return [str(godot),'--headless','--path',str(project),'--audio-driver','Dummy','--resolution','390x844',
            '--fixed-fps','30','--script',str(harness),'--',str(stage/REPORT),build]

def finite(value):
    if isinstance(value,float): p.require(math.isfinite(value),'Nonfinite report value')
    elif isinstance(value,dict):
        for item in value.values(): finite(item)
    elif isinstance(value,list):
        for item in value: finite(item)

def read_report(path,lock):
    report=logic.read_report(path) # unchanged 4MiB/regular-file/duplicate/constants gate
    finite(report) # Also reject JSON exponent overflow such as 1e999.
    p.require(report.get('schema')=='vc-normal-full-match-v1','Wrong report schema')
    p.require(report.get('policy_version')=='ordinary-policy-v2','Wrong policy version')
    p.require(type(report.get('final_public_records')) is list and type(report.get('public_samples')) is list,'Missing final public observations')
    p.require(len(report['public_samples'])<=64 and len(report.get('commands',[]))<=2048,'Diagnostic evidence bound exceeded')
    p.require(type(report.get('passed')) is bool,'Invalid report pass')
    p.require(report.get('build')==lock['build'],'Report build mismatch')
    for key,name in [('game_sha256','scripts/game.gd'),('rules_sha256','scripts/rules.gd')]:
        p.require(report.get(key)==lock['project_files'][name],'Runtime source mismatch')
    p.require(type(report.get('stop_reason')) is str and 0<len(report['stop_reason'])<=128,'Missing stop reason')
    p.require(type(report.get('phases')) is dict and type(report.get('events')) is list and type(report.get('commands')) is list,'Invalid partial evidence')
    p.require(report.get('engine_time_scale')==1,'Wrong engine time scale')
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
    harness=r.path_checked(Path(__file__).with_name('full_match.gd'))
    p.require(all(not harness.is_relative_to(path) for path in paths),'Harness must be external to source/output/private')
    required={'runner_sha256':r.__file__,'owned_process_sha256':p.__file__,'full_match_runner_sha256':__file__,
              'full_match_supervisor_sha256':logic.__file__,'full_match_validator_sha256':v.__file__,'full_match_harness_sha256':harness}
    bound=[lockpath,godot]
    for key,path in required.items(): bound.append(r.checked(path,lock[key]))
    source,uids=p.source_inventory(project,lock);cache=p.cache_inputs(project)
    p.require(cache,'Guarded import required')
    marker=r.path_checked(args.import_marker);bound.append(marker)
    bound+=r.validate_import(project,lock,marker,cache,uids)
    bindings={str(x):p.digest(x) for x in bound}
    output.mkdir(parents=True);private.mkdir(parents=True,mode=0o700)
    receipt={'passed':False,'build':lock['build'],'source_commit':lock['source_commit'],'game_tree':lock['game_tree'],
             'scope':'Headless normal command match; fixed-fps simulation, not rendering/realtime/touch proof',
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
        stage=output/'full-match';stage.mkdir()
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
            receipt['partial_summary']={'passed':report['passed'],'stop_reason':report['stop_reason'],'phases':report['phases'],'final':report.get('final',{})}
        else: raise ValueError('No full-match report; retain monitor/log evidence')
        p.require(result['passed'] and result['cleanup_complete'] and not result['test_dependencies'] and not result['unexpected_descendants'],'Failed monitor or incomplete cleanup; no next process')
        p.require(receipt['log_sha256']==result['log_sha256'],'Log drift')
        receipt['validation']=v.validate(report)
        receipt['passed']=True
    except BaseException as exc:
        receipt['error']={'type':type(exc).__name__,'message':p.safe_diagnostic_text(exc)}
    finally:
        try:
            unchanged();receipt['post_run_binding_matches']=True
        except BaseException as exc:
            receipt['passed']=False;receipt['post_run_binding_matches']=False
            receipt['binding_error']={'type':type(exc).__name__,'message':p.safe_diagnostic_text(exc)}
        (output/'full-match-receipt.json').write_text(json.dumps(receipt,indent=2)+'\n')
        print(json.dumps({'passed':receipt['passed'],'scope':receipt['scope'],'partial':receipt.get('partial_summary'),'error':receipt.get('error')}))
    return 0 if receipt['passed'] else 1

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    for key in ('lock','project','output','private','godot','import-marker'): parser.add_argument('--'+key,type=Path,required=True)
    raise SystemExit(run(parser.parse_args()))

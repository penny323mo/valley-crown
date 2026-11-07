#!/usr/bin/env python3
"""Direct-child, hash-bound CI import and native-test commands for one frozen source."""
from pathlib import Path
import argparse
import hashlib
import importlib.util
import json
import os
import shutil
import sys

HERE = Path(__file__).resolve().parent
BUILD = 'vc-8fcc302051f0'
ENGINE_SHA = 'f64d4ed19fc9df9440321653fcc80df8c6e365ba7b6de0a29e2cfa9fa71bfeb3'
ARCHIVE_SHA = '92e660f43172fb731574a5b9f40ff9059cfd036b27845d226b3bd804849c564e'
MONITOR_SHA = 'd7e1bee799c4ecd8edd67fbdc49ed26dacfb4c8c5a59e31c1d5a140ad0be4258'
SOURCE_MANIFEST_SHA = 'afd826fe829e7e46e6dc4371149d3de2333cdce523c481644165bb3113ad513e'
TEST_MANIFEST_SHA = 'a28a518eed22873330681ee8d1a31eb475768ec833e60e5b4513eef8b56a3525'
RUNNER_SHA = '6ddda312199a8a1e5fee780a9f1f1281cbaed3493787d5cd7aa1ca69bfd4d3bc'
GAME_SHA = 'b87388a439940574ed2af3498f425f90958dc3577355c71f7fb0c39f587f81e7'
ORDER = ['web_bridge_stub','canopy_geometry','held_preview_regression','touch_box_regression',
         'touch_epoch_regression','input_accumulation_regression','phone_input_edges','phone_core_flow']

def sha(path):
    with Path(path).open('rb') as stream:
        return hashlib.file_digest(stream,'sha256').hexdigest()

def require(ok,message):
    if not ok:
        raise RuntimeError(message)

def checked(path,expected):
    path = Path(path)
    require(path.is_file() and not path.is_symlink(),'Missing/nonregular input: '+str(path))
    require(sha(path)==expected,'Input hash mismatch: '+str(path))
    return path.resolve()

def load_monitor():
    path=checked(HERE/'hardened_monitored_run.py',MONITOR_SHA)
    spec=importlib.util.spec_from_file_location('phone_ci_monitor',path)
    module=importlib.util.module_from_spec(spec);sys.modules[spec.name]=module;spec.loader.exec_module(module)
    return module

def verify_inputs(project,engine,archive):
    artifacts={'adapter':Path(__file__).resolve(),'monitor':HERE/'hardened_monitored_run.py'}
    expected={'adapter':sha(__file__),'monitor':MONITOR_SHA}
    fixed={'engine':(engine,ENGINE_SHA),'source-archive':(archive,ARCHIVE_SHA),
           'source-manifest':(project/'tools/source_manifest.json',SOURCE_MANIFEST_SHA),
           'test-manifest':(project/'tools/test_manifest.json',TEST_MANIFEST_SHA),
           'original-runner':(project/'tools/run_phone_checks.py',RUNNER_SHA)}
    for name,(path,digest) in fixed.items():
        artifacts[name]=checked(path,digest);expected[name]=digest
    source=json.loads(artifacts['source-manifest'].read_text())
    tests=json.loads(artifacts['test-manifest'].read_text())
    require(source['build']==tests['build']==BUILD,'Unexpected build identity')
    require(source['engine']=='4.6.3.stable.official.7d41c59c4','Unexpected source engine')
    require(tests['engine_linux_x86_64_sha256']==ENGINE_SHA and tests['runner_sha256']==RUNNER_SHA,'Unexpected pinned tools')
    require(len(source['source_sha256'])==106 and len(tests['source_sha256'])==8,'Unexpected source/test count')
    require(tests['run_order']==ORDER,'Unexpected test order')
    for prefix,entries in [('runtime',source['source_sha256']),('test',tests['source_sha256'])]:
        for name,digest in entries.items():
            path=project/name
            require(not Path(name).is_absolute() and path.resolve().is_relative_to(project),'Unsafe source path')
            key=prefix+':'+name;artifacts[key]=checked(path,digest);expected[key]=digest
    return artifacts,expected

def isolated_environment(xdg):
    # Do not pass CI credentials or dump an inherited environment into evidence.
    env={key:os.environ[key] for key in ('PATH','LANG','LC_ALL','TZ') if key in os.environ}
    for key,name in [('HOME','home'),('TMPDIR','tmp'),('XDG_DATA_HOME','data'),
                     ('XDG_CONFIG_HOME','config'),('XDG_CACHE_HOME','cache')]:
        path=xdg/name;path.mkdir(parents=True,exist_ok=True);env[key]=str(path)
    env['GODOT_SILENCE_ROOT_WARNING']='1'
    return env

def cache_snapshot(project):
    paths=list((project/'.godot/imported').glob('*'))
    paths += [project/'.godot/uid_cache.bin',project/'.godot/global_script_class_cache.cfg']
    result={}
    for path in paths:
        if path.is_file():
            require(not path.is_symlink(),'Imported cache symlink rejected')
            result[path.relative_to(project).as_posix()]=sha(path)
    require(result and any(name.startswith('.godot/imported/') for name in result),'Import produced no resource cache')
    return dict(sorted(result.items()))

def validate_report(path):
    require(path.is_file(),'Test report is absent')
    report=json.loads(path.read_text())
    require(type(report.get('failed')) is int and report['failed']==0,'Test reports failures or invalid count')
    require(type(report.get('passed')) is int and report['passed']>0,'Test reports no passing assertions')
    if 'build' in report:
        require(report['build']==BUILD,'Report build identity mismatch')
    hashes=[report[key] for key in ('source_sha256','game_sha256') if key in report]
    require(hashes and all(value==GAME_SHA for value in hashes),'Report source identity mismatch')
    return {'passed':report['passed'],'failed':report['failed'],'sha256':sha(path)}

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('phase',choices=['import','test'])
    parser.add_argument('--project',type=Path,required=True)
    parser.add_argument('--godot',required=True)
    parser.add_argument('--archive',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True)
    parser.add_argument('--xdg',type=Path,required=True)
    args=parser.parse_args()
    project=args.project.resolve();archive=args.archive.resolve();output=args.output.resolve();xdg=args.xdg.resolve()
    executable=shutil.which(args.godot)
    require(executable is not None,'Godot binary not found')
    engine=Path(executable).resolve()
    require(not output.exists(),'Evidence directory already exists')
    require(not output.is_relative_to(project) and not xdg.is_relative_to(project),'Evidence/XDG must be outside project')
    output.mkdir(parents=True)
    env=isolated_environment(xdg)
    monitor=load_monitor()
    limits=monitor.Limits(timeout_s=300,sample_target_s=0.05,terminate_grace_s=5,kill_reap_grace_s=5,
                          launch_min_available_kib=4194304,runtime_min_available_kib=1048576,max_rss_kib=2097152)
    summary={'build':BUILD,'phase':args.phase,'passed':False,'commands':[],
             'scope':'Direct-child guarded native CI and separate inert JavaScript checks; not browser/device acceptance.'}
    summary_path=output/'phase-summary.json'
    marker=xdg/'import-complete.json'
    def save():
        summary_path.write_text(json.dumps(summary,indent=2)+'\n')
    def invoke(name,command,extra=None):
        artifacts,expected=verify_inputs(project,engine,archive)
        for key,(path,digest) in (extra or {}).items():
            artifacts[key]=checked(path,digest);expected[key]=digest
        print('START '+args.phase+' '+name+' build='+BUILD,flush=True)
        result=monitor.run(output/name,command,env=env,limits=limits,
                           artifacts=artifacts,expected_artifact_hashes=expected)
        row={key:result[key] for key in ('passed','exit','stop_reason','cleanup_complete','seconds','sampled_peak_rss_kib')}
        row['name']=name;row['receipt']=name+'.json';summary['commands'].append(row);save()
        print(json.dumps(row),flush=True)
        require(result['passed'] and result['cleanup_complete'],'Guarded command failed: '+name)
        verify_inputs(project,engine,archive)
        return row
    save()
    try:
        if args.phase=='import':
            require(not marker.exists(),'Import marker already exists; use a fresh source/XDG directory')
            require(not (project/'.godot').exists(),'Import requires a fresh source tree without cache')
            invoke('import',[str(engine),'--headless','--editor','--path',str(project),'--import'])
            receipt=output/'import.json'
            certificate={'build':BUILD,'project':str(project),'archive_sha256':ARCHIVE_SHA,'engine_sha256':ENGINE_SHA,
                         'monitor_receipt':str(receipt),'monitor_receipt_sha256':sha(receipt),'cache_sha256':cache_snapshot(project)}
            with marker.open('x') as stream:json.dump(certificate,stream,indent=2);stream.write('\n')
        else:
            require(marker.is_file(),'Successful guarded import marker required')
            certificate=json.loads(marker.read_text())
            require(certificate['build']==BUILD and certificate['project']==str(project),'Import marker is for another source')
            require(certificate['archive_sha256']==ARCHIVE_SHA and certificate['engine_sha256']==ENGINE_SHA,'Import inputs differ')
            receipt=checked(Path(certificate['monitor_receipt']),certificate['monitor_receipt_sha256'])
            prior=json.loads(receipt.read_text())
            require(prior.get('passed') is True and prior.get('cleanup_complete') is True,'Import receipt did not pass')
            cache=certificate['cache_sha256']
            require(cache_snapshot(project)==cache,'Imported cache changed before tests')
            extra={'import-marker':(marker,sha(marker)),'import-receipt':(receipt,sha(receipt))}
            for name,digest in cache.items():extra['cache:'+name]=(project/name,digest)
            for name in ORDER:
                report=output/(name+'.report.json')
                require(not report.exists(),'Report already exists')
                if name=='web_bridge_stub':
                    node=shutil.which('node',path=env.get('PATH'))
                    require(node is not None,'Node.js is required for the inert listener stub')
                    command=[node,str(project/'tests/web_bridge_stub.cjs'),str(report)]
                    kind='inert_js'
                else:
                    command=[str(engine),'--headless','--path',str(project),'--script','res://tests/'+name+'.gd','--',str(report)]
                    kind='native_godot'
                row=invoke(name,command,extra)
                row['kind']=kind;row['test_report']=validate_report(report);save()
        summary['passed']=True;save();return 0
    except BaseException as exc:
        summary['error']={'type':type(exc).__name__,'message':str(exc)};save()
        print(json.dumps({'phase':args.phase,'passed':False,'error':summary['error']}),flush=True)
        return 1

if __name__=='__main__':
    sys.exit(main())

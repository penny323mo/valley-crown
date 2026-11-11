#!/usr/bin/env python3
"""Fixed Blender product authoring guard. Preparation is inert until review lock."""
import argparse, hashlib, json, os, re, signal, subprocess, time
from pathlib import Path
import owned_process as p
KINDS = ('villager','spearman','archer','scout')
SOURCE_FILES = {'villager.blend': '8d43a1e693343bcf44f1f00fe138f0a2906ff51b8053f3e80d3b202b173a70db', 'spearman.blend': '70ad16d2cd92cd239547bcf21e2384acb75cd8b6dea71c11d9cf6ab18025b898', 'archer.blend': '7456bcb026fbd2045656766fbffcf65aa4c95f15f6aa6e57b621544480a83206', 'scout.blend': 'effca2c4ccece6b815640f449da1786db66d5ec61433447621475b4ba8212e75'}
SCHEMA = 'vc-fixed-blender-grip-authoring-v1'
ARCHIVE_URL = 'https://download.blender.org/release/Blender4.3/blender-4.3.2-linux-x64.tar.xz'
ARCHIVE_SHA = '4da1c956673c0485e63054e563ee69198cc8f80d8157dd7592dffc8a6a5592e6'
REAL = (subprocess.Popen, p.metrics, p.process_metrics, p.observe_descendants,
        p.cleanup_observed_descendant, p.reap_owned, time.monotonic, time.sleep,
        signal.signal, p.process_identity, os.pidfd_open, signal.pidfd_send_signal,
        p.select.select, os.close)

def check_sample(system, before, row):
    p.require(system['available_kib'] >= 1048576, 'Available-memory guard')
    p.require(system['oom_kill'] == before['oom_kill'], 'OOM count changed')
    if row:
        p.require(row['VmRSS'] <= 2621440 and row['VmHWM'] <= 2621440, 'Blender RSS/HWM guard')
        p.require(row['VmRSS'] <= 3145728, 'Combined RSS guard')


def supervise(argv, env, directory, before):
    """One owned child, no shells or process groups; all descendants fatal."""
    receipt = {'passed': False, 'cleanup_complete': False, 'unexpected_descendants': [],
               'samples': [], 'argv': argv, 'system_before': before,
               'limits': {'timeout_seconds': 120, 'admission_kib': 4194304,
                          'reserve_kib': 1048576, 'blender_rss_hwm_kib': 2621440,
                          'combined_rss_kib': 3145728},
               'test_dependencies': any(a is not b for a,b in zip(
                   (subprocess.Popen, p.metrics, p.process_metrics, p.observe_descendants,
                    p.cleanup_observed_descendant, p.reap_owned, time.monotonic, time.sleep,
                    signal.signal, p.process_identity, os.pidfd_open, signal.pidfd_send_signal,
                    p.select.select, os.close), REAL))}
    child = None; tracked = []; handlers = {}; stopped = False
    start = time.monotonic()
    def save():
        (directory / 'receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
    def stop(sig, frame):
        nonlocal stopped
        stopped = True
    def sample():
        p.require(not stopped, 'Termination requested')
        p.require(time.monotonic() - start <= 120, 'Authoring timeout')
        system = p.metrics(); row = None
        logpath = directory / 'blender.log'
        if logpath.exists():
            p.require(logpath.stat().st_size <= 16*1024*1024, 'Authoring log oversized')
        if child is not None and child.poll() is None:
            try:
                row = p.process_metrics(child)
            except (FileNotFoundError, KeyError, ProcessLookupError):
                child.wait(timeout=0.05)
            if row and row['child_pids']:
                receipt['unexpected_descendants'].append({'status': 'unexpected_child_detected',
                    'parent_pid': child.pid, 'pids': row['child_pids'][:16], 'truncated': len(row['child_pids']) > 16})
                save()
                try:
                    receipt['unexpected_descendants'].extend(p.observe_descendants('blender', child, row['child_pids'], tracked))
                except Exception as exc:
                    receipt['unexpected_descendants'].append({'status': 'observation_failed', 'type': type(exc).__name__})
                raise RuntimeError('Unexpected descendant; no retry')
        check_sample(system, before, row)
        receipt['samples'].append({'seconds': round(time.monotonic()-start, 3), **system, 'process': row})
        return system
    try:
        save()
        p.require(before['available_kib'] >= 4194304, 'Admission below 4 GiB')
        for sig in (signal.SIGTERM, signal.SIGINT):
            handlers[sig] = signal.signal(sig, stop)
        with (directory / 'blender.log').open('x') as log:
            admission = sample()
            p.require(admission['available_kib'] >= 4194304, 'Fresh admission below 4 GiB')
            receipt['launch_admission'] = admission
            child = subprocess.Popen(argv, env=env, stdin=subprocess.DEVNULL, stdout=log,
                                     stderr=subprocess.STDOUT, close_fds=True)
            receipt['pid'] = child.pid; save()
            while child.poll() is None:
                sample(); time.sleep(0.05)
            sample()
            receipt['exit'] = child.wait(timeout=0.05)
            p.require(receipt['exit'] == 0, 'Authoring nonzero exit')
            receipt['authoring_completed'] = True
    except BaseException as exc:
        receipt['error'] = {'type': type(exc).__name__, 'message': p.safe_diagnostic_text(exc)}
    finally:
        receipt['cleanup'] = p.reap_owned(child) if child is not None else {'complete': True, 'errors': [], 'signals': []}
        receipt['descendant_cleanup'] = [p.cleanup_observed_descendant(x) for x in reversed(tracked)]
        for sig, handler in handlers.items():
            try: signal.signal(sig, handler)
            except BaseException as exc: receipt.setdefault('handler_errors', []).append(type(exc).__name__)
        receipt['cleanup_complete'] = (receipt['cleanup']['complete'] and not receipt['cleanup']['errors']
            and not receipt['unexpected_descendants'] and not receipt.get('handler_errors')
            and all(x['exited'] and x['pidfd_closed'] for x in receipt['descendant_cleanup']))
        try:
            receipt['system_after'] = p.metrics(); check_sample(receipt['system_after'], before, None)
            p.require(receipt.get('authoring_completed') and 'error' not in receipt and receipt['cleanup_complete'], 'Incomplete logic run')
            log = directory / 'blender.log'
            p.require(log.stat().st_size <= 16*1024*1024, 'Authoring log oversized')
            p.require(not re.search(r'(?im)^\s*(?:SCRIPT ERROR:|ERROR:|FATAL:)', log.read_text(errors='replace')), 'Authoring log error')
            receipt['log_sha256'] = p.digest(log)
            receipt['passed'] = True
        except BaseException as exc:
            receipt['final_error'] = {'type': type(exc).__name__, 'message': p.safe_diagnostic_text(exc)}
        receipt['seconds'] = round(time.monotonic()-start, 3); save()
    return receipt


def safe_path(value):
    path = Path(value).absolute()
    p.require('..' not in path.parts and not any(x.is_symlink() for x in [path,*path.parents]), 'Unsafe path')
    return path

def digest_value(value):
    p.require(type(value) is str and re.fullmatch('[a-f0-9]{64}',value), 'Invalid digest')
    return value

def checked(path, expected, maximum):
    path=safe_path(path);p.regular(path)
    p.require(0 < path.stat().st_size <= maximum, 'File size bound')
    p.require(p.digest(path)==digest_value(expected), 'Hash mismatch')
    return path

def inventory(root, expected, maximum):
    root=safe_path(root);p.require(root.is_dir(), 'Missing inventory root')
    actual={}
    for f in root.rglob('*'):
        p.require(not f.is_symlink(), 'Symlink inventory')
        if f.is_dir():
            p.require(any(n.startswith(f.relative_to(root).as_posix()+'/') for n in expected),'Unexpected directory')
            continue
        name=f.relative_to(root).as_posix()
        p.require(name in expected,'Unexpected file')
        checked(f,expected[name],maximum);actual[name]=expected[name]
    p.require(actual==expected,'Missing inventory file')
    return actual

def validate_lock(lock):
    keys={'schema','reviewed_for_execution','source_commit','archive_url','archive_sha256','runner_sha256','owned_process_sha256','tool_files','code_files','source_files','calibration_sha256','extraction_receipt_sha256','extraction_helper_sha256'}
    p.require(type(lock) is dict and set(lock)==keys,'Wrong lock keys')
    p.require(lock['schema']==SCHEMA and lock['reviewed_for_execution'] is True,'Execution not reviewed')
    p.require(re.fullmatch('[a-f0-9]{40}',lock['source_commit']) is not None,'Invalid source commit')
    p.require(lock['archive_url']==ARCHIVE_URL and lock['archive_sha256']==ARCHIVE_SHA,'Wrong official archive')
    for key in ('runner_sha256','owned_process_sha256','calibration_sha256','extraction_receipt_sha256','extraction_helper_sha256'):digest_value(lock[key])
    p.require(lock['source_files']==SOURCE_FILES,'Wrong source inventory')
    p.require(set(lock['code_files'])=={'correct_public_grips.py','equipment_geometry.py'},'Wrong script inventory')
    p.require(type(lock['tool_files']) is dict and 'blender' in lock['tool_files'],'Missing tool inventory')
    for group in ('source_files','code_files','tool_files'):
        for name,h in lock[group].items():
            p.require(type(name) is str and not name.startswith('/') and '\\' not in name and all(x not in ('','.','..') for x in name.split('/')),'Unsafe inventory path')
            digest_value(h)

def validate_extraction_receipt(receipt,lock):
    expected={'schema':'vc-official-blender-extraction-v1','extraction_helper_sha256':lock['extraction_helper_sha256'],
              'archive_url':ARCHIVE_URL,'archive_sha256':ARCHIVE_SHA,'tool_files':lock['tool_files'],
              'blender_sha256':lock['tool_files']['blender'],'reviewed_for_execution':False}
    p.require(type(receipt) is dict and set(receipt)==set(expected),'Wrong extraction receipt schema')
    p.require(all(type(receipt[k]) is type(v) and receipt[k]==v for k,v in expected.items()),'Extraction receipt binding mismatch')


def fixed_argv(tool,code,source,calibration,calibration_sha,kind,output):
    p.require(kind in KINDS,'Unknown kind')
    return [str(tool/'blender'),'--background','--factory-startup','--disable-autoexec','--threads','1','--python-exit-code','1','--python',str(code/'correct_public_grips.py'),'--','--kind',kind,'--input-root',str(source),'--calibration',str(calibration),'--calibration-sha256',calibration_sha,'--output-root',str(output)]

def outputs(root,kind,lock):
    p.require(kind in KINDS,'Unknown kind')
    root=safe_path(root);expected={kind+'.blend':16<<20,kind+'.glb':4<<20,kind+'-audit.json':2<<20}
    p.require(root.is_dir() and {x.name for x in root.iterdir()}==set(expected),'Unexpected/missing output')
    hashes={}
    for name,maximum in expected.items():
        f=safe_path(root/name);p.regular(f);p.require(0<f.stat().st_size<=maximum,'Output size bound');hashes[name]=p.digest(f)
    audit=json.loads((root/(kind+'-audit.json')).read_text())
    required={'schema':'rts-public-grip-correction-v1','unit':kind,'source_blend_sha256':lock['source_files'][kind+'.blend'],'script_sha256':lock['code_files']['correct_public_grips.py'],'equipment_script_sha256':lock['code_files']['equipment_geometry.py'],'calibration_sha256':lock['calibration_sha256'],'blend_sha256':hashes[kind+'.blend'],'glb_sha256':hashes[kind+'.glb']}
    p.require(all(audit.get(k)==v for k,v in required.items()),'Audit binding mismatch')
    return hashes

def run(args):
    # No process/telemetry is touched until the entire static binding is admitted.
    lockpath=safe_path(args.lock);p.regular(lockpath)
    p.require(lockpath.stat().st_size<=8<<20,'Oversize lock')
    lock=json.loads(lockpath.read_text());validate_lock(lock)
    p.require(os.environ.get('GITHUB_ACTIONS')=='true' and os.environ.get('RUNNER_ENVIRONMENT')=='github-hosted','Fresh GitHub-hosted runner required')
    p.require('VERSION_ID="24.04"' in Path('/etc/os-release').read_text(),'Ubuntu 24.04 required')
    tool,code,source,calibration,output,evidence=map(safe_path,(args.tool_root,args.code_root,args.input_root,args.calibration,args.output_root,args.evidence_root))
    roots=[tool,code,source,output,evidence]
    p.require(len(set(roots))==len(roots) and all(not a.is_relative_to(b) for a in roots for b in roots if a!=b),'Overlapping roots')
    p.require(not output.exists() and not evidence.exists(),'Fresh output/evidence required')
    p.require(not any(calibration.is_relative_to(x) for x in roots),'Calibration must be separate')
    checked(__file__,lock['runner_sha256'],1<<20);checked(p.__file__,lock['owned_process_sha256'],1<<20)
    checked(args.archive,ARCHIVE_SHA,512<<20)
    extraction_receipt=checked(args.extraction_receipt,lock['extraction_receipt_sha256'],8<<20)
    extraction_helper=checked(Path(__file__).with_name('prepare_official_tool.py'),lock['extraction_helper_sha256'],1<<20)
    validate_extraction_receipt(json.loads(extraction_receipt.read_text()),lock)
    bindings={str(safe_path(x)):p.digest(p.regular(safe_path(x))) for x in (lockpath,__file__,p.__file__,calibration,args.archive,extraction_receipt,extraction_helper)}
    def recheck():
        inventory(tool,lock['tool_files'],512<<20)
        inventory(code,lock['code_files'],1<<20)
        inventory(source,lock['source_files'],16<<20)
        checked(calibration,lock['calibration_sha256'],16<<20)
        for path,h in bindings.items():p.require(p.digest(p.regular(safe_path(path)))==h,'Input drift')
    recheck();output.mkdir(mode=0o700);evidence.mkdir(mode=0o700)
    report={'schema':SCHEMA,'passed':False,'source_commit':lock['source_commit'],'runs':{},'outputs':{},'input_bindings':bindings,'visual_acceptance':False}
    try:
        for kind in KINDS:
            recheck();private=evidence/kind;private.mkdir(mode=0o700)
            env={'PATH':'/usr/bin:/bin','LANG':'C.UTF-8','TZ':'UTC','OMP_NUM_THREADS':'1','OPENBLAS_NUM_THREADS':'1','PYTHONDONTWRITEBYTECODE':'1'}
            for key,name in [('HOME','home'),('TMPDIR','tmp'),('XDG_CONFIG_HOME','config'),('XDG_CACHE_HOME','cache'),('XDG_DATA_HOME','data'),('BLENDER_USER_CONFIG','blender-config'),('BLENDER_USER_SCRIPTS','blender-scripts'),('BLENDER_USER_EXTENSIONS','blender-extensions')]:
                d=private/name;d.mkdir(mode=0o700);env[key]=str(d)
            result=supervise(fixed_argv(tool,code,source,calibration,lock['calibration_sha256'],kind,output/kind),env,private,p.metrics())
            report['runs'][kind]=result
            recheck()
            p.require(result['passed'] and not result['test_dependencies'],'Authoring monitor failed or mocked; stop batch')
            report['outputs'][kind]=outputs(output/kind,kind,lock)
        p.require({x.name for x in output.iterdir()}==set(KINDS),'Unexpected batch output')
        report['passed']=True
    except BaseException as exc:report['error']={'type':type(exc).__name__,'message':p.safe_diagnostic_text(exc)}
    finally:
        try:recheck();report['post_run_binding_matches']=True
        except BaseException as exc:report['passed']=False;report['post_run_binding_matches']=False;report['binding_error']=type(exc).__name__
        (evidence/'authoring-receipt.json').write_text(json.dumps(report,indent=2)+'\n')
    return 0 if report['passed'] else 1

if __name__=='__main__':
    parser=argparse.ArgumentParser(allow_abbrev=False)
    for name in ('lock','archive','extraction-receipt','tool-root','code-root','input-root','calibration','output-root','evidence-root'):parser.add_argument('--'+name,required=True,type=Path)
    raise SystemExit(run(parser.parse_args()))

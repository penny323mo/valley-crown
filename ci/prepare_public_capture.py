#!/usr/bin/env python3
"""Prepare bounded capture using only an exact already-public game checkout."""
from pathlib import Path
import argparse,hashlib,importlib.util,json,os,re,shutil,subprocess,sys,zipfile
sys.dont_write_bytecode=True
HERE=Path(__file__).resolve().parent
SOURCE_COMMIT='c5b78df4dab1e1f58f83bc2d8678512ddc628045'
GAME_TREE='c133ed816d338bfabab2ae617bee917f4080799b'
BUILD='vc-dd795d96905c'
ENGINE='4.6.3.stable.official.7d41c59c4'
ENGINE_SHA='f64d4ed19fc9df9440321653fcc80df8c6e365ba7b6de0a29e2cfa9fa71bfeb3'
SHADER_UID='assets/mature/shaders/building_damage_soot.gdshader.uid'

def need(v,m):
    if not v:raise ValueError(m)
def sha(p):
    with Path(p).open('rb') as f:return hashlib.file_digest(f,'sha256').hexdigest()
def dump(p,j):p.write_text(json.dumps(j,indent=2,sort_keys=True)+'\n')
def canonical(j):return hashlib.sha256(json.dumps(j,sort_keys=True,separators=(',',':')).encode()).hexdigest()
def git(root,*args):return subprocess.check_output(['git','-C',str(root),*args],text=True,timeout=15).strip()
def entries_from_git(root):
    need(git(root,'rev-parse','HEAD:game')==GAME_TREE,'Public game tree differs')
    rows=git(root,'ls-tree','-r','HEAD:game').splitlines();entries={}
    for line in rows:
        meta,name=line.split('\t',1);mode,kind,digest=meta.split()
        need(mode=='100644' and kind=='blob','Nonregular public source')
        entries[name]=digest
    need(len(entries)==206,'Public source count differs');return entries

def prepare(project,work,public_blobs):
    project=project.resolve();work=work.resolve()
    need(not work.exists() and not work.is_relative_to(project) and not project.is_relative_to(work),'Fresh separate work root required')
    entries={};actual={}
    for p in sorted(project.rglob('*')):
        need(not p.is_symlink(),'Source symlink')
        if p.is_dir():continue
        need(p.is_file(),'Special source')
        name=p.relative_to(project).as_posix();size=p.stat().st_size
        with p.open('rb') as f:
            h=hashlib.sha1(b'blob '+str(size).encode()+b'\0')
            while b:=f.read(1024*1024):h.update(b)
        actual[name]=h.hexdigest();entries[name]=dict(file=name,size=size,sha256=sha(p))
    need(actual==public_blobs and len(actual)==206,'Exact public source bytes differ')
    spec=importlib.util.spec_from_file_location('public_runtime',project/'tools/runtime_manifest.py');module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
    module.verify_mature_export_exclusions(project)
    runtime_names=[p.relative_to(project).as_posix() for p in module.runtime_paths(project)]
    runtime=dict(build=BUILD,engine=ENGINE,source_sha256={n:entries[n]['sha256'] for n in runtime_names})
    h=hashlib.sha256()
    for n in sorted(runtime_names):
        b=(project/n).read_bytes()
        if n=='scripts/rules.gd':
            need(re.findall(rb'const BUILD_ID = "([^"]*)"',b)==[BUILD.encode()],'Rules build differs')
            b=re.sub(rb'const BUILD_ID = "[^"]*"',b'const BUILD_ID = "normalized"',b)
        h.update(n.encode());h.update(b'\0');h.update(b)
    need('vc-'+h.hexdigest()[:12]==BUILD,'Public runtime digest differs')
    work.mkdir(parents=True);dest=work/'project';shutil.copytree(project,dest)
    archive=work/'source.zip'
    with zipfile.ZipFile(archive,'x',compression=zipfile.ZIP_STORED) as z:
        for n in sorted(entries):
            info=zipfile.ZipInfo(n,date_time=(2026,1,1,0,0,0));info.create_system=3;info.external_attr=0o100644<<16
            with (dest/n).open('rb') as src,z.open(info,'w') as out:shutil.copyfileobj(src,out,1024*1024)
    descriptor=dict(inputs=len(runtime_names),sha256=canonical(runtime))
    suite='tests/map80_contract.gd';suite_sha=entries[suite]['sha256'];report='OUTPUT/not-invoked.json'
    manifest=dict(candidate=BUILD,engine_expected=ENGINE,execution_enabled=False,files=list(entries.values()),runtime_manifest=descriptor,public_runtime_descriptor=runtime,
        suites=[dict(name='unused_map_descriptor',script=suite,script_sha256=suite_sha,argv=['GODOT','--headless','--path','PROJECT','--script','res://'+suite,'--',report],report=report,report_contract=dict(format='JSON object',must_be_new_file_from_this_run=True,process_exit_code=0,minimum_rows=1,rows_field='checks',row_verdict=dict(key='pass',equals=True,type='boolean'),count_equations=['passed == len(checks)','failed == 0'],required_integer_fields=dict(passed=dict(minimum=1),failed=dict(equals=0)),required_external_receipt=dict(candidate_build=BUILD,runtime_manifest_sha256=descriptor['sha256'],suite_sha256=suite_sha,require_process_and_output_hash_binding=True)))])
    dump(work/'import-manifest.json',manifest)
    generated=sorted(n+'.uid' for n in entries if n.endswith('.gd') and n+'.uid' not in entries)
    if SHADER_UID[:-4] in entries and SHADER_UID not in entries:generated=sorted(generated+[SHADER_UID])
    support={str(p.relative_to(HERE.parent)):sha(p) for p in sorted(HERE.glob('*')) if p.is_file()}
    support['.github/workflows/public-main-web.yml']=sha(HERE.parent/'.github/workflows/public-main-web.yml')
    lock=dict(native_renderer='linux-x11-mesa-llvmpipe-gl_compatibility',build=BUILD,reviewed_for_execution=True,diagnostic_only=False,require_skeletal_animation=True,project_files={n:v['sha256'] for n,v in entries.items()},allowed_generated_uid_files=generated,capture_contract=dict(frame_count=10,kind='genuine_native_game_viewport',mode='gameplay'),godot_sha256=ENGINE_SHA,harness_sha256=sha(HERE/'capture_native.gd'),supervisor_sha256=sha(HERE/'run_native.py'),support_files=support,source_archive_sha256=sha(archive),import_manifest_sha256=sha(work/'import-manifest.json'),source_commit=SOURCE_COMMIT,public_game_tree=GAME_TREE,scope='Pre-import public source identity; generated sidecars recorded separately; scripted UI inspection, not physical-touch acceptance')
    from run_native import validate_capture_lock
    validate_capture_lock(lock)
    dump(work/'capture-lock.json',lock)
    # Shell values are validated fixed-length digests only, not source content.
    (work/'pins.env').write_text('ARCHIVE_SHA='+lock['source_archive_sha256']+'\nMANIFEST_SHA='+lock['import_manifest_sha256']+'\n')
    return dict(source_commit=SOURCE_COMMIT,build=BUILD,public_game_tree=GAME_TREE,source_files=len(entries),runtime_inputs=len(runtime_names),engine_executed=False)

def main():
    p=argparse.ArgumentParser();p.add_argument('phase',choices=['prepare','engine']);p.add_argument('--work',type=Path,required=True);a=p.parse_args()
    need(os.environ.get('GITHUB_ACTIONS')=='true' and os.environ.get('RUNNER_ENVIRONMENT')=='github-hosted','Hosted runner required')
    need(os.environ.get('GITHUB_REPOSITORY')=='penny323mo/valley-crown' and os.environ.get('GITHUB_REF')=='refs/heads/ci/public-main-interfaces-vc-dd795d96905c' and os.environ.get('GITHUB_RUN_ATTEMPT')=='1','Wrong repository/branch/attempt')
    root=HERE.parent;work=a.work.resolve()
    if a.phase=='prepare':print(json.dumps(prepare(root/'game',work,entries_from_git(root))))
    else:
        import official_download as d
        need((work/'capture-lock.json').is_file(),'Source preparation missing')
        d.download(d.ENGINE_URL,work/'engine.zip');d.safe_extract(work/'engine.zip',{d.ENGINE_NAME:ENGINE_SHA},work/'engine',max_total=256*1024*1024,max_member=256*1024*1024)
        (work/'engine'/d.ENGINE_NAME).chmod(0o755)
        print('Pinned official engine prepared, not launched')
if __name__=='__main__':main()

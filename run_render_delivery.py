#!/usr/bin/python3
"""Fixed narrow hosted chain. No matrix, export, generic commands or upload."""
from pathlib import Path
import argparse,hashlib,json,os,re,subprocess,sys
sys.dont_write_bytecode=True
from stage_render import need,read,regular,sha,stage
import delivery_helpers
ROOT=Path(__file__).resolve().parent
SCENARIOS=(('studies',844,390,'capture_material_studies.gd'),('portrait',390,844,'capture_material_gameplay.gd'),('landscape',844,390,'capture_material_gameplay.gd'))

def child_environment():
    keep=('PATH','LANG','LC_ALL','TZ','HOME','TMPDIR','GITHUB_ACTIONS','RUNNER_ENVIRONMENT')
    return {**{key:os.environ[key] for key in keep if key in os.environ},'PYTHONDONTWRITEBYTECODE':'1'}

def validate(contract):
    need(contract.get('schema')=='material-delivery-v1' and contract.get('mode')=='render' and contract.get('execution_enabled') is True)
    need(os.environ.get('GITHUB_ACTIONS')=='true' and os.environ.get('RUNNER_ENVIRONMENT')=='github-hosted')
    need(set(contract.get('artifacts',{}))=={'old_licensed','old_native','generated','native_accepted'})
    need(type(contract.get('bindings')) is dict)
    paths=set()
    for binding in contract['bindings'].values():
        need(type(binding) is dict and set(binding)=={'path','sha256'})
        name,digest=binding['path'],binding['sha256']
        need(name not in paths);paths.add(name)
        need(type(name) is str and not Path(name).is_absolute() and '\\' not in name and all(part not in ('','.','..') for part in name.split('/')))
        need(type(digest) is str and re.fullmatch('[0-9a-f]{64}',digest) is not None and sha(regular(ROOT/name))==digest)
    return contract

def run(contract,phase,engine,_checked=None):
    if _checked is None:
        checked_root,checked=delivery_helpers.validate_contract(contract,strict=False)
        need(checked_root==ROOT)
    else:checked=_checked
    c=validate(checked)
    if phase=='all':
        for fixed_phase in ('prepare','import','capture'):run(contract,fixed_phase,engine,c)
        return
    def pin(name):
        matches=[row['sha256'] for row in c['bindings'].values() if row['path']==name]
        need(len(matches)==1);return matches[0]
    def call(script,*args):
        pin(script)
        subprocess.run(['/usr/bin/python3',str(ROOT/script),*map(str,args)],cwd=ROOT,stdin=subprocess.DEVNULL,check=True,env=child_environment())
    def local(name):return ROOT/name
    def artifact(key):
        row=c['artifacts'][key];need(type(row.get('destination')) is str)
        name=row['destination'];need(not Path(name).is_absolute() and all(part not in ('','.','..') for part in name.split('/')))
        return local(name)
    ci=local('source/render/ci');project=local('work/render-source/project')
    archive=local('work/render-source/material-render-source.zip');manifest=local('work/render-source/MATERIAL_RENDER_SOURCE_PACKAGE.json')
    marker=local('work/private/import/import-complete.json')
    def prepared_review(name):
        prepared='controls/'+name+'.prepared.json';pin(prepared)
        review_name='controls/'+name+'.review.json';pin(review_name)
        lock=read(local(prepared));review=read(local(review_name))
        need(lock.get('reviewed_for_execution') is True and lock.get('import_certificate_sha256') is None)
        need(lock.get('independent_review',{}).get('passed') is True and lock['independent_review'].get('report_sha256')==sha(local(review_name)))
        core=dict(lock);core.pop('independent_review',None);core['import_certificate_sha256']=None
        expected=hashlib.sha256(json.dumps(core,sort_keys=True,separators=(',',':'),allow_nan=False).encode()).hexdigest()
        need(review.get('peer_reviewed') is True and review.get('render_contract_core_sha256')==expected)
        need(review.get('binder_sha256')==sha(local('source/bind_render_after_import.py')) and review.get('assembly_helper_sha256')==sha(local('source/assemble_material_source.py')))
        for helper,digest in lock['support_files'].items():
            need(helper.startswith('ci/') and '/' not in helper[3:] and sha(regular(ci/helper[3:]))==digest)
        need(sha(archive)==lock.get('source_archive_sha256') and sha(manifest)==lock.get('import_manifest_sha256'))
        return lock
    if phase=='prepare':
        need(not local('work').exists());local('work').mkdir()
        call('reconstruct_baseline.py','--source',local('baseline-public'),'--licensed',artifact('old_licensed'),'--native',artifact('old_native'),'--plan',local('BASELINE_CHAIN.json'),'--plan-sha256',pin('BASELINE_CHAIN.json'),'--baseline-lock',local('BASELINE_192.json'),'--output',local('work/baseline'))
        generated_archive=c['artifacts']['generated']['archive_path'];need(generated_archive=='downloads/generated.zip')
        generation=read(local('controls/MATERIAL_SOURCE_INPUTS.json'));g=c['artifacts']['generated']
        need(generation.get('generation_run_id')==g['run_id'] and generation.get('generation_artifact_id')==g['artifact_id'] and generation.get('generation_commit')==g['head_sha'] and generation.get('generated_archive_sha256')==g['archive_sha256'])
        native_input=read(local('controls/MATERIAL_RENDER_SOURCE_INPUTS.json'));n=c['artifacts']['native_accepted']
        need(native_input.get('native_run_id')==n['run_id'] and native_input.get('native_artifact_id')==n['artifact_id'] and native_input.get('native_artifact_archive_sha256')==n['archive_sha256'])
        call('source/assemble_material_source.py','--baseline',local('work/baseline/project'),'--baseline-lock',local('BASELINE_192.json'),'--generated-archive',local(generated_archive),'--generator',local('tools/build_licensed_action_characters.py'),'--inputs',local('controls/MATERIAL_SOURCE_INPUTS.json'),'--inputs-sha256',pin('controls/MATERIAL_SOURCE_INPUTS.json'),'--review',local('controls/GENERATION_REVIEW.json'),'--geometry-check',local('tools/compare_glb_nonmaterial.py'),'--output',local('work/assembly'))
        native=artifact('native_accepted')/'accepted-runtime'
        call('source/prepare_render_source.py','--inputs',local('controls/MATERIAL_RENDER_SOURCE_INPUTS.json'),'--inputs-sha256',pin('controls/MATERIAL_RENDER_SOURCE_INPUTS.json'),'--assembled-project',local('work/assembly/project'),'--assembled-lock',local('work/assembly/assembled-source-lock.json'),'--native-archive',native/'runtime-delta.zip','--native-final-lock',native/'final-source-lock.json','--native-receipt',native/'receipt.json','--native-review',local('controls/NATIVE_OUTPUT_REVIEW.json'),'--baseline-package',local('baseline-public/GROUND_RALLY_TEXT_SOURCE_PACKAGE.json'),'--output',local('work/render-source'))
        # Cross-bind regenerated final package to already independently reviewed locks.
        for name,_,_,_ in SCENARIOS:
            prepared_review(name)
    elif phase=='import':
        for name,_,_,_ in SCENARIOS:prepared_review(name)
        need(engine is not None);engine=regular(engine)
        need(sha(engine)=='f64d4ed19fc9df9440321653fcc80df8c6e365ba7b6de0a29e2cfa9fa71bfeb3')
        call('source/render/ci/guarded_manifest_ci.py','import','--project',project,'--godot',engine,'--archive',archive,'--manifest',manifest,'--archive-sha256',sha(archive),'--manifest-sha256',sha(manifest),'--xdg',local('work/private/import'),'--hosted-execution-approved','--output',local('work/import-evidence'))
    elif phase=='capture':
        need(engine is not None);engine=regular(engine);local('work/final-locks').mkdir(exist_ok=False)
        for name,width,height,harness in SCENARIOS:
            prepared='controls/'+name+'.prepared.json';final=local('work/final-locks/'+name+'.json')
            call('source/bind_render_after_import.py','--prepared-lock',local(prepared),'--prepared-lock-sha256',pin(prepared),'--review',local('controls/'+name+'.review.json'),'--helpers',ci,'--import-marker',marker,'--project',project,'--godot',engine,'--archive',archive,'--manifest',manifest,'--output',final)
            call('source/render/ci/run_native.py','--project',project,'--godot',engine,'--harness',ci/harness,'--lock',final,'--import-marker',marker,'--output',local('work/evidence/'+name),'--private',local('work/private/'+name),'--width',width,'--height',height)
            call('source/render/ci/scan_evidence.py','--directory',local('work/evidence/'+name),'--lock',final,'--report',local('work/evidence/'+name+'-scan.json'))
        stage(local('work/evidence'),local('safe-render'),marker,local('work/import-evidence'),local('work/final-locks'))
    else:raise ValueError('Unknown fixed phase')
if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--contract',type=Path,required=True);p.add_argument('--phase',choices=('all',),required=True);p.add_argument('--engine',type=Path);a=p.parse_args()
    try:run(a.contract,a.phase,a.engine)
    except Exception:print(json.dumps({'passed':False,'reason':'Render delivery phase rejected; details withheld'}));raise SystemExit(1)

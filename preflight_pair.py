"""Read-only pair/source/admission checks. No browser, subprocess or host sampling."""
from pathlib import Path
import argparse,hashlib,importlib,json,os,sys
ROOT=Path(__file__).resolve().parent

def need(ok,message):
    if not ok:raise ValueError(message)

def sha(path):return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def load(side):
    need(side in ('baseline','candidate'),'Unknown side');qa=ROOT/side/'qa'
    for name in ('source_pins','validate_visibility_binding','check_export_pins'):sys.modules.pop(name,None)
    sys.path.insert(0,str(qa))
    try:gate=importlib.import_module('check_export_pins');validator=importlib.import_module('validate_visibility_binding')
    finally:sys.path.pop(0)
    return qa,gate,validator

def source_check(side,admission=False):
    qa,gate,validator=load(side);expected=json.loads((qa/'expected-export.json').read_text());scenario=json.loads((qa/'scenario-manifest.json').read_text())
    receipt_path=ROOT/'review'/(side+'-chain.json');need(sha(receipt_path)==expected['source_chain_verification_sha256'],'Independent receipt bytes changed')
    receipt=json.loads(receipt_path.read_text());export=expected['export_manifest']
    need(receipt['schema']=='vc-paused-diagnostic-chain-review-v1' and receipt['side']==side,'Wrong independent receipt')
    need(receipt['files_sha256']==expected['files_sha256'] and receipt['artifact_zip_sha256']==expected['artifact_zip_sha256'],'Independent output/ZIP pin differs')
    need(str(receipt['artifact_id'])==str(expected['artifact_id']) and str(receipt['run'])==str(expected['export_run_id']),'Independent artifact/run differs')
    need(receipt['ci_commit']==export['diagnostic_export_commit'] and receipt['source_commit']==scenario['source_commit'] and receipt['game_tree']==scenario['game_tree'],'Independent source identity differs')
    need(receipt['export_receipt_sha256']==export['guard_receipt_sha256'],'Independent export guard receipt differs')
    need(receipt['source_files_verified']==235 and receipt['two_exports_identical'] is True and receipt['import_cleanup_complete'] is True and receipt['import_oom_unchanged'] is True,'Incomplete chain acceptance')
    need(len(receipt['exports'])==2 and all(x['cleanup_complete'] is True and x['oom_unchanged'] is True for x in receipt['exports']),'Incomplete export cleanup/OOM proof')
    need(receipt['full_compiled_zip_locally_verified'] is False and expected['full_compiled_zip_locally_verified'] is False,'Incorrect local compiled-ZIP verification claim')
    for key in ('source_archive_sha256','import_manifest_sha256','export_manifest_sha256','diagnostic_source_inventory_sha256'):
        need(receipt[key]==scenario[key],'Independent chain pin differs: '+key)
    checked=dict(scenario)
    if not admission:checked['execution_approved']=True  # Pure structural check only; never persisted or used to launch.
    gate.validate_pins(expected,checked,hashlib.sha256(json.dumps(checked,sort_keys=True).encode()).hexdigest())
    return expected,scenario

def admitted(env=None):
    env=os.environ if env is None else env;approval=json.loads((ROOT/'admission.json').read_text())
    need(approval['reviewed'] is True and approval['execution_approved'] is True,'Pair execution admission remains disabled')
    need(approval['order']==['baseline','candidate'] and approval['same_fresh_hosted_job'] is True and approval['automatic_promotion'] is False,'Pair scope differs')
    need(env.get('GITHUB_ACTIONS')=='true' and env.get('RUNNER_ENVIRONMENT')=='github-hosted','Fresh hosted VM required')
    need(env.get('GITHUB_REPOSITORY')==approval['repository']=='penny323mo/valley-crown' and env.get('GITHUB_REF')==approval['branch'],'Wrong repository/branch')
    need(env.get('GITHUB_RUN_ATTEMPT')==approval['run_attempt']=='1','Only first attempt admitted')
    for side in approval['order']:source_check(side,True)

def host_lock(side,path):
    qa,_,validator=load(side);data=(qa/'scenario-manifest.json').read_bytes()
    validator.validate(json.loads(data),json.loads(Path(path).read_text()),hashlib.sha256(data).hexdigest())

def safe_next(path):
    receipt=json.loads(Path(path).read_text())
    need(receipt.get('cleanup_verified') is True and receipt.get('host_oom_unchanged_after_cleanup') is True and receipt.get('post_run_inputs_unchanged') is True,'Previous original service cleanup/OOM/input checks incomplete')

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--admit',action='store_true');p.add_argument('--side',choices=['baseline','candidate']);p.add_argument('--host-lock',type=Path);p.add_argument('--previous-guard',type=Path);a=p.parse_args()
    if a.previous_guard:safe_next(a.previous_guard)
    elif a.host_lock:host_lock(a.side,a.host_lock)
    elif a.admit:admitted()
    else:
        for side in ('baseline','candidate'):source_check(side)
    print('Read-only pair binding check passed; no browser launched.')

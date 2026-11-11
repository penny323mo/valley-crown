"""Read-only source policy. No process launch, host probe or resource sampling."""
from pathlib import Path
import hashlib,json,os,re

ROOT=Path(__file__).resolve().parents[1]
NAMES={'diagnostic/visibility_paused.gd','diagnostic/visibility_paused.tscn'}

def need(ok,message):
    if not ok:raise ValueError(message)

def sha(path):
    with Path(path).open('rb') as stream:return hashlib.file_digest(stream,'sha256').hexdigest()

def canonical(value):
    return hashlib.sha256(json.dumps(value,sort_keys=True,separators=(',',':')).encode()).hexdigest()

def digest(value):return isinstance(value,str) and re.fullmatch('[0-9a-f]{64}',value) is not None

def configuration():
    value=json.loads((ROOT/'sources.json').read_text())
    need(value.get('schema')=='vc-paused-diagnostic-sources-v1','Source binding schema differs')
    need(set(value.get('arms',{}))=={'baseline','candidate'},'Exact pair required')
    need(set(value.get('overlay_files_sha256',{}))==NAMES,'Exact observer file set required')
    return value

def snapshot_path(side):
    config=configuration();need(side in config['arms'],'Unknown arm')
    name=config['arms'][side]['snapshot']
    need(name=='inputs/'+side+'.json','Unexpected snapshot path')
    return ROOT/name

def baseline(side):
    config=configuration();path=snapshot_path(side)
    need(sha(path)==config['arms'][side]['snapshot_sha256'],'Product snapshot binding differs')
    value=json.loads(path.read_text())
    need(value['side']==side and len(value['project_files'])==config['expected_product_files'],'Product source count differs')
    need(len(value['runtime']['source_sha256'])==config['expected_runtime_inputs'],'Product runtime count differs')
    need(len(value['expected_generated_uid_names'])==config['expected_product_generated_uid_names'],'Product UID expectation differs')
    need(value['runtime']['build']==value['build'],'Original runtime build differs')
    need(hashlib.sha256(value['original_project_text'].encode()).hexdigest()==value['project_files']['project.godot'],'Original project text hash differs')
    return value

def execution_identity(side):
    config=configuration();arm=config['arms'].get(side,{});base=baseline(side)
    need(config.get('final_source_reviewed') is True and arm.get('final_source_bound') is True,'Final corrected product source unbound')
    need((arm.get('final_source_commit'),arm.get('final_game_tree'))==(base['source_commit'],base['game_tree']),'Final product source identity differs')
    return {key:base[key] for key in ('source_commit','game_tree','build')}

def validate_admission(config,approval,env,side):
    need(config.get('execution_approved') is True and approval.get('reviewed') is True and approval.get('execution_approved') is True,'Diagnostic execution remains disabled')
    arm=config['arms'].get(side,{})
    need(config.get('final_source_reviewed') is True and arm.get('final_source_bound') is True,'Final source review missing')
    need(digest(arm.get('lifecycle_acceptance_sha256')),'Actual corrected lifecycle acceptance unbound')
    need(approval.get('side')==side and approval.get('branch','').startswith('refs/heads/ci/'),'Exact reviewed arm/branch missing')
    need(env.get('GITHUB_ACTIONS')=='true' and env.get('RUNNER_ENVIRONMENT')=='github-hosted','Fresh hosted runner required')
    need(env.get('GITHUB_REPOSITORY')==approval.get('repository')=='penny323mo/valley-crown' and env.get('GITHUB_REF')==approval['branch'],'Repository/branch differs')
    need(env.get('GITHUB_RUN_ATTEMPT')==approval.get('run_attempt')=='1' and env.get('DIAGNOSTIC_EXECUTION_APPROVED')=='true','First attempt/explicit execution review missing')

def admitted(side=None):
    side=side or os.environ.get('DIAGNOSTIC_SIDE','')
    validate_admission(configuration(),json.loads((ROOT/'approval.json').read_text()),os.environ,side)
    execution_identity(side)

def tree(root):
    root=Path(root)
    need(root.is_dir() and not any(p.is_symlink() for p in [root,*root.parents]),'Nonregular root')
    result={}
    for p in sorted(root.rglob('*')):
        need(not p.is_symlink(),'Symlink input')
        if p.is_dir():continue
        need(p.is_file(),'Special input');result[p.relative_to(root).as_posix()]=sha(p)
    return result

def override(data):
    config=configuration();old=config['main_scene_from'];new=config['main_scene_to']
    need(old=='run/main_scene="res://main_menu.tscn"' and new=='run/main_scene="res://diagnostic/visibility_paused.tscn"','Main-scene override scope changed')
    need(data.count(old)==1,'Ambiguous original main scene')
    return data.replace(old,new).encode()

def verify_product(project,base):
    need(tree(project)==base['project_files'],'Original product source changed')
    h=hashlib.sha256()
    for name,digest_value in sorted(base['runtime']['source_sha256'].items()):
        need(base['project_files'].get(name)==digest_value,'Original runtime/source inventory differs')
        data=(project/name).read_bytes();need(hashlib.sha256(data).hexdigest()==digest_value,'Original runtime bytes differ')
        if name=='scripts/rules.gd':
            need(re.findall(rb'const BUILD_ID = "([^"]*)"',data)==[base['build'].encode()],'Original build label differs')
            data=re.sub(rb'const BUILD_ID = "[^"]*"',b'const BUILD_ID = "normalized"',data)
        h.update(name.encode());h.update(b'\0');h.update(data)
    need('vc-'+h.hexdigest()[:12]==base['build'],'Original derived runtime build differs')

def verify(side,files,overlay):
    base=baseline(side);need(overlay==configuration()['overlay_files_sha256'] and set(overlay)==NAMES,'Observer binding differs')
    expected=dict(base['project_files']);expected.update(overlay)
    expected['project.godot']=hashlib.sha256(override(base['original_project_text'])).hexdigest()
    need(files==expected and len(files)==len(base['project_files'])+2,'Not exactly original product plus two observers and main-scene override')
    return base

def binding_inputs(side):
    return {'policy':Path(__file__),'sources':ROOT/'sources.json','snapshot':snapshot_path(side),'approval':ROOT/'approval.json'}

def import_policy(package,entries):
    binding=package['diagnostic_binding'];side=binding['side'];base=verify(side,entries,binding['overlay_sha256'])
    need(binding['bound_files_sha256']=={k:sha(p) for k,p in binding_inputs(side).items()},'Diagnostic source-policy inputs differ')
    need(package['public_runtime_descriptor']==base['runtime'],'Original runtime descriptor differs')
    return base

def lock_policy(lock):
    side=lock['side'];base=verify(side,lock['project_files'],lock['diagnostic_overlay_sha256'])
    need(lock.get('diagnostic_only') is True and lock.get('release_artifact_identity_claim') is False,'Mislabelled diagnostic artifact')
    need(lock.get('artifact_kind')=='paused-visibility-diagnostic-web','Diagnostic artifact kind differs')
    need(lock['bound_files_sha256']=={k:sha(p) for k,p in binding_inputs(side).items()},'Diagnostic policy binding changed')
    need({k:lock[k] for k in ('source_commit','game_tree','build')}==execution_identity(side),'Product source identity differs')
    return base

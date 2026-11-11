"""Pure diagnostic binding validator; intentionally not the construction contract."""
from pathlib import Path
import hashlib,json,re
from source_pins import SIDE,BUILD,SOURCE_COMMIT,GAME_TREE,GAME_SOURCE_SHA256,OVERLAY_SHA256

PREPARED_SCENARIO='visibility-paused-startup'
PREPARED_PROFILE='portrait'
PREPARED_VIEWPORT=[390,844]
EXPORT_NAMES={'index.html','index.js','index.wasm','index.pck','index.png','index.icon.png','index.apple-touch-icon.png','index.audio.worklet.js','index.audio.position.worklet.js'}
CHAIN_FIELDS=('source_archive_sha256','import_manifest_sha256','export_manifest_sha256','source_chain_verification_sha256','diagnostic_source_inventory_sha256','export_artifact_sha256','qa_inventory_sha256')

def need(ok,message):
    if not ok:raise ValueError(message)

def digest(value):return isinstance(value,str) and re.fullmatch('[0-9a-f]{64}',value) is not None

def inventory(value):
    need(isinstance(value,dict) and value,'Missing exact file inventory')
    for name,sha in value.items():
        need(isinstance(name,str) and not name.startswith('/') and '\\' not in name and all(p not in ('','.','..') for p in name.split('/')) and digest(sha),'Invalid inventory entry')

def qa_code_inventory_sha256():
    # Scenario/expected-export pins cannot contain their own full-bundle digest.
    # The original host lock separately hashes EVERY QA file including both JSONs.
    root=Path(__file__).resolve().parent;files={}
    for path in sorted(root.iterdir()):
        if path.suffix in ('.py','.mjs') or path.name in ('package.json','package-lock.json'):
            need(path.is_file() and not path.is_symlink(),'Nonregular QA code file')
            files[path.name]=hashlib.sha256(path.read_bytes()).hexdigest()
    need(files,'Empty QA code inventory')
    return hashlib.sha256(json.dumps(files,sort_keys=True,separators=(',',':')).encode()).hexdigest()

def validate(manifest,lock,manifest_sha256):
    need(manifest.get('schema')=='vc-paused-diagnostic-binding-v1','Wrong diagnostic scenario schema')
    need(all(manifest.get(k) is True for k in ('reviewed','bound','execution_approved')) and lock.get('reviewed') is True,'Diagnostic source/export/execution review missing')
    need(manifest.get('diagnostic_only') is True and manifest.get('release_artifact_identity_claim') is False,'Mislabelled diagnostic bytes')
    need(manifest.get('scenario')==PREPARED_SCENARIO and manifest.get('profile')==lock.get('profile')==PREPARED_PROFILE and manifest.get('viewport')==PREPARED_VIEWPORT,'Wrong fixed paused scenario/viewport')
    for key,wanted in [('build',BUILD),('source_commit',SOURCE_COMMIT),('game_tree',GAME_TREE),('game_source_sha256',GAME_SOURCE_SHA256),('overlay_sha256',OVERLAY_SHA256)]:
        need(manifest.get(key)==wanted,'Exact product/observer identity differs: '+key)
    need(manifest.get('side')==SIDE,'Wrong exact pair side')
    for key in CHAIN_FIELDS:need(digest(manifest.get(key)),'Independent diagnostic chain unbound: '+key)
    need(manifest['qa_inventory_sha256']==qa_code_inventory_sha256(),'Reviewed QA code inventory differs')
    inventory(manifest.get('files_sha256'));need(set(manifest['files_sha256'])==EXPORT_NAMES,'Exact diagnostic Web output set differs')
    for key in ('build','source_commit','files_sha256'):need(lock.get(key)==manifest[key],'Host lock identity differs: '+key)
    need(digest(manifest_sha256) and lock.get('qa_files_sha256',{}).get('scenario-manifest.json')==manifest_sha256,'Scenario is not byte-bound in full host QA inventory')

"""Pure source-binding policy. No process launch or resource sampling."""
import hashlib,json
from pathlib import Path
BASELINE_SHA = '6b925bbfcc97557c2d2b42c362348529762cd025b3447286240533ebe758a652'
BRANCH = 'refs/heads/ci/rendered-match-diagnostic-vc-79ebcaef19e3'
NAMES = {'diagnostic/full_rendered_match.gd','diagnostic/full_rendered_match.tscn'}
OLD = 'run/main_scene="res://main_menu.tscn"'
NEW = 'run/main_scene="res://diagnostic/full_rendered_match.tscn"'
def need(ok,message):
    if not ok: raise ValueError(message)
def sha(path):
    with Path(path).open('rb') as f: return hashlib.file_digest(f,'sha256').hexdigest()
def baseline():
    p=Path(__file__).resolve().parents[1]/'baseline.json'
    need(sha(p)==BASELINE_SHA,'Baseline pin differs')
    return json.loads(p.read_text())
def override(data):
    need(data.count(OLD)==1,'Ambiguous main scene')
    return data.replace(OLD,NEW).encode()
def verify(files,overlay):
    base=baseline()
    need(set(overlay)==NAMES,'Overlay scope differs')
    expected=dict(base['project_files']); expected.update(overlay)
    expected['project.godot']=hashlib.sha256(override(base['original_project_text'])).hexdigest()
    need(files==expected and len(files)==234,'Diagnostic inventory differs from baseline plus permitted overlay')
    return base
def lock_policy(lock):
    base=verify(lock['project_files'],lock['diagnostic_overlay_sha256'])
    need(lock.get('diagnostic_only') is True and lock.get('release_artifact_identity_claim') is False,'Mislabelled diagnostic artifact')
    need(lock.get('baseline_sha256')==BASELINE_SHA,'Baseline identity differs')
    need(lock.get('diagnostic_policy_sha256')==sha(__file__),'Source policy differs')
    need(lock.get('artifact_kind')=='rendered-match-diagnostic-web','Artifact kind differs')
    need((lock.get('source_commit'),lock.get('game_tree'),lock.get('build'))==(base['source_commit'],base['game_tree'],base['build']),'Product identity differs')
def import_policy(package,entries):
    d=package['diagnostic_binding'];base=verify(entries,d['overlay_sha256'])
    need(d['baseline_sha256']==BASELINE_SHA and d['policy_sha256']==sha(__file__),'Import diagnostic policy binding differs')
    need(package['public_runtime_descriptor']==base['runtime'],'Original product runtime descriptor differs')
    return base

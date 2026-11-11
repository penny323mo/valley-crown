"""Fail-closed diagnostic artifact-chain gate. No retrieval, browser or host probe."""
from pathlib import Path
import argparse,hashlib,json,re
from source_pins import BUILD,SOURCE_COMMIT,GAME_TREE,GAME_SOURCE_SHA256,OVERLAY_SHA256,OVERLAY_SCENE_SHA256
from validate_visibility_binding import validate,need,digest,inventory,PREPARED_PROFILE

def validate_pins(expected,scenario,scenario_digest):
    need(expected.get('schema')=='vc-paused-diagnostic-browser-export-pins-v1','Wrong diagnostic artifact-pin schema')
    need(all(expected.get(k) is True for k in ('reviewed','bound','source_chain_verified')),'Independent diagnostic artifact review remains disabled/unbound')
    need(expected.get('diagnostic_only') is True and expected.get('release_artifact_identity_claim') is False,'Not diagnostic-only artifact pins')
    need(expected.get('build')==BUILD and expected.get('game_source_sha256')==GAME_SOURCE_SHA256 and expected.get('side')==scenario.get('side'),'Product/side pin differs')
    for field in ('artifact_id','export_run_id'):need(re.fullmatch('[1-9][0-9]*',str(expected.get(field,''))) is not None,'Missing actual '+field)
    for field in ('artifact_zip_sha256','export_manifest_sha256','source_chain_verification_sha256','diagnostic_source_inventory_sha256','qa_inventory_sha256'):
        need(digest(expected.get(field)),'Missing independent '+field)
    export=expected.get('export_manifest',{})
    need(export.get('schema')=='vc-paused-diagnostic-web-artifact-v1' and export.get('diagnostic_only') is True and export.get('release_artifact_identity_claim') is False,'Wrong actual diagnostic export manifest')
    need((export.get('product_build'),export.get('product_source_commit'),export.get('product_game_tree'))==(BUILD,SOURCE_COMMIT,GAME_TREE),'Actual export product identity differs')
    need(export.get('side')==expected['side'],'Actual export side differs')
    need(str(export.get('diagnostic_export_run_id',''))==str(expected['export_run_id']) and type(export.get('diagnostic_export_run_attempt')) is int and export.get('diagnostic_export_run_attempt')==1,'Actual diagnostic export run/attempt differs')
    need(re.fullmatch('[0-9a-f]{40}',export.get('diagnostic_export_commit','')) is not None,'Actual export adapter commit missing')
    need(export.get('diagnostic_overlay_sha256')=={'diagnostic/visibility_paused.gd':OVERLAY_SHA256,'diagnostic/visibility_paused.tscn':OVERLAY_SCENE_SHA256},'Actual observer source differs')
    for key in ('source_archive_sha256','import_manifest_sha256','export_lock_sha256','guard_receipt_sha256'):need(digest(export.get(key)),'Actual diagnostic chain incomplete: '+key)
    files=expected.get('files_sha256');inventory(files);inventory(export.get('files_sha256'))
    need(files.get('diagnostic-export-manifest.json')==expected['export_manifest_sha256'],'Raw actual export manifest bytes unbound')
    for label in ('clean-a','clean-b'):
        prefix='artifacts/'+label+'/'
        need({n[len(prefix):]:h for n,h in files.items() if n.startswith(prefix)}==export['files_sha256'],'Repeat diagnostic output inventory differs: '+label)
    for key in ('source_archive_sha256','import_manifest_sha256'):need(scenario.get(key)==export[key],'Scenario chain differs: '+key)
    for key in ('export_manifest_sha256','source_chain_verification_sha256','diagnostic_source_inventory_sha256','qa_inventory_sha256'):
        need(scenario.get(key)==expected[key],'Scenario independent binding differs: '+key)
    need(scenario.get('export_artifact_sha256')==expected['artifact_zip_sha256'],'Scenario artifact ZIP differs')
    need(scenario.get('files_sha256')==export['files_sha256'],'Scenario served bytes differ')
    lock={'reviewed':True,'build':BUILD,'source_commit':SOURCE_COMMIT,'profile':PREPARED_PROFILE,'files_sha256':export['files_sha256'],'qa_files_sha256':{'scenario-manifest.json':scenario_digest}}
    validate(scenario,lock,scenario_digest)

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--expected',type=Path,required=True);parser.add_argument('--scenario',type=Path,required=True);parser.add_argument('--github-output',type=Path)
    args=parser.parse_args();data=args.scenario.read_bytes();expected=json.loads(args.expected.read_text());validate_pins(expected,json.loads(data),hashlib.sha256(data).hexdigest())
    if args.github_output:
        with args.github_output.open('a') as f:f.write('artifact_id='+str(expected['artifact_id'])+'\nrun_id='+str(expected['export_run_id'])+'\n')
    print('Reviewed diagnostic source/import/export/PCK chain pins validated; no browser launched.')

if __name__=='__main__':main()

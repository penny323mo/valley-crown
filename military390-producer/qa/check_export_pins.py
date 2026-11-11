"""Fail-closed read-only identity gate before artifact retrieval/preparation."""
import argparse
import hashlib
import json
from pathlib import Path
import re
from guard_contract import BUILD
from source_pins import GAME_TREE, GAME_SOURCE_SHA256
from run_browser import SOURCE_COMMIT
from validate_construction_binding import validate, PREPARED_PROFILE


def validate_pins(expected, scenario, scenario_digest):
    if expected.get('reviewed') is not True:
        raise ValueError('Final menu export pins remain disabled')
    if expected.get('build') != BUILD or expected.get('export_manifest', {}).get('source_commit') != SOURCE_COMMIT:
        raise ValueError('Reviewed guard source identity differs from export pins')
    for field in ('artifact_id','export_run_id'):
        if not re.fullmatch(r'[1-9][0-9]*',str(expected.get(field,''))):
            raise ValueError('Missing exact ' + field)
    if not re.fullmatch('[0-9a-f]{64}',str(expected.get('artifact_zip_sha256',''))):
        raise ValueError('Missing independently verified artifact ZIP identity')
    if expected.get('export_manifest',{}).get('game_tree') != GAME_TREE:
        raise ValueError('Missing game tree identity')
    if expected.get('game_source_sha256') != GAME_SOURCE_SHA256 or scenario.get('game_source_sha256') != GAME_SOURCE_SHA256 or scenario.get('game_tree') != GAME_TREE:
        raise ValueError('Exact game source/tree pins differ')
    files=expected.get('files_sha256')
    if not isinstance(files,dict) or not files:
        raise ValueError('Complete downloaded artifact inventory missing')
    for name,digest in files.items():
        if name.startswith('/') or '\\' in name or any(part in ('','..','.') for part in name.split('/')) or not re.fullmatch('[0-9a-f]{64}',digest):
            raise ValueError('Invalid artifact inventory entry')
    export=expected['export_manifest']
    if export.get('build') != BUILD:
        raise ValueError('Export manifest build mismatch')
    lock={'reviewed':True,'build':BUILD,'source_commit':SOURCE_COMMIT,'profile':PREPARED_PROFILE,
          'files_sha256':export.get('files_sha256'),'qa_files_sha256':{'scenario-manifest.json':scenario_digest}}
    validate(scenario,lock,scenario_digest)


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--expected',type=Path,required=True)
    parser.add_argument('--scenario',type=Path,required=True)
    parser.add_argument('--github-output',type=Path)
    args=parser.parse_args()
    expected=json.loads(args.expected.read_text()); data=args.scenario.read_bytes()
    validate_pins(expected,json.loads(data),hashlib.sha256(data).hexdigest())
    if args.github_output:
        with args.github_output.open('a') as stream:
            stream.write('artifact_id='+str(expected['artifact_id'])+'\nrun_id='+str(expected['export_run_id'])+'\n')
    print('Final reviewed menu source/export pins validated; no browser launched.')


if __name__=='__main__': main()

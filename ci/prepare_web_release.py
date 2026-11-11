#!/usr/bin/env python3
"""Prepare the current already-public game for reviewed export; no game launch."""
from pathlib import Path
import argparse
import json
import os
import prepare_public_capture as source

BRANCH = 'refs/heads/ci/touch-focus-web-vc-79ebcaef19e3'
OUTPUT_FILES = sorted(['index.html', 'index.js', 'index.wasm', 'index.pck', 'index.png', 'index.icon.png', 'index.apple-touch-icon.png', 'index.audio.worklet.js', 'index.audio.position.worklet.js'])

def admitted():
    source.need(os.environ.get('GITHUB_ACTIONS') == 'true' and os.environ.get('RUNNER_ENVIRONMENT') == 'github-hosted', 'Fresh GitHub-hosted runner required')
    source.need(os.environ.get('GITHUB_REPOSITORY') == 'penny323mo/valley-crown' and os.environ.get('GITHUB_REF') == BRANCH and os.environ.get('GITHUB_RUN_ATTEMPT') == '1', 'Wrong repository/branch/attempt')

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('phase', choices=['prepare', 'engine'])
    parser.add_argument('--work', type=Path, required=True)
    args = parser.parse_args()
    admitted()
    root = Path(__file__).resolve().parents[1]
    work = args.work.resolve()
    if args.phase == 'prepare':
        result = source.prepare(root / 'game', work, source.entries_from_git(root))
        capture = json.loads((work / 'capture-lock.json').read_text())
        lock = dict(schema='vc-web-export-v1', reviewed_for_execution=os.environ.get('CONSTRUCTION_EXECUTION_APPROVED')=='true',
            contracts_reviewed_for_execution=os.environ.get('CONSTRUCTION_EXECUTION_APPROVED')=='true',
            contracts_stop_reviewed_for_execution=os.environ.get('CONSTRUCTION_EXECUTION_APPROVED')=='true',
            contracts_consolidated_reviewed_for_execution=os.environ.get('CONSTRUCTION_EXECUTION_APPROVED')=='true',
            full_match_reviewed_for_execution=os.environ.get('FULL_MATCH_EXECUTION_APPROVED')=='true',
            full_match_runner_sha256=source.sha(root / 'ci/run_full_match.py'),
            full_match_supervisor_sha256=source.sha(root / 'ci/run_logic.py'),
            full_match_harness_sha256=source.sha(root / 'ci/full_match.gd'),
            full_match_validator_sha256=source.sha(root / 'ci/validate_full_match.py'),
            military_reviewed_for_execution=os.environ.get('MILITARY_EXECUTION_APPROVED')=='true',
            military_runner_sha256=source.sha(root / 'ci/run_military.py'),
            military_supervisor_sha256=source.sha(root / 'ci/run_logic.py'),
            military_validator_sha256=source.sha(root / 'ci/validate_military.py'),
            military_names_sha256=source.sha(root / 'ci/military_contract.json'),
            faction_reviewed_for_execution=os.environ.get('FACTION_EXECUTION_APPROVED')=='true',
            faction_runner_sha256=source.sha(root / 'ci/run_faction.py'),
            faction_supervisor_sha256=source.sha(root / 'ci/run_logic.py'),
            faction_validator_sha256=source.sha(root / 'ci/validate_faction.py'),
            faction_harness_sha256=source.sha(root / 'game/tests/faction_publish_contract.gd'),
            contracts_runner_sha256=source.sha(root / 'ci/run_contracts.py'),
            contracts_supervisor_sha256=source.sha(root / 'ci/run_logic.py'),
            contracts_validator_sha256=source.sha(root / 'ci/validate_contracts.py'),
            contracts_names_sha256=source.sha(root / 'ci/check_contract.json'),
            source_commit=source.SOURCE_COMMIT, game_tree=source.GAME_TREE, build=source.BUILD,
            godot_sha256=source.ENGINE_SHA,
            web_release_sha256='1446f79dc12f60ce5d244c39fb6628ec298337ca5c4f91a16491feea72aa1bc9',
            runner_sha256=source.sha(root / 'ci/run_export.py'),
            owned_process_sha256=source.sha(root / 'ci/owned_process.py'),
            source_archive_sha256=capture['source_archive_sha256'],
            import_manifest_sha256=capture['import_manifest_sha256'],
            import_adapter_sha256=source.sha(root / 'ci/guarded_manifest_ci.py'),
            project_files=capture['project_files'], allowed_generated_uid_files=capture['allowed_generated_uid_files'],
            output_files=OUTPUT_FILES)
        from run_export import validate_lock
        validate_lock(dict(lock, reviewed_for_execution=True))
        source.dump(work / 'export-lock.json', lock)
        print(json.dumps(result))
    else:
        source.need(os.environ.get('CONSTRUCTION_EXECUTION_APPROVED') == 'true', 'Execution approval remains pending')
        import official_download as download
        source.need((work / 'export-lock.json').is_file(), 'Public source preparation missing')
        download.download(download.ENGINE_URL, work / 'engine.zip')
        download.safe_extract(work / 'engine.zip', {download.ENGINE_NAME: source.ENGINE_SHA}, work / 'engine', max_total=256*1024*1024, max_member=256*1024*1024)
        (work / 'engine' / download.ENGINE_NAME).chmod(0o755)
        print('Pinned official engine prepared without launch')

if __name__ == '__main__':
    main()

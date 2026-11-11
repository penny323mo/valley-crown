#!/usr/bin/env python3
"""Package only verified Web bytes and public legal notices; no deploy."""
from pathlib import Path
import argparse
import hashlib
import json
import os
import shutil
from prepare_web_release import admitted, OUTPUT_FILES
from prepare_public_capture import BUILD, SOURCE_COMMIT, GAME_TREE, need, sha

NOTICES = ['GODOT-LICENSES.txt', 'THIRD_PARTY_NOTICES.txt', 'assets/fonts/NOTO-LICENSE.txt', 'assets/fonts/DEJAVU-LICENSE.txt', 'assets/fonts/MENU-TITLE-LICENSE.txt'] + [
    'art/action_characters/licenses/' + name for name in ['quaternius-outfits.txt', 'kaykit-animations.txt', 'quaternius-ual.txt', 'quaternius-ual2.txt', 'quaternius-base.txt']]

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--work', type=Path, required=True)
    work = parser.parse_args().work.resolve()
    admitted()
    receipt = json.loads((work / 'exports/web-export-receipt.json').read_text())
    lock = json.loads((work / 'export-lock.json').read_text())
    need(receipt.get('passed') is True and receipt.get('build') == BUILD and receipt.get('source_commit') == SOURCE_COMMIT and receipt.get('game_tree') == GAME_TREE, 'Export evidence identity failed')
    need(len(receipt['exports']) == 2 and all(x['passed'] is True and x['cleanup_complete'] is True and x['test_dependencies'] is False and not x['unexpected_descendants'] for x in receipt['exports']), 'Export guard incomplete')
    need(receipt['exports'][0]['output_sha256'] == receipt['exports'][1]['output_sha256'] and sorted(receipt['exports'][0]['output_sha256']) == OUTPUT_FILES, 'Repeat export mismatch')
    contracts = json.loads((work / 'construction-contracts/construction-contracts-receipt.json').read_text())
    need(contracts.get('passed') is True and contracts.get('post_run_binding_matches') is True and contracts.get('build') == BUILD and contracts.get('source_commit') == SOURCE_COMMIT and contracts.get('game_tree') == GAME_TREE, 'Construction contracts failed or identity differs')
    need([row['suite'] for row in contracts['suites']] == ['construction_status', 'construction_status_hud', 'mobile_stop_control_contract', 'mobile_stop_control_phone', 'stance_target_cancel_phone', 'contextual_touch_contract', 'contextual_touch_phone', 'main_menu_flow_contract'], 'Consolidated suites incomplete')
    candidate = work / 'candidate'
    candidate.mkdir()
    for number, label in [(1, 'clean-a'), (2, 'clean-b')]:
        source = work / 'exports' / ('export-' + str(number)) / 'web'
        expected = receipt['exports'][number-1]['output_sha256']
        need(not any(p.is_symlink() for p in source.rglob('*')), 'Export symlink')
        actual = {p.relative_to(source).as_posix(): sha(p) for p in source.rglob('*') if p.is_file()}
        need(actual == expected, 'Export changed after monitoring')
        shutil.copytree(source, candidate / 'artifacts' / label)
    for name in NOTICES:
        source = work / 'project' / name
        need(not source.is_symlink() and source.is_file() and sha(source) == lock['project_files'][name], 'Public notice differs from tested source')
        target = candidate / 'clean-a' / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, target)
    run = os.environ['GITHUB_RUN_ID']
    manifest = dict(build=BUILD, source_commit=SOURCE_COMMIT, game_tree=GAME_TREE,
        export_run='https://github.com/penny323mo/valley-crown/actions/runs/' + run,
        export_scope='Two byte-identical repeat Web exports from one clean guarded import. Browser validation is a separate required release gate.',
        files_sha256=receipt['exports'][0]['output_sha256'])
    (work / 'web-manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    files = {p.relative_to(candidate).as_posix(): sha(p) for p in candidate.rglob('*') if p.is_file()}
    summary = dict(build=BUILD, files_sha256=files, export_manifest=manifest,
        guard_receipt_sha256=sha(work / 'exports/web-export-receipt.json'), not_yet_deployed=True)
    (work / 'release-summary.json').write_text(json.dumps(summary, indent=2) + '\n')
    print('WEB_RELEASE_SUMMARY ' + json.dumps(summary, sort_keys=True))

if __name__ == '__main__':
    main()

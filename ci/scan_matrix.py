#!/usr/bin/env python3
"""Exact prepared-matrix schema plus proven process/provenance/privacy admission."""
from pathlib import Path
import argparse
import json
import scan_evidence as base
from matrix_contracts import schema, KINDS


def validate_scenario(report, lock):
    mode = lock['capture_contract']['mode']; contract = schema(mode)
    base.require(lock['capture_contract'] == contract['capture_contract'] and lock.get('matrix_schema') == contract, 'Matrix contract differs')
    frames = report['frames']
    base.require([{'label': row['label'], 'framebuffer': row['framebuffer']} for row in frames] == [{key: row[key] for key in ('label','framebuffer')} for row in contract['frames']], 'Matrix frame coverage differs')
    fixture = 'tests/occlusion_stencil_matrix.gd' if mode == 'occlusion_matrix' else 'tests/occlusion_viewport_lifecycle.gd'
    sources = ['scripts/observed_occlusion.gd', 'scripts/observed_character_presenter.gd', 'scripts/action_character.gd',
               'assets/mature/shaders/observed_visibility_mask.gdshader', 'assets/mature/shaders/observed_occlusion.gdshader',
               'tests/occlusion_render_fixture.gd', fixture]
    base.require(report.get('source_sha256') == {name: lock['project_files'][name] for name in sources}, 'Source mismatch')
    for index, frame in enumerate(frames):
        base.require(frame.get('capture_timing') == contract['capture_timing'] and frame.get('fixture_sha256') == lock['project_files'][fixture], 'Matrix timing/source differs')
        poses = frame.get('animation_poses')
        base.require(type(poses) is list and len(poses) == contract['frames'][index]['visible_rig_count'] <= 24, 'Matrix pose count differs')
        for pose in poses:
            base.pose_identity(pose, lock)
            base.require(type(pose.get('occlusion_authorized')) is bool and type(pose.get('overlay_enabled')) is bool, 'Matrix authorization metadata differs')
        if mode == 'occlusion_matrix' and '-unoccluded-' in frame['label']:
            kind, clip, _, toggle = frame['label'].split('-')
            base.require(kind in KINDS and len(poses) == 1 and poses[0]['kind'] == kind and poses[0]['clip'] == clip
                         and poses[0]['overlay_enabled'] is (toggle == 'on'), 'Matrix rig/action/toggle differs')
        if 'corpse' in frame['label']:
            base.require(all(p['occlusion_authorized'] is False and p['overlay_enabled'] is False for p in poses), 'Corpse overlay metadata differs')
        if frame['label'].startswith('cost-'):
            _, count, toggle = frame['label'].split('-')
            base.require(len(poses) == int(count) and all(p['overlay_enabled'] is (toggle == 'on') for p in poses), 'Matrix cost-rig coverage differs')
    checks = report.get('checks', [])
    base.require([row.get('name') for row in checks] == contract['checks'] and all(type(row.get('pass')) is bool for row in checks), 'Matrix check coverage differs')
    base.require(all(row['pass'] for row in checks if row['name'] in contract['critical_checks']), 'Matrix evidence production failed')
    failed = [row['name'] for row in checks if not row['pass']]
    base.require(type(report.get('failed')) is int and report['failed'] == len(failed)
                 and report.get('functional_checks_passed') is (not failed), 'Matrix functional result inconsistent')
    return [{'kind': 'controlled_matrix_check_failed', 'check': name} for name in failed]


base.validate_scenario = validate_scenario


def scan(directory, lock_path):
    lock = json.loads(lock_path.read_text()); contract = schema(lock['capture_contract']['mode'])
    guard = json.loads((directory / 'guard-receipt.json').read_text())
    base.require(guard.get('expected_framebuffer_sequence') == [row['framebuffer'] for row in contract['frames']]
                 and guard.get('expected_framebuffer') == contract['launch_framebuffer'], 'Matrix framebuffer sequence differs')
    return base.scan(directory, lock, base.sha(lock_path))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('directory', 'lock', 'report'): parser.add_argument('--' + name, type=Path, required=True)
    args = parser.parse_args(); base.require(not args.report.exists(), 'Refusing to replace scan evidence')
    try: result = scan(args.directory, args.lock)
    except Exception as exc: result = {'passed': False, 'error': base.safe_scan_exception(exc)}
    args.report.write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps({'evidence_admitted': result['passed'], 'visual_finding_count': len(result.get('visual_findings', [])), 'error': result.get('error')}, sort_keys=True))
    return 0 if result['passed'] else 1


if __name__ == '__main__': raise SystemExit(main())

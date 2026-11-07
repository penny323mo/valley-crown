#!/usr/bin/env python3
"""Recompute prepared matrix RGB assertions from admitted original PNGs, bounded RAM."""
from pathlib import Path
from functools import lru_cache
import argparse
import json
from check_pixel_gate import decoded_rgb
import scan_matrix
from matrix_contracts import schema, KINDS, OBSTACLES

base = scan_matrix.base


def metrics(a, b, world):
    base.require(len(a) == len(b) == len(world), 'Frame dimensions mismatch')
    visible = changed_visible = silhouette = 0; colors = set()
    for x, y, z in zip(a, b, world):
        if x != z:
            visible += 1; changed_visible += x != y
        elif x != y:
            silhouette += 1; colors.add(y)
    return {'visible': visible, 'changed_visible': changed_visible, 'silhouette': silhouette, 'colors': len(colors)}


def differences(a, b):
    base.require(len(a) == len(b), 'Frame dimensions mismatch')
    return sum(x != y for x, y in zip(a, b))


def footprint(a, b, c, d):
    base.require(len(a) == len(b) == len(c) == len(d), 'Frame dimensions mismatch')
    return sum((x != y) != (z != w) for x, y, z, w in zip(a, b, c, d))


def evaluate(mode, image, frames):
    checks = []
    def check(name, okay, detail): checks.append({'name': name, 'pass': bool(okay), 'detail': detail})
    def equal(a, b):
        count = differences(image(a), image(b)); check(a + ' == ' + b, count == 0, {'changed_pixels': count})
    def nonempty(a, b):
        count = differences(image(a), image(b)); check(a + ' nonempty versus ' + b, count > 30, {'changed_pixels': count})
    def full(reference, empty, covered, wall):
        count = footprint(image(reference), image(empty), image(covered), image(wall))
        check(covered + ' exact whole footprint', count == 0, {'mismatch_pixels': count})
    def full_stats(off, on, wall):
        values = metrics(image(off), image(on), image(wall))
        check(on + ' fully covered flat silhouette', values['visible'] == 0 and values['silhouette'] > 30 and values['colors'] == 1, values)
        equal(off, wall)
    if mode == 'occlusion_matrix':
        for kind in KINDS:
            for clip in ('idle', 'walk', 'attack'):
                prefix = kind + '-' + clip + '-unoccluded'
                equal(prefix + '-off', prefix + '-on')
                colors = len(set(image(prefix + '-off')))
                check(prefix + ' not a blank framebuffer', colors > 1, {'colors': colors})
        for label in OBSTACLES:
            values = metrics(image(label + '-off'), image(label + '-on'), image(label + '-object-only'))
            check(label + ' nonvacuous exact partial mask', values['visible'] > 30 and values['changed_visible'] == 0 and values['silhouette'] > 30 and values['colors'] == 1, values)
        equal('object-behind-unit-off', 'object-behind-unit-on')
        empty = 'temporal-empty-reference'; a = 'temporal-unit-a-reference'; b = 'temporal-unit-b-reference'; wall = 'temporal-wall-only'
        nonempty(a, empty); nonempty(b, empty); nonempty(a, b)
        equal(a, 'temporal-a-visible-mask-written')
        full_stats('temporal-b-fully-occluded-off', 'temporal-b-fully-occluded-on', wall)
        full(b, empty, 'temporal-b-fully-occluded-on', wall)
        full(a, empty, 'temporal-return-a-fully-occluded', wall)
        equal(b, 'temporal-b-visible-again'); equal(empty, 'temporal-all-units-hidden')
        full(a, empty, 'temporal-occluded-after-empty-frame', wall)
        for prefix in ('overlapping-units', 'moving-overlap-1', 'moving-overlap--1', 'animated-source-local-trs'):
            equal(prefix + '-off', prefix + '-on')
        equal('source-tool-hidden', 'source-tool-absent-reference'); equal('corpse-overlay-off', 'corpse-reenable-denied')
        for count in (1, 12, 24):
            before = frames['cost-' + str(count) + '-off']['visible_draw_calls']; after = frames['cost-' + str(count) + '-on']['visible_draw_calls']
            check('exact local draw budget ' + str(count), type(before) is int and type(after) is int and after - before == 4 * count,
                  {'off': before, 'on': after, 'delta': after - before, 'expected': 4 * count, 'unrelated_world_meshes': 40})
    elif mode == 'occlusion_lifecycle':
        for index in range(4):
            prefix = 'resize-' + str(index)
            nonempty(prefix + '-normal-off', prefix + '-empty')
            equal(prefix + '-normal-off', prefix + '-normal-on')
            full_stats(prefix + '-covered-off', prefix + '-covered-on', prefix + '-wall-only')
            full(prefix + '-normal-off', prefix + '-empty', prefix + '-covered-on', prefix + '-wall-only')
            equal(prefix + '-normal-off', prefix + '-normal-restored')
        equal('camera-layer-excluded-unit', 'camera-layer-excluded-reference')
        nonempty('camera-layer-included-unit', 'camera-layer-excluded-reference')
        nonempty('clip-unit-off', 'clip-empty-reference'); nonempty('clip-original-unit', 'clip-unit-off')
        equal('clip-unit-off', 'clip-unit-on')
        absent = 'observation-absent-reference'; visible = 'observation-visible-enemy-behind-wall'
        nonempty(visible, absent); equal(visible, 'observation-enemy-reappears')
        for name in ('enemy-enters-fog', 'unwitnessed-death', 'witnessed-corpse-behind-wall', 'corpse-enters-fog'):
            equal('observation-' + name, absent)
    else: raise ValueError('Unreviewed matrix mode')
    return checks


def run(directory, lock_path, report_path):
    base.require(not report_path.exists(), 'Refusing to replace scan evidence')
    result = {'passed': False, 'scope': 'Strict raw-pixel prepared matrix only; no phone/performance/material acceptance'}
    try:
        admission = scan_matrix.scan(directory, lock_path)
        base.require(admission['passed'] is True, 'Evidence admission failed')
        lock = json.loads(lock_path.read_text()); mode = lock['capture_contract']['mode']
        report = json.loads((directory / 'frames/capture-report.json').read_text())
        frames = {row['label']: row for row in report['frames']}
        @lru_cache(maxsize=4)
        def image(label): return decoded_rgb(directory / 'frames' / frames[label]['image'])
        checks = evaluate(mode, image, frames); image.cache_clear()
        failed = [row for row in checks if not row['pass']]
        result.update(build=lock['build'], mode=mode, checks=checks, failed=len(failed),
                      passed=not failed and report['failed'] == 0 and report['functional_checks_passed'] is True,
                      fixture_functional_failures=report['failed'], frame_count=len(frames),
                      frame_sha256={row['image']: row['image_sha256'] for row in report['frames']},
                      lock_sha256=base.sha(lock_path), capture_report_sha256=base.sha(directory / 'frames/capture-report.json'))
    except Exception as exc: result['error'] = base.safe_scan_exception(exc)
    report_path.write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps({'pixel_gate_passed': result['passed'], 'mode': result.get('mode'), 'failed': result.get('failed'),
                      'fixture_functional_failures': result.get('fixture_functional_failures'), 'error': result.get('error')}, sort_keys=True))
    return 0 if result['passed'] else 1


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('directory', 'lock', 'report'): parser.add_argument('--' + name, type=Path, required=True)
    args = parser.parse_args(); raise SystemExit(run(args.directory, args.lock, args.report))

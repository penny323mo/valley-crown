#!/usr/bin/env python3
"""Read-only strict pixel acceptance after unchanged source/process/privacy admission.

Decodes the actual six PNGs; never synthesizes, rewrites or edits evidence images.
"""
from pathlib import Path
import argparse
import json
import struct
import zlib
import scan_occlusion

base = scan_occlusion.base


def decoded_rgb(path):
    # The existing bounded parser validates CRCs, dimensions, chunk allowlist,
    # decompression limits and layout first. Decode only that accepted layout.
    base.png_info(path, minimum_colors=1)
    data = path.read_bytes(); offset = 8; packed = bytearray()
    while offset < len(data):
        length = struct.unpack('>I', data[offset:offset + 4])[0]
        kind = data[offset + 4:offset + 8]; body = data[offset + 8:offset + 8 + length]
        if kind == b'IHDR':
            width, height, _, color, _, _, _ = struct.unpack('>IIBBBBB', body)
            channels = 3 if color == 2 else 4
        if kind == b'IDAT': packed.extend(body)
        offset += length + 12
    stride = width * channels; expected = height * (stride + 1)
    decoder = zlib.decompressobj(); raw = decoder.decompress(packed, expected + 1)
    base.require(len(raw) == expected and decoder.eof and not decoder.unconsumed_tail and not decoder.unused_data, 'PNG decompression size/stream mismatch')
    previous = bytearray(stride); pixels = []
    for y in range(height):
        start = y * (stride + 1); mode = raw[start]; row = bytearray(raw[start + 1:start + 1 + stride])
        for x in range(stride):
            a = row[x - channels] if x >= channels else 0; b = previous[x]
            c = previous[x - channels] if x >= channels else 0
            prediction = 0
            if mode == 1: prediction = a
            elif mode == 2: prediction = b
            elif mode == 3: prediction = (a + b) // 2
            elif mode == 4:
                p = a + b - c; distances = (abs(p - a), abs(p - b), abs(p - c))
                prediction = (a, b, c)[distances.index(min(distances))]
            row[x] = (row[x] + prediction) & 255
        pixels.extend(bytes(row[x:x + 3]) for x in range(0, stride, channels))
        previous = row
    return pixels


def pixel_metrics(images):
    normal_off, normal_on, partial_off, partial_on, hidden, absent = images
    base.require(len({len(image) for image in images}) == 1 and len(normal_off) > 0, 'Frame dimensions mismatch')
    visible = changed_visible = silhouette = 0; colors = set()
    for a, b, world in zip(partial_off, partial_on, hidden):
        if a != world:
            visible += 1; changed_visible += a != b
        elif a != b:
            silhouette += 1; colors.add(b)
    return {
        'normal_changed_pixels': sum(a != b for a, b in zip(normal_off, normal_on)),
        'partial_visible_unit_pixels': visible, 'partial_changed_visible_pixels': changed_visible,
        'silhouette_pixels': silhouette, 'silhouette_colors': len(colors),
        'hidden_changed_pixels': sum(a != b for a, b in zip(hidden, absent)),
    }


def passes(metrics):
    return (metrics['normal_changed_pixels'] == 0 and metrics['partial_visible_unit_pixels'] > 30
            and metrics['partial_changed_visible_pixels'] == 0 and metrics['silhouette_pixels'] > 30
            and metrics['silhouette_colors'] == 1 and metrics['hidden_changed_pixels'] == 0)


def run(directory, lock_path, report_path):
    base.require(not report_path.exists(), 'Refusing to replace scan evidence')
    result = {'passed': False, 'scope': 'Strict exact-RGB six-frame native stencil gate; not phone/performance/art acceptance'}
    try:
        lock = json.loads(lock_path.read_text())
        admission = base.scan(directory, lock, base.sha(lock_path))
        base.require(admission['passed'] is True, 'Evidence admission failed')
        report = json.loads((directory / 'frames/capture-report.json').read_text())
        expected_sources = ['scripts/observed_occlusion.gd', 'assets/mature/shaders/observed_visibility_mask.gdshader',
                            'assets/mature/shaders/observed_occlusion.gdshader', 'tests/occlusion_render_fixture.gd',
                            'tests/occlusion_stencil_contract.gd']
        base.require(report.get('source_sha256') == {name: lock['project_files'][name] for name in expected_sources}, 'Source mismatch')
        metrics = pixel_metrics([decoded_rgb(directory / 'frames' / row['image']) for row in report['frames']])
        check_rows = {row['name']: row for row in report['checks']}
        base.require(check_rows['normal visible mesh unchanged']['detail']['changed_pixels'] == metrics['normal_changed_pixels'], 'Recorded normal pixel count differs')
        partial = check_rows['partially visible unit fragments unchanged']['detail']
        base.require(partial == {'visible_unit_pixels': metrics['partial_visible_unit_pixels'],
                               'changed_visible_unit_pixels': metrics['partial_changed_visible_pixels'],
                               'silhouette_pixels': metrics['silhouette_pixels'], 'silhouette_colors': metrics['silhouette_colors']}, 'Recorded partial pixel counts differ')
        draw_delta = report['frames'][1]['visible_draw_calls'] - report['frames'][0]['visible_draw_calls']
        draw_contract = check_rows['only two local geometry passes added']['detail']
        base.require(draw_delta == draw_contract['measured_delta'], 'Recorded draw delta differs')
        result.update(build=lock['build'], metrics=metrics, measured_extra_draw_calls=draw_delta,
                      frame_sha256={row['image']: row['image_sha256'] for row in report['frames']},
                      lock_sha256=base.sha(lock_path), capture_report_sha256=base.sha(directory / 'frames/capture-report.json'),
                      functional_checks_passed=report['functional_checks_passed'],
                      passed=passes(metrics) and report['functional_checks_passed'] is True and report['failed'] == 0
                      and draw_delta == 4 == draw_contract['contract']['extra_surface_draws_max'])
    except Exception as exc:
        result['error'] = base.safe_scan_exception(exc)
    report_path.write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps({'pixel_gate_passed': result['passed'], 'metrics': result.get('metrics'), 'error': result.get('error')}, sort_keys=True))
    return 0 if result['passed'] else 1


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('directory', 'lock', 'report'):
        parser.add_argument('--' + name, type=Path, required=True)
    args = parser.parse_args()
    raise SystemExit(run(args.directory, args.lock, args.report))

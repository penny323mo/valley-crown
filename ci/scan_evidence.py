#!/usr/bin/env python3
"""Read-only screenshot provenance + artifact admission checks. Never edits pixels."""
from pathlib import Path
import argparse
import hashlib
import json
import re
import struct
import zlib

SIGNATURES = {
    'github_token': rb'(?:gh[pousr]_[A-Za-z0-9]{36,255}|github_pat_[A-Za-z0-9_]{40,255})',
    'aws_access_key': rb'AKIA[0-9A-Z]{16}',
    'openai_key': rb'sk-(?:proj-|svcacct-)?[A-Za-z0-9_-]{40,255}',
    'slack_token': rb'xox[baprs]-[A-Za-z0-9-]{20,255}',
    'private_key': rb'-----BEGIN (?:RSA |EC |DSA |OPENSSH |ENCRYPTED )?PRIVATE KEY-----',
    'private_source_path': rb'/(?:home/agent|workspace/scratch|workspace/shared|agent_notes|user_notes)/',
}


def require(ok, message):
    if not ok:
        raise ValueError(message)


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def png_info(path):
    data = path.read_bytes()
    require(len(data) < 8 * 1024 * 1024 and data[:8] == b'\x89PNG\r\n\x1a\n', 'PNG signature/size')
    offset, packed, dimensions, ended = 8, bytearray(), None, False
    while offset < len(data):
        require(offset + 12 <= len(data), 'Truncated PNG chunk')
        length = struct.unpack('>I', data[offset:offset + 4])[0]
        kind = data[offset + 4:offset + 8]
        require(offset + 12 + length <= len(data), 'PNG chunk exceeds file')
        body = data[offset + 8:offset + 8 + length]
        crc = struct.unpack('>I', data[offset + 8 + length:offset + 12 + length])[0]
        require(zlib.crc32(kind + body) & 0xffffffff == crc, 'PNG CRC failure')
        require(kind in (b'IHDR', b'IDAT', b'IEND', b'sRGB', b'gAMA', b'cHRM', b'pHYs'),
                'Unexpected metadata/chunk in unmodified framebuffer PNG')
        if kind == b'IHDR':
            require(dimensions is None and length == 13 and offset == 8, 'PNG IHDR invalid')
            width, height, depth, color, compression, filtering, interlace = struct.unpack('>IIBBBBB', body)
            require((width, height) in ((390, 844), (844, 390)), 'Unapproved framebuffer dimensions')
            require(depth == 8 and color in (2, 6) and compression == filtering == interlace == 0, 'Unsupported PNG layout')
            dimensions = (width, height, 3 if color == 2 else 4)
        elif kind == b'IDAT':
            require(dimensions is not None and not ended, 'PNG IDAT ordering')
            packed.extend(body)
        elif kind == b'IEND':
            require(length == 0, 'Invalid IEND'); ended = True
        offset += length + 12
        if ended:
            break
    require(ended and offset == len(data) and dimensions is not None, 'PNG trailing/missing data')
    width, height, channels = dimensions
    expected = height * (1 + width * channels)
    decoder = zlib.decompressobj()
    raw = decoder.decompress(packed, expected + 1)
    require(len(raw) == expected and decoder.eof and not decoder.unused_data and not decoder.unconsumed_tail,
            'PNG decompression size/stream mismatch')
    # Undo filters to check actual decoded RGB, not compressed-byte variety.
    stride = width * channels; previous = bytearray(stride); colors = set()
    for row_index in range(height):
        base = row_index * (stride + 1)
        mode = raw[base]; row = bytearray(raw[base + 1:base + 1 + stride])
        require(mode <= 4, 'Invalid PNG filter')
        for x in range(stride):
            a = row[x - channels] if x >= channels else 0
            b = previous[x]; c = previous[x - channels] if x >= channels else 0
            prediction = 0
            if mode == 1: prediction = a
            elif mode == 2: prediction = b
            elif mode == 3: prediction = (a + b) // 2
            elif mode == 4:
                p = a + b - c; distances = (abs(p-a), abs(p-b), abs(p-c))
                prediction = (a, b, c)[distances.index(min(distances))]
            row[x] = (row[x] + prediction) & 255
        if row_index % 4 == 0:
            for x in range(0, stride, channels * 4):
                colors.add(bytes(row[x:x + 3]))
        previous = row
    require(len(colors) >= 128, 'Framebuffer is blank or implausibly uniform')
    return {'width': width, 'height': height, 'sampled_rgb_colors': len(colors)}


def scan(directory, lock, lock_sha256):
    report_path = directory / 'frames/capture-report.json'
    report = json.loads(report_path.read_text())
    guard = json.loads((directory / 'guard-receipt.json').read_text())
    require(guard.get('passed') is True and guard.get('capture_completed') is True and
            guard.get('cleanup_complete') is True, 'Guard did not pass or cleanup is unconfirmed')
    require(guard.get('test_dependencies') is False, 'Fake/injected process evidence cannot be admitted')
    require(guard.get('diagnostic_only') is False, 'Diagnostic-only run cannot produce accepted visual artifacts')
    require(guard['input_sha256']['lock'] == lock_sha256, 'Guard lock identity differs')
    for key in ('harness', 'godot', 'supervisor'):
        require(guard['input_sha256'][key] == lock[key + '_sha256'], 'Guard tool identity differs: ' + key)
    generated = guard.get('generated_uid_sha256', {})
    require(set(generated) == set(lock['allowed_generated_uid_files']), 'Generated UID binding set differs')
    require(all(re.fullmatch(r'[0-9a-f]{64}', digest) for digest in generated.values()), 'Invalid generated UID hash binding')
    require(guard.get('original_file_count') == len(lock['project_files']) and
            guard.get('source_file_count') == len(lock['project_files']) + len(generated), 'Frozen inventory count differs')
    require(guard['build'] == report['build'] == lock['build'], 'Build identity mismatch')
    require(report.get('passed') is True and len(report['frames']) == report['frame_count'] == 10, 'Incomplete report')
    allowed = {'guard-receipt.json', 'godot.log', 'xvfb.log', 'frames/capture-report.json'}
    files, findings, poses = {}, [], set()
    previous_usec = -1
    for frame in report['frames']:
        name = frame['image']
        require(re.fullmatch(r'\d{3}-[a-z0-9-]+\.png', name) is not None, 'Unsafe frame name')
        allowed.update({'frames/' + name, 'frames/' + name + '.json'})
        path = directory / 'frames' / name
        require(frame['image_sha256'] == sha(path), 'PNG identity mismatch')
        require(json.loads(path.with_suffix('.png.json').read_text()) == frame, 'Frame metadata mismatch')
        require(frame['capture_kind'] == 'genuine_native_game_viewport', 'Unknown capture kind')
        require(frame['build'] == lock['build'] and frame['game_sha256'] == lock['project_files']['scripts/game.gd'], 'Source mismatch')
        require(frame['rules_sha256'] == lock['project_files']['scripts/rules.gd'], 'Rules mismatch')
        require(frame['monotonic_usec'] > previous_usec, 'Nonincreasing capture times')
        previous_usec = frame['monotonic_usec']
        require(frame['display'] == 'X11' and 'llvmpipe' in frame['adapter_name'].lower(), 'Not the reviewed renderer')
        require(frame['economy_audit_ok'] is True, 'Economy audit failed')
        info = png_info(path)
        require([info['width'], info['height']] == frame['framebuffer'] == guard['expected_framebuffer'], 'Frame dimensions mismatch')
        if frame['label'].startswith('woodcut-'):
            poses.add(json.dumps(frame['animation_poses'], sort_keys=True))
        files['frames/' + name] = {'sha256': sha(path), **info}
    sequence = [frame for frame in report['frames'] if frame['label'].startswith('woodcut-')]
    require(len({frame['image_sha256'] for frame in sequence}) >= 3, 'Sequence does not show changing rendered frames')
    if lock.get('require_skeletal_animation'):
        require(all(frame['animation_poses'] for frame in sequence) and len(poses) >= 3,
                'Required skeletal pose evidence is missing or static')
    actual = set()
    for path in directory.rglob('*'):
        require(not path.is_symlink(), 'Artifact symlink')
        if not path.is_file():
            require(path.is_dir(), 'Artifact special file'); continue
        relative = path.relative_to(directory).as_posix(); actual.add(relative)
        require(relative in allowed, 'Unapproved artifact file: ' + relative)
        require(path.stat().st_size <= 16 * 1024 * 1024, 'Artifact size limit')
        body = path.read_bytes()
        for kind, pattern in SIGNATURES.items():
            for match in re.finditer(pattern, body):
                findings.append({'file': relative, 'kind': kind, 'offset': match.start()})
        files.setdefault(relative, {'sha256': sha(path)})
    require(actual == allowed, 'Missing evidence files')
    return {'passed': not findings, 'files': files, 'findings': findings,
            'build': lock['build'], 'scope': 'Hash-bound native source framebuffer evidence; no automatic art-quality approval',
            'scan_limitations': 'High-confidence token/key patterns and private paths only; not proof all possible secrets are absent.'}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--directory', type=Path, required=True)
    parser.add_argument('--lock', type=Path, required=True)
    parser.add_argument('--report', type=Path, required=True)
    args = parser.parse_args()
    require(not args.report.exists(), 'Refusing to replace scan evidence')
    try:
        result = scan(args.directory, json.loads(args.lock.read_text()), sha(args.lock))
    except Exception as exc:
        result = {'passed': False, 'error': {'type': type(exc).__name__, 'message': str(exc)}}
    args.report.write_text(json.dumps(result, indent=2) + '\n')
    raise SystemExit(0 if result['passed'] else 1)

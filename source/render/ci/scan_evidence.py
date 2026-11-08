#!/usr/bin/env python3
"""Read-only screenshot provenance + artifact admission checks. Never edits pixels."""
from pathlib import Path
import argparse
import hashlib
import json
import math
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


def validate_frame_name(name):
    require(type(name) is str and re.fullmatch(r'\d{3}-[a-z0-9-]+\.png',name) is not None, 'Unsafe frame name')


def png_info(path, minimum_colors=128):
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
    require(len(colors) >= minimum_colors, 'Framebuffer is blank or implausibly uniform')
    return {'width': width, 'height': height, 'sampled_rgb_colors': len(colors)}


KINDS = ('villager','spearman','archer','scout')
STUDIES = [(kind,clip) for clip in ('attack','death') for kind in KINDS]
STUDIES += [(kind,clip) for kind in KINDS for clip in ('idle','walk','hit')]
STUDIES += [('villager',clip) for clip in ('carry_walk','gather_wood','gather_food','build','repair')]
OCCLUSION_LABELS = ['01-normal-overlay-off','02-normal-overlay-on','03-object-occluded-overlay-off',
                    '04-object-occluded-overlay-on','05-fog-hidden-parent','06-no-unit-reference']


OCCLUSION_CHECKS = [
    'fixture bound real exported rig', '01-normal-overlay-off framebuffer saved',
    '02-normal-overlay-on framebuffer saved', 'normal visible mesh unchanged',
    '03-object-occluded-overlay-off framebuffer saved', '04-object-occluded-overlay-on framebuffer saved',
    'occluded authorized unit receives silhouette', '05-fog-hidden-parent framebuffer saved',
    '06-no-unit-reference framebuffer saved', 'hidden ancestor silhouette is absent']
FUNCTIONAL_OCCLUSION_CHECKS = {OCCLUSION_CHECKS[i] for i in (3,6,9)}


def pose_identity(pose, lock):
    require(type(pose) is dict and pose.get('kind') in KINDS, 'Invalid skeletal class')
    asset='assets/mature/models/'+pose['kind']+'_action.scn'
    require(pose.get('asset_path') == 'res://'+asset and pose.get('asset_sha256') == lock['project_files'][asset], 'Rig asset identity differs')
    bones=pose.get('poses');count=pose.get('bone_count')
    require(type(count) is int and 20 <= count <= 32 and type(bones) is list and len(bones)==count, 'Rig bone evidence count differs')
    require(all(type(row) is dict and set(row)=={'bone','pose'} and type(row['bone']) is str and row['bone']
                and type(row['pose']) is str and row['pose'] and not re.search(r'(?i)\b(?:nan|inf)\b',row['pose']) for row in bones), 'Malformed bone pose evidence')
    require(len({row['bone'] for row in bones})==count, 'Duplicate bone name')
    canonical=json.dumps(bones,sort_keys=True,separators=(',',':'),ensure_ascii=False).encode()
    require(hashlib.sha256(canonical).hexdigest()==pose.get('pose_sha256'), 'Bone pose hash does not match recorded transforms')
    seek=pose.get('seek_seconds')
    require(type(seek) in (int,float) and math.isfinite(seek) and 0 <= seek <= 120, 'Invalid animation seek')
    return pose['pose_sha256']


def study_camera_numeric_diagnostic(report):
    # Fixed, bounded scalars only. Never paths, raw arrays or exception text.
    unavailable={'diagnostic_only':True,'available':False}
    if type(report) is not dict or report.get('mode')!='material_studies':return unavailable
    frames=report.get('frames');opening=report.get('opening_camera')
    if type(frames) is not list or len(frames)!=8 or type(opening) is not dict:return unavailable
    def basis_ok(basis):
        return type(basis) is list and len(basis)==3 and all(type(column) is list and len(column)==3 and all(type(v) in (int,float) and math.isfinite(v) and abs(v)<=2 for v in column) for column in basis)
    reference=opening.get('basis')
    if not basis_ok(reference):return unavailable
    delta=0.0;sizes=[]
    for frame in frames:
        if type(frame) is not dict or type(frame.get('camera')) is not dict:return unavailable
        basis=frame['camera'].get('basis');size=frame['camera'].get('size')
        if not basis_ok(basis) or type(size) not in (int,float) or not math.isfinite(size) or not 0<size<=128:return unavailable
        delta=max(delta,max(abs(a-b) for ac,bc in zip(basis,reference) for a,b in zip(ac,bc)))
        sizes.append(size)
    return {'diagnostic_only':True,'available':True,'basis_max_abs_delta':float(format(delta,'.12g')),'size_min':float(format(min(sizes),'.12g')),'size_max':float(format(max(sizes),'.12g'))}


def validate_scenario(report, lock):
    from material_contract import validate_report
    if lock['capture_contract']['mode']=='material_studies':
        print('MATERIAL_CAMERA_NUMERIC_DIAGNOSTIC '+json.dumps(study_camera_numeric_diagnostic(report),sort_keys=True),flush=True)
    return validate_report(report, lock, pose_identity)


def strict_json(path):
    require(path.is_file() and not path.is_symlink() and path.stat().st_size <= 16*1024*1024, 'Unsafe JSON evidence')
    def pairs(rows):
        value = {}
        for key, item in rows:
            require(key not in value, 'Duplicate JSON key')
            value[key] = item
        return value
    def invalid(value):
        raise ValueError('Nonfinite JSON number')
    value=json.loads(path.read_text(), object_pairs_hook=pairs, parse_constant=invalid)
    def finite_tree(node):
        if type(node) is float: require(math.isfinite(node), 'Nonfinite JSON number')
        elif type(node) is dict:
            for item in node.values(): finite_tree(item)
        elif type(node) is list:
            for item in node: finite_tree(item)
    finite_tree(value)
    return value


def scan(directory, lock, lock_sha256):
    from material_contract import validate_lock
    validate_lock(lock)
    require(directory.is_dir() and not directory.is_symlink(), 'Artifact symlink')
    for path in directory.rglob('*'):
        require(not path.is_symlink(), 'Artifact symlink')
        require(path.is_file() or path.is_dir(), 'Artifact special file')
        if path.is_file(): require(path.stat().st_size <= 16*1024*1024, 'Artifact size limit')
    report_path = directory / 'frames/capture-report.json'
    report = strict_json(report_path)
    guard = strict_json(directory / 'guard-receipt.json')
    require(guard.get('passed') is True and guard.get('capture_completed') is True and
            guard.get('cleanup_complete') is True, 'Guard did not pass or cleanup is unconfirmed')
    require(guard.get('test_dependencies') is False, 'Fake/injected process evidence cannot be admitted')
    require(guard.get('diagnostic_only') is False, 'Diagnostic-only run cannot produce accepted visual artifacts')
    require(guard.get('renderer_configuration') == {'DRI_PRIME': '0', 'LIBGL_ALWAYS_SOFTWARE': '1', 'GALLIUM_DRIVER': 'llvmpipe'},
            'Pinned software-renderer configuration differs')
    require(guard.get('startup', {}).get('complete') is True, 'Xvfb startup was not completed before capture')
    require(guard['input_sha256']['startup'] == lock['support_files']['ci/xvfb_startup.py'], 'Startup helper hash differs')
    require(guard['input_sha256']['import_adapter'] == lock['support_files']['ci/guarded_manifest_ci.py'], 'Import adapter hash differs')
    startup_helpers = guard['startup'].get('helpers', [])
    require(not startup_helpers or {row['role'] for row in startup_helpers} == {'dash', 'xkbcomp'} and len(startup_helpers) == 2,
            'Startup helper pair differs')
    require(all(row.get('exit_confirmed_before_engine') is True and row['sampled_peak_rss_kib'] <= 131072
                and row['sampled_peak_hwm_kib'] <= 131072 and row['sampled_peak_threads'] <= 4 for row in startup_helpers),
            'Startup helper completion/resource evidence differs')
    require(guard['input_sha256']['lock'] == lock_sha256, 'Guard lock identity differs')
    require(guard['input_sha256']['import_marker'] == lock['import_certificate_sha256'], 'Reviewed import certificate hash differs')
    for key in ('harness', 'godot', 'supervisor'):
        require(guard['input_sha256'][key] == lock[key + '_sha256'], 'Guard tool identity differs: ' + key)
    generated = guard.get('generated_uid_sha256', {})
    require(set(generated) == set(lock['allowed_generated_uid_files']), 'Generated UID binding set differs')
    require(all(re.fullmatch(r'[0-9a-f]{64}', digest) for digest in generated.values()), 'Invalid generated UID hash binding')
    require(guard.get('original_file_count') == len(lock['project_files']) and
            guard.get('source_file_count') == len(lock['project_files']) + len(generated), 'Frozen inventory count differs')
    require(guard['build'] == report['build'] == lock['build'], 'Build identity mismatch')
    contract=lock['capture_contract']
    require(guard.get('capture_contract')==contract, 'Guard capture contract differs')
    require(report.get('passed') is True and len(report['frames']) == report['frame_count'] == contract['frame_count'], 'Incomplete report')
    allowed = {'guard-receipt.json', 'godot.log', 'xvfb.log', 'frames/capture-report.json'}
    files, findings, poses = {}, [], set()
    previous_usec = -1
    for frame in report['frames']:
        name = frame['image']
        validate_frame_name(name)
        allowed.update({'frames/' + name, 'frames/' + name + '.json'})
        path = directory / 'frames' / name
        require(frame['image_sha256'] == sha(path), 'PNG identity mismatch')
        require(strict_json(path.with_suffix('.png.json')) == frame, 'Frame metadata mismatch')
        require(frame['capture_kind'] == contract['kind'], 'Unknown capture kind')
        require(frame['build'] == lock['build'] and frame['game_sha256'] == lock['project_files']['scripts/game.gd'], 'Source mismatch')
        require(frame['rules_sha256'] == lock['project_files']['scripts/rules.gd'], 'Rules mismatch')
        require(frame['monotonic_usec'] > previous_usec, 'Nonincreasing capture times')
        previous_usec = frame['monotonic_usec']
        require(frame['display'] == 'X11' and 'llvmpipe' in frame['adapter_name'].lower(), 'Not the reviewed renderer')
        if contract['mode']=='gameplay':require(frame['economy_audit_ok'] is True, 'Economy audit failed')
        # The final depth references intentionally contain only a flat box and
        # background. Keep the richer-scene threshold for all other modes.
        info = png_info(path, minimum_colors=2 if contract['mode']=='occlusion' else 128)
        require([info['width'], info['height']] == frame['framebuffer'] == guard['expected_framebuffer'], 'Frame dimensions mismatch')
        if frame['label'].startswith('woodcut-'):
            poses.add(json.dumps(frame['animation_poses'], sort_keys=True))
        files['frames/' + name] = {'sha256': sha(path), **info}
    visual_findings=validate_scenario(report,lock)
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
            'visual_findings': visual_findings,
            'build': lock['build'], 'scope': 'Hash-bound native source framebuffer evidence; no automatic art-quality approval',
            'scan_limitations': 'High-confidence token/key patterns and private paths only; not proof all possible secrets are absent.'}


# Exact source-authored literals only. Never emit arbitrary exception text.
SAFE_SCAN_REASONS = frozenset(['Artifact size limit', 'Artifact special file', 'Artifact symlink', 'Bone pose hash does not match recorded transforms', 'Build identity mismatch', 'Commanded visible worker is not actually woodcutting', 'Commanded worker bone transforms are static', 'Controlled rig labeling missing', 'Current class/action coverage differs', 'Diagnostic-only run cannot produce accepted visual artifacts', 'Duplicate bone name', 'Economy audit failed', 'Fake/injected process evidence cannot be admitted', 'Frame dimensions mismatch', 'Frame metadata mismatch', 'Framebuffer is blank or implausibly uniform', 'Frozen inventory count differs', 'Gameplay command provenance differs', 'Gameplay frame sequence is static', 'Gameplay sequence differs', 'Generated UID binding set differs', 'Guard capture contract differs', 'Guard did not pass or cleanup is unconfirmed', 'Guard lock identity differs', 'Guard tool identity differs: godot', 'Guard tool identity differs: harness', 'Guard tool identity differs: supervisor', 'Hidden rig leaked pose evidence', 'Import adapter hash differs', 'Incomplete report', 'Invalid IEND', 'Invalid PNG filter', 'Invalid animation seek', 'Invalid generated UID hash binding', 'Invalid rig clip length', 'Invalid skeletal class', 'Malformed bone pose evidence', 'Missing evidence files', 'Nonincreasing capture times', 'Not the reviewed renderer', 'Occlusion binding/framebuffer production failed', 'Occlusion check coverage differs', 'Occlusion functional result inconsistent', 'Occlusion rig/action/toggle differs', 'Occlusion sequence differs', 'Occlusion visibility provenance differs', 'PNG CRC failure', 'PNG IDAT ordering', 'PNG IHDR invalid', 'PNG chunk exceeds file', 'PNG decompression size/stream mismatch', 'PNG identity mismatch', 'PNG signature/size', 'PNG trailing/missing data', 'Pinned software-renderer configuration differs', 'Refusing to replace scan evidence', 'Rig asset identity differs', 'Rig bone evidence count differs', 'Rig sample seek does not match clip fraction', 'Rig study binding/overlay differs', 'Rig study bone transforms do not change', 'Rig study checks failed', 'Rig study phases differ', 'Rules mismatch', 'Source mismatch', 'Startup helper completion/resource evidence differs', 'Startup helper hash differs', 'Startup helper pair differs', 'Truncated PNG chunk', 'Unapproved framebuffer dimensions', 'Unexpected metadata/chunk in unmodified framebuffer PNG', 'Unknown capture kind', 'Unsafe frame name', 'Unsupported PNG layout', 'Visible game-root pose evidence missing', 'Worker public state differs', 'Xvfb startup was not completed before capture'])
SAFE_EXCEPTION_TYPES = frozenset(('ValueError','KeyError','FileNotFoundError','PermissionError','IsADirectoryError','JSONDecodeError','TypeError','OSError','RuntimeError'))


def safe_scan_exception(exc):
    from material_contract import MATERIAL_ASSERTION_IDS
    kind=type(exc).__name__
    message=str(exc)
    material_reasons={'Material contract rejected: '+code for code in MATERIAL_ASSERTION_IDS}
    if isinstance(exc,ValueError) and message in SAFE_SCAN_REASONS | material_reasons:
        reason=message
    elif isinstance(exc,ValueError) and message.startswith('Unapproved artifact file: '):
        reason='Unapproved artifact file; path withheld'
    elif kind=='JSONDecodeError':reason='Malformed JSON evidence'
    elif kind=='KeyError':reason='Required evidence field missing'
    else:reason='Unexpected scanner exception; details withheld'
    return {'type':kind if kind in SAFE_EXCEPTION_TYPES else 'Exception','reason':reason}


def scan_to_report(directory, lock_path, report_path):
    require(not report_path.exists(), 'Refusing to replace scan evidence')
    try:
        result=scan(directory,strict_json(lock_path),sha(lock_path))
    except Exception as exc:
        result={'passed':False,'error':safe_scan_exception(exc)}
    report_path.write_text(json.dumps(result,indent=2)+'\n')
    summary={'passed':result.get('passed') is True}
    if 'error' in result:summary['error']=result['error']
    else:
        summary['admitted_file_count']=min(128,len(result.get('files',{}))) if result.get('passed') is True else 0
        summary['finding_counts']={key:min(1000,sum(row.get('kind')==key for row in result.get('findings',[]))) for key in SIGNATURES}
        summary['visual_finding_count']=min(3,len(result.get('visual_findings',[])))
    # Bounded, sanitized diagnostic only; no filenames, paths or captured bytes.
    print('NATIVE_SCAN_RESULT '+json.dumps(summary,sort_keys=True),flush=True)
    return 0 if result['passed'] else 1


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--directory', type=Path, required=True)
    parser.add_argument('--lock', type=Path, required=True)
    parser.add_argument('--report', type=Path, required=True)
    args = parser.parse_args()
    raise SystemExit(scan_to_report(args.directory,args.lock,args.report))

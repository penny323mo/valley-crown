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


def validate_scenario(report, lock):
    frames=report['frames'];mode=lock['capture_contract']['mode'];findings=[]
    if mode=='gameplay':
        require([f['label'] for f in frames]==['opening', 'walk-to-wood', 'worker-commands', 'target-command', 'house-placement', 'barracks-placement', 'town-center-training', 'rally-command', 'game-menu', 'paused-game'], 'Gameplay sequence differs')
        commands=report.get('commands',[])
        require(len(commands)==1 and commands[0].get('kind')=='order' and type(commands[0].get('worker')) is int, 'Gameplay command provenance differs')
        states=[f.get('interface_state',{}) for f in frames[2:]]
        require(len(states)==8 and all(type(x) is dict for x in states), 'Interface evidence missing')
        require(states[0]['build_mode']=='' and states[0]['touch_command'] is False, 'Worker commands absent')
        require(states[1]['touch_command'] is True and states[1]['rally_building']==-1, 'Target command absent')
        require(states[2]['build_mode']=='house' and states[3]['build_mode']=='barracks', 'Build previews absent')
        require(states[4]['build_mode']=='' and frames[6]['selected'], 'Town center selection absent')
        require(states[5]['rally_building']==frames[6]['selected'][0], 'Rally command absent')
        require(states[6]['menu_visible'] is True and states[7]['menu_visible'] is False and states[7]['paused'] is True, 'Menu or pause interface absent')
        require(all(x['tutorial_visible'] is True for i,x in enumerate(states) if i!=6), 'Tutorial silently hidden')
        worker=commands[0]['worker'];poses=set()
        for frame in frames[2:]:
            roots=frame.get('animation_poses')
            require(type(roots) is list and len(roots)==1 and roots[0].get('node')=='.', 'Visible game-root pose evidence missing')
            pose=roots[0]['snapshot']['live'].get(str(worker))
            require(type(pose) is dict and pose.get('kind')=='villager' and pose.get('clip')=='gather_wood'
                    and pose.get('dead_visual_only') is False, 'Commanded visible worker is not actually woodcutting')
            own=[row for row in frame['own_units'] if row['id']==worker]
            require(len(own)==1 and own[0]['state']=='gather', 'Worker public state differs')
            poses.add(pose_identity(pose,lock))
        require(len(poses)>=3, 'Commanded worker bone transforms are static')
        require(len({f['image_sha256'] for f in frames[2:]})>=3, 'Gameplay frame sequence is static')
    elif mode=='rig_studies':
        require([(f.get('kind'),f.get('clip')) for f in frames]==STUDIES, 'Current class/action coverage differs')
        for frame in frames:
            kind,clip=frame['kind'],frame['clip'];poses=frame.get('animation_poses',[])
            middle=(.62 if kind=='archer' else .56) if clip=='attack' else (.5 if clip=='death' else .35)
            require(frame.get('fractions')==[0.0,middle,1.0] and len(poses)==3, 'Rig study phases differ')
            length=frame.get('clip_length_seconds')
            require(type(length) in (int,float) and math.isfinite(length) and 0<length<=120, 'Invalid rig clip length')
            require(all(type(p.get('seek_seconds')) in (int,float) and math.isfinite(p['seek_seconds'])
                        and math.isclose(p['seek_seconds'],length*fraction,rel_tol=1e-6,abs_tol=1e-6)
                        for p,fraction in zip(poses,frame['fractions'])), 'Rig sample seek does not match clip fraction')
            require(all(p.get('kind')==kind and p.get('clip')==clip and p.get('occlusion',{}).get('authorized') is False for p in poses), 'Rig study binding/overlay differs')
            require(len({pose_identity(p,lock) for p in poses})>=2, 'Rig study bone transforms do not change')
            require(frame.get('unit_state')=='controlled_paused_clip_samples', 'Controlled rig labeling missing')
        require(report.get('mode')=='rig_studies' and report.get('failed')==0, 'Rig study checks failed')
    else:
        require(mode=='occlusion' and [f['label'] for f in frames]==OCCLUSION_LABELS, 'Occlusion sequence differs')
        for index,frame in enumerate(frames):
            require(frame.get('unit_state')=='controlled_depth_comparison' and frame.get('rig_visible_in_tree') is (index<4), 'Occlusion visibility provenance differs')
            poses=frame.get('animation_poses',[])
            require(len(poses)==(1 if index<4 else 0), 'Hidden rig leaked pose evidence')
            if poses:
                require(poses[0].get('kind')=='spearman' and poses[0].get('clip')=='idle'
                        and poses[0].get('occlusion',{}).get('authorized') is (index in (1,3)), 'Occlusion rig/action/toggle differs')
                pose_identity(poses[0],lock)
        checks=report.get('checks',[])
        require([row.get('name') for row in checks]==OCCLUSION_CHECKS and all(type(row.get('pass')) is bool for row in checks), 'Occlusion check coverage differs')
        require(all(row['pass'] for row in checks if row['name'] not in FUNCTIONAL_OCCLUSION_CHECKS), 'Occlusion binding/framebuffer production failed')
        failed=[row['name'] for row in checks if not row['pass']]
        require(report.get('failed')==len(failed) and report.get('functional_checks_passed') is (not failed), 'Occlusion functional result inconsistent')
        findings += [{'kind':'controlled_occlusion_check_failed','check':name} for name in failed]
    return findings


def scan(directory, lock, lock_sha256):
    from run_native import validate_capture_lock
    validate_capture_lock(lock)
    report_path = directory / 'frames/capture-report.json'
    report = json.loads(report_path.read_text())
    guard = json.loads((directory / 'guard-receipt.json').read_text())
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
        require(re.fullmatch(r'\d{3}-[a-z0-9-]+\.png', name) is not None, 'Unsafe frame name')
        allowed.update({'frames/' + name, 'frames/' + name + '.json'})
        path = directory / 'frames' / name
        require(frame['image_sha256'] == sha(path), 'PNG identity mismatch')
        require(json.loads(path.with_suffix('.png.json').read_text()) == frame, 'Frame metadata mismatch')
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

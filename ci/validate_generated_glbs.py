#!/usr/bin/env python3
"""Data-only prototype artifact checks. Passing is not visual acceptance."""
import argparse
import hashlib
import json
import math
from pathlib import Path
import struct

KINDS = ('villager', 'spearman', 'archer', 'scout')
COMMON = {'idle', 'walk', 'attack', 'hit', 'death'}
WORK = {'carry_walk', 'gather_wood', 'gather_food', 'build', 'repair'}
EXPECTED_MANIFEST = '1cbfddb27a4ce08a765208d262f545e4bf560e382281caf505216c9be1f32bce'
def sha(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()

def parse_glb(path):
    raw = path.read_bytes()
    assert 20 < len(raw) < 32 * 1024 * 1024, 'GLB size outside prototype bound'
    assert struct.unpack_from('<III', raw) == (0x46546c67, 2, len(raw))
    chunks = []; at = 12
    while at < len(raw):
        n, tag = struct.unpack_from('<II', raw, at); at += 8
        assert n % 4 == 0 and at + n <= len(raw)
        chunks.append((tag, raw[at:at+n])); at += n
    assert [c[0] for c in chunks] == [0x4e4f534a, 0x004e4942]
    doc = json.loads(chunks[0][1]); binary = chunks[1][1]
    assert len(doc['buffers']) == 1 and 'uri' not in doc['buffers'][0]
    assert 0 <= len(binary) - doc['buffers'][0]['byteLength'] <= 3
    for view in doc.get('bufferViews', []):
        assert view.get('buffer', 0) == 0
        assert 0 <= view.get('byteOffset', 0) <= len(binary)
        assert 0 <= view['byteLength'] <= len(binary) - view.get('byteOffset', 0)
    def accessor(i):
        a = doc['accessors'][i]; assert 'sparse' not in a
        v = doc['bufferViews'][a['bufferView']]
        code = {5120:'b', 5121:'B', 5122:'h', 5123:'H', 5125:'I', 5126:'f'}[a['componentType']]
        width = {'SCALAR':1, 'VEC2':2, 'VEC3':3, 'VEC4':4, 'MAT4':16}[a['type']]
        size = struct.calcsize('<' + code * width); stride = v.get('byteStride', size)
        assert stride >= size and a['count'] <= 300000
        off = v.get('byteOffset', 0) + a.get('byteOffset', 0)
        assert off + (max(0, a['count'] - 1) * stride) + size <= v.get('byteOffset', 0) + v['byteLength']
        data = [struct.unpack_from('<' + code * width, binary, off + k * stride) for k in range(a['count'])]
        assert all(math.isfinite(x) for row in data for x in row)
        if a.get('normalized'):
            divisor = {5121:255, 5123:65535}[a['componentType']]
            data = [tuple(x / divisor for x in row) for row in data]
        return data
    return doc, binary, accessor

def inspect(path, kind):
    doc, binary, acc = parse_glb(path)
    assert len(doc.get('skins', [])) == 1 and len(doc.get('meshes', [])) == 1
    assert len(doc.get('materials', [])) == 2
    assert not doc.get('extensionsRequired'), 'Unreviewed required glTF extension'
    skin = doc['skins'][0]; joints = skin['joints']
    assert 20 <= len(joints) <= 32 and len(set(joints)) == len(joints)
    nodes = doc['nodes']; names = [nodes[j].get('name') for j in joints]
    assert len(set(names)) == len(names)
    assert {'root', 'pelvis', 'Head', 'hand_l', 'hand_r', 'foot_l', 'foot_r'} <= set(names)
    assert len(acc(skin['inverseBindMatrices'])) == len(joints)
    mesh_nodes = [n for n in nodes if 'mesh' in n]
    assert len(mesh_nodes) == 1 and mesh_nodes[0].get('skin') == 0
    triangles = 0; vertices = 0; material_indices = set()
    primitives = doc['meshes'][0]['primitives']; assert len(primitives) <= 2
    for p in primitives:
        assert p.get('mode', 4) == 4 and not p.get('targets')
        a = p['attributes']; assert {'POSITION', 'NORMAL', 'JOINTS_0', 'WEIGHTS_0'} <= set(a)
        if doc['materials'][p['material']].get('name') == 'field_textured':
            assert {'TEXCOORD_0', 'COLOR_0'} <= set(a), 'Textured surface lost UV or vertex tint'
        assert not any(k.startswith(('JOINTS_', 'WEIGHTS_')) and not k.endswith('_0') for k in a)
        positions = acc(a['POSITION']); weights = acc(a['WEIGHTS_0']); bone_ids = acc(a['JOINTS_0'])
        assert len(positions) == len(weights) == len(bone_ids)
        assert all(len(w) == 4 and min(w) >= 0 and abs(sum(w)-1) < .002 for w in weights)
        assert all(0 <= j < len(joints) for row in bone_ids for j in row)
        indices = acc(p['indices']); assert len(indices) % 3 == 0
        assert all(0 <= row[0] < len(positions) for row in indices)
        triangles += len(indices) // 3; vertices += len(positions); material_indices.add(p['material'])
    assert triangles <= 6500 and material_indices == {0, 1}
    images = doc.get('images', []); assert len(images) == 1
    for im in images:
        assert 'uri' not in im and im.get('mimeType') == 'image/png'
        v = doc['bufferViews'][im['bufferView']]; data = binary[v.get('byteOffset', 0):v.get('byteOffset', 0)+v['byteLength']]
        assert data[:8] == b'\x89PNG\r\n\x1a\n'
        assert struct.unpack_from('>II', data, 16) == (1024, 1024)
    field = [m for m in doc['materials'] if m.get('name') == 'field_textured']
    team = [m for m in doc['materials'] if m.get('name') == 'team_blue']
    assert len(field) == len(team) == 1
    assert 'baseColorTexture' in field[0]['pbrMetallicRoughness'], 'Texture lost during shader export'
    animations = doc.get('animations', [])
    expected = COMMON | (WORK if kind == 'villager' else set())
    assert {a['name'] for a in animations} == expected and len(animations) == len(expected)
    clips = {}
    for anim in animations:
        changed = 0; duration = 0.0; targeted = set()
        for c in anim['channels']:
            target = c['target']; assert target['node'] in joints
            assert target['path'] in {'translation', 'rotation', 'scale'}
            sampler = anim['samplers'][c['sampler']]; assert sampler.get('interpolation', 'LINEAR') in {'LINEAR', 'STEP'}
            times = [v[0] for v in acc(sampler['input'])]; values = acc(sampler['output'])
            assert len(times) == len(values) and times and times[0] >= -1e-6
            assert all(x < y for x, y in zip(times, times[1:]))
            duration = max(duration, times[-1]); targeted.add(nodes[target['node']].get('name'))
            delta = max(abs(x-y) for v in values for x,y in zip(v, values[0]))
            changed += delta > 1e-5
            if nodes[target['node']].get('name') == 'root':
                assert delta < 1e-5, 'Root motion retained'
        assert changed > 0 and .25 <= duration <= 3 and 'pelvis' in targeted
        clips[anim['name']] = {'duration':duration, 'varying_channels':changed}
    return {'sha256':sha(path), 'triangles':triangles, 'vertices':vertices, 'bones':len(joints), 'surfaces':len(primitives), 'clips':clips}

def validate(root):
    art = root/'art/action_characters'; manifest = json.loads((root/'reports/asset_manifest.json').read_text())
    assert manifest['blender'] == '4.3.2' and manifest['input_manifest_sha256'] == EXPECTED_MANIFEST
    assert sha(art/'input-manifest.json') == EXPECTED_MANIFEST
    inputs = json.loads((art/'input-manifest.json').read_text())
    for name, entry in inputs['files'].items():
        if name.startswith('licenses/'):
            assert sha(art/name) == entry['sha256']
    assert set(manifest['units']) == set(KINDS)
    output = {'scope':'DATA ONLY; no visual acceptance', 'units':{}}
    for kind in KINDS:
        unit = manifest['units'][kind]
        assert sha(art/(kind+'.blend')) == unit['blend_sha256']
        path = art/'interchange'/(kind+'.glb'); assert sha(path) == unit['glb_sha256']
        output['units'][kind] = inspect(path, kind)
    return output

if __name__ == '__main__':
    parser = argparse.ArgumentParser(); parser.add_argument('--output-root', required=True, type=Path); parser.add_argument('--report', required=True, type=Path)
    args = parser.parse_args(); result = validate(args.output_root.resolve())
    with args.report.open('x') as f: json.dump(result, f, indent=2); f.write('\n')
    print('GENERATED_GLB_DATA_PASS')

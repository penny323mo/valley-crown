"""Four exact creation-only scene imports. Parsing data never runs Godot code.

Godot 4.6.3 scene importer defaults and import-path derivation are documented in
review/DESCRIPTOR_SCHEMA.md. This module never creates an .import descriptor.
"""
from pathlib import Path
import hashlib
import json
import re

PAIRS = {
    'stable': ('3a8e26b0520c162c00841358dcbdfec3a7478bfbfa1442863b74b22b334a52cc', '28401a9ef257b4c299f8cadeccf61ab7cda562c9faae0b5f2ff0c825d5776ab9'),
    'workshop': ('1ff38fd60b4bc55e16130ef4a8ea45fa9f06766117330c8a9a62d91d2579dd0f', '592c58d0616cba573d6fa6f169b6c1ae66c067604148b0394b830c0b17ce3ce7'),
    'tower': ('77d0d16f912923bab5ffe0b6526e6efd739ed67d80fc267c878d2099817c0e90', '6b41f5cf8283f80f9920b2f603eb8bdec375321e59bed1afeef611558b47e35a'),
    'farm': ('2afe0e81fce12ed4f26d8595561b6db9a19d3c350952edcd80bf79e6d50e72be', '8b691683d3dc5ca7f3bcb3ced483660da413f9fc3d794c20bb999d23614925ec'),
}
PREFIX = 'assets/advanced_buildings/'
PARAMS = {
    'nodes/root_type': '""', 'nodes/root_name': '""', 'nodes/root_script': 'null',
    'nodes/apply_root_scale': 'true', 'nodes/root_scale': '1.0',
    'nodes/import_as_skeleton_bones': 'false', 'nodes/use_name_suffixes': 'true',
    'nodes/use_node_type_suffixes': 'true', 'meshes/ensure_tangents': 'true',
    'meshes/generate_lods': 'true', 'meshes/create_shadow_meshes': 'true',
    'meshes/light_baking': '1', 'meshes/lightmap_texel_size': '0.2',
    'meshes/force_disable_compression': 'false', 'skins/use_named_skins': 'true',
    'animation/import': 'true', 'animation/fps': '30', 'animation/trimming': 'false',
    'animation/remove_immutable_tracks': 'true', 'animation/import_rest_as_RESET': 'false',
    'import_script/path': '""', 'materials/extract': '0', 'materials/extract_format': '0',
    'materials/extract_path': '""', '_subresources': '{}',
    'gltf/naming_version': '2', 'gltf/embedded_image_handling': '1',
}
UID_ALPHABET = b'abcdefghijklmnopqrstuvwxy012345678'


def need(value, message):
    if not value:
        raise ValueError(message)


def digest(path, algorithm='sha256'):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, algorithm).hexdigest()


def expected(entries):
    names = set()
    for kind, hashes in PAIRS.items():
        for suffix, value in zip(('.gltf', '.bin'), hashes):
            need(entries.get(PREFIX + kind + suffix) == value, 'Unreviewed building source pair')
        name = PREFIX + kind + '.gltf.import'
        need(name not in entries, 'Collection requires creation-only descriptors absent from source')
        names.add(name)
    need(entries.get('art/.gdignore') == hashlib.sha256(b'').hexdigest(), 'Donor ignore boundary differs')
    return names


def uid_number(value):
    need(type(value) is str and re.fullmatch(r'"uid://[a-y0-8]{1,13}"', value), 'Malformed scene UID')
    digits = value[7:-1].encode('ascii')
    need(len(digits) == 1 or digits[0] != ord('a'), 'Noncanonical scene UID')
    number = 0
    for digit in digits:
        number = number * 34 + UID_ALPHABET.index(digit)
    need(0 < number <= 0x7fffffffffffffff, 'Invalid scene UID range')
    return number


def parse(data, source_name):
    need(source_name in {PREFIX + kind + '.gltf' for kind in PAIRS}, 'Unexpected source binding')
    need(type(data) is bytes and 0 < len(data) <= 8192, 'Descriptor size')
    need(data.endswith(b'\n') and b'\r' not in data and b'\x00' not in data, 'Descriptor encoding')
    sections = {}; current = None
    for line in data.decode('utf-8').splitlines():
        if line == '':
            continue
        if line.startswith('['):
            need(line in ('[remap]', '[deps]', '[params]') and line[1:-1] not in sections, 'Descriptor section')
            current = line[1:-1]; sections[current] = {}
        else:
            need(current is not None and '=' in line and line == line.strip(), 'Descriptor assignment')
            key, value = line.split('=', 1)
            need(re.fullmatch(r'[A-Za-z0-9_/]+', key) and key not in sections[current], 'Descriptor key')
            sections[current][key] = value
    need(list(sections) == ['remap', 'deps', 'params'], 'Descriptor section order')
    uri = 'res://' + source_name
    compiled = '.godot/imported/' + Path(source_name).name + '-' + hashlib.md5(uri.encode()).hexdigest() + '.scn'
    remap = sections['remap']
    need(set(remap) == {'importer', 'importer_version', 'type', 'uid', 'path'}, 'Unexpected remap fields')
    uid = uid_number(remap['uid'])
    need(remap == {'importer': '"scene"', 'importer_version': '1', 'type': '"PackedScene"',
                   'uid': remap['uid'], 'path': json.dumps('res://' + compiled)}, 'Scene remap differs')
    need(sections['deps'] == {'source_file': json.dumps(uri), 'dest_files': json.dumps(['res://' + compiled])}, 'Scene dependency binding differs')
    need(sections['params'] == PARAMS, 'Unreviewed scene importer options')
    return {'source': source_name, 'compiled': compiled, 'uid': uid, 'parameters': sections['params']}


def regular(project, name, maximum):
    path = project / name
    need(path.is_relative_to(project) and not any(p.is_symlink() for p in [path, *path.parents]), 'Generated path symlink')
    need(path.is_file() and 0 < path.stat().st_size <= maximum, 'Missing or oversized generated artifact')
    return path


def descriptors(project, entries, complete=False):
    names = expected(entries); result = {}; ids = set()
    for name in entries:
        if name.endswith('.uid'):
            raw = (project / name).read_text().strip()
            ids.add(raw)
        elif name.endswith('.import'):
            ids.update(re.findall(r'^uid="([^"]+)"$', (project / name).read_text(), re.M))
    for name in generated_uids(entries):
        path = project / name
        if path.is_file() and not path.is_symlink():
            need(path.stat().st_size <= 20, 'Oversized generated UID')
            ids.add(path.read_text().strip())
    for name in sorted(names):
        path = project / name
        if not path.exists() and not path.is_symlink():
            need(not complete, 'Missing generated scene descriptor')
            continue
        path = regular(project, name, 8192)
        data = path.read_bytes(); row = parse(data, name[:-7])
        uid = re.search(rb'^uid="([^"]+)"$', data, re.M).group(1).decode()
        need(uid not in ids, 'Generated scene UID collision'); ids.add(uid)
        row['descriptor_sha256'] = digest(path)
        row['source_sha256'] = entries[row['source']]
        result[name] = row
    return result


def validate_outputs(project, entries):
    rows = descriptors(project, entries, complete=True)
    for name, row in rows.items():
        scene = regular(project, row['compiled'], 8 * 1024 * 1024)
        with scene.open('rb') as stream:
            need(stream.read(4) in (b'RSCC', b'RSRC'), 'Unexpected compiled scene signature')
        md5_name = row['compiled'][:-4] + '.md5'
        md5_path = regular(project, md5_name, 256)
        expected_md5 = ('source_md5="' + digest(project / row['source'], 'md5') + '"\n' +
                        'dest_md5="' + digest(scene, 'md5') + '"\n\n').encode()
        need(md5_path.read_bytes() == expected_md5, 'Compiled/source MD5 binding differs')
        row.update(compiled_sha256=digest(scene), compiled_bytes=scene.stat().st_size,
                   md5_path=md5_name, md5_sha256=digest(md5_path))
    return rows


def generated_uids(entries):
    names = {name + '.uid' for name in entries if name.endswith('.gd') and name + '.uid' not in entries}
    for shader in ('assets/mature/shaders/building_damage_soot.gdshader', 'assets/mature/menu/menu_backdrop.gdshader'):
        if shader in entries and shader + '.uid' not in entries:
            names.add(shader + '.uid')
    return names


def retain_actual(project, output, entries):
    """Success or failure evidence only, bounded named copies; never source files."""
    target = output / 'actual-generated'
    need(not target.exists() and not target.is_symlink(), 'Retention already consumed')
    target.mkdir()
    result = {'schema': 'vc-building-import-retention-v1', 'accepted': False, 'files': {}, 'errors': []}
    planned = []
    for kind in sorted(PAIRS):
        name = PREFIX + kind + '.gltf'
        base = '.godot/imported/' + kind + '.gltf-' + hashlib.md5(('res://' + name).encode()).hexdigest()
        planned.extend([(name + '.import', 'descriptors/' + kind + '.gltf.import', 8192),
                        (base + '.scn', 'compiled/' + Path(base).name + '.scn', 8 * 1024 * 1024),
                        (base + '.md5', 'compiled/' + Path(base).name + '.md5', 256)])
    planned.extend((name, 'uids/' + name, 20) for name in sorted(generated_uids(entries)))
    for source, destination, limit in planned:
            try:
                path = regular(project, source, limit)
                before = digest(path); dest = target / destination; dest.parent.mkdir(parents=True, exist_ok=True)
                with path.open('rb') as inp, dest.open('xb') as out:
                    while chunk := inp.read(1024 * 1024):
                        out.write(chunk)
                need(digest(dest) == before == digest(path), 'Generated artifact changed during retention')
                result['files'][source] = {'retained': destination, 'sha256': before, 'bytes': dest.stat().st_size}
            except (OSError, ValueError) as exc:
                result['errors'].append({'source': source, 'reason': str(exc)})
    (target / 'retention.json').write_text(json.dumps(result, indent=2, sort_keys=True) + '\n')
    return result

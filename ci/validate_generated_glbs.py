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

# Independent material checks. The generator is never imported here.
def png_rgb(raw):
    import zlib
    assert raw[:8] == b'\x89PNG\r\n\x1a\n'
    offset=8; compressed=bytearray(); header=None; ended=False
    while offset<len(raw):
        length,=struct.unpack_from('>I',raw,offset); tag=raw[offset+4:offset+8]; end=offset+12+length
        assert end<=len(raw)
        data=raw[offset+8:offset+8+length];crc,=struct.unpack_from('>I',raw,offset+8+length)
        assert zlib.crc32(tag+data)&0xffffffff==crc,'PNG CRC failure'
        if tag==b'IHDR':
            assert header is None and length==13; header=struct.unpack('>IIBBBBB',data)
        elif tag==b'IDAT': compressed.extend(data)
        elif tag==b'IEND': assert length==0; ended=True;offset=end;break
        offset=end
    assert ended and offset==len(raw) and header
    width,height,depth,color,compression,filtering,interlace=header
    assert 0<width<=1024 and 0<height<=1024 and depth==8 and color in (2,6)
    assert compression==filtering==interlace==0
    channels=3 if color==2 else 4; stride=width*channels; expected=(stride+1)*height
    decoder=zlib.decompressobj();data=decoder.decompress(bytes(compressed),expected+1)
    assert len(data)==expected and decoder.eof and not decoder.unused_data and not decoder.unconsumed_tail
    previous=bytearray(stride);rgb=bytearray(width*height*3)
    def paeth(a,b,c):
        p=a+b-c;d=(abs(p-a),abs(p-b),abs(p-c));return (a,b,c)[d.index(min(d))]
    for y in range(height):
        start=y*(stride+1);mode=data[start];assert 0<=mode<=4
        row=bytearray(data[start+1:start+1+stride])
        for x in range(stride):
            a=row[x-channels] if x>=channels else 0;b=previous[x];c=previous[x-channels] if x>=channels else 0
            if mode:row[x]=(row[x]+(a if mode==1 else b if mode==2 else (a+b)//2 if mode==3 else paeth(a,b,c)))&255
        for x in range(width):rgb[(y*width+x)*3:(y*width+x+1)*3]=row[x*channels:x*channels+3]
        previous=row
    return width,height,rgb


def check_material_inputs(root):
    assert sha(root/'input-manifest.json')==EXPECTED_MANIFEST
    manifest=json.loads((root/'input-manifest.json').read_text())
    assert not root.is_symlink() and all(not p.is_symlink() for p in root.rglob('*'))
    assert {p.relative_to(root).as_posix() for p in root.rglob('*') if p.is_file()}==set(manifest['files'])|{'input-manifest.json'}
    for n,entry in manifest['files'].items():assert sha(root/n)==entry['sha256']
    color_vertices=0
    for path in sorted(root.glob('*/*.gltf')):
        doc=json.loads(path.read_text());buffers=[(path.parent/b['uri']).read_bytes() for b in doc['buffers']]
        for material in doc['materials']:
            pbr=material['pbrMetallicRoughness'];assert pbr.get('baseColorFactor',[1]*4)==[1]*4 and material.get('alphaMode','OPAQUE')=='OPAQUE'
            tex=pbr['baseColorTexture'];assert tex.get('texCoord',0)==0 and not tex.get('extensions')
        for mesh in doc['meshes']:
            for prim in mesh['primitives']:
                index=prim['attributes'].get('COLOR_0')
                if index is None:continue
                a=doc['accessors'][index];assert 'sparse' not in a
                view=doc['bufferViews'][a['bufferView']];code={5121:'B',5123:'H',5126:'f'}[a['componentType']];width={'VEC3':3,'VEC4':4}[a['type']]
                size=struct.calcsize('<'+code*width);stride=view.get('byteStride',size);offset=view.get('byteOffset',0)+a.get('byteOffset',0)
                scale={5121:255,5123:65535}.get(a['componentType'],1) if a.get('normalized') else 1
                for i in range(a['count']):assert all(abs(x/scale-1)<1e-6 for x in struct.unpack_from('<'+code*width,buffers[view['buffer']],offset+i*stride))
                color_vertices+=a['count']
    assert color_vertices>10000
    return manifest


def inspect_material(path, kind, unit, root, input_manifest):
    audit=unit['atlas'];assert audit['size']==[1024,1024] and audit['field_uv']=='FieldUV' and audit['prop_uv']==[.125,.875]
    sources=audit['sources'];assert len(sources)==5 and len({s['sha256'] for s in sources})==5
    expected_names={'T_Peasant_BaseColor.png' if kind in ('villager','spearman') else 'T_Ranger_BaseColor.png','T_Regular_Male_Dark_BaseColor.png','T_Superhero_Male_Dark.png','T_Eye_Brown.png','T_Hair_1_BaseColor.png'}
    assert {Path(s['source']).name for s in sources}==expected_names
    bindings=audit['bindings'];assert bindings and {b['source_sha256'] for b in bindings}=={s['sha256'] for s in sources}
    assert all(b['rendered_color'] in ('white COLOR_0','none') and type(b['mapped_loops']) is int and b['mapped_loops']>0 and type(b['polygons']) is int and b['polygons']>0 for b in bindings)
    atlas_path=path.parent.parent/'textures'/(kind+'_atlas.png');raw=atlas_path.read_bytes();assert sha(atlas_path)==audit['atlas_sha256']
    width,height,pixels=png_rgb(raw);assert width==height==1024
    doc,binary,acc=parse_glb(path);image=doc['images'][0];view=doc['bufferViews'][image['bufferView']]
    assert binary[view.get('byteOffset',0):view.get('byteOffset',0)+view['byteLength']]==raw,'Embedded image differs from saved atlas'
    field_index=next(i for i,m in enumerate(doc['materials']) if m['name']=='field_textured')
    texture=doc['materials'][field_index]['pbrMetallicRoughness']['baseColorTexture'];assert texture.get('texCoord',0)==0 and not texture.get('extensions')
    assert doc['textures'][texture['index']]['source']==0
    primitive=next(p for p in doc['meshes'][0]['primitives'] if p['material']==field_index)
    assert {k for k in primitive['attributes'] if k.startswith('TEXCOORD_')}=={'TEXCOORD_0'}
    assert {k for k in primitive['attributes'] if k.startswith('COLOR_')}=={'COLOR_0'}
    uv=[(a,1-b) for a,b in acc(primitive['attributes']['TEXCOORD_0'])];colors=acc(primitive['attributes']['COLOR_0']);ids=[x[0] for x in acc(primitive['indices'])]
    assigned=set();regions=[];eye_crossings=0
    for index,source in enumerate(sources):
        n=source['source'];assert n in input_manifest['files'] and source['sha256']==input_manifest['files'][n]['sha256']
        assert not Path(n).is_absolute() and '..' not in Path(n).parts
        sw,sh,sp=png_rgb((root/n).read_bytes());assert sw<=512 and sh<=512
        low=source['tile_low'];span=source['tile_span'];minimum=source['uv_min'];maximum=source['uv_max']
        assert len(low)==len(span)==len(minimum)==len(maximum)==2 and all(type(x) is int for x in low+span)
        assert all(math.isfinite(x) for x in minimum+maximum) and all(1<=x<=3 for x in span)
        assert low==[math.floor(x) for x in minimum] and span==[max(low[a]+1,math.ceil(maximum[a]))-low[a] for a in range(2)]
        size=512 if index==0 else 256;ox,oy=(0,0) if index==0 else (512+((index-1)%2)*256,((index-1)//2)*256)
        assert source['gutter_pixels']==4
        tw,th=(size-8)//span[0],(size-8)//span[1];x,y,iw,ih=source['pixel_rect']
        assert [x,y,iw,ih]==[ox+4,oy+4,tw*span[0],th*span[1]]
        def pixel(px,py):return pixels[((1023-py)*1024+px)*3:((1023-py)*1024+px+1)*3]
        # Independently check repeated tiles and all four gutter edges in encoded PNG.
        for py in range(oy,oy+size,7):
            for px in range(ox,ox+size,7):assert pixel(px,py)==pixel(x+(px-x)%tw,y+(py-y)%th)
        mean=[sum(sp[c::3])/(sw*sh) for c in range(3)]
        actual=[sum(pixel(px,py)[c] for py in range(y,y+th) for px in range(x,x+tw))/(tw*th) for c in range(3)]
        assert max(abs(a-b) for a,b in zip(mean,actual))<5,'Atlas source color statistics mismatch'
        selected={i for i,p in enumerate(uv) if x/1024-2e-6<=p[0]<=(x+iw)/1024+2e-6 and y/1024-2e-6<=p[1]<=(y+ih)/1024+2e-6}
        assert selected and not assigned&selected;assigned|=selected
        recovered=[((uv[i][0]*1024-x)/iw*span[0]+low[0],(uv[i][1]*1024-y)/ih*span[1]+low[1]) for i in selected]
        assert all(abs(min(p[a] for p in recovered)-minimum[a])<2e-4 and abs(max(p[a] for p in recovered)-maximum[a])<2e-4 for a in (0,1)),'UV envelope lost or clamped'
        assert all(all(abs(c-1)<1e-5 for c in colors[i]) for i in selected),'Source white COLOR_0 changed'
        loops=sum(i in selected for i in ids);expected_loops=sum(b['mapped_loops'] for b in bindings if b['source_sha256']==source['sha256'])
        assert loops==expected_loops,'Source material loop coverage lost'
        if Path(n).name=='T_Eye_Brown.png':
            assert span[0]==2 and maximum[0]>1
            seam=(x+(1-low[0])/span[0]*iw)/1024
            eye_crossings=sum(all(i in selected for i in ids[j:j+3]) and min(uv[i][0] for i in ids[j:j+3])<seam<max(uv[i][0] for i in ids[j:j+3]) for j in range(0,len(ids),3))
            assert eye_crossings>0,'Eye repeat seam lost'
        regions.append({'source_sha256':source['sha256'],'referenced_vertices':len(selected),'mapped_index_loops':loops,'rgb_mean_max_error':max(abs(a-b) for a,b in zip(mean,actual))})
    props=set(range(len(uv)))-assigned;assert props and all(abs(uv[i][0]-.125)<1e-6 and abs(uv[i][1]-.875)<1e-6 for i in props)
    at=((1023-896)*1024+128)*3;assert pixels[at:at+3]==b'\xff\xff\xff'
    return {'atlas_sha256':audit['atlas_sha256'],'source_regions':regions,'eye_triangles_crossing_repeat_seam':eye_crossings,'sole_texcoord':0,'embedded_png_exact':True}


def validate(root, inputs_root):
    input_manifest=check_material_inputs(inputs_root)
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
        output['units'][kind]['material']=inspect_material(path,kind,unit,inputs_root,input_manifest)
    return output

if __name__ == '__main__':
    parser = argparse.ArgumentParser(); parser.add_argument('--output-root', required=True, type=Path); parser.add_argument('--report', required=True, type=Path); parser.add_argument('--inputs', required=True, type=Path)
    args = parser.parse_args(); result = validate(args.output_root.resolve(),args.inputs.resolve())
    with args.report.open('x') as f: json.dump(result, f, indent=2); f.write('\n')
    print('GENERATED_GLB_DATA_PASS')

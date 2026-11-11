#!/usr/bin/env python3
"""Bounded stdlib inspection of authored bytes. Never starts Godot/Blender/browser."""
from pathlib import Path
import argparse
import hashlib
import json
import math
import struct

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'assets/advanced_buildings'
SIZES={'stable':3,'workshop':3,'tower':2,'farm':3}
HEIGHTS={'stable':2.375,'workshop':3.020,'tower':3.910,'farm':.727}
TEXTURED={'stone','oak','plaster','slate','clay'}
checks=0


def check(ok,label):
    global checks
    checks+=1
    if not ok:raise AssertionError(label)


def inspect(kind,base):
    j=json.loads((OUT/(kind+'.gltf')).read_text())
    check(j['asset']['version']=='2.0','glTF version')
    check(set(j['nodes'][0])=={'name','mesh'} and len(j['nodes'])==1,'one static node, no scripts/transforms')
    check(not any(k in j for k in ['skins','animations','extensionsRequired']),'no special importer requirements')
    raw=(OUT/(kind+'.bin')).read_bytes()
    check(len(raw)==j['buffers'][0]['byteLength'],'exact buffer bytes')
    check(j['buffers'][0]['uri']==kind+'.bin','local only geometry buffer')
    def accessor(index):
        a=j['accessors'][index];v=j['bufferViews'][a['bufferView']]
        check(a['componentType']==5126,'float source attributes')
        width={'VEC3':3,'VEC2':2,'VEC4':4}[a['type']]
        check(v['byteOffset']%4==0 and v['byteLength']==a['count']*width*4,'aligned tight float buffer')
        check(v['byteOffset']+v['byteLength']<=len(raw),'accessor in buffer')
        result=list(struct.iter_unpack('<'+'f'*width,raw[v['byteOffset']:v['byteOffset']+v['byteLength']]))
        for row in result:check(all(math.isfinite(v) for v in row),'finite vertex attributes')
        if 'min' in a:
            for axis in range(3):
                check(abs(min(v[axis] for v in result)-a['min'][axis])<1e-5,'accurate accessor min')
                check(abs(max(v[axis] for v in result)-a['max'][axis])<1e-5,'accurate accessor max')
        return result
    all_points=[];count=0;area_by_material={}
    for prim in j['meshes'][0]['primitives']:
        p=accessor(prim['attributes']['POSITION']);n=accessor(prim['attributes']['NORMAL'])
        uv=accessor(prim['attributes']['TEXCOORD_0']);color=accessor(prim['attributes']['COLOR_0'])
        check(len(p)==len(n)==len(uv)==len(color) and len(p)%3==0,'attribute count and triangles')
        for rgba in color:
            check(all(0.0<=component<=1.0 for component in rgba),'COLOR_0 components in legal glTF [0,1] range')
        check(all(0.0<=component<=1.0 for component in j['materials'][prim['material']]['pbrMetallicRoughness'].get('baseColorFactor',[1,1,1,1])),'baseColorFactor components in legal glTF [0,1] range')
        material=j['materials'][prim['material']]['name'];area=0
        for i in range(0,len(p),3):
            a,b,c=p[i:i+3];u=tuple(b[k]-a[k] for k in range(3));v=tuple(c[k]-a[k] for k in range(3))
            cr=(u[1]*v[2]-u[2]*v[1],u[2]*v[0]-u[0]*v[2],u[0]*v[1]-u[1]*v[0]);length=math.sqrt(sum(v*v for v in cr))
            check(length>1e-10,'nondegenerate source triangles')
            check(sum(cr[k]*n[i][k] for k in range(3))/length>.999,'outward normal follows glTF CCW front')
            for normal in n[i:i+3]:check(abs(sum(x*x for x in normal)-1)<1e-5,'unit normal')
            area+=length*.5
        area_by_material[material]=area;all_points+=p;count+=len(p)//3
        if material=='team_blue':
            check('baseColorTexture' not in j['materials'][prim['material']]['pbrMetallicRoughness'],'cloth batch only, no roof texture')
            check(area<.75,'limited faction cloth area')
    check(count<=3000,'triangle ceiling')
    check(len(j['materials'])<=6,'six surfaces maximum')
    check(len({m['name'] for m in j['materials']})==len(j['materials']),'material batching')
    check(all(m['name'] in TEXTURED|{'palette','team_blue'} for m in j['materials']),'shared material palette')
    check(all(m.get('alphaMode','OPAQUE')=='OPAQUE' and not m.get('doubleSided',False) for m in j['materials']),'opaque culled surfaces')
    lo=[min(p[i] for p in all_points) for i in range(3)];hi=[max(p[i] for p in all_points) for i in range(3)]
    check(all(abs(p[axis])<=SIZES[kind]/2 for p in all_points for axis in [0,2]),'all geometry fits logical footprint')
    check(abs(lo[1])<1e-6,'grounded foundation')
    check(abs(hi[1]-HEIGHTS[kind])<.001,'declared height is measured')
    check(HEIGHTS[kind]+.25-.035>hi[1]+.20,'health bar bottom clears highest vertex')
    textures=[]
    for img in j['images']:
        uri=img['uri'];check(uri in ['../mature/textures/'+s+'.png' for s in TEXTURED],'only exact existing project textures')
        target=base/'assets/mature/textures'/Path(uri).name
        check(target.is_file() and not target.is_symlink(),'shared texture exists')
        textures.append({'path':target.relative_to(base).as_posix(),'sha256':hashlib.sha256(target.read_bytes()).hexdigest()})
    return {'kind':kind,'triangles':count,'surfaces':len(j['materials']),'min':lo,'max':hi,'health_bar_y':HEIGHTS[kind]+.25,'footprint':SIZES[kind],'material_surface_area':area_by_material,'textures':textures}


def main():
    p=argparse.ArgumentParser();p.add_argument('--base-game',type=Path,default=ROOT);args=p.parse_args()
    report={'status':'PASS_SOURCE_DATA_ONLY','models':[inspect(kind,args.base_game) for kind in SIZES],
            'engine_import_semantics':'NOT_RUN','render_visual_phone':'NOT_RUN','checks':checks}
    print(json.dumps(report,indent=2))


if __name__=='__main__':main()

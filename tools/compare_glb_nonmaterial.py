#!/usr/bin/env python3
"""Read-only independent GLB comparison; ignores only UV/color/image/material data."""
import argparse, collections, hashlib, json, pathlib, struct
FORMATS={5120:('b',1),5121:('B',1),5122:('h',2),5123:('H',2),5125:('I',4),5126:('f',4)}
WIDTHS={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4,'MAT4':16}
def read_glb(path):
    data=pathlib.Path(path).read_bytes()
    assert data[:4]==b'glTF' and struct.unpack_from('<II',data,4)==(2,len(data))
    chunks=[];offset=12
    while offset<len(data):
        size,kind=struct.unpack_from('<II',data,offset);offset+=8
        assert offset+size<=len(data);chunks.append((kind,data[offset:offset+size]));offset+=size
    assert len(chunks)==2 and chunks[0][0]==0x4e4f534a and chunks[1][0]==0x004e4942
    doc=json.loads(chunks[0][1]);binary=chunks[1][1]
    def acc(index):
        a=doc['accessors'][index];assert 'sparse' not in a and not a.get('normalized',False)
        view=doc['bufferViews'][a['bufferView']];fmt,width=FORMATS[a['componentType']];n=WIDTHS[a['type']]
        stride=view.get('byteStride',width*n);start=view.get('byteOffset',0)+a.get('byteOffset',0)
        assert start+(a['count']-1)*stride+width*n<=len(binary)
        return [tuple(struct.unpack_from('<'+fmt*n,binary,start+i*stride)) for i in range(a['count'])]
    return doc,acc

def nonmaterial(path):
    d,acc=read_glb(path)
    assert set(d) <= {'asset','extensionsUsed','extensionsRequired','scene','scenes','nodes','animations','materials','meshes','textures','images','skins','accessors','bufferViews','samplers','buffers'}
    assert all(x.startswith('KHR_materials_') for x in d.get('extensionsUsed',[])+d.get('extensionsRequired',[]))
    assert all(set(m) <= {'name','primitives'} for m in d['meshes'])
    assert all(set(s) <= {'name','joints','inverseBindMatrices','skeleton'} for s in d['skins'])
    assert all(set(n) <= {'name','children','mesh','skin','matrix','translation','rotation','scale'} for n in d['nodes'])
    joints=[[d['nodes'][n].get('name',str(n)) for n in s['joints']] for s in d['skins']]
    triangles=[];geometry_counts=[]
    for mesh in d['meshes']:
        for p in mesh['primitives']:
            assert p.get('mode',4)==4 and set(p) <= {'attributes','indices','material','mode'}
            attrs=p['attributes'];keys=sorted(k for k in attrs if not k.startswith(('TEXCOORD_','COLOR_')))
            assert {'POSITION','NORMAL','JOINTS_0','WEIGHTS_0'} <=set(keys)
            values={k:acc(attrs[k]) for k in keys};idx=[v[0] for v in acc(p['indices'])]
            assert len(idx)%3==0
            material=d['materials'][p['material']]['name']
            for i in range(0,len(idx),3):
                vertices=tuple(tuple((k,values[k][v]) for k in keys) for v in idx[i:i+3])
                # Preserve winding, permit only cyclic rotation or face order changes.
                vertices=min(vertices,vertices[1:]+vertices[:1],vertices[2:]+vertices[:2])
                triangles.append((material,vertices))
            geometry_counts.append({'material':material,'triangles':len(idx)//3})
    animation={}
    for a in d['animations']:
        assert set(a) <= {'name','channels','samplers'}
        channels=[]
        for c in a['channels']:
            sampler=a['samplers'][c['sampler']];target=c['target'];node=d['nodes'][target['node']]['name']
            assert set(c)=={'sampler','target'} and set(target)=={'node','path'} and set(sampler)<={'input','output','interpolation'}
            channels.append((node,target['path'],sampler.get('interpolation','LINEAR'),acc(sampler['input']),acc(sampler['output'])))
        animation[a['name']]=sorted(channels)
    skins=[{'joints':joints[i],'inverse_bind_matrices':acc(s['inverseBindMatrices']),'skeleton':d['nodes'][s['skeleton']].get('name') if 'skeleton'in s else None,'name':s.get('name')} for i,s in enumerate(d['skins'])]
    nodes=[{k:v for k,v in n.items() if k not in ('extras','extensions')} for n in d['nodes']]
    return {'triangles':sorted(triangles),'animation':animation,'skins':skins,'nodes':nodes,'geometry_counts':geometry_counts,'scene':d.get('scene'),'scenes':d['scenes'],'mesh_names':[m.get('name') for m in d['meshes']]}

def main():
    p=argparse.ArgumentParser();p.add_argument('before',type=pathlib.Path);p.add_argument('after',type=pathlib.Path);p.add_argument('--report',type=pathlib.Path,required=True);a=p.parse_args()
    assert a.report.resolve().is_relative_to(pathlib.Path(__file__).resolve().parent)
    b,c=nonmaterial(a.before),nonmaterial(a.after)
    results={k:b[k]==c[k] for k in b}
    report={'scope':'Independent non-material GLB data, exact decoded numeric equality; not render acceptance','before':str(a.before),'after':str(a.after),'before_sha256':hashlib.sha256(a.before.read_bytes()).hexdigest(),'after_sha256':hashlib.sha256(a.after.read_bytes()).hexdigest(),'equal':results,'passed':all(results.values()),'before_geometry_counts':b['geometry_counts'],'after_geometry_counts':c['geometry_counts']}
    a.report.write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2))
if __name__=='__main__':main()

#!/usr/bin/env python3
"""Deterministically author glTF data. Standard library only, no engine or renderer.

Original project architecture with two explicitly attributed CC0 detail meshes.
All completed geometry is baked by material, not generated during gameplay.
Coordinates are metres, +Y up, +Z entrance, CCW glTF fronts. No colliders/scripts.
"""
from pathlib import Path
import collections
import hashlib
import json
import math
import struct

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'assets/advanced_buildings'
UPSTREAM = ROOT / 'art/advanced_buildings/upstream'
TEXTURES = ('stone', 'oak', 'plaster', 'slate', 'clay')
COLORS = {'iron': (0.30, 0.33, 0.33, 1), 'dark': (0.075, 0.085, 0.075, 1),
          'straw': (0.69, 0.57, 0.29, 1), 'earth': (0.24, 0.17, 0.105, 1),
          'linen': (0.73, 0.69, 0.56, 1), 'grain': (0.78, 0.67, 0.37, 1),
          'green': (0.30, 0.36, 0.18, 1)}
WHITE = (1, 1, 1, 1)


def add(a, b): return tuple(x+y for x, y in zip(a, b))
def sub(a, b): return tuple(x-y for x, y in zip(a, b))
def mul(a, s): return tuple(x*s for x in a)
def dot(a, b): return sum(x*y for x, y in zip(a, b))
def cross(a, b): return (a[1]*b[2]-a[2]*b[1], a[2]*b[0]-a[0]*b[2], a[0]*b[1]-a[1]*b[0])
def norm(a): return mul(a, 1/math.sqrt(dot(a, a)))


class Model:
    def __init__(self, kind):
        self.kind = kind
        self.batches = collections.defaultdict(list)
        self.parts = []
        self.origin = (0, 0, 0)
        self.angle = 0

    def transform(self, p):
        c, s = math.cos(self.angle), math.sin(self.angle)
        return add((c*p[0]+s*p[2], p[1], -s*p[0]+c*p[2]), self.origin)

    def tri(self, a, b, c, material, shade=WHITE):
        local = (a, b, c)
        a, b, c = (self.transform(v) for v in local)
        n = cross(sub(b, a), sub(c, a))
        if dot(n, n) < 1e-14: return
        n = norm(n)
        if material in COLORS:
            shade = tuple(x*y for x, y in zip(COLORS[material], shade))
            material = 'palette'
        for p in (a, b, c):
            uv = (p[0], p[2]) if abs(n[1]) > .5 else ((p[2], -p[1]) if abs(n[0]) > .5 else (p[0], -p[1]))
            scale = .7 * (.45 if material in ('slate', 'clay') else 1)
            self.batches[material].append((p, n, tuple(v*scale for v in uv), shade))

    def quad(self, a, b, c, d, material, shade=WHITE):
        self.tri(a, b, c, material, shade)
        self.tri(a, c, d, material, shade)

    def box(self, center, size, material, shade=WHITE):
        x, y, z = center; w, h, d = (n/2 for n in size)
        p = [(x+sx*w, y+sy*h, z+sz*d) for sx, sy, sz in
             [(-1,-1,-1),(1,-1,-1),(1,1,-1),(-1,1,-1),(-1,-1,1),(1,-1,1),(1,1,1),(-1,1,1)]]
        for a,b,c,d in [(0,3,2,1),(4,5,6,7),(0,4,7,3),(1,2,6,5),(3,7,6,2),(0,1,5,4)]:
            self.quad(p[a],p[b],p[c],p[d],material,shade)

    def beam(self, a, b, radius, material='oak', sides=6, end_radius=None):
        axis = norm(sub(b,a)); side = cross(axis,(0,1,0))
        if dot(side,side)<.01: side=cross(axis,(1,0,0))
        side=norm(side); other=cross(axis,side)
        er=radius if end_radius is None else end_radius
        for i in range(sides):
            r1=add(mul(side,math.cos(2*math.pi*i/sides)),mul(other,math.sin(2*math.pi*i/sides)))
            r2=add(mul(side,math.cos(2*math.pi*(i+1)/sides)),mul(other,math.sin(2*math.pi*(i+1)/sides)))
            a1,a2=add(a,mul(r1,radius)),add(a,mul(r2,radius))
            b1,b2=add(b,mul(r1,er)),add(b,mul(r2,er))
            self.quad(a1,a2,b2,b1,material)
            self.tri(a,a2,a1,material); self.tri(b,b1,b2,material)

    def tapered(self, center, width, depth, height, top_scale, material):
        x,y,z=center; lo=y-height/2; hi=y+height/2
        p=[(x+sx*width/2,yv,z+sz*depth/2) for yv in [lo] for sx,sz in [(-1,-1),(1,-1),(1,1),(-1,1)]]
        p += [(x+sx*width*top_scale/2,hi,z+sz*depth*top_scale/2) for sx,sz in [(-1,-1),(1,-1),(1,1),(-1,1)]]
        for a,b,c,d in [(0,1,2,3),(4,7,6,5),(0,4,5,1),(1,5,6,2),(2,6,7,3),(3,7,4,0)]:
            self.quad(p[a],p[b],p[c],p[d],material)

    def roof(self, width, depth, eave, rise, material='slate', gables=True):
        w,d=width/2,depth/2
        self.quad((-w,eave,d),(w,eave,d),(w,eave+rise,0),(-w,eave+rise,0),material)
        self.quad((w,eave,-d),(-w,eave,-d),(-w,eave+rise,0),(w,eave+rise,0),material)
        if gables:
            self.tri((-w,eave,-d),(-w,eave,d),(-w,eave+rise,0),'plaster')
            self.tri((w,eave,d),(w,eave,-d),(w,eave+rise,0),'plaster')
        self.beam((-w,eave+rise,0),(w,eave+rise,0),.045,'oak',4)
        for x in [-w,w]:
            for s in [-1,1]:self.beam((x,eave,s*d),(x,eave+rise,0),.045,'oak',4)
        for z in [-d,d]:self.box((0,eave-.025,z),(width,.07,.08),'oak')
        # Broken slate/clay courses add real relief, while the shared texture
        # supplies smaller detail. Faction colour never replaces these roofs.
        for row in range(1,6):
            t=row/6
            for s in [-1,1]:
                self.beam((-w,eave+rise*t+.01,s*d*(1-t)),(w,eave+rise*t+.01,s*d*(1-t)),.012,material,4)

    def banner(self, x,y,z,w=.25,h=.55):
        # A notched double-sided pennon, with a small neutral heraldic stripe.
        p=[(x-w/2,y+h/2,z),(x+w/2,y+h/2,z),(x+w/2,y-h/2,z),(x,y-h*.34,z),(x-w/2,y-h/2,z)]
        for i in range(1,4):
            self.tri(p[0],p[i+1],p[i],'team_blue')
            self.tri(p[0],p[i],p[i+1],'team_blue')
        self.box((x,y+.03,z+.008),(w*.13,h*.67,.018),'linen')
        self.beam((x-w*.65,y+h*.55,z),(x+w*.65,y+h*.55,z),.021,'oak',4)

    def barrel(self,x,y,z,r=.15,h=.36):
        self.beam((x,y,z),(x,y+h,z),r,'oak',10)
        for yy in [y+.07,y+h-.06]:
            for i in range(10):
                a=2*math.pi*i/10;b=2*math.pi*(i+1)/10
                self.beam((x+math.cos(a)*r*1.02,yy,z+math.sin(a)*r*1.02),(x+math.cos(b)*r*1.02,yy,z+math.sin(b)*r*1.02),.015,'iron',4)

    def source_prop(self,name,center,scale,material,angle=0):
        # Import only raw triangle POSITION/indices, not source materials/textures.
        # No executables, extras, scripts, URI network access or external loaders.
        j=json.loads((UPSTREAM/(name+'.gltf')).read_text())
        assert len(j['nodes'])==1 and set(j['nodes'][0])<= {'mesh','name'}
        assert len(j['buffers'])==1 and j['buffers'][0]['uri']==name+'.bin'
        raw=(UPSTREAM/(name+'.bin')).read_bytes()
        def accessor(index):
            a=j['accessors'][index]; v=j['bufferViews'][a['bufferView']]
            fmt={5126:'f',5123:'H',5125:'I'}[a['componentType']]
            width={'VEC3':3,'SCALAR':1}[a['type']]
            step=v.get('byteStride',struct.calcsize('<'+fmt)*width)
            start=v.get('byteOffset',0)+a.get('byteOffset',0)
            return [struct.unpack_from('<'+fmt*width,raw,start+i*step) for i in range(a['count'])]
        old_origin,old_angle=self.origin,self.angle
        self.origin=center;self.angle=angle
        for primitive in j['meshes'][0]['primitives']:
            assert primitive.get('mode',4)==4
            v=accessor(primitive['attributes']['POSITION']); ids=[i[0] for i in accessor(primitive['indices'])]
            for i in range(0,len(ids),3):
                p=[tuple(v[ids[i+k]][axis]*scale[axis] for axis in range(3)) for k in range(3)]
                self.tri(*p,material)
        self.origin,self.angle=old_origin,old_angle
        self.parts.append({'source':name,'position':center,'scale':scale,'rotation_y':angle,'material':material})


def stable():
    m=Model('stable')
    m.box((0,.065,-.20),(2.62,.13,2.30),'stone')
    m.box((0,.72,-.99),(2.40,1.30,.13),'plaster')
    for x in [-1.18,1.18]:m.box((x,.72,-.25),(.12,1.30,1.56),'plaster')
    for x in [-1.18,-.40,.40,1.18]:
        for z in [-.98,.53]:m.box((x,.85,z),(.11,1.56,.11),'oak')
    for z in [-1.0,.55]:m.box((0,1.57,z),(2.50,.12,.12),'oak')
    for x in [-.4,.4]:m.box((x,.43,-.11),(.10,.61,1.27),'oak')
    for x in [-.79,0,.79]:
        # Half-height stall doors keep the recessed stable openings legible.
        m.box((x,.37,.56),(.67,.45,.065),'oak')
        for y in [.20,.52]:m.box((x,y,.604),(.67,.055,.035),'iron')
        m.box((x,.16,-.37),(.57,.08,.84),'straw')
        m.beam((x-.26,1.51,.59),(x+.26,1.13,.59),.025,'oak',4)
    m.origin=(0,0,-.22);m.roof(2.68,1.94,1.68,.65,'clay');m.origin=(0,0,0)
    # Upper hayloft opening and practical long hitching rail.
    m.box((-1.346,1.88,-.22),(.014,.26,.34),'dark')
    for z in [-.34,-.10]:m.box((-1.358,1.88,z),(.025,.28,.025),'oak')
    for x in [-1.15,.78]:m.beam((x,.1,1.10),(x,.74,1.10),.048,'oak',6)
    m.beam((-1.22,.62,1.10),(.85,.62,1.10),.04,'oak',6)
    m.barrel(1.06,.13,.89,.16,.40)
    m.source_prop('Prop_Crate',(-.96,.13,.77),(.32,.32,.32),'oak',.11)
    m.box((0,1.44,.62),(.42,.32,.045),'oak')
    # Horseshoe silhouette, open at the top; no miniature horse/unit duplication.
    for i in range(10):
        a=math.pi*.12+math.pi*1.76*i/10;b=math.pi*.12+math.pi*1.76*(i+1)/10
        m.beam((math.sin(a)*.105,1.47+math.cos(a)*.105,.66),(math.sin(b)*.105,1.47+math.cos(b)*.105,.66),.022,'iron',4)
    m.banner(.98,1.20,.62,.22,.48)
    return m


def workshop():
    m=Model('workshop')
    m.box((-.23,.065,-.23),(2.12,.13,2.40),'stone')
    m.box((-.30,.79,-1.00),(1.70,1.40,.14),'plaster')
    m.box((-1.10,.79,-.23),(.14,1.40,1.55),'plaster')
    for x in [-1.10,.51]:
        for z in [-.99,.54]:m.box((x,.88,z),(.13,1.63,.13),'oak')
    for z in [-1,.57]:m.box((-.30,1.63,z),(1.82,.13,.13),'oak')
    m.origin=(-.30,0,-.22);m.roof(1.96,1.98,1.72,.66);m.origin=(0,0,0)
    m.source_prop('Prop_Chimney2',(.62,.15,-.68),(.48,.92,.48),'stone')
    m.box((.608,2.96,-.68),(.54,.10,.54),'stone')
    m.box((.608,3.014,-.68),(.30,.012,.30),'dark')
    # Real open forge bay with ash-dark hearth, layered voussoirs and anvil horn.
    m.box((.33,.31,-.47),(.87,.36,.78),'stone')
    m.box((.33,.66,-.78),(.87,.48,.16),'stone')
    m.box((.33,.65,-.35),(.59,.42,.025),'dark')
    for x in [-.06,.72]:m.box((x,.63,-.35),(.18,.55,.28),'stone')
    for i in range(6):
        a=i*math.pi/6;b=(i+1)*math.pi/6
        p=[(.33+math.cos(t)*r,.65+math.sin(t)*r,-.18) for t,r in [(a,.27),(a,.43),(b,.43),(b,.27)]]
        m.quad(*p,'stone')
    m.box((.33,.48,-.22),(.58,.04,.36),'dark')
    m.box((-.49,.57,.71),(1.17,.13,.47),'oak')
    for x in [-.96,-.02]:
        for z in [.56,.86]:m.box((x,.31,z),(.08,.48,.08),'oak')
    m.tapered((-.47,.75,.70),.33,.24,.25,.57,'iron')
    m.box((-.46,.90,.70),(.48,.09,.25),'iron')
    m.beam((-.23,.90,.70),(-.02,.88,.70),.08,'iron',6,.012)
    # Four-spoked cart wheel leaned in the yard. This is a static spare wheel,
    # not a repurposed siege unit and not a copied cavalry/ram asset.
    cx,cy,cz=1.04,.50,.68
    for i in range(12):
        a=i*2*math.pi/12;b=(i+1)*2*math.pi/12
        m.beam((cx+math.cos(a)*.35,cy+math.sin(a)*.35,cz),(cx+math.cos(b)*.35,cy+math.sin(b)*.35,cz),.04,'oak',4)
    for a in [0,math.pi/2]:m.beam((cx+math.cos(a)*.33,cy+math.sin(a)*.33,cz),(cx-math.cos(a)*.33,cy-math.sin(a)*.33,cz),.026,'oak',4)
    m.beam((cx,cy,cz-.06),(cx,cy,cz+.07),.075,'iron',8)
    for i in range(3):m.beam((.98,.19+i*.13,-1.16),(.98,.19+i*.13,-.29),.075,'oak',7)
    m.source_prop('Prop_Crate',(-.92,.13,-.57),(.34,.34,.34),'oak')
    m.banner(-1.02,1.27,.66,.23,.49)
    return m


def tower():
    m=Model('tower')
    m.box((0,.09,0),(1.72,.18,1.72),'stone')
    m.tapered((0,1.44,0),1.36,1.36,2.52,.88,'stone')
    for y in [.27,1.14,2.12]:m.box((0,y,0),(1.39 if y<1 else 1.31,.09,1.39 if y<1 else 1.31),'stone')
    # Banded corners make the tall stone shaft read as masonry, not one prism.
    for level in range(7):
        y=.44+level*.28; side=.67-(y-.18)*.030
        for sx in [-1,1]:
            for sz in [-1,1]:m.box((sx*(side-.045),y,sz*(side-.045)),(.19,.18,.19),'stone',(1.0,.98,.92,1))
    m.box((0,.64,.695),(.40,.92,.036),'oak')
    for y in [.35,.83]:m.box((0,y,.72),(.40,.045,.025),'iron')
    m.box((0,.11,.82),(.66,.12,.22),'stone')
    for z in [-.65,.65]:
        m.box((0,1.76,z),(.095,.49,.025),'dark')
        m.box((0,1.70,z*1.01),(.22,.05,.026),'dark')
    for x in [-.65,.65]:
        m.box((x,1.76,0),(.025,.49,.095),'dark')
        m.box((x*1.01,1.70,0),(.026,.05,.22),'dark')
    # Cantilevered gallery with brackets and crenellations: a distinct military
    # silhouette, open to the sky, no unrelated cottage roof substituted.
    m.box((0,2.76,0),(1.76,.18,1.76),'stone')
    for sx in [-1,1]:
        for z in [-.56,0,.56]:m.beam((sx*.58,2.30,z),(sx*.82,2.68,z),.075,'oak',4)
    for sz in [-1,1]:
        for x in [-.56,0,.56]:m.beam((x,2.30,sz*.58),(x,2.68,sz*.82),.075,'oak',4)
    m.box((0,2.86,0),(1.44,.06,1.44),'oak')
    for s in [-1,1]:
        m.box((0,3.01,s*.77),(1.74,.26,.20),'stone')
        m.box((s*.77,3.01,0),(.20,.26,1.34),'stone')
        for t in [-.68,0,.68]:
            m.box((t,3.30,s*.77),(.34,.34,.22),'stone')
        for t in [0]:m.box((s*.77,3.30,t),(.22,.34,.34),'stone')
    m.beam((-.48,2.91,-.37),(-.48,3.91,-.37),.025,'oak',6)
    m.banner(-.26,3.66,-.37,.40,.30)
    m.banner(0,2.29,.69,.30,.55)
    return m


def farm():
    m=Model('farm')
    m.box((0,.035,0),(2.74,.07,2.74),'earth')
    # Footprint-wide cultivated rows, paths and mature grain are visible from
    # a high RTS camera. Every ear is solid geometry, with no alpha overdraw.
    for row in range(6):
        x=-1.10+row*.44
        m.tapered((x,.09,-.02),.26,2.20,.10,.70,'earth')
        for plant in range(8):
            z=-.96+plant*.265
            # Two opposed leaves and a tapered grain head form a wheat tuft.
            y=.37+.035*((row*3+plant)%4)
            dx=.025*((plant%3)-1)
            m.beam((x,.11,z),(x+dx,y,z),.012,'straw',4,.008)
            m.beam((x+dx,y-.025,z),(x+dx+.025,y+.11,z),.035,'grain',5,.008)
            for s in [-1,1]:
                a=(x,.23,z);b=(x+s*.11,.34,z+.03);c=(x+s*.025,.31,z-.015)
                m.tri(a,b,c,'green');m.tri(a,c,b,'green')
    # Split-rail boundary has a full central working entrance, no fake wall
    # or occupied navigation outside the existing 3 x 3 farm footprint.
    for x in [-1.29,1.29]:
        for z in [-1.28,0,1.28]:m.beam((x,.07,z),(x,.54,z),.035,'oak',5)
        for y in [.24,.44]:m.beam((x,y,-1.28),(x,y,1.28),.024,'oak',4)
    for x1,x2 in [(-1.29,-.49),(.49,1.29)]:
        for y in [.24,.44]:m.beam((x1,y,1.28),(x2,y,1.28),.024,'oak',4)
    m.box((0,.075,1.20),(.64,.08,.34),'stone')
    m.beam((-.40,.07,1.27),(-.40,.72,1.27),.025,'oak',5)
    m.banner(-.24,.59,1.27,.25,.21)
    return m


def save(model):
    binary=bytearray(); views=[];accessors=[];primitives=[];materials=[];images=[];textures=[]
    def store(values,width,atype):
        while len(binary)%4:binary.append(0)
        start=len(binary)
        for value in values:binary.extend(struct.pack('<'+'f'*width,*value))
        views.append({'buffer':0,'byteOffset':start,'byteLength':len(binary)-start,'target':34962})
        a={'bufferView':len(views)-1,'componentType':5126,'count':len(values),'type':atype}
        if atype=='VEC3':a.update(min=[min(v[i] for v in values) for i in range(3)],max=[max(v[i] for v in values) for i in range(3)])
        accessors.append(a);return len(accessors)-1
    for key,verts in sorted(model.batches.items()):
        pbr={'metallicFactor':0,'roughnessFactor':.90}
        if key in TEXTURES:
            images.append({'uri':'../mature/textures/'+key+'.png'})
            textures.append({'sampler':0,'source':len(images)-1})
            pbr['baseColorTexture']={'index':len(textures)-1}
        if key=='team_blue':pbr['baseColorFactor']=[.263,.365,.424,1]
        materials.append({'name':key,'pbrMetallicRoughness':pbr})
        attrs={name:store([v[i] for v in verts],width,typ) for i,(name,width,typ) in enumerate([('POSITION',3,'VEC3'),('NORMAL',3,'VEC3'),('TEXCOORD_0',2,'VEC2'),('COLOR_0',4,'VEC4')])}
        primitives.append({'attributes':attrs,'material':len(materials)-1,'mode':4})
    gltf={'asset':{'version':'2.0','generator':'Valley Crown original bounded data authoring'},'scene':0,'scenes':[{'nodes':[0]}],
          'nodes':[{'name':'AdvancedBuilding_'+model.kind,'mesh':0}],'meshes':[{'name':model.kind+'_material_batches','primitives':primitives}],
          'materials':materials,'buffers':[{'uri':model.kind+'.bin','byteLength':len(binary)}],'bufferViews':views,'accessors':accessors,
          'images':images,'textures':textures,'samplers':[{'magFilter':9729,'minFilter':9987,'wrapS':10497,'wrapT':10497}]}
    OUT.mkdir(parents=True,exist_ok=True)
    (OUT/(model.kind+'.bin')).write_bytes(binary)
    (OUT/(model.kind+'.gltf')).write_text(json.dumps(gltf,separators=(',',':'))+'\n')
    points=[v[0] for vertices in model.batches.values() for v in vertices]
    return {'kind':model.kind,'triangles':len(points)//3,'surfaces':len(materials),'vertices':len(points),
            'bounds_min':[min(p[i] for p in points) for i in range(3)],'bounds_max':[max(p[i] for p in points) for i in range(3)],
            'source_props':model.parts,'sha256':{ext:hashlib.sha256((OUT/(model.kind+ext)).read_bytes()).hexdigest() for ext in ('.gltf','.bin')}}


def main():
    report=[save(fn()) for fn in (stable,workshop,tower,farm)]
    path=ROOT/'art/advanced_buildings/geometry.json'
    path.write_text(json.dumps({'status':'SOURCE_GEOMETRY_ONLY','models':report,'engine_import':'NOT_RUN','visual_acceptance':'NOT_RUN'},indent=2)+'\n')
    print(json.dumps(report,indent=2))


if __name__=='__main__':main()

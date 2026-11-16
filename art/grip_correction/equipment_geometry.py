"""Original low-poly equipment in a calibrated grip frame; no external assets.
Axes: +Z follows knuckle row/haft; +Y points away from the palm; +X completes RH frame.
The grip is always at (0,0,0). Dimensions are modelling choices, not hand offsets.
"""
import math

def cylinder(a,b,radius,sides=10):
    # Pure Python geometry is independently testable without Blender.
    delta=[b[i]-a[i] for i in range(3)];length=math.sqrt(sum(x*x for x in delta))
    assert length>1e-7 and radius>0 and 6<=sides<=16
    axis=[x/length for x in delta];ref=[1.,0.,0.] if abs(axis[0])<.8 else [0.,1.,0.]
    def cross(u,v):return [u[1]*v[2]-u[2]*v[1],u[2]*v[0]-u[0]*v[2],u[0]*v[1]-u[1]*v[0]]
    x=cross(axis,ref);norm=math.sqrt(sum(v*v for v in x));x=[v/norm for v in x];y=cross(axis,x)
    vertices=[]
    for end in (a,b):
        for i in range(sides):
            angle=2*math.pi*i/sides;vertices.append([end[k]+radius*(x[k]*math.cos(angle)+y[k]*math.sin(angle)) for k in range(3)])
    faces=[tuple(reversed(range(sides))),tuple(range(sides,2*sides))]
    faces += [(i,(i+1)%sides,(i+1)%sides+sides,i+sides) for i in range(sides)]
    return vertices,faces

def box(center,size):
    vertices=[[center[k]+size[k]*(1 if bits&(1<<k) else -1)*.5 for k in range(3)]for bits in range(8)]
    return vertices,[(0,4,6,2),(1,3,7,5),(0,1,5,4),(2,6,7,3),(0,2,3,1),(4,5,7,6)]

def spear_head():
    vertices=[(-.045,0,1.40),(.045,0,1.40),(0,-.015,1.40),(0,.015,1.40),(0,0,1.67),(0,0,1.32)]
    return vertices,[(0,2,4),(2,1,4),(1,3,4),(3,0,4),(2,0,5),(1,2,5),(3,1,5),(0,3,5)]

def shield_plate():
    # Chamfered shoulders and tapered base, with real thickness rather than a plane.
    outline=[(-.19,.19),(-.13,.29),(.13,.29),(.19,.19),(.17,-.14),(0,-.29),(-.17,-.14)]
    vertices=[(x,y,z)for y in (.067,.095)for x,z in outline];n=len(outline)
    faces=[tuple(reversed(range(n))),tuple(range(n,2*n))]+[(i,(i+1)%n,(i+1)%n+n,i+n)for i in range(n)]
    return vertices,faces

def build(prop):
    """Return named opaque pieces. Contact haft/handle is actual round geometry."""
    pieces=[]
    def add(name,geometry,color=(.20,.13,.065,1),team=False):
        vertices,faces=geometry;pieces.append(dict(name=name,vertices=vertices,faces=faces,color=color,team=team))
    metal=(.31,.35,.35,1)
    if prop in ('axe','hammer','sickle','sword','spear'):
        lower,upper={'axe':(-.14,.51),'hammer':(-.08,.30),'sickle':(-.08,.25),'sword':(-.09,.10),'spear':(-.38,1.43)}[prop]
        add(prop+'_round_grip',cylinder((0,0,lower),(0,0,upper),.0175))
        if prop=='axe':add('axe_head',box((.07,0,.46),(.22,.055,.13)),metal)
        elif prop=='hammer':add('hammer_head',box((0,0,.29),(.20,.09,.09)),metal)
        elif prop=='sickle':
            add('sickle_shoulder',cylinder((0,0,.23),(.10*math.cos(.65),0,.23+.10*math.sin(.65)),.014,6),metal)
            for i in range(5):
                a=.65+i*.28;b=a+.28
                add('sickle_curve_'+str(i),cylinder((.10*math.cos(a),0,.23+.10*math.sin(a)),(.10*math.cos(b),0,.23+.10*math.sin(b)),.014,6),metal)
        elif prop=='sword':
            add('sword_guard',box((0,0,.10),(.17,.045,.035)),metal)
            add('sword_blade',box((0,0,.37),(.052,.022,.51)),metal)
            add('sword_pommel',box((0,0,-.09),(.047,.04,.04)),metal)
        else:add('spear_point',spear_head(),metal)
    elif prop=='shield':
        add('shield_face',shield_plate(),(1,1,1,1),True)
        # Palm curls around the central grip; both brackets reach the shield back.
        add('shield_grip',cylinder((0,0,-.055),(0,0,.055),.0175),(.13,.075,.035,1))
        for z in (-.055,.055):add('shield_grip_bracket',cylinder((0,0,z),(0,.074,z),.012,8),metal)
        # A narrow visible central boss is on the face, not between hand and grip.
        add('shield_boss',cylinder((0,.095,0),(0,.12,0),.046,10),metal)
    elif prop=='bow':
        add('bow_grip',cylinder((0,0,-.06),(0,0,.06),.0175),(.17,.095,.045,1))
        # Ends curve back toward the archer (-Y). Centre of the wood is the grip.
        for i in range(12):
            aa=-math.pi/2+i*math.pi/12;bb=aa+math.pi/12
            a=(0,-.14*(1-math.cos(aa)),.40*math.sin(aa));b=(0,-.14*(1-math.cos(bb)),.40*math.sin(bb))
            add('bow_limb_'+str(i),cylinder(a,b,.013,8),(.25,.15,.065,1))
    else:raise ValueError(prop)
    return pieces

if __name__=='__main__':
    for prop in ['axe','hammer','sickle','sword','spear','shield','bow']:
        pieces=build(prop);print(prop,sum(len(p['vertices'])for p in pieces),sum(sum(len(f)-2 for f in p['faces'])for p in pieces))

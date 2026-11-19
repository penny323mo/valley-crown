extends Node3D
## Fixed low world dressing, separate from all pickable resource bodies.
## Reconciles only the currently published faction observation snapshots.
const TYPES=["stone","iron","berry"]
const LIMIT=256
const PALETTES=[
 ["545346","81765f","a49779","c3b79f"],
 ["383a3b","555759","767372","9c8066"],
 ["3a3f26","535137","70603f","856c46"],
]
var layouts:Dictionary={}
var previous:Dictionary={}
func _ready():
 for i in TYPES.size():
  var mm:=MultiMesh.new()
  mm.transform_format=MultiMesh.TRANSFORM_3D
  mm.use_colors=true
  mm.mesh=_patch(i)
  mm.instance_count=LIMIT
  mm.visible_instance_count=0
  var display:=MultiMeshInstance3D.new()
  display.name="SiteFloor_"+TYPES[i]
  display.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
  display.multimesh=mm
  add_child(display)
  layouts[TYPES[i]]=mm
  previous[TYPES[i]]=[]
func reconcile(records:Dictionary):
 var active={"stone":[],"iron":[],"berry":[]}
 for rec in records.values():
  if rec.get("category","")!="resource" or not rec.get("alive",false):continue
  var kind=rec.get("kind","")
  if not active.has(kind) or active[kind].size()>=LIMIT:continue
  active[kind].append([rec.id,rec.pos,rec.get("remembered",false)])
 for kind in TYPES:
  var rows=active[kind]
  if rows==previous[kind]:continue
  previous[kind]=rows
  var mm:MultiMesh=layouts[kind]
  mm.visible_instance_count=rows.size()
  for i in rows.size():
   var rec=rows[i]
   var turn=posmod(int(rec[0])*7,19)*TAU/19.0
   mm.set_instance_transform(i,Transform3D(Basis(Vector3.UP,turn),rec[1]))
   mm.set_instance_color(i,Color(0.87,0.91,0.85) if rec[2] else Color.WHITE)

static func _surface(st:SurfaceTool,a:Vector3,b:Vector3,c:Vector3,col:Color):
 st.set_color(col.srgb_to_linear())
 st.add_vertex(a);st.add_vertex(b);st.add_vertex(c)
static func _patch(index:int)->ArrayMesh:
 var st:=SurfaceTool.new()
 st.begin(Mesh.PRIMITIVE_TRIANGLES)
 var tones=PALETTES[index]
 # Ground litter with a ragged outline and changing interior foliage/gravel tones.
 # Never a circular UI ring, nor convex physical blocker.
 var rim=[]
 var middle=[]
 for i in 11:
  var phase=i*TAU/11.0
  var radius=0.81+0.16*cos(i*13.36)+0.07*sin(i*7.11)
  var direction=Vector3(cos(phase),0,sin(phase))
  rim.append(direction*radius+Vector3(0,0.020+(i%3)*0.003,0))
  middle.append(direction*radius*0.59+Vector3(0,0.031,0))
 for i in 11:
  var j=(i+1)%11
  var dark=Color(tones[0]).lightened(0.06*(i%3))
  var soil=Color(tones[1]).lightened(0.035*(i%4))
  _surface(st,rim[i],rim[j],middle[i],dark)
  _surface(st,rim[j],middle[j],middle[i],dark.lerp(soil,0.23))
  _surface(st,middle[i],middle[j],Vector3(0,0.027,0),soil)
 for i in 9:
  var phase=i*2.39996+index*0.24
  var radial=Vector3(cos(phase),0,sin(phase))
  var side=Vector3(-sin(phase),0,cos(phase))
  var c=radial*(0.56+0.23*sin(i*9.31))+Vector3(0,0.036,0)
  var half_long=0.06+0.03*(i%3)
  var half_width=(0.041 if index==2 else 0.069)+0.011*(i%4)
  var a=c-radial*half_long
  var b=c+side*half_width
  var d=c+radial*half_long*1.2
  var e=c-side*half_width
  var raised=c+Vector3(0,0.015+0.005*(i%3),0)
  _surface(st,a,b,raised,Color(tones[2]))
  _surface(st,b,d,raised,Color(tones[3]))
  _surface(st,d,e,raised,Color(tones[3]).darkened(0.1))
  _surface(st,e,a,raised,Color(tones[2]).darkened(0.16))
 st.generate_normals()
 var m:=StandardMaterial3D.new()
 m.cull_mode=BaseMaterial3D.CULL_DISABLED
 m.vertex_color_use_as_albedo=true
 m.roughness=0.98
 st.set_material(m)
 return st.commit()

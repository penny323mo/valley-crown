extends RefCounted
## Deterministic code-native palisade. Presentation only: no world queries,
## neighbour links, rotation, collision, randomness or concealed-state inputs.
const HEIGHT=1.40
const HALF_WIDTH=0.95
static func material(name:String,color:Color):
 var m=StandardMaterial3D.new();m.resource_name=name;m.albedo_color=color;m.roughness=1.0
 return m
static func surface(m:Material):
 var s=SurfaceTool.new();s.begin(Mesh.PRIMITIVE_TRIANGLES);s.set_material(m);return s
static func box(s:SurfaceTool,position:Vector3,size:Vector3):
 var mesh=BoxMesh.new();mesh.size=size;s.append_from(mesh,0,Transform3D(Basis.IDENTITY,position))
static func post(s:SurfaceTool,p:Vector3,height:float):
 var trunk=CylinderMesh.new();trunk.top_radius=.085;trunk.bottom_radius=.105;trunk.height=height-.22;trunk.radial_segments=4;trunk.rings=1
 s.append_from(trunk,0,Transform3D(Basis.IDENTITY,p+Vector3(0,(height-.22)*.5,0)))
 var tip=CylinderMesh.new();tip.top_radius=0;tip.bottom_radius=.085;tip.height=.22;tip.radial_segments=4;tip.rings=1
 s.append_from(tip,0,Transform3D(Basis.IDENTITY,p+Vector3(0,height-.11,0)))
static func instantiate_asset(team:Color)->Node3D:
 var root=Node3D.new();root.name="TimberPalisade";root.set_meta("asset_kind","wall")
 var timber=surface(material("oak",Color("70513a")))
 var beam=surface(material("wall_beam",Color("99744b")))
 var rope=surface(material("wall_rope",Color("b5a175")))
 var cloth=surface(material("team",team))
 # Every direction is intentionally solid, matching the square grid footprint.
 for side in [-1,1]:
  for i in 5:
   var offset=-.8+i*.4
   post(timber,Vector3(offset,0,side*.8),1.4 if i%2==0 else 1.32)
  for i in 3:
   post(timber,Vector3(side*.8,0,-.4+i*.4),1.36 if i%2==0 else 1.4)
  for y in [.40,.94]:
   box(beam,Vector3(0,y,side*.78),Vector3(1.88,.13,.12))
   box(beam,Vector3(side*.78,y,0),Vector3(.12,.13,1.88))
  for i in [-1,0,1]:
   box(rope,Vector3(i*.8,.94,side*.80),Vector3(.15,.055,.24))
  box(cloth,Vector3(side*.8,.72,-.812),Vector3(.15,.32,.055))
 var mesh=timber.commit();beam.commit(mesh);rope.commit(mesh);cloth.commit(mesh)
 var visible_mesh=MeshInstance3D.new();visible_mesh.name="PalisadeMesh";visible_mesh.mesh=mesh;root.add_child(visible_mesh)
 return root
static func construction_mesh(stage:int)->ArrayMesh:
 var timber=surface(material("oak",Color("70513a")))
 var rope=surface(material("wall_rope",Color("b5a175")))
 # Markers and a paid timber stack; never show a complete wall at 0%.
 for x in [-.8,.8]:
  for z in [-.8,.8]:post(timber,Vector3(x,0,z),.42 if stage==0 else 1.4)
 if stage==0:
  for i in 3:box(timber,Vector3(-.35+i*.35,.12,0),Vector3(.17,.17,1.35))
 if stage>=1:
  for side in [-1,1]:
   box(timber,Vector3(0,.4,side*.78),Vector3(1.88,.13,.12))
   box(timber,Vector3(side*.78,.4,0),Vector3(.12,.13,1.88))
 if stage>=2:
  for side in [-1,1]:
   for offset in [-.4,0,.4]:post(timber,Vector3(offset,0,side*.8),1.32)
   box(timber,Vector3(0,.94,side*.78),Vector3(1.88,.13,.12))
   box(timber,Vector3(side*.78,.94,0),Vector3(.12,.13,1.88))
 # Simple ties retain two material surfaces at every construction stage.
 for side in [-1,1]:box(rope,Vector3(side*.8,.28,-.81),Vector3(.15,.05,.22))
 var result=timber.commit();rope.commit(result);return result

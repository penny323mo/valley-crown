extends RefCounted
## Cosmetic release-time trajectory, not a projectile authority or delayed hit.
const LIFETIME=0.35
static func part(parent, name, mesh, color, position):
 var node=MeshInstance3D.new();node.name=name;node.mesh=mesh;node.position=position
 var material=StandardMaterial3D.new();material.albedo_color=color;material.roughness=0.85
 node.material_override=material;parent.add_child(node);return node
static func make(start: Vector3, finish: Vector3, color: Color) -> Node3D:
 var root=Node3D.new();root.name="WitnessedArrow"
 root.set_meta("start",start);root.set_meta("finish",finish)
 root.set_meta("visual_only",true)
 var shaft=CylinderMesh.new();shaft.top_radius=0.025;shaft.bottom_radius=0.025;shaft.height=0.65;shaft.radial_segments=6
 part(root,"Shaft",shaft,Color("a88752"),Vector3.ZERO).rotation.x=PI/2
 var tip=CylinderMesh.new();tip.top_radius=0;tip.bottom_radius=0.085;tip.height=0.18;tip.radial_segments=4
 part(root,"Head",tip,Color("d8d7c9"),Vector3(0,0,-0.40)).rotation.x=-PI/2
 for i in 2:
  var feather=BoxMesh.new();feather.size=Vector3(0.17,0.025,0.19)
  part(root,"Fletching%d" % i,feather,color,Vector3(0,0,0.24)).rotation.z=i*PI/2
 present(root,0);return root
static func position_at(start: Vector3, finish: Vector3, t: float) -> Vector3:
 var progress=clampf(t,0,1)
 var lift=minf(1.0,start.distance_to(finish)*0.12)
 return start.lerp(finish,progress)+Vector3.UP*(4*lift*progress*(1-progress))
static func present(root: Node3D, age: float):
 var start: Vector3=root.get_meta("start");var finish: Vector3=root.get_meta("finish")
 var t=clampf(age/LIFETIME,0,1)
 root.position=position_at(start,finish,t)
 var tangent=finish-start+Vector3.UP*(4*minf(1.0,start.distance_to(finish)*0.12)*(1-2*t))
 if tangent.length_squared()>0.0001:
  root.basis=Basis.looking_at(tangent.normalized(),Vector3.RIGHT if absf(tangent.normalized().dot(Vector3.UP))>0.99 else Vector3.UP)

extends RefCounted
## Witnessed ram strike presentation only; no damage or entity references.
const LIFETIME=0.55
static func make(_start: Vector3,finish: Vector3) -> Node3D:
	var root=Node3D.new();root.name="SiegeStrikeCue";root.position=finish
	for i in 6:
		var shard=MeshInstance3D.new();shard.name="Shard%d" % i
		var mesh=BoxMesh.new();mesh.size=Vector3(0.09,0.07,0.17);shard.mesh=mesh
		var material=StandardMaterial3D.new();material.albedo_color=Color("b6a180");material.roughness=1.0;material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA;shard.material_override=material
		root.add_child(shard)
	var dust=MeshInstance3D.new();dust.name="Dust"
	var ring=TorusMesh.new();ring.inner_radius=0.48;ring.outer_radius=0.58;ring.rings=16;ring.ring_segments=6;dust.mesh=ring
	var mat=StandardMaterial3D.new();mat.albedo_color=Color(0.68,0.57,0.40,0.7);mat.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA;mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;dust.material_override=mat
	root.add_child(dust);present(root,0.0);return root
static func present(root: Node3D,age: float):
	var t=clampf(age/LIFETIME,0.0,1.0)
	for i in 6:
		var shard=root.get_node("Shard%d" % i)
		var angle=i*TAU/6.0
		shard.position=Vector3(cos(angle)*t*0.8,t*1.4-t*t*2.0,sin(angle)*t*0.8)
		shard.rotation=Vector3(t*5+i,t*3,0)
		shard.material_override.albedo_color.a=1.0-t
	var dust=root.get_node("Dust")
	dust.position=Vector3(0,0.12-root.position.y,0)
	dust.scale=Vector3.ONE*(0.4+t*1.6)
	dust.material_override.albedo_color.a=0.7*(1.0-t)

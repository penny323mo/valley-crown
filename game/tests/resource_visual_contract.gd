extends SceneTree
const Fog = preload("res://scripts/remembered_material.gd")
const Visuals = preload("res://scripts/resource_visuals.gd")
func _initialize():
	var checks:=0
	for kind in ["stone","iron","berry"]:
		var root:=Node3D.new()
		var first:=Visuals.build(root,kind)
		var second:=Visuals.build(root,kind)
		assert(first.mesh==second.mesh);checks+=1
		assert(first.mesh.get_surface_count()==1);checks+=1
		var count: int = first.mesh.surface_get_array_len(0)
		assert(count<6000);checks+=1
		var aabb: AABB = first.mesh.get_aabb()
		assert(aabb.size.x<1.2 and aabb.size.z<1.2);checks+=1
		assert(first.get_meta("visual_only"));checks+=1
		var original=first.mesh.surface_get_material(0)
		Fog.apply(first,true)
		assert(first.get_surface_override_material(0)!=original);checks+=1
		assert(first.get_surface_override_material(0).vertex_color_use_as_albedo);checks+=1
		assert(second.get_surface_override_material(0)==null);checks+=1
		Fog.apply(first,false)
		assert(first.get_surface_override_material(0)==null);checks+=1
		print("RESOURCE_METRIC ",kind," vertices=",count," surfaces=1 bounds=",aabb)
		root.free()
	print("RESOURCE_CONTRACT_PASS ",checks)
	quit(0)

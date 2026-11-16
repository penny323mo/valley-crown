extends SceneTree
const Visuals=preload("res://scripts/resource_visuals.gd")
var checks:=0
func _initialize():
	for kind in ["stone","iron","berry"]:
		var root:=Node3D.new()
		var visual=Visuals.build(root,kind)
		var arrays=visual.mesh.surface_get_arrays(0)
		var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
		var colors:PackedColorArray=arrays[Mesh.ARRAY_COLOR]
		var normals:PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
		assert(vertices.size()==colors.size() and vertices.size()==normals.size());checks+=1
		assert(vertices.size()<=4000);checks+=1
		for i in range(0,vertices.size(),3):
			assert((vertices[i+1]-vertices[i]).cross(vertices[i+2]-vertices[i]).length_squared()>0.000000000001)
		for i in vertices.size():
			assert(vertices[i].is_finite() and normals[i].is_finite() and is_equal_approx(colors[i].a,1.0))
		checks+=2
		var mat=visual.mesh.surface_get_material(0)
		assert(mat.transparency==BaseMaterial3D.TRANSPARENCY_DISABLED and mat.roughness>0.9);checks+=1
		var same=Visuals.build(root,kind)
		assert(same.mesh==visual.mesh and same.material_override==null);checks+=1
		assert(root.get_child_count()==2 and visual.get_child_count()==0);checks+=1
		assert(visual.mesh.get_aabb().size.y<0.60);checks+=1
		print("POLISH_METRIC ",kind," triangles=",vertices.size()/3," bounds=",visual.mesh.get_aabb())
		root.free()
	print("RESOURCE_POLISH_PASS ",checks)
	quit(0)

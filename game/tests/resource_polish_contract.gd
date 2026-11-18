extends SceneTree
const Visuals=preload("res://scripts/resource_visuals.gd")
var checks:=0
func _initialize():
	for kind in ["stone","iron","berry"]:
		var root:=Node3D.new()
		var visual=Visuals.build(root,kind)
		var total=0;var attributes=true;var finite=true;var nondegenerate=true;var materials=true
		for surface in visual.mesh.get_surface_count():
			var arrays=visual.mesh.surface_get_arrays(surface);var vertices=arrays[Mesh.ARRAY_VERTEX];var normals=arrays[Mesh.ARRAY_NORMAL];var colors=arrays[Mesh.ARRAY_COLOR];var indices=arrays[Mesh.ARRAY_INDEX]
			var leaf=kind=="berry" and surface==0
			attributes=attributes and vertices.size()==normals.size() and vertices.size()==colors.size()
			var n=indices.size() if indices!=null and indices.size()>0 else vertices.size();total+=n
			for i in range(0,n,3):
				var a=vertices[indices[i] if indices!=null and indices.size()>0 else i];var b=vertices[indices[i+1] if indices!=null and indices.size()>0 else i+1];var c=vertices[indices[i+2] if indices!=null and indices.size()>0 else i+2]
				nondegenerate=nondegenerate and (b-a).cross(c-a).length_squared()>0.000000000001
			for i in vertices.size():finite=finite and vertices[i].is_finite() and normals[i].is_finite() and is_equal_approx(colors[i].a,1.0)
			var mat=visual.mesh.surface_get_material(surface)
			materials=materials and (not leaf or (is_equal_approx(mat.alpha_scissor_threshold,.2) and mat.albedo_texture!=null)) and mat.roughness>0.9 and mat.transparency==(BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR if leaf else BaseMaterial3D.TRANSPARENCY_DISABLED)
		assert(attributes);checks+=1
		assert(total<=(4356 if kind=="berry" else 4000));checks+=1
		assert(nondegenerate);checks+=1
		assert(finite);checks+=1
		assert(materials);checks+=1
		var same=Visuals.build(root,kind)
		assert(same.mesh==visual.mesh and same.material_override==null);checks+=1
		assert(root.get_child_count()==2 and visual.get_child_count()==0);checks+=1
		var expected_height={"stone":0.610226,"iron":0.669126,"berry":0.76}[kind]
		assert(absf(visual.mesh.get_aabb().size.y-expected_height)<=0.00001 and visual.mesh.get_aabb().size.y<1.0);checks+=1
		print("POLISH_METRIC ",kind," triangles=",total/3," bounds=",visual.mesh.get_aabb())
		root.free()
	print("RESOURCE_POLISH_PASS ",checks)
	quit(0)

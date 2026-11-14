extends SceneTree
const V=preload("res://scripts/resource_visuals.gd")
func _initialize():
	for kind in ["rock","fruit","leaf"]:
		var st=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
		if kind=="rock": V._boulder(st,Vector3.ZERO,Vector3.ONE,0.0,Color.WHITE)
		elif kind=="fruit": V._fruit(st,Vector3.ZERO,1.0,Color.WHITE)
		else: V._leaf(st,Vector3.ZERO,0.0,0.1,1.0,Color.WHITE)
		st.generate_normals();var a=st.commit().surface_get_arrays(0)
		var min_dot=100.;var max_dot=-100.;var avg=0.
		for i in a[Mesh.ARRAY_VERTEX].size():
			var p=a[Mesh.ARRAY_VERTEX][i]-Vector3(0,0.3,0) if kind=="rock" else a[Mesh.ARRAY_VERTEX][i]
			var d=a[Mesh.ARRAY_NORMAL][i].y if kind=="leaf" else p.dot(a[Mesh.ARRAY_NORMAL][i]);min_dot=minf(d,min_dot);max_dot=maxf(d,max_dot);avg+=d
		assert(min_dot>0.25)
		print(kind," normal dots ",min_dot," ",max_dot," avg ",avg/a[Mesh.ARRAY_VERTEX].size())
	print("NORMALS_PASS 3")
	quit(0)

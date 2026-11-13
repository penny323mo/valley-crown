extends RefCounted
## Original presentation-only resource meshes. No economy, targeting or RNG writes.
## One shared vertex-colour mesh per resource kind; opaque surfaces, no alpha overdraw.
static var cache: Dictionary = {}
static func build(parent: Node3D, kind: String) -> MeshInstance3D:
	if not cache.has(kind): cache[kind] = _make_mesh(kind)
	var visual := MeshInstance3D.new()
	visual.name = "ResourceVisual_" + kind
	visual.mesh = cache[kind]
	visual.set_meta("visual_only", true)
	parent.add_child(visual)
	return visual

static func _triangle(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	st.set_color(color.srgb_to_linear())
	st.add_vertex(a); st.add_vertex(b); st.add_vertex(c)

static func _rock(st: SurfaceTool, origin: Vector3, size: Vector3, phase: float, color: Color) -> void:
	# Unequal staggered rings, buried foot and tilted crown: no cube silhouette.
	var rings: Array = []
	for level in 3:
		var ring: Array[Vector3] = []
		for i in 7:
			var angle := TAU * i / 7.0 + phase + level * 0.12
			var jitter := 0.88 + 0.12 * sin(i * 8.13 + phase * 5.1 + level)
			var radius: float = [0.94, 1.0, 0.53][level]
			var p := Vector3(cos(angle)*radius*jitter, [-0.08,0.42,0.9][level] + sin(i*2.7+phase)*0.07, sin(angle)*radius*jitter)
			ring.append(origin + p * size)
		rings.append(ring)
	for level in 2:
		for i in 7:
			var n := (i+1)%7
			var tint := color * (0.86 + 0.18 * (sin(i*2.4+phase+level)*0.5+0.5)); tint.a=1.0
			_triangle(st,rings[level][i],rings[level+1][i],rings[level][n],tint)
			_triangle(st,rings[level][n],rings[level+1][i],rings[level+1][n],tint)
	for i in 7:
		_triangle(st,rings[2][i],origin+Vector3(0.04,0.96,-0.03)*size,rings[2][(i+1)%7],color.lightened(0.08))

static func _leaf(st: SurfaceTool, center: Vector3, angle: float, tilt: float, scale: float, color: Color) -> void:
	var direction := Vector3(cos(angle),tilt,sin(angle)).normalized()
	var side := Vector3(-sin(angle),0,cos(angle))*scale*0.43
	var base := center-direction*scale*0.4
	var tip := center+direction*scale*0.52
	var ridge := center+Vector3(0,0.04,0)
	_triangle(st,base,ridge,center-side,color.darkened(0.12))
	_triangle(st,center-side,ridge,tip,color)
	_triangle(st,tip,ridge,center+side,color.lightened(0.08))
	_triangle(st,center+side,ridge,base,color)

static func _make_mesh(kind: String) -> ArrayMesh:
	var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
	if kind in ["stone","iron"]:
		var color := Color("92958a") if kind=="stone" else Color("656b64")
		_rock(st,Vector3(-0.16,0,0.06),Vector3(0.36,0.57,0.33),0.4,color)
		_rock(st,Vector3(0.23,0,-0.12),Vector3(0.28,0.43,0.28),1.7,color.darkened(0.08))
		_rock(st,Vector3(-0.31,0,-0.25),Vector3(0.24,0.35,0.21),2.5,color.lightened(0.08))
		_rock(st,Vector3(0.16,0,0.3),Vector3(0.25,0.26,0.2),3.4,color)
		for i in 5:
			var a := i*2.4
			_rock(st,Vector3(cos(a)*0.47,0,sin(a)*0.43),Vector3(0.09,0.11,0.07),a,color.darkened(0.05))
		if kind=="iron":
			for i in 4:
				_rock(st,Vector3(-0.28+i*0.14,0.34+i*0.04,-0.05),Vector3(0.07,0.13,0.09),i,Color("ba8660"))
	else:
		# Compact bramble canopy; leaf faces stay legible at the normal RTS distance.
		for branch in 4:
			var a := branch*TAU/4.0
			_rock(st,Vector3(cos(a)*0.10,0,sin(a)*0.10),Vector3(0.035,0.31,0.03),a,Color("65503b"))
		for i in 72:
			var a := i*2.39996
			var r := 0.12 + 0.28*sqrt(float(i%13)/12.0)
			var h := 0.23 + 0.24*(1.0-r/0.5) + 0.08*sin(i*3.1)
			_leaf(st,Vector3(cos(a)*r,h,sin(a)*r),a,0.15+0.4*sin(i*1.7),0.24,Color("47602f").lightened(0.06*(i%4)))
		for cluster in 6:
			var a := cluster*TAU/6.0+0.3
			for fruit in 3:
				var p := Vector3(cos(a)*0.34,0.40+0.045*(fruit%2),sin(a)*0.34)+Vector3(cos(fruit*2.1)*0.055,0,sin(fruit*2.1)*0.055)
				_rock(st,p,Vector3(0.047,0.085,0.047),a,Color("983c48") if fruit%2==0 else Color("b95353"))
	st.generate_normals()
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo=true; material.roughness=0.96
	material.cull_mode=BaseMaterial3D.CULL_DISABLED
	st.set_material(material)
	return st.commit()

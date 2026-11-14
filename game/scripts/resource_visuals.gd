extends RefCounted
## Original opaque resource art. Presentation only; no economy or random-stream writes.
## Shared single-surface meshes keep resource patches cheap on the mobile renderer.
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

static func _boulder(st: SurfaceTool, origin: Vector3, size: Vector3, phase: float, color: Color, ore: bool=false) -> void:
	# Offset fractured shelves, not regular radial cones. Foot penetrates the soil.
	var rings: Array = []
	for level in 4:
		var ring: Array[Vector3] = []
		for i in 8:
			var angle: float = TAU * i / 8.0 + phase + [0.0,0.03,-0.07,0.01][level]
			var jitter := 0.88 + 0.12*sin(i*7.71+phase*3.4)
			var radius: float = [0.87,1.0,0.89,0.64][level]
			var height: float = [-0.08,0.28,0.66,0.82][level]
			var offset := Vector3(0.13*level/3.0,0,-0.12*level/3.0)
			ring.append(origin+(Vector3(cos(angle)*radius*jitter,height+0.055*sin(i*2.3+phase),sin(angle)*radius*jitter)+offset)*size)
		rings.append(ring)
	for level in 3:
		for i in 8:
			var n := (i+1)%8
			var tint := color * (0.83+0.17*(sin(i*2.4+phase+level)*0.5+0.5)); tint.a=1.0
			# Rust follows a fracture band rather than orange crystals floating on top.
			if ore and level==1 and (i==1 or i==2 or i==5): tint=Color("8b6044")
			_triangle(st,rings[level][i],rings[level][n],rings[level+1][i],tint)
			_triangle(st,rings[level][n],rings[level+1][n],rings[level+1][i],tint.lightened(0.025))
	var crown := origin+Vector3(0.10,0.86,-0.09)*size
	for i in 8:
		_triangle(st,rings[3][i],rings[3][(i+1)%8],crown,color.lightened(0.04+0.025*sin(i+phase)))

static func _branch(st: SurfaceTool, start: Vector3, end: Vector3, radius: float) -> void:
	var axis := (end-start).normalized()
	var right := axis.cross(Vector3.FORWARD).normalized()
	var forward := axis.cross(right).normalized()
	for i in 5:
		var a := TAU*i/5.0; var b := TAU*(i+1)/5.0
		var side_a := (right*cos(a)+forward*sin(a))*radius
		var side_b := (right*cos(b)+forward*sin(b))*radius
		_triangle(st,start+side_a,start+side_b,end+side_a*0.5,Color("655038"))
		_triangle(st,start+side_b,end+side_b*0.5,end+side_a*0.5,Color("735b3e"))

static func _leaf(st: SurfaceTool, center: Vector3, angle: float, tilt: float, scale: float, color: Color) -> void:
	var direction := Vector3(cos(angle),tilt,sin(angle)).normalized()
	var side := Vector3(-sin(angle),0,cos(angle))*scale*0.30
	var base := center-direction*scale*0.55
	var tip := center+direction*scale*0.55
	var ridge := center+Vector3(0,0.022,0)
	_triangle(st,base,center-side,ridge,color.darkened(0.08))
	_triangle(st,center-side,tip,ridge,color)
	_triangle(st,tip,center+side,ridge,color.lightened(0.09))
	_triangle(st,center+side,base,ridge,color)

static func _fruit(st: SurfaceTool, center: Vector3, radius: float, color: Color) -> void:
	# Round fruit with a short stem, rather than scaled rock-shaped spikes.
	for band in 4:
		var a := PI*band/4.0; var b := PI*(band+1)/4.0
		for i in 6:
			var u := TAU*i/6.0; var v := TAU*(i+1)/6.0
			var p0 := center+Vector3(sin(a)*cos(u),cos(a),sin(a)*sin(u))*radius
			var p1 := center+Vector3(sin(b)*cos(u),cos(b),sin(b)*sin(u))*radius
			var p2 := center+Vector3(sin(a)*cos(v),cos(a),sin(a)*sin(v))*radius
			var p3 := center+Vector3(sin(b)*cos(v),cos(b),sin(b)*sin(v))*radius
			if band>0: _triangle(st,p0,p1,p2,color)
			if band<3: _triangle(st,p2,p1,p3,color.lightened(0.035))

static func _make_mesh(kind: String) -> ArrayMesh:
	var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
	if kind in ["stone","iron"]:
		var color := Color("9a998e") if kind=="stone" else Color("73736a")
		_boulder(st,Vector3(-0.17,0,-0.08),Vector3(0.36,0.52,0.32),0.4,color,kind=="iron")
		_boulder(st,Vector3(0.23,0,0.10),Vector3(0.29,0.31,0.27),1.8,color.darkened(0.07),kind=="iron")
		_boulder(st,Vector3(-0.28,0,0.29),Vector3(0.20,0.21,0.16),2.9,color.lightened(0.04))
		for i in 5:
			var a := i*2.4
			_boulder(st,Vector3(cos(a)*0.46,0,sin(a)*0.42),Vector3(0.075,0.07,0.06),a,color.darkened(0.08))
	else:
		# Branched fruiting shrub, irregular outline with visible gaps at its base.
		for branch in 5:
			var a := branch*TAU/5.0+0.2
			_branch(st,Vector3(0,0.015,0),Vector3(cos(a)*0.26,0.31+0.04*sin(a),sin(a)*0.26),0.018)
		for i in 80:
			var a := i*2.39996
			var r := 0.10+0.27*sqrt(float(i%17)/16.0)
			var h := 0.20+0.24*(1.0-r/0.50)+0.075*sin(i*3.1)
			_leaf(st,Vector3(cos(a)*r,h,sin(a)*r),a+0.25*sin(i),0.10+0.35*sin(i*1.7),0.21,Color("506536").lightened(0.025*(i%4)))
		for cluster in 7:
			var a := cluster*TAU/7.0+0.3
			for fruit in 3:
				var p := Vector3(cos(a)*0.31,0.32+0.055*sin(cluster*1.9),sin(a)*0.31)+Vector3(cos(fruit*2.1)*0.043,0.028*(fruit%2),sin(fruit*2.1)*0.043)
				_fruit(st,p,0.034+0.004*(fruit%2),Color("a03e42") if fruit%2==0 else Color("79323b"))
	st.generate_normals()
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo=true; material.roughness=0.96
	material.cull_mode=BaseMaterial3D.CULL_DISABLED
	st.set_material(material)
	return st.commit()

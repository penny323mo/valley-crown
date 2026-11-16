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

static func _slab(st:SurfaceTool,center:Vector3,size:Vector3,phase:float,color:Color,ore:bool) -> void:
	# Six unequal cut faces with horizontal bedding and a tilted fractured top.
	# Broad planes, not radial pebble/cone silhouettes; footprint stays physical.
	var outline=[Vector2(-1,-0.7),Vector2(0.45,-1),Vector2(1,-0.25),Vector2(0.65,1),Vector2(-0.75,0.85),Vector2(-1,0.05)]
	var rings=[]
	for level in 4:
		var ring=[]
		for i in outline.size():
			var q:Vector2=outline[i].rotated(phase)
			var scale_x:float=[0.96,1.0,0.90,0.70][level]
			var height:float=[-0.025,0.28,0.57,0.88][level]+(0.07*q.x if level==3 else 0.0)
			ring.append(center+Vector3(q.x*scale_x*size.x,height*size.y,q.y*scale_x*size.z))
		rings.append(ring)
	for level in 3:
		for i in 6:
			var n=(i+1)%6
			var tint=color*(0.78+0.07*level+0.045*(i%3));tint.a=1.0
			if ore and level==1 and i in [0,1,4]:tint=Color("bc794f")
			_triangle(st,rings[level][i],rings[level][n],rings[level+1][i],tint)
			_triangle(st,rings[level][n],rings[level+1][n],rings[level+1][i],tint)
	var top=center+Vector3(-0.12*size.x,0.92*size.y,0.08*size.z)
	for i in 6:_triangle(st,rings[3][i],rings[3][(i+1)%6],top,color.lightened(0.08+0.025*(i%2)))

static func _canopy(st:SurfaceTool,center:Vector3,size:Vector3,color:Color) -> void:
	for band in 4:
		var a:=PI*band/4.0;var b:=PI*(band+1)/4.0
		for i in 6:
			var u:=TAU*i/6.0;var v:=TAU*(i+1)/6.0
			var p0:=center+Vector3(sin(a)*cos(u),cos(a),sin(a)*sin(u))*size
			var p1:=center+Vector3(sin(b)*cos(u),cos(b),sin(b)*sin(u))*size
			var p2:=center+Vector3(sin(a)*cos(v),cos(a),sin(a)*sin(v))*size
			var p3:=center+Vector3(sin(b)*cos(v),cos(b),sin(b)*sin(v))*size
			var tint:=color.lightened(0.035*(i%3)).darkened(0.06*band)
			if band>0:_triangle(st,p0,p1,p2,tint)
			if band<3:_triangle(st,p2,p1,p3,tint)

static func _make_mesh(kind: String, depletion: int=0) -> ArrayMesh:
	var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
	if kind in ["stone","iron"]:
		var color:=Color("c6c1aa") if kind=="stone" else Color("8c9591")
		var height:float=[0.94,0.67,0.40,0.15][depletion]
		_slab(st,Vector3(-0.13,0,-0.04),Vector3(0.37,height,0.35),0.12,color,kind=="iron")
		if depletion<3:_slab(st,Vector3(0.23,0,0.12),Vector3(0.29,height*0.62,0.31),-0.30,color.darkened(0.07),kind=="iron")
		_slab(st,Vector3(-0.26,0,0.26),Vector3(0.20,0.16,0.18),0.5,color.lightened(0.03),false)
		for i in 5+depletion*2:
			var a:=i*2.39996
			_slab(st,Vector3(cos(a)*0.42,0,sin(a)*0.39),Vector3(0.07,0.045+0.015*(i%2),0.06),a,color.darkened(0.08),false)
	else:
		# Raised opaque leaf masses make a shrub legible at normal game zoom.
		# Individual leaf edges and fruit remain part of the same shared surface.
		for branch in 5:
			var a:=branch*TAU/5.0+0.2
			var tip:=Vector3(cos(a)*0.25,0.43+0.045*sin(a),sin(a)*0.25)
			_branch(st,Vector3(0,0.015,0),tip,0.027)
			_canopy(st,tip,Vector3(0.24,0.23,0.24),Color("668744").lightened(0.025*(branch%3)))
		_canopy(st,Vector3(-0.04,0.58,0.02),Vector3(0.26,0.20,0.24),Color("7f984d"))
		for i in 28:
			var a:=i*2.39996
			var r:=0.32+0.09*sin(i*1.2)
			_leaf(st,Vector3(cos(a)*r,0.46+0.12*sin(i*2.1),sin(a)*r),a,0.30,0.19,Color("7c9b4d").lightened(0.025*(i%4)))
		for cluster in [7,4,2,1][depletion]:
			var a:float=cluster*TAU/7.0+0.3
			for fruit in 3:
				var p:=Vector3(cos(a)*0.43,0.52+0.07*sin(cluster*1.9),sin(a)*0.43)+Vector3(cos(fruit*2.1)*0.045,0.04*(fruit%2),sin(fruit*2.1)*0.045)
				_fruit(st,p,0.055+0.004*(fruit%2),Color("c6553f") if fruit%2==0 else Color("9e3e3a"))
	st.generate_normals()
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo=true; material.roughness=0.96
	material.cull_mode=BaseMaterial3D.CULL_DISABLED
	st.set_material(material)
	return st.commit()

static func stage(record:Dictionary) -> int:
	var maximum=float(record.get("max_hp",0))
	if maximum<=0:return 0
	var ratio=clampf(float(record.get("hp",maximum))/maximum,0.0,1.0)
	return 3 if ratio<=0.25 else (2 if ratio<=0.5 else (1 if ratio<=0.75 else 0))

static func present(parent:Node3D,record:Dictionary) -> void:
	var kind=record.get("kind","")
	if record.get("category","")!="resource" or kind not in ["stone","iron","berry"]:return
	var visual=parent.get_node_or_null("ResourceVisual_"+kind)
	if not visual is MeshInstance3D:return
	var level=stage(record)
	if visual.get_meta("depletion_stage",0)==level:return
	var key=kind+"_"+str(level) if level>0 else kind
	if not cache.has(key):cache[key]=_make_mesh(kind,level)
	# Replacement affects only this observed proxy. Clear its old dim overrides,
	# then reapply remembered styling from this same immutable observation.
	visual.mesh=cache[key]
	visual.set_surface_override_material(0,null)
	visual.remove_meta("observed_material_override")
	visual.remove_meta("observed_surface_overrides")
	visual.set_meta("depletion_stage",level)
	preload("res://scripts/remembered_material.gd").apply(visual,record.get("remembered",false))

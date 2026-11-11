extends RefCounted
## Temporary construction presentation only. No authority or visibility inputs.
## Uses the existing building's stone/oak materials, with two batched surfaces.
const DIMENSIONS = {
	"farm": Vector3(2.74,0.5,2.74),
	"stable": Vector3(2.62,1.68,2.30),
	"tower": Vector3(1.76,2.76,1.76),
	"workshop": Vector3(2.60,1.72,2.40),
	"town_center": Vector3(2.65,3.05,2.45),
	"house": Vector3(1.60,1.90,1.35),
	"storehouse": Vector3(1.65,1.85,1.38),
	"barracks": Vector3(2.42,2.18,1.95),
	"range": Vector3(2.48,1.92,1.55),
}
static var meshes: Dictionary = {}

static func stage_for(built: bool, progress: float) -> int:
	if built: return 3
	if progress >= 0.65: return 2
	if progress >= 0.15: return 1
	return 0

static func apply(body: Node3D, kind: String, built: bool, progress: float) -> void:
	if not DIMENSIONS.has(kind): return
	var stage := stage_for(built,progress)
	# Metadata holds only a scalar, so an observed proxy can safely duplicate it.
	if body.get_meta("construction_stage",-1) == stage: return
	body.set_meta("construction_stage",stage)
	var site := body.get_node_or_null("ConstructionSite") as MeshInstance3D
	if stage < 3 and site == null:
		site = MeshInstance3D.new()
		site.name = "ConstructionSite"
		body.add_child(site)
	for child in body.get_children():
		if child is Node3D: child.visible = (stage < 3) if child == site else (stage == 3)
	if stage == 3: return
	var key := kind + ":" + str(stage)
	if not meshes.has(key): meshes[key] = _make_mesh(body,kind,stage)
	site.mesh = meshes[key]

static func _material(node: Node, name: String) -> Material:
	if node is MeshInstance3D and node.mesh != null and node.name != "ConstructionSite":
		for i in node.mesh.get_surface_count():
			var material: Material = node.mesh.surface_get_material(i)
			if material != null and material.resource_name == name: return material
	for child in node.get_children():
		var found := _material(child,name)
		if found != null: return found
	return null

static func _box(surface: SurfaceTool, center: Vector3, size: Vector3) -> void:
	var box := BoxMesh.new()
	box.size = size
	surface.append_from(box,0,Transform3D(Basis.IDENTITY,center))

static func _beam(surface: SurfaceTool, a: Vector3, b: Vector3) -> void:
	var axis := (b-a).normalized()
	var side := Vector3.RIGHT
	if absf(axis.dot(side)) > 0.9: side = Vector3.FORWARD
	var z := side.cross(axis).normalized()
	var x := axis.cross(z).normalized()
	var box := BoxMesh.new()
	box.size = Vector3(0.10,a.distance_to(b),0.10)
	surface.append_from(box,0,Transform3D(Basis(x,axis,z),(a+b)*0.5))

static func _make_mesh(body: Node3D, kind: String, stage: int) -> ArrayMesh:
	if kind == "farm": return _make_farm(body,stage)
	var size: Vector3 = DIMENSIONS[kind]
	var stone := SurfaceTool.new()
	stone.begin(Mesh.PRIMITIVE_TRIANGLES)
	stone.set_material(_material(body,"stone"))
	_box(stone,Vector3(0,0.07,0),Vector3(size.x,0.14,size.z))
	var mesh := stone.commit()
	var wood := SurfaceTool.new()
	wood.begin(Mesh.PRIMITIVE_TRIANGLES)
	wood.set_material(_material(body,"oak"))
	var x := size.x*0.5-0.07
	var z := size.z*0.5-0.07
	# First stage is a marked foundation, never a flattened finished roof.
	var top := 0.60 if stage == 0 else size.y
	for sx in [-1,1]:
		for sz in [-1,1]: _beam(wood,Vector3(sx*x,0.14,sz*z),Vector3(sx*x,top,sz*z))
	if stage >= 1:
		for sz in [-1,1]: _beam(wood,Vector3(-x,top,sz*z),Vector3(x,top,sz*z))
		for sx in [-1,1]:
			_beam(wood,Vector3(sx*x,top,-z),Vector3(sx*x,top,z))
			_beam(wood,Vector3(sx*x,0.20,-z),Vector3(sx*x,top,z))
	if stage >= 2:
		if kind == "tower":
			# A working gallery scaffold, not a cottage roof on a stone tower.
			for sz in [-1,1]: _beam(wood,Vector3(-x,top+0.42,sz*z),Vector3(x,top+0.42,sz*z))
			for sx in [-1,1]:
				_beam(wood,Vector3(sx*x,top+0.42,-z),Vector3(sx*x,top+0.42,z))
				for sz in [-1,1]: _beam(wood,Vector3(sx*x,top,sz*z),Vector3(sx*x,top+0.42,sz*z))
		else:
			var rise := 0.65 if kind == "stable" else (0.66 if kind == "workshop" else (0.87 if kind == "house" else 0.75))
			var ridge := top + rise
			_beam(wood,Vector3(-x,ridge,0),Vector3(x,ridge,0))
			for sx in [-1,1]:
				for sz in [-1,1]: _beam(wood,Vector3(sx*x,top,sz*z),Vector3(sx*x,ridge,0))
	wood.commit(mesh)
	return mesh

static func _make_farm(body: Node3D, stage: int) -> ArrayMesh:
	var soil := SurfaceTool.new()
	soil.begin(Mesh.PRIMITIVE_TRIANGLES)
	var earth := StandardMaterial3D.new()
	earth.albedo_color = Color(0.24,0.17,0.105)
	earth.roughness = 1.0
	soil.set_material(earth)
	_box(soil,Vector3(0,0.035,0),Vector3(2.74,0.07,2.74))
	if stage >= 1:
		for row in range(6): _box(soil,Vector3(-1.10+row*0.44,0.10,0),Vector3(0.26,0.08,2.20))
	var mesh := soil.commit()
	var timber := SurfaceTool.new()
	timber.begin(Mesh.PRIMITIVE_TRIANGLES)
	timber.set_material(_material(body,"oak"))
	for sx in [-1,1]:
		for sz in [-1,1]: _beam(timber,Vector3(sx*1.29,0.07,sz*1.28),Vector3(sx*1.29,0.54,sz*1.28))
	if stage >= 1:
		for sx in [-1,1]: _beam(timber,Vector3(sx*1.29,0.44,-1.28),Vector3(sx*1.29,0.44,1.28))
	timber.commit(mesh)
	if stage >= 2:
		var sprouts := SurfaceTool.new()
		sprouts.begin(Mesh.PRIMITIVE_TRIANGLES)
		var leaf := StandardMaterial3D.new()
		leaf.albedo_color = Color(0.30,0.36,0.18)
		leaf.roughness = 1.0
		sprouts.set_material(leaf)
		for row in range(6):
			for plant in range(4): _box(sprouts,Vector3(-1.10+row*0.44,0.20,-0.9+plant*0.6),Vector3(0.05,0.18,0.05))
		sprouts.commit(mesh)
	return mesh

extends RefCounted
## Temporary construction presentation only. No authority or visibility inputs.
## Uses the existing building's stone/oak materials, with two batched surfaces.
const DIMENSIONS = {
	"farm": Vector3(2.5,0.5,2.5),
	"stable": Vector3(2.5,2.2,2.5),
	"tower": Vector3(1.6,3.4,1.6),
	"workshop": Vector3(2.5,2.2,2.5),
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
		var ridge := top + (0.87 if kind == "house" else 0.75)
		_beam(wood,Vector3(-x,ridge,0),Vector3(x,ridge,0))
		for sx in [-1,1]:
			for sz in [-1,1]: _beam(wood,Vector3(sx*x,top,sz*z),Vector3(sx*x,ridge,0))
	wood.commit(mesh)
	return mesh

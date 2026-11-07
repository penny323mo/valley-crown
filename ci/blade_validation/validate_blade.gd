extends SceneTree
const Apply = preload("res://blade_validation/apply_blade_stream.gd")
const Preservation = preload("res://blade_validation/scene_preservation.gd")
const SOURCE = "res://assets/mature/models/spearman_action.scn"
const SOURCE_SHA = "af925f0f70fc14567796230dbc4d1543003e3a4bd52b3bc4554d4daea83c0038"
const PROPOSAL = "res://blade_validation/SELECTED_PROPOSAL.json"
const PROPOSAL_SHA = "49346ade0466c97ba8aeff1732ab6be0848ab10344ff7420df7ad8bebcda40c2"
const EXPECTED = "res://blade_validation/expected_vertex_data.bin"
const EXPECTED_SHA = "0c2c3ebd8733af7567777635391992417a83e8989b321567aaa3094025fe803e"
const OUT = "res://blade_validation_output/spearman_action.scn"
var owned: Array[Node] = []
func _initialize() -> void:
	call_deferred("run")
func cleanup() -> void:
	for node in owned:
		if is_instance_valid(node): node.free()
	owned.clear()
func require_ok(ok: bool, code: String) -> bool:
	if not ok:
		push_error(code)
		cleanup()
		quit(1)
	return ok
func meshes(node: Node) -> Array:
	var result: Array = []
	if node is MeshInstance3D: result.append(node)
	for child in node.get_children(): result.append_array(meshes(child))
	return result
func digest(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()
func bounds_array(box: AABB) -> Array:
	return [box.position.x,box.position.y,box.position.z,box.size.x,box.size.y,box.size.z]
func contains_closed(box: AABB, point: Vector3) -> bool:
	return point.is_finite() and point.x >= box.position.x and point.y >= box.position.y and point.z >= box.position.z and point.x <= box.end.x and point.y <= box.end.y and point.z <= box.end.z
func run() -> void:
	if not require_ok(OS.is_debug_build() and FileAccess.get_sha256(SOURCE) == SOURCE_SHA and FileAccess.get_sha256(PROPOSAL) == PROPOSAL_SHA and FileAccess.get_sha256(EXPECTED) == EXPECTED_SHA, "BLADE_INPUT_HASH"): return
	if not require_ok(not FileAccess.file_exists(OUT), "BLADE_OUTPUT_EXISTS"): return
	var plan: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PROPOSAL)).plan
	var packed: PackedScene = ResourceLoader.load(SOURCE, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)
	var scene := packed.instantiate()
	var untouched := packed.instantiate()
	owned.append(scene)
	owned.append(untouched)
	var targets := meshes(scene)
	if not require_ok(targets.size() == 1 and targets[0].mesh is ArrayMesh, "BLADE_MESH_COUNT"): return
	var target: MeshInstance3D = targets[0]
	var old_mesh: ArrayMesh = target.mesh
	var before := Preservation.snapshot(scene)
	if not require_ok(before == Preservation.snapshot(untouched), "BLADE_SOURCE_SNAPSHOT"): return
	var surfaces: Array = old_mesh.get("_surfaces")
	if not require_ok(surfaces.size() == 2 and surfaces[0].format == 34359803007 and surfaces[0].vertex_count == 4102, "BLADE_FORMAT"): return
	if not require_ok(RenderingServer.mesh_surface_get_format_vertex_stride(surfaces[0].format,4102) == 12 and RenderingServer.mesh_surface_get_format_normal_tangent_stride(surfaces[0].format,4102) == 8 and RenderingServer.mesh_surface_get_format_offset(surfaces[0].format,4102,Mesh.ARRAY_NORMAL) == 49224 and RenderingServer.mesh_surface_get_format_offset(surfaces[0].format,4102,Mesh.ARRAY_TANGENT) == 49228, "BLADE_NATIVE_OFFSETS"): return
	var result := Apply.transform(surfaces[0].vertex_data, plan)
	if not require_ok(result.get("completed",false), "BLADE_APPLY_" + str(result.get("code","UNKNOWN"))): return
	if not require_ok(result.vertex_data == FileAccess.get_file_as_bytes(EXPECTED), "BLADE_REFERENCE_BYTES"): return
	var raw: PackedByteArray = surfaces[0].vertex_data
	var encoded: PackedByteArray = result.vertex_data
	var unaffected: PackedByteArray = encoded.slice(0,48072) + encoded.slice(49224,81272)
	var changed_bytes: int = 0
	for i in raw.size():
		if raw[i] != encoded[i]: changed_bytes += 1
	if not require_ok(changed_bytes == 877 and unaffected.size() == 80120 and digest(unaffected) == "0e465bc5163d64b768d3d73279f963cea2298ed40e680e0b8945809f8d543f37", "BLADE_CHANGED_BYTE_CONTRACT"): return
	var changed: Array = surfaces.duplicate(true)
	changed[0].vertex_data = result.vertex_data
	var bounds: AABB = changed[0].aabb
	var bone_bounds: Array = changed[0].bone_aabbs
	if not require_ok(bone_bounds.size() > 16, "BLADE_BOUNDS"): return
	var spear_bounds: AABB = bone_bounds[16]
	for position in plan.replacement_mesh_positions:
		var point := Vector3(position[0],position[1],position[2])
		bounds = bounds.expand(point)
		spear_bounds = spear_bounds.expand(point)
	for position in plan.replacement_mesh_positions:
		var point := Vector3(position[0],position[1],position[2])
		if not require_ok(contains_closed(bounds,point) and contains_closed(spear_bounds,point),"BLADE_BOUNDS_CONTAINMENT"): return
	changed[0].aabb = bounds
	bone_bounds[16] = spear_bounds
	changed[0].bone_aabbs = bone_bounds
	var private_mesh: ArrayMesh = old_mesh.duplicate(false)
	private_mesh.set("_surfaces",changed)
	for info in old_mesh.get_property_list():
		if (int(info.usage) & PROPERTY_USAGE_STORAGE) != 0 and str(info.name) != "_surfaces":
			if not require_ok(Preservation._value(old_mesh.get(info.name),scene,{}) == Preservation._value(private_mesh.get(info.name),scene,{}), "BLADE_MESH_METADATA"): return
	if not require_ok(var_to_bytes(private_mesh.get("_surfaces")) == var_to_bytes(changed), "BLADE_NATIVE_STREAM_READBACK"): return
	target.mesh = private_mesh
	var corrected := Preservation.snapshot(scene)
	# Prove every other stored scene property by restoring the original resource temporarily.
	target.mesh = old_mesh
	if not require_ok(Preservation.snapshot(scene) == before and Preservation.snapshot(untouched) == before, "BLADE_UNRELATED_MUTATION"): return
	target.mesh = private_mesh
	if not require_ok(Preservation.snapshot(scene) == corrected, "BLADE_REATTACH"): return
	var output := PackedScene.new()
	if not require_ok(output.pack(scene) == OK, "BLADE_PACK"): return
	if not require_ok(DirAccess.make_dir_recursive_absolute("res://blade_validation_output") == OK and ResourceSaver.save(output,OUT) == OK, "BLADE_SAVE"): return
	var reload: PackedScene = ResourceLoader.load(OUT,"PackedScene",ResourceLoader.CACHE_MODE_IGNORE)
	var check := reload.instantiate()
	owned.append(check)
	if not require_ok(Preservation.snapshot(check) == corrected and Preservation.snapshot(untouched) == before, "BLADE_RELOAD"): return
	if not require_ok(FileAccess.get_sha256(SOURCE) == SOURCE_SHA,"BLADE_SOURCE_FILE_CHANGED"): return
	var report := {"schema":"blade-stream-validation-v1","completed":true,"source_sha256":SOURCE_SHA,"proposal_sha256":PROPOSAL_SHA,"output_sha256":FileAccess.get_sha256(OUT),"vertex_stream_sha256":EXPECTED_SHA,"selected_vertices":96,"allowed_bytes":1920,"preservation":true,"reload":true,"surface_aabb":bounds_array(bounds),"bone16_aabb":bounds_array(spear_bounds),"selected_bounds_contained":true,"changed_bytes":changed_bytes,"unaffected_vertex_bytes":unaffected.size(),"unaffected_vertex_sha256":digest(unaffected),"source_file_unchanged":true,"limits":"No new pose, continuous clearance, or visual acceptance."}
	var file := FileAccess.open("res://blade_validation_output/validation-report.json",FileAccess.WRITE)
	if not require_ok(file != null,"BLADE_REPORT"): return
	file.store_string(JSON.stringify(report,"  "))
	file.close()
	cleanup()
	quit(0)

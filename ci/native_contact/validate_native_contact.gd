extends SceneTree
## Separate fresh-process proof over already-patched native output; no writes to inputs.
const Probe = preload("res://native_contact/probe_native_contact.gd")
func _initialize() -> void:
	call_deferred("_run")
func _run() -> void:
	if not OS.is_debug_build():
		push_error("Native contact validation requires assertions-enabled editor/debug engine")
		quit(2)
		return
	var lock_path: String = "res://native_contact/input-lock.json"
	var lock: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(lock_path))
	var patch_path: String = "res://native_contact_output/patch-report.json"
	var patched: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(patch_path))
	assert(patched.size() == 3)
	var report: Dictionary = {"schema":"native-contact-engine-probe-v1", "status":"PASS", "input_lock_sha256":FileAccess.get_sha256(lock_path), "patch_report_sha256":FileAccess.get_sha256(patch_path), "continuous_clearance_certified":false, "visual_acceptance":false, "units":{}}
	for kind in ["spearman", "archer", "scout"]:
		var original_path: String = "res://assets/mature/models/" + kind + "_action.scn"
		var output_path: String = "res://native_contact_output/" + kind + "_action.scn"
		var data_path: String = "res://native_contact/" + kind + ".json"
		assert(FileAccess.get_sha256(original_path) == lock[kind].native_sha256)
		assert(FileAccess.get_sha256(data_path) == lock[kind].data_sha256)
		assert(FileAccess.get_sha256(output_path) == patched[kind].output_sha256)
		assert(patched[kind].reloaded_other_track_snapshot_equal and patched[kind].reloaded_other_scene_storage_equal)
		var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(data_path))
		assert(data.kind == kind and data.source_native_sha256 == lock[kind].native_sha256)
		var original: Node3D = (load(original_path) as PackedScene).instantiate()
		var corrected: Node3D = (load(output_path) as PackedScene).instantiate()
		root.add_child(original)
		root.add_child(corrected)
		assert(corrected.get_meta("native_death_contact_sha256") == lock[kind].data_sha256)
		var probed: Variant = Probe.run(corrected, original, kind, data)
		if not (probed is Dictionary) or probed.get("status", "") != "PASS":
			push_error("Native contact probe did not complete; no success report permitted")
			corrected.free()
			original.free()
			call_deferred("quit", 1)
			return
		var unit: Dictionary = probed
		unit["source_native_sha256"] = lock[kind].native_sha256
		unit["output_native_sha256"] = patched[kind].output_sha256
		unit["data_sha256"] = lock[kind].data_sha256
		report.units[kind] = unit
		corrected.free()
		original.free()
	var file: FileAccess = FileAccess.open("res://native_contact_output/native-probe-report.json", FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	quit(0)

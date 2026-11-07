extends SceneTree
## Run only in an authorized isolated CI copy. Never invokes an importer.
const Diagnostic = preload("res://native_contact/diagnose_reload.gd")
const Preservation = preload("res://native_contact/scene_preservation.gd")
const Contact = preload("res://native_contact/apply_native_contact.gd")
func _initialize() -> void:
	call_deferred("_run")
func _run() -> void:
	if not OS.is_debug_build():
		push_error("Native contact validation requires assertions-enabled editor/debug engine")
		quit(2)
		return
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://native_contact/input-lock.json"))
	var report: Dictionary = {}
	DirAccess.make_dir_recursive_absolute("res://native_contact_output")
	for kind in ["spearman", "archer", "scout"]:
		var path: String = "res://assets/mature/models/" + kind + "_action.scn"
		assert(FileAccess.get_sha256(path) == manifest[kind].native_sha256)
		var sidecar: String = "res://native_contact/" + kind + ".json"
		assert(FileAccess.get_sha256(sidecar) == manifest[kind].data_sha256)
		var packed: PackedScene = load(path)
		var untouched: Node3D = packed.instantiate()
		var untouched_player: AnimationPlayer = untouched.find_child("AnimationPlayer", true, false)
		var untouched_tracks: PackedByteArray = Contact._snapshot(untouched_player, [])
		var scene: Node3D = packed.instantiate()
		root.add_child(scene)
		var player: AnimationPlayer = scene.find_child("AnimationPlayer", true, false)
		var skeleton: Skeleton3D = scene.find_child("Skeleton3D", true, false)
		assert(player != null and skeleton != null)
		# Own the animation libraries and clips before any mutation of shared resources.
		for library_name in player.get_animation_library_list():
			var old_library: AnimationLibrary = player.get_animation_library(library_name)
			var own_library: AnimationLibrary = old_library.duplicate(true)
			for clip_name in old_library.get_animation_list():
				own_library.remove_animation(clip_name)
				assert(own_library.add_animation(clip_name, old_library.get_animation(clip_name).duplicate(true)) == OK)
			player.remove_animation_library(library_name)
			assert(player.add_animation_library(library_name, own_library) == OK)
		var original_scene: PackedByteArray = Preservation.snapshot(scene)
		var original: PackedByteArray = Contact._snapshot(player, Contact.ALLOWED[kind])
		var restore: Array = []
		for bone in skeleton.get_bone_count():
			restore.append([skeleton.get_bone_pose_position(bone), skeleton.get_bone_pose_rotation(bone), skeleton.get_bone_pose_scale(bone)])
		var result: Dictionary = Contact.apply(scene, player, skeleton, kind, manifest[kind].native_sha256, sidecar, manifest[kind].data_sha256)
		var corrected_tracks: PackedByteArray = Contact._snapshot(player, [])
		assert(Contact._snapshot(untouched_player, []) == untouched_tracks, "Accepted cached animation resources were mutated")
		scene.set_meta("native_death_contact_sha256", manifest[kind].data_sha256)
		var output := PackedScene.new()
		assert(output.pack(scene) == OK)
		var destination: String = "res://native_contact_output/" + kind + "_action.scn"
		assert(ResourceSaver.save(output, destination) == OK)
		scene.free()
		var reloaded: PackedScene = ResourceLoader.load(destination, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)
		var check: Node3D = reloaded.instantiate()
		root.add_child(check)
		var checked_player: AnimationPlayer = check.find_child("AnimationPlayer", true, false)
		var checked_skeleton: Skeleton3D = check.find_child("Skeleton3D", true, false)
		assert(Contact._snapshot(checked_player, Contact.ALLOWED[kind]) == original)
		var reloaded_tracks: PackedByteArray = Contact._snapshot(checked_player, [])
		if reloaded_tracks != corrected_tracks:
			var diagnostic: Dictionary = Diagnostic.describe(kind, corrected_tracks, reloaded_tracks)
			print("NATIVE_CONTACT_RELOAD_DIAGNOSTIC=" + JSON.stringify(diagnostic))
			push_error("Corrected track keys or metadata changed during native reload")
			quit(1)
			return
		assert(reloaded_tracks == corrected_tracks, "Corrected track keys or metadata changed during native reload")
		assert(not checked_player.is_playing() and checked_player.autoplay.is_empty())
		for bone in checked_skeleton.get_bone_count():
			assert(checked_skeleton.get_bone_pose_position(bone) == restore[bone][0])
			assert(checked_skeleton.get_bone_pose_rotation(bone) == restore[bone][1])
			assert(checked_skeleton.get_bone_pose_scale(bone) == restore[bone][2])
		assert(Preservation.snapshot(check) == original_scene, "Geometry/material/skin/hierarchy or another serialized property changed")
		assert(check.get_meta("native_death_contact_sha256") == manifest[kind].data_sha256)
		result["output_sha256"] = FileAccess.get_sha256(destination)
		result["reloaded_other_track_snapshot_equal"] = true
		result["reloaded_other_scene_storage_equal"] = true
		report[kind] = result
		check.free()
		assert(Contact._snapshot(untouched_player, []) == untouched_tracks)
		untouched.free()
	var file := FileAccess.open("res://native_contact_output/patch-report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	quit(0)

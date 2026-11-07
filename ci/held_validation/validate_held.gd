extends SceneTree
# Isolated held-only validation. No importer, controller, material or camera changes.
const Held = preload("res://held_validation/apply_held_spear.gd")
const Preservation = preload("res://held_validation/scene_preservation.gd")
const SOURCE = "res://assets/mature/models/spearman_action.scn"
const PROPOSAL = "res://held_validation/spear-held-key-proposal.json"
const SOURCE_SHA = "a3c93a0cdf95d6bf049140c384841ecd59c7fc5933ebd53fd9619f16ca9bab89"
const PROPOSAL_SHA = "1a00de57c262f624b8858b372646d338d5ac77812937d5ff9c0144ba5d53f6bf"
const OUT = "res://held_validation_output/spearman_action.scn"
var owned: Array[Node] = []
func cleanup() -> void:
	for node in owned:
		if is_instance_valid(node): node.free()
	owned.clear()
func vector(v: Vector3) -> Array:
	return [v.x, v.y, v.z]
func quaternion(q: Quaternion) -> Array:
	return [q.x, q.y, q.z, q.w]
func _initialize() -> void:
	call_deferred("run")
func require_ok(value: bool, message: String) -> bool:
	if not value:
		push_error(message)
		cleanup()
		quit(1)
	return value
func selected_ok(player: AnimationPlayer, plan: Dictionary) -> bool:
	var count: int = 0
	for name in Held.CLIPS:
		var clip: Animation = player.get_animation(name)
		for change in plan.clips[name].changes:
			var track: Dictionary = change.replacement
			for key in track.times.size():
				if clip.track_get_key_value(int(track.index), key) != Held._value(track.type, track.values[key]): return false
				count += 1
	return count == 290
func run() -> void:
	if not require_ok(OS.is_debug_build(), "Debug engine required"): return
	if not require_ok(FileAccess.get_sha256(SOURCE) == SOURCE_SHA and FileAccess.get_sha256(PROPOSAL) == PROPOSAL_SHA, "Input hash mismatch"): return
	if not require_ok(not FileAccess.file_exists(OUT), "Fresh isolated output required"): return
	var plan: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PROPOSAL))
	var packed: PackedScene = ResourceLoader.load(SOURCE, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)
	var untouched: Node3D = packed.instantiate()
	owned.append(untouched)
	var scene: Node3D = packed.instantiate()
	owned.append(scene)
	var player: AnimationPlayer = scene.find_child("AnimationPlayer", true, false)
	var skeleton: Skeleton3D = scene.find_child("Skeleton3D", true, false)
	var original_player: AnimationPlayer = untouched.find_child("AnimationPlayer", true, false)
	if not require_ok(player != null and skeleton != null and original_player != null, "Missing native nodes"): return
	if not require_ok(not player.is_playing() and player.autoplay.is_empty(), "Unexpected native autoplay"): return
	var storage: PackedByteArray = Preservation.snapshot(scene)
	var original_storage: PackedByteArray = Preservation.snapshot(untouched)
	var tracks: PackedByteArray = Held._snapshot(original_player, false)
	if not require_ok(storage == original_storage and Held._snapshot(player, false) == tracks, "Actual instance not equal to untouched source"): return
	var preserved: PackedByteArray = Held._snapshot(player, true)
	var result: Dictionary = Held.apply(scene, player, skeleton, SOURCE, PROPOSAL, PROPOSAL_SHA)
	if not require_ok(result.get("completed", false), "Apply failed; no packing allowed"): return
	if not require_ok(selected_ok(player, plan) and Held._snapshot(player, true) == preserved, "Selected or preserved keys mismatch"): return
	if not require_ok(Preservation.snapshot(scene) == storage and Preservation.snapshot(untouched) == original_storage and Held._snapshot(original_player, false) == tracks, "Stored scene or shared source mutation"): return
	var corrected: PackedByteArray = Held._snapshot(player, false)
	var output := PackedScene.new()
	if not require_ok(output.pack(scene) == OK, "Pack failure"): return
	if not require_ok(DirAccess.make_dir_recursive_absolute("res://held_validation_output") == OK, "Output directory failure"): return
	if not require_ok(ResourceSaver.save(output, OUT) == OK, "Native save failure"): return
	scene.free()
	var reloaded: PackedScene = ResourceLoader.load(OUT, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)
	var check: Node3D = reloaded.instantiate()
	owned.append(check)
	var checked_player: AnimationPlayer = check.find_child("AnimationPlayer", true, false)
	var checked_skeleton: Skeleton3D = check.find_child("Skeleton3D", true, false)
	if not require_ok(Preservation.snapshot(check) == storage and Held._snapshot(checked_player, false) == corrected and selected_ok(checked_player, plan), "Reload differs from verified scene/keys"): return
	if not require_ok(Held._snapshot(original_player, false) == tracks and Preservation.snapshot(untouched) == original_storage and FileAccess.get_sha256(SOURCE) == SOURCE_SHA, "Source changed during reload"): return
	# Sample a second, disposable reloaded instance; never save sampled bone poses.
	root.add_child(check)
	checked_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var samples: Array = []
	var spear: int = checked_skeleton.find_bone("prop_spear")
	if not require_ok(spear >= 0, "Spear bone missing"): return
	for name in Held.CLIPS:
		var clip: Animation = checked_player.get_animation(name)
		var position_track: int = clip.find_track(NodePath("FieldRig/Skeleton3D:prop_spear"), Animation.TYPE_POSITION_3D)
		var rotation_track: int = clip.find_track(NodePath("FieldRig/Skeleton3D:prop_spear"), Animation.TYPE_ROTATION_3D)
		var scale_track: int = clip.find_track(NodePath("FieldRig/Skeleton3D:prop_spear"), Animation.TYPE_SCALE_3D)
		if not require_ok(position_track >= 0 and rotation_track >= 0 and scale_track >= 0, "Missing evaluated tracks"): return
		for index in 153:
			var t: float = clip.length * float(index) / 152.0
			# Avoid loop-end wrap ambiguity; record both nominal and requested times.
			var requested: float = minf(t, clip.length - 0.000001) if clip.loop_mode != Animation.LOOP_NONE else t
			checked_player.play(name)
			checked_player.seek(requested, true)
			checked_player.pause()
			checked_skeleton.force_update_all_bone_transforms()
			if not require_ok(str(checked_player.current_animation) == name and absf(checked_player.current_animation_position - requested) <= 0.0000001 and not checked_player.is_playing(), "Wrong sampled clip/time/state"): return
			var expected_position: Vector3 = clip.position_track_interpolate(position_track, requested)
			var expected_rotation: Quaternion = clip.rotation_track_interpolate(rotation_track, requested)
			var expected_scale: Vector3 = clip.scale_track_interpolate(scale_track, requested)
			var actual_position: Vector3 = checked_skeleton.get_bone_pose_position(spear)
			var actual_rotation: Quaternion = checked_skeleton.get_bone_pose_rotation(spear)
			var actual_scale: Vector3 = checked_skeleton.get_bone_pose_scale(spear)
			if not require_ok(actual_position.is_finite() and actual_rotation.is_finite() and actual_scale.is_finite() and expected_position.is_finite() and expected_rotation.is_finite() and expected_scale.is_finite(), "Nonfinite local pose"): return
			if not require_ok(actual_position.distance_to(expected_position) <= 0.000001 and minf((Vector4(actual_rotation.x,actual_rotation.y,actual_rotation.z,actual_rotation.w) - Vector4(expected_rotation.x,expected_rotation.y,expected_rotation.z,expected_rotation.w)).length(), (Vector4(actual_rotation.x,actual_rotation.y,actual_rotation.z,actual_rotation.w) + Vector4(expected_rotation.x,expected_rotation.y,expected_rotation.z,expected_rotation.w)).length()) <= 0.000001 and actual_scale.distance_to(expected_scale) <= 0.000001, "Native sampled local pose differs from track evaluation"): return
			var bones: Array = []
			for bone in checked_skeleton.get_bone_count():
				var pose: Transform3D = checked_skeleton.get_bone_global_pose(bone)
				if not require_ok(pose.is_finite(), "Nonfinite sampled bone"): return
				bones.append([checked_skeleton.get_bone_name(bone), vector(pose.basis.x), vector(pose.basis.y), vector(pose.basis.z), vector(pose.origin)])
			samples.append({"clip":name, "nominal_time":t, "requested_time":requested, "actual_clip":str(checked_player.current_animation), "actual_time":checked_player.current_animation_position, "paused":not checked_player.is_playing(), "actual_position":vector(actual_position), "expected_position":vector(expected_position), "actual_rotation":quaternion(actual_rotation), "expected_rotation":quaternion(expected_rotation), "actual_scale":vector(actual_scale), "expected_scale":vector(expected_scale), "bones":bones})
	var report: Dictionary = {"schema":"held-native-validation-v1", "passed":true, "source_sha256":SOURCE_SHA, "proposal_sha256":PROPOSAL_SHA, "output_sha256":FileAccess.get_sha256(OUT), "changed_tracks":8, "verified_selected_keys":290, "full_scene_storage_preserved":true, "untouched_source_preserved":true, "exact_reload_verified":true, "sampling_grid":"153 uniform nominal times per clip; loop endpoint clamped length-1e-6; distinct from prior offline612 grid", "local_pose_tolerance":0.000001, "time_tolerance":0.0000001, "finite_sample_count":samples.size(), "samples":samples, "limits":["Finite sampled bone transforms only; not mesh clearance or visual acceptance", "Death unchanged and not accepted", "No gameplay, device, material or camera acceptance"]}
	var file := FileAccess.open("res://held_validation_output/validation-report.json", FileAccess.WRITE)
	if not require_ok(file != null, "Report write failure"): return
	file.store_string(JSON.stringify(report, "\t")); file.close()
	cleanup(); quit(0)

extends RefCounted
## SOURCE-ONLY helper. No packing, import, publication or runtime invocation.
## Caller must use a disposable exact-base scene and independently verify reload.
const CLIPS: Array[String] = ["idle", "walk", "attack", "hit"]

static func _value(kind: String, row: Array) -> Variant:
	if kind == "position_3d":
		return Vector3(row[0], row[1], row[2])
	return Quaternion(row[0], row[1], row[2], row[3])

static func _snapshot(player: AnimationPlayer, omit_values: bool) -> PackedByteArray:
	var all: Array = []
	for name in player.get_animation_list():
		var clip: Animation = player.get_animation(name)
		var rows: Array = [str(name), clip.length, clip.loop_mode, clip.step, clip.get_track_count()]
		for index in clip.get_track_count():
			var path: NodePath = clip.track_get_path(index)
			var selected: bool = str(name) in CLIPS and path.get_subname_count() == 1 and str(path.get_subname(0)) == "prop_spear" and clip.track_get_type(index) in [Animation.TYPE_POSITION_3D, Animation.TYPE_ROTATION_3D]
			var keys: Array = []
			for key in clip.track_get_key_count(index):
				keys.append([clip.track_get_key_time(index,key), clip.track_get_key_transition(index,key), null if omit_values and selected else clip.track_get_key_value(index,key)])
			rows.append([index, path, clip.track_get_type(index), clip.track_get_interpolation_type(index), clip.track_get_interpolation_loop_wrap(index), clip.track_is_enabled(index), clip.track_is_imported(index), keys])
		all.append(rows)
	return var_to_bytes(all)

static func _failure(code: String) -> Dictionary:
	return {"completed": false, "failure_code": code}

static func _time_failure(key_index: int, track_type: int, actual: float, expected: float) -> Dictionary:
	if not is_finite(actual) or not is_finite(expected):
		return _failure("HELD_KEY_TIME_NONFINITE")
	return {"completed": false, "failure_code": "HELD_KEY_TIME", "time_diagnostic": {"key_index": key_index, "track_type": track_type, "actual_type": typeof(actual), "expected_type": typeof(expected), "actual_variant_hex": var_to_bytes(actual).hex_encode(), "expected_variant_hex": var_to_bytes(expected).hex_encode(), "actual_float32_hex": PackedFloat32Array([actual]).to_byte_array().hex_encode(), "expected_float32_hex": PackedFloat32Array([expected]).to_byte_array().hex_encode()}}

static func apply(scene: Node3D, player: AnimationPlayer, skeleton: Skeleton3D, source_scene_path: String, proposal_path: String, proposal_sha256: String) -> Dictionary:
	if not FileAccess.file_exists(proposal_path) or FileAccess.get_sha256(proposal_path) != proposal_sha256:
		return _failure("HELD_PROPOSAL_HASH")
	var plan: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(proposal_path))
	if plan.get("schema", "") != "native-spear-held-key-proposal-v1" or FileAccess.get_sha256(source_scene_path) != plan.source_native_sha256:
		return _failure("HELD_SOURCE_SCHEMA_HASH")
	if not scene.is_ancestor_of(player) or not scene.is_ancestor_of(skeleton) or player.is_playing() or plan.clips.size() != 4:
		return _failure("HELD_INSTANCE_STATE")
	var animation_root: Node = player.get_node(player.root_node)
	var edits: Array = []
	# Validate every old value, native timestamp and exact skeleton target before edits.
	for name in CLIPS:
		if not plan.clips.has(name) or not player.has_animation(name): return _failure("HELD_CLIP_MISSING")
		var clip: Animation = player.get_animation(name)
		var entry: Dictionary = plan.clips[name]
		if clip.length != float(entry.length_unchanged): return _failure("HELD_CLIP_LENGTH")
		if entry.changes.size() != 2: return _failure("HELD_CHANGE_COUNT")
		var seen: Array = []
		for change in entry.changes:
			var track: Dictionary = change.replacement
			var index: int = int(track.index)
			if index < 0 or index >= clip.get_track_count() or index in seen: return _failure("HELD_TRACK_INDEX")
			seen.append(index)
			var path: NodePath = clip.track_get_path(index)
			if path.is_absolute() or path.get_subname_count() != 1 or str(path.get_subname(0)) != "prop_spear" or animation_root.get_node_or_null(NodePath(path.get_concatenated_names())) != skeleton: return _failure("HELD_TRACK_TARGET")
			var expected_type: int = Animation.TYPE_POSITION_3D if track.type == "position_3d" else Animation.TYPE_ROTATION_3D
			if track.type not in ["position_3d", "rotation_3d"] or clip.track_get_type(index) != expected_type: return _failure("HELD_TRACK_TYPE")
			if clip.track_get_key_count(index) != track.times.size() or change.original_values.size() != track.times.size() or track.values.size() != track.times.size(): return _failure("HELD_KEY_COUNT")
			for key in track.times.size():
				if clip.track_get_key_time(index,key) != float(track.times[key]): return _time_failure(key, clip.track_get_type(index), clip.track_get_key_time(index,key), float(track.times[key]))
				if clip.track_get_key_value(index,key) != _value(track.type, change.original_values[key]): return _failure("HELD_OLD_KEY_VALUE")
				for number in track.values[key]:
					if not is_finite(float(number)): return _failure("HELD_NONFINITE_REPLACEMENT")
			edits.append({"clip": name, "track": index, "data": track})
	if edits.size() != 8: return _failure("HELD_EDIT_COUNT")
	var preserved: PackedByteArray = _snapshot(player, true)
	var before: PackedByteArray = _snapshot(player, false)
	# Own all libraries/animations; never modify imported cached shared resources.
	for library_name in player.get_animation_library_list():
		var original: AnimationLibrary = player.get_animation_library(library_name)
		var owned: AnimationLibrary = original.duplicate(true)
		for clip_name in original.get_animation_list():
			owned.remove_animation(clip_name)
			if owned.add_animation(clip_name, original.get_animation(clip_name).duplicate(true)) != OK: return _failure("HELD_OWNED_ANIMATION_ADD")
		player.remove_animation_library(library_name)
		if player.add_animation_library(library_name, owned) != OK: return _failure("HELD_OWNED_LIBRARY_ADD")
	if _snapshot(player, false) != before: return _failure("HELD_DUPLICATE_SNAPSHOT")
	for edit in edits:
		var clip: Animation = player.get_animation(edit.clip)
		for key in edit.data.times.size():
			clip.track_set_key_value(edit.track,key,_value(edit.data.type,edit.data.values[key]))
	if _snapshot(player, true) != preserved: return _failure("HELD_PRESERVED_SNAPSHOT")
	return {"completed": true, "changed_tracks": 8, "source_native_sha256": plan.source_native_sha256, "death_changed": false, "reload_verified": false}

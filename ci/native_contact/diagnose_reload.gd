extends RefCounted
## Bounded scalar/hash diagnostics only. Never normalizes data or authorizes a pass.
const LIMIT: int = 16
static func _hash(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()
static func _summary(value: Variant) -> Dictionary:
	var bytes: PackedByteArray = var_to_bytes(value)
	var result: Dictionary = {"variant_type":typeof(value), "byte_count":bytes.size(), "sha256":_hash(bytes)}
	if value is float:
		if is_finite(value):
			result["scalar"] = value
			result["scalar_variant_hex"] = bytes.hex_encode()
		else:
			result["nonfinite"] = true
	elif value is int or value is bool:
		result["scalar"] = value
	elif value is Vector3:
		if value.is_finite():
			result["components"] = [value.x, value.y, value.z]
	elif value is Quaternion:
		if value.is_finite():
			result["components"] = [value.x, value.y, value.z, value.w]
	elif value is Array:
		result["count"] = value.size()
	# Strings/NodePaths/resources are represented ONLY by type/count/hash.
	return result
static func _property(location: Array) -> String:
	if location.size() == 2 and int(location[1]) < 5:
		return ["clip_name", "clip_length", "clip_loop_mode", "clip_step", "clip_track_count"][int(location[1])]
	if location.size() >= 3 and int(location[1]) >= 5:
		var field: int = int(location[2])
		if field < 7:
			return ["track_index", "track_type", "track_path_hash", "track_interpolation", "track_wrap", "track_enabled", "track_imported"][field]
		if field == 7 and location.size() >= 5:
			return ["key_time", "key_transition", "key_value"][int(location[4])]
	return "array_structure"
static func _walk(before: Variant, after: Variant, location: Array, rows: Array) -> void:
	if rows.size() >= LIMIT or var_to_bytes(before) == var_to_bytes(after):
		return
	if before is Array and after is Array and before.size() == after.size():
		for index in before.size():
			var child: Array = location.duplicate()
			child.append(index)
			_walk(before[index], after[index], child, rows)
			if rows.size() >= LIMIT:
				return
	else:
		rows.append({"snapshot_indices":location, "property":_property(location), "expected":_summary(before), "actual":_summary(after)})
static func describe(kind: String, before: PackedByteArray, after: PackedByteArray) -> Dictionary:
	assert(kind in ["spearman", "archer", "scout"])
	var rows: Array = []
	_walk(bytes_to_var(before), bytes_to_var(after), [], rows)
	return {"schema":"native-contact-reload-diagnostic-v1", "kind":kind, "strict_equal":before == after, "expected_snapshot_sha256":_hash(before), "actual_snapshot_sha256":_hash(after), "max_differences":LIMIT, "difference_count_reported":rows.size(), "differences":rows}

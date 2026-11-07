extends RefCounted
## Pure stream transform. Caller MUST check source hashes, full scene preservation,
## private mesh ownership, exact save/reload, and failure diagnostics before acceptance.
static func _v(a: Array) -> Vector3:
	return Vector3(a[0], a[1], a[2])
static func _matrix(rows: Array) -> Basis:
	return Basis(_v(rows[0]), _v(rows[1]), _v(rows[2])).transposed()
static func _decode(data: PackedByteArray, offset: int, tangent: bool) -> Array:
	var oct := Vector2(float(data.decode_u16(offset)) / 65535.0, float(data.decode_u16(offset + 2)) / 65535.0)
	var sign_value := 1.0
	if tangent:
		oct.y = oct.y * 2.0 - 1.0
		sign_value = 1.0 if oct.y >= 0.0 else -1.0
		oct.y = absf(oct.y)
	return [Vector3.octahedron_decode(oct), sign_value]
static func _encode(data: PackedByteArray, offset: int, direction: Vector3, tangent: bool, sign_value: float) -> void:
	var oct := direction.octahedron_encode()
	if tangent:
		oct.y = maxf(oct.y, 1.0 / 32767.0)
		oct.y = oct.y * 0.5 + 0.5
		oct.y = oct.y if sign_value >= 0.0 else 1.0 - oct.y
	var x: int = int(clampf(PackedFloat32Array([oct.x * 65535.0])[0], 0.0, 65535.0))
	var y: int = int(clampf(PackedFloat32Array([oct.y * 65535.0])[0], 0.0, 65535.0))
	if tangent and x == 0 and y == 65535:
		x = 65535
	data.encode_u16(offset, x)
	data.encode_u16(offset + 2, y)
static func transform(source: PackedByteArray, plan: Dictionary) -> Dictionary:
	if source.size() != 82040 or plan.vertex_ids.size() != 96:
		return {"completed": false, "code": "BLADE_INPUT_SIZE"}
	var target := source.duplicate()
	var linear := _matrix(plan.mesh_position_linear_transform)
	var normal_matrix := _matrix(plan.mesh_normal_linear_transform)
	if linear.determinant() <= 0.0:
		return {"completed": false, "code": "BLADE_HANDEDNESS"}
	for j in range(96):
		var index: int = plan.vertex_ids[j]
		if index != 4006 + j:
			return {"completed": false, "code": "BLADE_VERTEX_ID"}
		var expected := PackedFloat32Array(plan.original_mesh_positions[j]).to_byte_array()
		if source.slice(index * 12, index * 12 + 12) != expected:
			return {"completed": false, "code": "BLADE_OLD_POSITION"}
		var replacement := PackedFloat32Array(plan.replacement_mesh_positions[j]).to_byte_array()
		for k in range(12):
			target[index * 12 + k] = replacement[k]
		var no: int = 49224 + index * 8
		var decoded_n: Array = _decode(source, no, false)
		var decoded_t: Array = _decode(source, no + 4, true)
		var n: Vector3 = (normal_matrix * decoded_n[0]).normalized()
		var t: Vector3 = linear * decoded_t[0]
		t = (t - n * n.dot(t)).normalized()
		if not n.is_finite() or not t.is_finite() or n.length_squared() < 0.99 or t.length_squared() < 0.99:
			return {"completed": false, "code": "BLADE_FRAME"}
		_encode(target, no, n, false, 1.0)
		_encode(target, no + 4, t, true, decoded_t[1])
	# Two contiguous allowed intervals cover exactly selected positions and frames.
	if target.slice(0, 48072) != source.slice(0, 48072) or target.slice(49224, 81272) != source.slice(49224, 81272):
		return {"completed": false, "code": "BLADE_UNRELATED_BYTES"}
	return {"completed": true, "vertex_data": target, "allowed_bytes": 1920}

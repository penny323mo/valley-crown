extends RefCounted
## Actual loaded mesh/skin data and engine-evaluated bone poses. No renderer readback.
## Finite samples only: NOT continuous collision certification or visual acceptance.
const Contact = preload("res://native_contact/apply_native_contact.gd")

static func _seek(player: AnimationPlayer, skeleton: Skeleton3D, time: float) -> void:
	player.play("death")
	player.seek(time, true)
	player.pause()
	skeleton.force_update_all_bone_transforms()

static func _rigid_vertices(scene: Node3D, skeleton: Skeleton3D, bone: int) -> Dictionary:
	var points: Array = []
	var meshes: Array[Node] = scene.find_children("*", "MeshInstance3D", true, false)
	assert(not meshes.is_empty())
	for node in meshes:
		var instance: MeshInstance3D = node as MeshInstance3D
		assert(instance.get_node(instance.skeleton) == skeleton)
		assert(instance.mesh != null and instance.skin != null)
		assert((scene.global_transform.affine_inverse() * instance.global_transform).is_equal_approx(Transform3D.IDENTITY))
		assert((scene.global_transform.affine_inverse() * skeleton.global_transform).is_equal_approx(Transform3D.IDENTITY))
		var skin: Skin = instance.skin
		var binding: Array[int] = []
		for bind in skin.get_bind_count():
			var name: StringName = skin.get_bind_name(bind)
			var index: int = skeleton.find_bone(name) if not name.is_empty() else skin.get_bind_bone(bind)
			assert(index >= 0 and index < skeleton.get_bone_count())
			binding.append(index)
		for surface in instance.mesh.get_surface_count():
			var arrays: Array = instance.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var joints: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			assert(not vertices.is_empty() and joints.size() == weights.size())
			assert(weights.size() == vertices.size() * 4 or weights.size() == vertices.size() * 8)
			var stride: int = 8 if weights.size() == vertices.size() * 8 else 4
			for vertex in vertices.size():
				var total: float = 0.0
				var prop_weight: float = 0.0
				var local: Vector3 = Vector3.ZERO
				for slot in stride:
					var offset: int = vertex * stride + slot
					var weight: float = weights[offset]
					assert(is_finite(weight) and weight >= 0.0)
					total += weight
					if weight == 0.0:
						continue
					var bind: int = joints[offset]
					assert(bind >= 0 and bind < binding.size())
					if binding[bind] == bone:
						prop_weight += weight
						local += (skin.get_bind_pose(bind) * vertices[vertex]) * weight
				# Body skin weights use quantized normalized uint16 storage. They are
				# outside this rigid-prop extraction; do not normalize or alter them.
				if prop_weight == 0.0:
					continue
				# Every positive prop contribution, however small, must be rigid/full.
				assert(absf(total - 1.0) < 0.000001)
				assert(prop_weight > 0.999999, "Mixed prop skin weights are unsupported")
				assert(prop_weight == total, "Tiny cross-bone weights cannot be ignored")
				assert(local.is_finite())
				points.append(local)
	assert(points.size() >= 4)
	return {"completed":true, "points":points}

static func _desired(samples: Array, time: float) -> Transform3D:
	var left: int = 0
	while left + 1 < samples.size() and float(samples[left + 1].time) <= time:
		left += 1
	var right: int = mini(left + 1, samples.size() - 1)
	var a: Transform3D = Contact._pose(samples[left])
	var b: Transform3D = Contact._pose(samples[right])
	var alpha: float = 0.0 if left == right else (time - float(samples[left].time)) / (float(samples[right].time) - float(samples[left].time))
	return Transform3D(Basis(a.basis.get_rotation_quaternion().slerp(b.basis.get_rotation_quaternion(), alpha)), a.origin.lerp(b.origin, alpha))

static func run(scene: Node3D, original: Node3D, kind: String, data: Dictionary) -> Dictionary:
	var player: AnimationPlayer = scene.find_child("AnimationPlayer", true, false)
	var skeleton: Skeleton3D = scene.find_child("Skeleton3D", true, false)
	var old_player: AnimationPlayer = original.find_child("AnimationPlayer", true, false)
	var old_skeleton: Skeleton3D = original.find_child("Skeleton3D", true, false)
	assert(player != null and skeleton != null and old_player != null and old_skeleton != null)
	var report: Dictionary = {"status":"INCOMPLETE", "method":"engine AnimationPlayer poses with actual reloaded native mesh weights and Skin binds", "continuous_clearance_certified":false, "visual_acceptance":false, "props":{}}
	for bone_name in Contact.ALLOWED[kind]:
		var bone: int = skeleton.find_bone(bone_name)
		var old_bone: int = old_skeleton.find_bone(bone_name)
		assert(bone >= 0 and old_bone >= 0)
		var extracted: Variant = _rigid_vertices(scene, skeleton, bone)
		if not (extracted is Dictionary) or extracted.get("completed", false) != true or not (extracted.get("points") is Array):
			push_error("Corrected native prop extraction did not complete")
			return {}
		var original_extracted: Variant = _rigid_vertices(original, old_skeleton, old_bone)
		if not (original_extracted is Dictionary) or original_extracted.get("completed", false) != true or not (original_extracted.get("points") is Array):
			push_error("Original native prop extraction did not complete")
			return {}
		var points: Array = extracted.points
		var old_points: Array = original_extracted.points
		assert(var_to_bytes(points) == var_to_bytes(old_points), "Native mesh/bind prop points changed")
		var spec: Dictionary = data.props[bone_name]
		var time_set: Dictionary = {}
		for step in 1441:
			time_set[float(step) / 960.0] = true
		# Include every dense key and its immediate neighborhoods, plus named events.
		var anchors: Array = [spec.release_seconds, spec.contact_seconds, spec.settled_seconds]
		for row in spec.samples:
			anchors.append(row.time)
		var death: Animation = player.get_animation("death")
		var count: int = 0
		for track in death.get_track_count():
			var path: NodePath = death.track_get_path(track)
			if path.get_subname_count() == 1 and str(path.get_subname(0)) == bone_name:
				assert(death.track_get_type(track) in [Animation.TYPE_POSITION_3D, Animation.TYPE_ROTATION_3D, Animation.TYPE_SCALE_3D])
				assert(death.track_get_key_count(track) == 183 and death.track_get_interpolation_type(track) == Animation.INTERPOLATION_LINEAR)
				count += 1
				for key in death.track_get_key_count(track):
					anchors.append(death.track_get_key_time(track, key))
		assert(count == 3)
		for anchor in anchors:
			for delta in [-0.000001, 0.0, 0.000001]:
				var time: float = float(anchor) + float(delta)
				if time >= 0.0 and time <= 1.5:
					time_set[time] = true
		var times: Array = time_set.keys()
		times.sort()
		var minimum: float = INF
		var minimum_time: float = 0.0
		var max_error: float = 0.0
		var held_error: float = 0.0
		var release_error: float = 0.0
		var settled_error: float = 0.0
		var terminal_min: float = INF
		var terminal_support: int = 0
		var settled_pose: Transform3D = _desired(spec.samples, 1.5)
		for value in times:
			var time: float = float(value)
			_seek(player, skeleton, time)
			var actual: Transform3D = skeleton.get_bone_global_pose(bone)
			assert(actual.origin.is_finite() and actual.basis.is_finite())
			var ideal: Transform3D = _desired(spec.samples, time)
			if time <= float(spec.release_seconds) + 0.00000001:
				_seek(old_player, old_skeleton, time)
				ideal = old_skeleton.get_bone_global_pose(old_bone)
			for point in points:
				var position: Vector3 = actual * point
				var error: float = position.distance_to(ideal * point)
				assert(position.is_finite() and is_finite(error))
				if position.y < minimum:
					minimum = position.y
					minimum_time = time
				max_error = maxf(max_error, error)
				if time <= float(spec.release_seconds):
					held_error = maxf(held_error, error)
				if absf(time - float(spec.release_seconds)) < 0.00000001:
					release_error = maxf(release_error, error)
				if time >= float(spec.settled_seconds):
					settled_error = maxf(settled_error, position.distance_to(settled_pose * point))
				if time == 1.5:
					terminal_min = minf(terminal_min, position.y)
					if position.y <= 0.0021:
						terminal_support += 1
		var row: Dictionary = {"vertex_count":points.size(), "probe_count":times.size(), "min_y_m":minimum, "min_y_time":minimum_time, "max_world_path_error_m":max_error, "max_held_error_m":held_error, "release_error_m":release_error, "max_settled_drift_m":settled_error, "terminal_min_y_m":terminal_min, "terminal_vertices_within_2_1mm":terminal_support}
		report.props[bone_name] = row
		assert(minimum >= 0.001, "Native sampled prop floor clearance failed")
		assert(max_error < 0.01 and held_error < 0.00002 and release_error < 0.00002, "Native trajectory/held pose failed")
		assert(settled_error < 0.001 and terminal_min >= 0.001 and terminal_min <= 0.003 and terminal_support >= 3, "Native terminal support/drift failed")
	player.stop(true)
	old_player.stop(true)
	report.status = "PASS"
	return report

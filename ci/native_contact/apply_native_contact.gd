extends RefCounted
## SOURCE-ONLY NATIVE-AUTHORED proposal. Does not import Blender or modify materials.
## Apply directly to the exact accepted native scene, before packing. No runtime physics.
const ALLOWED: Dictionary = {"spearman":["prop_spear","prop_shield"],"archer":["prop_bow"],"scout":["prop_sword"]}

static func _snapshot(player: AnimationPlayer, excluded: Array) -> PackedByteArray:
	var result: Array = []
	for name in player.get_animation_list():
		var animation: Animation = player.get_animation(name)
		var rows: Array = [str(name),animation.length,animation.loop_mode,animation.step,animation.get_track_count()]
		for track in animation.get_track_count():
			var path: NodePath = animation.track_get_path(track)
			if name=="death" and path.get_subname_count()==1 and str(path.get_subname(0)) in excluded: continue
			var keys: Array = []
			for key in animation.track_get_key_count(track):
				keys.append([animation.track_get_key_time(track,key),animation.track_get_key_transition(track,key),animation.track_get_key_value(track,key)])
			rows.append([track,animation.track_get_type(track),path,animation.track_get_interpolation_type(track),animation.track_get_interpolation_loop_wrap(track),animation.track_is_enabled(track),animation.track_is_imported(track),keys])
		result.append(rows)
	return var_to_bytes(result)

static func _pose(row: Dictionary) -> Transform3D:
	assert(row.keys().size()==3 and row.has("time") and row.has("position") and row.has("rotation"))
	var p: Array = row.position
	var q: Array = row.rotation
	assert(p.size()==3 and q.size()==4)
	for value in p+q: assert((value is float or value is int) and is_finite(float(value)))
	var rotation: Quaternion = Quaternion(q[0],q[1],q[2],q[3])
	assert(absf(rotation.length_squared()-1.0)<0.00002)
	return Transform3D(Basis(rotation.normalized()),Vector3(p[0],p[1],p[2]))

static func apply(scene: Node3D, player: AnimationPlayer, skeleton: Skeleton3D, kind: String, source_native_sha: String, sidecar_path: String, sidecar_sha: String) -> Dictionary:
	assert(ALLOWED.has(kind),"No contact edit allowed for this class")
	assert(sidecar_path=="res://native_contact/"+kind+".json")
	assert(sidecar_sha.length()==64 and source_native_sha.length()==64)
	assert(FileAccess.file_exists(sidecar_path) and FileAccess.get_sha256(sidecar_path)==sidecar_sha)
	var raw: String = FileAccess.get_file_as_string(sidecar_path)
	assert(raw.to_utf8_buffer().size()<=250000)
	var data: Dictionary = JSON.parse_string(raw)
	assert(data.keys().size()==7 and data.source_native_sha256==source_native_sha)
	assert(data.schema=="native-death-equipment-world-v1" and data.kind==kind)
	assert(data.space=="gltf_scene_y_up" and data.clip=="death" and is_equal_approx(float(data.length),1.5))
	assert(scene.transform.is_equal_approx(Transform3D.IDENTITY))
	assert(not player.is_playing() and player.get_queue().is_empty() and player.autoplay.is_empty() and player.assigned_animation.is_empty(),"Fresh stopped import player required")
	var scene_from_skeleton: Transform3D = scene.global_transform.affine_inverse()*skeleton.global_transform
	# Current normalized asset hierarchy is identity; fail if later art changes it.
	assert(scene_from_skeleton.is_equal_approx(Transform3D.IDENTITY))
	var skeleton_from_scene: Transform3D = scene_from_skeleton.affine_inverse()
	var allowed: Array = ALLOWED[kind]
	var props: Dictionary = data.props
	assert(props.size()==allowed.size())
	for bone_name in allowed: assert(props.has(bone_name))
	var unchanged: PackedByteArray = _snapshot(player,allowed)
	var death: Animation = player.get_animation("death")
	var animation_root: Node = player.get_node(player.root_node)
	assert(is_equal_approx(death.length,float(data.length)))
	var restore: Array = []
	for bone in skeleton.get_bone_count(): restore.append([skeleton.get_bone_pose_position(bone),skeleton.get_bone_pose_rotation(bone),skeleton.get_bone_pose_scale(bone)])
	var collected: Dictionary = {}
	var summary: Dictionary = {}
	# Collect every parent and original held pose BEFORE replacing any track.
	for bone_name in allowed:
		var bone: int = skeleton.find_bone(bone_name)
		assert(bone>=0)
		var parent: int = skeleton.get_bone_parent(bone)
		assert(parent>=0)
		for child in skeleton.get_bone_count(): assert(skeleton.get_bone_parent(child)!=bone,"Contact props must remain leaf bones")
		var spec: Dictionary = props[bone_name]
		assert(spec.keys().size()==4 and spec.has("samples") and spec.has("release_seconds") and spec.has("contact_seconds") and spec.has("settled_seconds"))
		var release: float = float(spec.release_seconds)
		assert(float(spec.contact_seconds)>release and float(spec.settled_seconds)>float(spec.contact_seconds) and float(spec.settled_seconds)<=death.length)
		assert(absf(release-1.0/3.0)<0.0000001)
		var samples: Array = spec.samples
		assert(samples.size()>=181 and samples.size()<=190)
		var tracks: Dictionary = {}
		for track in death.get_track_count():
			var path: NodePath = death.track_get_path(track)
			if path.get_subname_count()==1 and str(path.get_subname(0))==bone_name:
				assert(not path.is_absolute() and animation_root.get_node_or_null(NodePath(path.get_concatenated_names()))==skeleton,"Contact track points at a different node")
				var type: int = death.track_get_type(track)
				assert(type in [Animation.TYPE_POSITION_3D,Animation.TYPE_ROTATION_3D,Animation.TYPE_SCALE_3D] and not tracks.has(type))
				tracks[type]=track
		assert(tracks.size()==3)
		var rows: Array = []
		var previous: float = -1.0
		var release_seen: bool = false
		var contact_seen: bool = false
		var settle_seen: bool = false
		for sample in samples:
			var row: Dictionary = sample
			assert(row.time is float or row.time is int)
			var t: float = float(row.time)
			assert(is_finite(t) and t>=0 and t<=death.length and t>previous)
			if previous>=0: assert(t-previous<=1.0/120.0+0.0000001)
			previous=t
			player.play("death"); player.seek(t,true); player.pause()
			skeleton.force_update_all_bone_transforms()
			var held: Transform3D = skeleton.get_bone_global_pose(bone)
			var desired: Transform3D = skeleton_from_scene*_pose(row)
			if absf(t-release)<0.0000001:
				release_seen=true
				assert(held.origin.distance_to(desired.origin)<0.00002)
				assert(absf(held.basis.get_rotation_quaternion().dot(desired.basis.get_rotation_quaternion()))>0.999999)
			if absf(t-float(spec.contact_seconds))<0.0000001: contact_seen=true
			if absf(t-float(spec.settled_seconds))<0.0000001: settle_seen=true
			if t<=release: desired=held
			var local: Transform3D = skeleton.get_bone_global_pose(parent).affine_inverse()*desired
			var scale: Vector3 = local.basis.get_scale()
			assert(scale.distance_to(Vector3.ONE)<0.00002)
			rows.append([t,local.origin,local.basis.get_rotation_quaternion().normalized(),scale])
		assert(release_seen and contact_seen and settle_seen)
		assert(absf(float(samples[0].time))<0.0000001 and absf(float(samples[-1].time)-death.length)<0.0000001)
		collected[bone_name]={"tracks":tracks,"rows":rows}
		summary[bone_name]={"keys_per_track":rows.size(),"release_seconds":release,"contact_seconds":spec.contact_seconds,"settled_seconds":spec.settled_seconds}
	for bone_name in allowed:
		var entry: Dictionary = collected[bone_name]
		var tracks: Dictionary = entry.tracks
		for type in tracks:
			var track: int = tracks[type]
			for key in range(death.track_get_key_count(track)-1,-1,-1): death.track_remove_key(track,key)
			death.track_set_interpolation_type(track,Animation.INTERPOLATION_LINEAR)
		for row in entry.rows:
			death.position_track_insert_key(tracks[Animation.TYPE_POSITION_3D],row[0],row[1])
			death.rotation_track_insert_key(tracks[Animation.TYPE_ROTATION_3D],row[0],row[2])
			death.scale_track_insert_key(tracks[Animation.TYPE_SCALE_3D],row[0],row[3])
	assert(_snapshot(player,allowed)==unchanged,"A body or non-death track changed")
	# assigned_animation has PROPERTY_USAGE_NONE; the transient death name is
	# intentionally not restored through its invalid empty-string setter.
	player.stop(true)
	assert(not player.is_playing() and player.get_queue().is_empty() and player.autoplay.is_empty())
	for bone in skeleton.get_bone_count():
		skeleton.set_bone_pose_position(bone,restore[bone][0])
		skeleton.set_bone_pose_rotation(bone,restore[bone][1])
		skeleton.set_bone_pose_scale(bone,restore[bone][2])
		assert(skeleton.get_bone_pose_position(bone)==restore[bone][0] and skeleton.get_bone_pose_rotation(bone)==restore[bone][1] and skeleton.get_bone_pose_scale(bone)==restore[bone][2])
	skeleton.force_update_all_bone_transforms()
	return {"sidecar_sha256":sidecar_sha,"method":"prop-only post-import parent compensation","props":summary,"unchanged_other_track_bytes":true}

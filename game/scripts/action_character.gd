extends RefCounted
## One observation-only skeletal presenter. No entities, orders, targets, or damage.
## Assets must have normalized names after the reviewed Blender authoring/import pass.
const Occlusion = preload("res://scripts/observed_occlusion.gd")
const ROOT := "res://assets/mature/models/"
const KINDS := ["villager", "spearman", "archer", "scout"]
const LOOP_CLIPS := ["idle", "walk", "carry_walk", "gather_wood", "gather_food", "build", "repair"]
# Markers must be verified against the selected source clips before art promotion.
const IMPACT_FRACTION := {"villager": 0.56, "spearman": 0.56, "scout": 0.56, "archer": 0.62}
const WALK_METRES_PER_CYCLE := 1.6
var occlusion = Occlusion.new()
var rig: Node3D
var player: AnimationPlayer
var skeleton: Skeleton3D
var body: Node3D
var kind := ""
var clip := "idle"
var playhead := 0.0
var walk_rate := 0.0
var previous_position := Vector3.ZERO
var previous_tick := -1
var last_attack_tick := -1
var last_hit_tick := -1
var running_last_frame := false
var one_shot := false
var dead := false
var finished := false
var pose_applications := 0
var update_budget := 0.0
var material_instances: Array[Material] = []
var prior_bone_poses: Array[Transform3D] = []
var transition_time := 1.0
var asset_path := ""

func bind(target_body: Node3D, unit_kind: String, team_color: Color) -> bool:
	assert(unit_kind in KINDS)
	kind = unit_kind; body = target_body
	asset_path = ROOT + kind + "_action.scn"
	if not ResourceLoader.exists(asset_path):
		push_error("Art candidate incomplete: missing articulated asset " + asset_path)
		return false
	rig = (load(asset_path) as PackedScene).instantiate()
	rig.name = "ObservedActionRig"
	rig.set_meta("visual_only", true)
	rig.set_meta("occlusion_authorized", true)
	body.add_child(rig)
	player = rig.find_children("*", "AnimationPlayer", true, false)[0]
	skeleton = rig.find_children("*", "Skeleton3D", true, false)[0]
	assert(player != null and skeleton != null)
	for required in ["idle", "walk", "attack", "hit", "death"]: assert(player.has_animation(required))
	if kind == "villager":
		for required in ["carry_walk", "gather_wood", "gather_food", "build", "repair"]: assert(player.has_animation(required))
	# Shared non-faction material remains immutable; only recolored cloth duplicates.
	for mesh: MeshInstance3D in rig.find_children("*", "MeshInstance3D", true, false):
		for surface in mesh.mesh.get_surface_count():
			var source: Material = mesh.mesh.surface_get_material(surface)
			if source is StandardMaterial3D and source.resource_name == "team_blue":
				var local: StandardMaterial3D = source.duplicate()
				local.albedo_color = team_color; local.vertex_color_use_as_albedo = false
				mesh.set_surface_override_material(surface, local); material_instances.append(local)
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	player.process_mode = Node.PROCESS_MODE_DISABLED
	_apply_pose(0.0)
	occlusion.bind(rig, team_color)
	return true

func _start(next: String, at: float = 0.0, shot: bool = false, blend: bool = true) -> void:
	prior_bone_poses.clear()
	if blend and is_instance_valid(skeleton):
		for bone in skeleton.get_bone_count(): prior_bone_poses.append(skeleton.get_bone_pose(bone))
	transition_time = 0.0 if not prior_bone_poses.is_empty() else 1.0
	clip = next; playhead = at; one_shot = shot; finished = false
	_apply_pose(0.0)

func observe(record: Dictionary, delta: float, running: bool) -> void:
	assert(not record.get("remembered", false))
	if dead or not is_instance_valid(rig): return
	body.position.y = 0.0; body.rotation.z = 0.0
	var now: int = record.last_seen_tick
	var position: Vector3 = record.pos
	if not running:
		running_last_frame = false; previous_position = position; previous_tick = now; walk_rate = 0.0
		return
	var reset := not running_last_frame or previous_tick < 0 or now < previous_tick or now - previous_tick > 5
	if reset:
		previous_position = position; previous_tick = now; walk_rate = 0.0; update_budget = 0.0
	elif now > previous_tick:
		var displacement := Vector2(position.x - previous_position.x, position.z - previous_position.z).length()
		walk_rate = clampf(displacement / ((now - previous_tick) * 0.05) / WALK_METRES_PER_CYCLE, 0.0, 3.5)
		previous_position = position; previous_tick = now
	running_last_frame = true
	var attack_tick: int = record.get("visual_attack_tick", -1)
	var hit_tick: int = record.get("visual_hit_tick", -1)
	# Reappearing actors do not replay a hidden event. Current release is observable.
	if reset:
		if attack_tick < now: last_attack_tick = maxi(last_attack_tick, attack_tick)
		if hit_tick < now: last_hit_tick = maxi(last_hit_tick, hit_tick)
	if hit_tick > last_hit_tick:
		last_hit_tick = hit_tick
		last_attack_tick = maxi(last_attack_tick, attack_tick) # Do not replay an interrupted release.
		_start("hit", 0.0, true, false)
	elif attack_tick > last_attack_tick:
		last_attack_tick = attack_tick
		# Authority damage already settled at release. Contact pose occurs immediately,
		# never a second hit, deferred damage, or animation callback into the ledger.
		_start("attack", player.get_animation("attack").length * IMPACT_FRACTION[kind], true, false)
	var action: String = record.get("visual_action", "idle")
	rig.rotation.y = angle_difference(body.rotation.y, record.get("visual_action_yaw", body.rotation.y)) if clip not in ["idle", "walk", "carry_walk"] else 0.0
	if not one_shot:
		var desired := "idle"
		# Current applied work wins over a queued final waypoint. Construction can
		# legally start within its work radius before that waypoint is consumed.
		if action in ["gather_wood", "gather_food", "build", "repair"] and player.has_animation(action): desired = action
		elif record.get("visual_moving", false):
			desired = "carry_walk" if kind == "villager" and record.get("visual_carrying", false) else "walk"
		elif action in LOOP_CLIPS and player.has_animation(action): desired = action
		# Anticipation is visible only after the legal in-range attack gate. It never
		# predicts a target position or commits a future hit.
		if record.get("visual_attack_ready", false):
			if clip != "attack": _start("attack", 0.0, false)
			var anticipation: float = record.get("visual_anticipation", 0.0)
			playhead = clampf(anticipation, 0.0, 1.0) * player.get_animation("attack").length * IMPACT_FRACTION[kind]
			_apply_pose(minf(maxf(delta, 0.0), .1))
			return
		if desired != clip: _start(desired)
	rig.rotation.y = angle_difference(body.rotation.y, record.get("visual_action_yaw", body.rotation.y)) if clip not in ["idle", "walk", "carry_walk"] else 0.0
	if reset or not is_finite(delta) or delta <= 0.0 or delta > 0.25: return
	var advance := minf(delta, 0.1)
	if clip in ["walk", "carry_walk"]: advance *= walk_rate * player.get_animation(clip).length
	if advance <= 0.0: return
	playhead += advance
	var length := player.get_animation(clip).length
	if one_shot:
		playhead = minf(playhead, length)
		if playhead >= length: one_shot = false
	else: playhead = fposmod(playhead, length)
	# Cap bone writes to 30Hz, independent of simulation and display frame rate.
	update_budget += minf(delta, .1)
	if update_budget >= 1.0 / 30.0:
		var pose_delta := update_budget; update_budget = 0.0; _apply_pose(pose_delta)

func start_death() -> void:
	dead = true; _start("death", 0.0, true, false)
	rig.set_meta("occlusion_authorized", false)
	occlusion.set_authorized(false)

func advance_death(delta: float, running: bool) -> void:
	if not dead or finished or not running or not is_finite(delta) or delta <= 0.0 or delta > .25: return
	playhead = minf(playhead + minf(delta, .1), player.get_animation("death").length)
	_apply_pose(minf(delta,.1))
	finished = playhead >= player.get_animation("death").length

func _apply_pose(delta: float) -> void:
	player.play(clip); player.seek(playhead, true); player.pause()
	transition_time = minf(1.0, transition_time + delta / .12)
	if transition_time < 1.0 and prior_bone_poses.size() == skeleton.get_bone_count():
		for bone in skeleton.get_bone_count():
			var blended := prior_bone_poses[bone].interpolate_with(skeleton.get_bone_pose(bone), transition_time)
			skeleton.set_bone_pose(bone, blended)
	else: prior_bone_poses.clear()
	skeleton.force_update_all_bone_transforms()
	pose_applications += 1

func visual_evidence_snapshot() -> Dictionary:
	var poses: Array = []
	for bone in skeleton.get_bone_count():
		var p := skeleton.get_bone_pose(bone)
		poses.append({"bone":skeleton.get_bone_name(bone), "pose":str(p)})
	return {"kind":kind, "clip":clip, "seek_seconds":playhead, "player_path":str(player.get_path()),
		"asset_path":asset_path, "asset_sha256":FileAccess.get_sha256(asset_path), "bone_count":skeleton.get_bone_count(),
		"pose_sha256":JSON.stringify(poses).sha256_text(), "poses":poses, "pose_applications":pose_applications,
		"occlusion":occlusion.stats(), "attack_release_tick":last_attack_tick, "hit_tick":last_hit_tick, "dead_visual_only":dead}

func release() -> void:
	occlusion.release()
	if is_instance_valid(rig):
		rig.set_meta("occlusion_authorized", false)
		player.stop(); player.clear_caches(); rig.free()
	material_instances.clear(); prior_bone_poses.clear()

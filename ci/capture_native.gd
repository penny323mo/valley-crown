extends SceneTree
## External QA harness. PNG bytes come directly from the real root viewport.
## No UI overlays, image synthesis, resource grants, teleportation or hidden-state reads.
var game
var destination: String
var build: String
var records: Array = []
var commands: Array = []
var failed := false
var width: int
var height: int
var checks: Array = []
var scout_id := -1
var enemy_id := -1
var enemy_initial_hp := 0
var retreat_start: Vector3
var tutorial_was_skipped := false
var observations: Array = []

func _initialize():
	call_deferred("run")

func fail(message: String):
	failed = true
	push_error(message)
	quit(1)

func frames(count: int):
	for index in count:
		await process_frame

func observed():
	return game.faction_views[0].records()

func choose_worker():
	for record in observed().values():
		if record.owned and record.kind == "villager" and record.alive:
			return record
	return {}

func nearest_visible_resource(worker, kinds: Array):
	var chosen = {}
	var distance := INF
	for record in observed().values():
		if record.kind not in kinds or record.remembered or not record.alive:
			continue
		var candidate: float = worker.pos.distance_to(record.pos)
		if candidate < distance:
			distance = candidate
			chosen = record
	return chosen

func pose_evidence():
	# Controllers may be RefCounted, not scene nodes. The game's explicit
	# observational API filters actual rigs through is_visible_in_tree().
	if game.has_method("visual_evidence_snapshot"):
		return [{"node": ".", "snapshot": game.visual_evidence_snapshot()}]
	return []  # The accepted baseline has no skeletal controller hook.

func capture(label: String):
	await RenderingServer.frame_post_draw
	if DisplayServer.get_name() == "headless":
		fail("A headless/dummy renderer cannot supply visual acceptance.")
		return
	var image: Image = root.get_texture().get_image()
	if image == null or image.is_empty() or image.get_width() != width or image.get_height() != height:
		fail("Missing framebuffer or unexpected framebuffer dimensions.")
		return
	var filename := "%03d-%s.png" % [records.size(), label]
	var path := destination.path_join(filename)
	if image.save_png(path) != OK:
		fail("Cannot save the unmodified viewport image.")
		return
	var own: Array = []
	for record in observed().values():
		if record.owned and record.category == "unit":
			own.append({"id": record.id, "kind": record.kind, "state": record.state,
				"position": [record.pos.x, record.pos.y, record.pos.z], "carry": record.get("carry", 0),
				"path_points": record.get("path", []).size()})
	var item := {"image": filename, "image_sha256": FileAccess.get_sha256(path),
		"capture_kind": "genuine_native_game_viewport", "label": label,
		"utc": Time.get_datetime_string_from_system(true, true), "unix_time": Time.get_unix_time_from_system(),
		"monotonic_usec": Time.get_ticks_usec(), "process_frame": Engine.get_process_frames(),
		"build": game.Rules.BUILD_ID, "version": game.Rules.VERSION,
		"game_sha256": FileAccess.get_sha256("res://scripts/game.gd"),
		"rules_sha256": FileAccess.get_sha256("res://scripts/rules.gd"),
		"engine": Engine.get_version_info(), "display": DisplayServer.get_name(),
		"rendering_method": RenderingServer.get_current_rendering_method(),
		"rendering_driver": RenderingServer.get_current_rendering_driver_name(),
		"adapter_name": RenderingServer.get_video_adapter_name(),
		"adapter_vendor": RenderingServer.get_video_adapter_vendor(),
		"framebuffer": [image.get_width(), image.get_height()],
		"logical_viewport": [root.get_visible_rect().size.x, root.get_visible_rect().size.y],
		"content_scale_factor": root.content_scale_factor,
		"game_tick": game.tick_count, "game_seconds": game.game_time,
		"camera_focus": [game.camera_focus.x, game.camera_focus.y, game.camera_focus.z],
		"camera_zoom": game.camera_zoom, "selected": game.selected.duplicate(),
		"economy_audit_ok": game.economy.audit().ok, "own_units": own,
		"animation_poses": pose_evidence(),
		"public_state": game._snapshot(), "encounter": encounter(), "tutorial_skipped": tutorial_was_skipped,
		"interface_state": {"build_mode": game.build_mode, "touch_command": game.touch_command, "rally_building": game.rally_building, "menu_visible": game.compact_menu.visible, "paused": game.paused, "tutorial_visible": game.tutorial_panel.visible, "tutorial_text": game.tutorial_label.text},
		"limitations": ["Scripted UI-handler inspection; not physical touch validation","Native Linux software OpenGL, not Web/iPhone", "Existing UI handlers and command queue, not physical touch acceptance", "Fixed engine delta, not performance evidence"]}
	records.append(item)
	var file := FileAccess.open(destination.path_join(filename + ".json"), FileAccess.WRITE)
	if file == null:
		fail("Cannot write framebuffer provenance.")
		return
	file.store_string(JSON.stringify(item, "  "))
	file.close()
	print("NATIVE_FRAME ", filename, " tick=", game.tick_count)

func check(name: String, ok: bool, detail: Dictionary = {}):
	checks.append({"name": name, "pass": ok, "tick": game.tick_count, "detail": detail})
	print("COMBAT_CHECK ", JSON.stringify(checks.back()))
	if not ok: fail("Combat flow: " + name)
	return ok

func scout():
	return observed().get(scout_id, {})

func enemy():
	return observed().get(enemy_id, {})

func public_unit(record):
	if record.is_empty(): return {}
	var result = {"id": record.id, "kind": record.kind, "owned": record.owned,
		"team": record.team, "remembered": record.remembered, "alive": record.alive,
		"hp": record.hp, "max_hp": record.max_hp,
		"position": [record.pos.x, record.pos.y, record.pos.z],
		"visual_attack_tick": record.visual_attack_tick, "visual_hit_tick": record.visual_hit_tick}
	if record.owned:
		result.state = record.state; result.target = record.target
	return result

func encounter():
	var visible_enemies: Array = []
	for record in observed().values():
		if record.team == 1 and record.category == "unit" and not record.remembered and record.alive:
			visible_enemies.append(public_unit(record))
	return {"scout": public_unit(scout()), "target": public_unit(enemy()), "visible_enemy_units": visible_enemies}

func frame_scout():
	# Existing scout shortcut includes a camera recenter; does not move the unit.
	game._select_group("scout")

func frame_encounter():
	var ours = scout(); var theirs = enemy()
	if ours.is_empty() or theirs.is_empty(): return
	# Pan through the ordinary camera handler using only currently public positions.
	var desired: Vector3 = (ours.pos + theirs.pos) * 0.5
	var delta: Vector3 = desired - game.camera_focus
	var right: Vector3 = game.camera.global_basis.x; right.y = 0
	var forward: Vector3 = game.camera.global_basis.z; forward.y = 0
	game._pan_camera(Vector2(delta.dot(right.normalized()), delta.dot(forward.normalized())) * float(height) / game.camera_zoom)

func healthy_session():
	return not game.paused and not game.game_over and not scout().is_empty()

func travel_to_tick(deadline: int):
	while game.tick_count < deadline:
		await process_frame
		if not healthy_session(): return false
		if Engine.get_process_frames() % 15 == 0: frame_scout()
	return true

func find_visible_villager(maximum_ticks: int):
	var deadline: int = game.tick_count + maximum_ticks
	while game.tick_count < deadline:
		await process_frame
		if not healthy_session(): return false
		if Engine.get_process_frames() % 15 == 0: frame_scout()
		var chosen = {}; var distance := INF
		for record in observed().values():
			if record.team != 1 or record.kind != "villager" or not record.alive or record.remembered: continue
			var d: float = scout().pos.distance_squared_to(record.pos)
			if d < distance:
				distance = d; chosen = record
		if not chosen.is_empty():
			enemy_id = chosen.id
			observations.append({"event": "first_visible_target", "tick": game.tick_count, "target": public_unit(chosen), "scout": public_unit(scout())})
			return true
	return false

func wait_for_damage(amount: int, maximum_ticks: int):
	var deadline: int = game.tick_count + maximum_ticks
	while game.tick_count < deadline:
		await process_frame
		if not healthy_session() or enemy().is_empty(): return false
		if Engine.get_process_frames() % 15 == 0: frame_encounter()
		if enemy().hp <= enemy_initial_hp - amount:
			observations.append({"event": "observed_damage", "tick": game.tick_count, "target": public_unit(enemy()), "scout": public_unit(scout())})
			return true
	return false

func wait_for_retreat(maximum_ticks: int):
	var deadline: int = game.tick_count + maximum_ticks
	while game.tick_count < deadline:
		await process_frame
		if not healthy_session(): return false
		if Engine.get_process_frames() % 15 == 0: frame_scout()
		if scout().pos.distance_to(retreat_start) >= 4.0 and scout().state == "move" and scout().target == -1: return true
	return false

func run():
	var args := OS.get_cmdline_user_args()
	if args.size() != 4:
		fail("Expected output directory, build ID, width and height."); return
	destination = args[0]; build = args[1]; width = int(args[2]); height = int(args[3])
	if Vector2i(width, height) != Vector2i(390, 844):
		fail("This encounter is reviewed for portrait only."); return
	root.size = Vector2i(width, height); root.content_scale_factor = 1.0
	game = load("res://main.tscn").instantiate(); root.add_child(game)
	if game.Rules.BUILD_ID != build:
		fail("Runtime build differs from the frozen source lock."); return
	await frames(12)
	for record in observed().values():
		if record.owned and record.kind == "scout" and record.alive:
			scout_id = record.id; break
	if not check("ordinary opening scout exists", scout_id >= 0 and scout().hp == 50 and not game.test_mode and game.ai_enabled): return
	frame_scout(); await frames(2)
	if not check("no enemy unit is initially visible", encounter().visible_enemy_units.is_empty()): return
	await capture("scout-before-expedition")
	if failed: return
	if not check("visible tutorial skip is available", game.tutorial_skip.is_visible_in_tree() and not game.demo_tutorial.skipped): return
	game.tutorial_skip.pressed.emit(); tutorial_was_skipped = true
	await frames(2)
	if not check("tutorial explicitly skipped not completed", game.demo_tutorial.skipped and not game.tutorial_panel.visible and game.demo_tutorial.step() < 6): return
	# Known map ground destination, not an unseen entity or hidden live coordinate.
	var destination_point := Vector3(22, 0, -22)
	game._submit("order", {"ids": [scout_id], "target": -1, "position": destination_point})
	commands.append({"kind": "scout_ground_move", "worker": scout_id, "target": -1, "position": [22, 0, -22], "tick": game.tick_count})
	var departure_tick: int = game.tick_count
	if not check("scout departs through normal movement", await travel_to_tick(departure_tick + 100) and scout().state == "move"): return
	await capture("scout-crossing-open-ground")
	if failed: return
	if not check("scout naturally reaches midfield", await travel_to_tick(departure_tick + 200) and scout().pos.distance_to(Vector3(-21, 0, 22)) > 20): return
	await capture("scout-revealing-midfield")
	if failed: return
	if not check("rival villager becomes currently visible", await find_visible_villager(600)): return
	frame_encounter(); await frames(2)
	var target = enemy()
	if not check("attack target is live public enemy", not target.is_empty() and target.team == 1 and target.kind == "villager" and not target.remembered and target.alive and target.hp > 12): return
	enemy_initial_hp = target.hp
	await capture("rival-revealed-before-attack")
	if failed: return
	target = enemy()
	var point: Vector2 = game.camera.unproject_position(target.pos + Vector3(0, 0.6, 0))
	if not check("visible target can be normally picked", game._box_point_in_world(point) and game._pick(point) == enemy_id): return
	game._start_unit_command(); game._tap(point, true)
	commands.append({"kind": "attack_visible_enemy", "scout": scout_id, "target": enemy_id, "tick": game.tick_count, "target_was_visible": not target.remembered, "target_hp_before": target.hp})
	await frames(3)
	if not check("normal attack command reaches authority", scout().state == "attack" and scout().target == enemy_id): return
	await capture("scout-ordered-to-attack")
	if failed: return
	for phase in [{"damage": 4, "label": "first-confirmed-hit"}, {"damage": 8, "label": "second-confirmed-hit"}, {"damage": 12, "label": "third-confirmed-hit"}]:
		if not check(phase.label, await wait_for_damage(phase.damage, 400), {"target": enemy_id, "hp_before": enemy_initial_hp}): return
		if not check(phase.label + " has public attack cue", scout().visual_attack_tick >= commands[1].tick and enemy().visual_hit_tick >= commands[1].tick and scout().state == "attack" and scout().target == enemy_id and game.economy.audit().ok): return
		frame_encounter(); await capture(phase.label)
		if failed: return
	retreat_start = scout().pos
	game._submit("order", {"ids": [scout_id], "target": -1, "position": Vector3(-8, 0, 8)})
	commands.append({"kind": "retreat_ground_move", "scout": scout_id, "target": -1, "position": [-8, 0, 8], "start": [retreat_start.x, retreat_start.y, retreat_start.z], "tick": game.tick_count})
	await frames(3)
	if not check("retreat replaces attack through normal queue", scout().state == "move" and scout().target == -1): return
	await capture("retreat-command-accepted")
	if failed: return
	if not check("living scout retreats four world units", await wait_for_retreat(160) and scout().hp > 0): return
	frame_scout(); await frames(2)
	await capture("scout-retreated-after-real-damage")
	if failed: return
	var report := {"passed": not failed, "scope": "native_software_rendered_source", "build": build,
		"frame_count": records.size(), "frames": records, "commands": commands, "observations": observations,
		"scenario": "scout_reveal_attack_damage_retreat", "checks": checks, "passed_checks": checks.size(), "failed_checks": 0,
		"scout": scout_id, "target": enemy_id, "enemy_hp_before": enemy_initial_hp, "tutorial": "Explicitly skipped with visible button; not completed",
		"simulation": "Unmodified game _process and ordinary commands; --fixed-fps 30; no test_mode, manual ticks, new units, HP edits or AI suppression",
		"not_verified": ["complete match", "victory", "target death", "Web", "physical touch", "iPhone", "performance", "visual quality acceptance"]}
	var file := FileAccess.open(destination.path_join("capture-report.json"), FileAccess.WRITE)
	if file == null:
		fail("Cannot write combat report."); return
	file.store_string(JSON.stringify(report, "  ")); file.close(); quit(0)

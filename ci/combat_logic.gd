extends SceneTree
## External headless simulated-gameplay logic fixture; no rendering evidence.
## Uses ordinary game _process and command routes. No direct simulation/state edits.
var game
var destination: String
var build: String
var records: Array = []
var commands: Array = []
var failed := false
var width: int = 390
var height: int = 844
var stop_reason := ""
var checks: Array = []
var scout_id := -1
var enemy_id := -1
var enemy_initial_hp := 0
var retreat_start: Vector3
var tutorial_was_skipped := false
var observations: Array = []
var latest_wait: Dictionary = {}

func _initialize():
	call_deferred("run")

func write_report(passed: bool):
	if destination.is_empty() or FileAccess.file_exists(destination): return false
	var passed_count := 0
	for item in checks:
		if item.pass: passed_count += 1
	var report := {"report_type": "vc-headless-combat-logic-v1", "passed": passed,
		"scope": "headless_simulated_gameplay_logic", "build": build,
		"checkpoint_count": records.size(), "checkpoints": records, "commands": commands,
		"observations": observations, "scenario": "scout_reveal_attack_damage_retreat",
		"checks": checks, "passed_checks": passed_count, "failed_checks": checks.size() - passed_count,
		"scout": scout_id, "target": enemy_id, "enemy_hp_before": enemy_initial_hp,
		"stop_reason": stop_reason, "latest_wait": latest_wait,
		"tutorial": "Tutorial skip handler used on logically visible button; not completed",
		"simulation": "Unmodified game _process and ordinary commands; --fixed-fps 30; no test_mode, manual ticks, new units, HP edits or AI suppression",
		"not_verified": ["rendering", "screenshots", "complete match", "victory", "target death", "Web", "physical touch", "iPhone", "realtime", "performance"]}
	var file := FileAccess.open(destination, FileAccess.WRITE)
	if file == null: return false
	file.store_string(JSON.stringify(report, "  ")); file.close()
	return true

func fail(message: String):
	failed = true
	stop_reason = message
	push_error(message)
	if not latest_wait.is_empty():
		push_error("COMBAT_WAIT " + JSON.stringify(latest_wait))
	write_report(false)
	quit(1)

func frames(count: int):
	for index in count:
		await process_frame

func observed():
	return game.faction_views[0].records()

func checkpoint(label: String):
	# One normal process frame; no rendering wait or direct simulation ticks.
	await process_frame
	if DisplayServer.get_name() != "headless" or not is_equal_approx(Engine.time_scale, 1.0):
		fail("Expected headless normal-time-scale logic run."); return
	var item := {"checkpoint_kind": "headless_public_state", "label": label,
		"monotonic_usec": Time.get_ticks_usec(), "process_frame": Engine.get_process_frames(),
		"build": game.Rules.BUILD_ID, "version": game.Rules.VERSION,
		"game_sha256": FileAccess.get_sha256("res://scripts/game.gd"),
		"rules_sha256": FileAccess.get_sha256("res://scripts/rules.gd"),
		"engine": Engine.get_version_info(), "display": DisplayServer.get_name(),
		"engine_time_scale": Engine.time_scale,
		"logical_viewport": [root.get_visible_rect().size.x, root.get_visible_rect().size.y],
		"game_tick": game.tick_count, "game_seconds": game.game_time,
		"economy_audit_ok": game.economy.audit().ok,
		"public_state": game._snapshot(), "encounter": encounter(), "tutorial_skipped": tutorial_was_skipped,
		"limitations": ["Headless simulated gameplay, not rendering or screenshot evidence", "Scripted UI-handler and command routes, not physical touch", "Fixed engine delta may run faster than wall time; not realtime or performance evidence"]}
	records.append(item)
	print("LOGIC_CHECKPOINT ", label, " tick=", game.tick_count)

func check(name: String, ok: bool, detail: Dictionary = {}):
	checks.append({"name": name, "pass": ok, "tick": game.tick_count, "detail": detail})
	print("COMBAT_CHECK ", JSON.stringify(checks.back()))
	if not ok: fail("Combat flow: " + name)
	return ok

func scout():
	return observed().get(scout_id, {})

func enemy():
	var record = observed().get(enemy_id, {})
	return {} if record.get("remembered", false) else record

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
	var started_tick: int = game.tick_count
	var deadline: int = started_tick + maximum_ticks
	var was_visible := true
	while game.tick_count < deadline:
		await process_frame
		var ours = scout(); var theirs = enemy()
		# Compact public-only fields fit the unchanged supervisor's 240-character line cap.
		latest_wait = {"reason": "waiting", "tick": game.tick_count, "end": deadline, "elapsed": game.tick_count - started_tick,
			"state": ours.get("state", "absent"), "target": ours.get("target", -1),
			"path": str(ours.get("path_status", "absent")).left(16), "points": ours.get("path", []).size(),
			"visible": not theirs.is_empty(), "own_hp": ours.get("hp", -1), "paused": game.paused, "over": game.game_over}
		if not theirs.is_empty(): latest_wait.hp = theirs.hp
		if not healthy_session():
			latest_wait.reason = "paused" if game.paused else ("game_over" if game.game_over else "scout_absent")
			return false
		# A moving visible target can leave sight. Keep the existing legitimate
		# last-known-position pursuit, without looking up or reordering hidden units.
		if not theirs.is_empty() and (not theirs.alive or theirs.hp <= 0):
			latest_wait.reason = "observed_target_death"
			return false
		if theirs.is_empty():
			if was_visible: observations.append({"event": "target_left_public_view", "tick": game.tick_count})
			was_visible = false
			if Engine.get_process_frames() % 15 == 0: frame_scout()
			continue
		if not was_visible:
			observations.append({"event": "target_reacquired", "tick": game.tick_count, "target": public_unit(theirs)})
		was_visible = true
		if Engine.get_process_frames() % 15 == 0: frame_encounter()
		if theirs.hp <= enemy_initial_hp - amount:
			latest_wait.reason = "damage_observed"
			observations.append({"event": "observed_damage", "tick": game.tick_count, "target": public_unit(theirs), "scout": public_unit(ours)})
			return true
	latest_wait.reason = "same_bounded_wait_expired"
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
	if args.size() != 2:
		fail("Expected output JSON path and build ID."); return
	destination = args[0]; build = args[1]
	if FileAccess.file_exists(destination):
		fail("Refusing to replace an existing report."); return
	if DisplayServer.get_name() != "headless" or not is_equal_approx(Engine.time_scale, 1.0):
		fail("Expected headless normal-time-scale logic run."); return
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
	await checkpoint("scout-before-expedition")
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
	await checkpoint("scout-crossing-open-ground")
	if failed: return
	if not check("scout naturally reaches midfield", await travel_to_tick(departure_tick + 200) and scout().pos.distance_to(Vector3(-21, 0, 22)) > 20): return
	await checkpoint("scout-revealing-midfield")
	if failed: return
	if not check("rival villager becomes currently visible", await find_visible_villager(600)): return
	frame_encounter(); await frames(2)
	var target = enemy()
	if not check("attack target is live public enemy", not target.is_empty() and target.team == 1 and target.kind == "villager" and not target.remembered and target.alive and target.hp > 12): return
	enemy_initial_hp = target.hp
	await checkpoint("rival-revealed-before-attack")
	if failed: return
	target = enemy()
	if target.is_empty() or not target.alive or target.remembered or target.team != 1:
		fail("Attack target no longer publicly available before UI command."); return
	var point: Vector2 = game.camera.unproject_position(target.pos + Vector3(0, 0.6, 0))
	if not check("visible target can be normally picked", game._box_point_in_world(point) and game._pick(point) == enemy_id): return
	game._start_unit_command(); game._tap(point, true)
	commands.append({"kind": "attack_visible_enemy", "scout": scout_id, "target": enemy_id, "tick": game.tick_count, "target_was_visible": not target.remembered, "target_hp_before": target.hp})
	await frames(3)
	if not check("normal attack command reaches authority", scout().state == "attack" and scout().target == enemy_id): return
	await checkpoint("scout-ordered-to-attack")
	if failed: return
	for phase in [{"damage": 4, "label": "first-confirmed-hit"}, {"damage": 8, "label": "second-confirmed-hit"}, {"damage": 12, "label": "third-confirmed-hit"}]:
		if not check(phase.label, await wait_for_damage(phase.damage, 400), {"target": enemy_id, "hp_before": enemy_initial_hp}): return
		if not check(phase.label + " has public attack cue", scout().visual_attack_tick >= commands[1].tick and enemy().visual_hit_tick >= commands[1].tick and scout().state == "attack" and scout().target == enemy_id and game.economy.audit().ok): return
		frame_encounter(); await checkpoint(phase.label)
		if failed: return
	retreat_start = scout().pos
	game._submit("order", {"ids": [scout_id], "target": -1, "position": Vector3(-8, 0, 8)})
	commands.append({"kind": "retreat_ground_move", "scout": scout_id, "target": -1, "position": [-8, 0, 8], "start": [retreat_start.x, retreat_start.y, retreat_start.z], "tick": game.tick_count})
	await frames(3)
	if not check("retreat replaces attack through normal queue", scout().state == "move" and scout().target == -1): return
	await checkpoint("retreat-command-accepted")
	if failed: return
	if not check("living scout retreats four world units", await wait_for_retreat(160) and scout().hp > 0): return
	frame_scout(); await frames(2)
	await checkpoint("scout-retreated-after-real-damage")
	if failed: return
	stop_reason = "scenario_completed"
	if not write_report(true):
		fail("Cannot write combat report."); return
	quit(0)

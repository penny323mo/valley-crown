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
		"interface_state": {"build_mode": game.build_mode, "touch_command": game.touch_command, "rally_building": game.rally_building, "menu_visible": game.compact_menu.visible, "paused": game.paused, "tutorial_visible": game.tutorial_panel.visible, "tutorial_text": game.tutorial_label.text},
		"limitations": ["Scripted UI-handler inspection; not physical touch validation","Native Linux software OpenGL, not Web/iPhone", "Command-level fixture, not touch-input acceptance", "Fixed engine delta, not performance evidence"]}
	records.append(item)
	var file := FileAccess.open(destination.path_join(filename + ".json"), FileAccess.WRITE)
	if file == null:
		fail("Cannot write framebuffer provenance.")
		return
	file.store_string(JSON.stringify(item, "  "))
	file.close()
	print("NATIVE_FRAME ", filename, " tick=", game.tick_count)

func wait_for_work(worker_id: int, target_id: int, maximum_ticks: int):
	var deadline: int = game.tick_count + maximum_ticks
	while game.tick_count < deadline:
		await process_frame
		var record = observed().get(worker_id, {})
		if record.is_empty() or game.game_over or game.paused:
			return false
		if record.state == "gather" and record.get("target", -1) == target_id and record.get("path", []).is_empty():
			return true
	return false

func run():
	var args := OS.get_cmdline_user_args()
	if args.size() != 4:
		fail("Expected output directory, build ID, width and height.")
		return
	destination = args[0]
	build = args[1]
	width = int(args[2]); height = int(args[3])
	if Vector2i(width, height) not in [Vector2i(390, 844), Vector2i(844, 390)]:
		fail("Capture size is outside the reviewed phone viewports.")
		return
	root.size = Vector2i(width, height)
	root.content_scale_factor = 1.0
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	if game.Rules.BUILD_ID != build:
		fail("Runtime build identity differs from the frozen source lock.")
		return
	await frames(12)
	await capture("opening")
	if failed: return
	var worker = choose_worker()
	if worker.is_empty():
		fail("No owned worker in the public faction view.")
		return
	var target = nearest_visible_resource(worker, ["pine", "oak"])
	if target.is_empty():
		fail("No currently visible wood target.")
		return
	game._select([worker.id])
	# Ordinary game command queue. No direct state edits or accelerated _tick calls.
	game._submit("order", {"ids": [worker.id], "target": target.id, "position": target.pos})
	commands.append({"kind": "order", "worker": worker.id, "target": target.id, "tick": game.tick_count})
	await frames(9)
	await capture("walk-to-wood")
	if not await wait_for_work(worker.id, target.id, 900):
		fail("Normal command did not reach wood gathering within the bounded scenario.")
		return
	# Scripted inspection through the game's existing user-action handlers.
	# No tutorial skip, resource grant, construction completion, or UI replacement.
	var town = {}
	for record in observed().values():
		if record.owned and record.kind == "town_center" and record.alive:
			town = record
			break
	if town.is_empty():
		fail("No owned town center for interface inspection.")
		return
	var labels = ["worker-commands", "target-command", "house-placement", "barracks-placement", "town-center-training", "rally-command", "game-menu", "paused-game"]
	for sample in 8:
		match sample:
			0: game._select([worker.id])
			1: game._start_unit_command()
			2: game._start_build("house")
			3: game._start_build("barracks")
			4: game._select([town.id])
			5: game._start_ground_rally(town.id)
			6:
				game._cancel_mode()
				game._toggle_compact_menu()
			7:
				game._toggle_compact_menu()
				game._toggle_pause()
		await frames(3)
		await capture(labels[sample])
		if failed: return
	var report := {"passed": not failed, "scope": "native_software_rendered_source",
		"build": build, "frame_count": records.size(), "frames": records, "commands": commands,
		"simulation": "Normal game _process and command queue; --fixed-fps 30",
		"interface_inspection": "Existing UI handlers; preview only, no construction/training completion or tutorial skip",
		"not_verified": ["Blender rig validity", "all action clips", "combat", "carry/deposit", "build/repair", "Web", "touch UX", "iPhone", "performance", "visual quality acceptance"]}
	var file := FileAccess.open(destination.path_join("capture-report.json"), FileAccess.WRITE)
	if file == null:
		fail("Cannot write capture report.")
		return
	file.store_string(JSON.stringify(report, "  ")); file.close()
	quit(0)

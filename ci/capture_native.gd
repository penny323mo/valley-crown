extends SceneTree
## External QA harness. PNG bytes come directly from the real root viewport.
## Actual house construction with normal simulation. No state grants or acceleration.
var game
var destination: String
var build: String
var records: Array = []
var commands: Array = []
var failed := false
var width: int
var height: int
var checks: Array = []
var worker_id := -1
var house_id := -1
var initial: Dictionary = {}

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
		"public_state": game._snapshot(), "own_buildings": own_buildings(),
		"interface_state": {"build_mode": game.build_mode, "touch_command": game.touch_command, "rally_building": game.rally_building, "menu_visible": game.compact_menu.visible, "paused": game.paused, "tutorial_visible": game.tutorial_panel.visible, "tutorial_text": game.tutorial_label.text},
		"limitations": ["Scripted UI-handler inspection; not physical touch validation","Native Linux software OpenGL, not Web/iPhone", "Existing UI handlers, not routed or physical touch acceptance", "Fixed engine delta, not performance evidence"]}
	records.append(item)
	var file := FileAccess.open(destination.path_join(filename + ".json"), FileAccess.WRITE)
	if file == null:
		fail("Cannot write framebuffer provenance.")
		return
	file.store_string(JSON.stringify(item, "  "))
	file.close()
	print("NATIVE_FRAME ", filename, " tick=", game.tick_count)

func own_buildings():
	var result: Array = []
	for record in observed().values():
		if record.owned and record.category == "building" and record.alive:
			result.append({"id": record.id, "kind": record.kind, "built": record.built,
				"progress": record.progress, "hp": record.hp, "max_hp": record.max_hp,
				"position": [record.pos.x, record.pos.y, record.pos.z]})
	return result

func house():
	for record in observed().values():
		if record.owned and record.kind == "house" and record.alive:
			return record
	return {}

func check(name: String, ok: bool, detail: Dictionary = {}):
	checks.append({"name": name, "pass": ok, "tick": game.tick_count, "detail": detail})
	print("GAMEPLAY_CHECK ", JSON.stringify(checks.back()))
	if not ok:
		fail("House flow: " + name)
	return ok

func wait_progress(fraction: float, maximum_ticks: int):
	var deadline: int = game.tick_count + maximum_ticks
	while game.tick_count < deadline:
		await process_frame
		var record = house()
		if game.game_over or game.paused or record.is_empty():
			return false
		if record.id != house_id:
			return false
		if record.progress >= fraction and (fraction < 1.0 or record.built):
			return true
	return false

func run():
	var args := OS.get_cmdline_user_args()
	if args.size() != 4:
		fail("Expected output directory, build ID, width and height.")
		return
	destination = args[0]; build = args[1]
	width = int(args[2]); height = int(args[3])
	if Vector2i(width, height) != Vector2i(390, 844):
		fail("This house scenario is reviewed for portrait only.")
		return
	root.size = Vector2i(width, height); root.content_scale_factor = 1.0
	game = load("res://main.tscn").instantiate(); root.add_child(game)
	if game.Rules.BUILD_ID != build:
		fail("Runtime build identity differs from the frozen source lock.")
		return
	await frames(12)
	initial = game._snapshot().duplicate(true)
	if not check("ordinary opening has no house", house().is_empty() and initial.wood == 200 and initial.capacity == 10 and initial.built == 0 and not game.test_mode): return
	await capture("opening-before-house")
	if failed: return
	var worker = choose_worker()
	if not check("owned live builder available", not worker.is_empty()): return
	worker_id = worker.id
	game._select([worker_id]); game._start_build("house")
	commands.append({"kind": "start_build_preview", "worker": worker_id, "tick": game.tick_count})
	await frames(3)
	if not check("preview makes no purchase", game.build_mode == "house" and not game.build_preview_held and game._snapshot().wood == initial.wood and house().is_empty()): return
	await capture("house-preview-unpaid")
	if failed: return
	game._cancel_mode(); await frames(3)
	commands.append({"kind": "cancel_preview", "tick": game.tick_count})
	if not check("cancel preview preserves resources and world", game.build_mode.is_empty() and game._snapshot().wood == initial.wood and house().is_empty() and game._snapshot().own_pending_commands == 0): return
	await capture("preview-cancelled-no-house")
	if failed: return
	game._start_build("house")
	# Choose an ordinary currently legal foreground plot; keep the original camera.
	var plot: Vector3 = Vector3.INF
	var nearest := INF
	for candidate in game.MapRoutes.build_plots(0, game.Rules.FOOTPRINT.house):
		var screen: Vector2 = game.camera.unproject_position(candidate)
		if not game._box_point_in_world(screen) or screen.x < 65 or screen.x > 325 or screen.y < 450 or screen.y > 640: continue
		if not game._placement_reason("house", candidate, 0, worker_id).is_empty(): continue
		var distance: float = screen.distance_squared_to(Vector2(195, 550))
		if distance < nearest:
			nearest = distance; plot = candidate
	if not check("foreground house plot available", plot != Vector3.INF): return
	var point: Vector2 = game.camera.unproject_position(plot)
	if not check("offered plot is legal and visible", game._placement_reason("house", plot, 0, worker_id).is_empty() and game._box_point_in_world(point), {"plot": [plot.x, plot.y, plot.z]}): return
	game._tap(point, true); await frames(3)
	if not check("plot selection still requires confirmation", game.build_mode == "house" and game.build_preview_held and game.placement_ok and not game.build_confirm.disabled and house().is_empty() and game._snapshot().wood == initial.wood): return
	await capture("legal-house-plot-selected")
	if failed: return
	game._confirm_build()
	commands.append({"kind": "confirm_house", "worker": worker_id, "position": [plot.x, plot.y, plot.z], "tick": game.tick_count})
	if not check("confirm queues exactly one build", game._snapshot().own_pending_commands == 1 and game._snapshot().wood == initial.wood and game.build_mode.is_empty()): return
	await frames(4)
	var site = house()
	if not check("authority creates paid unfinished house", not site.is_empty() and not site.built and game._snapshot().wood == initial.wood - 50 and game._snapshot().capacity == initial.capacity and game.economy.audit().ok): return
	house_id = site.id
	await capture("paid-house-foundation")
	if failed: return
	for phase in [{"fraction": 0.1, "label": "house-construction-started"}, {"fraction": 0.5, "label": "house-construction-halfway"}, {"fraction": 0.9, "label": "house-construction-nearly-ready"}]:
		if not check(phase.label, await wait_progress(phase.fraction, 600), {"house": house_id}): return
		var builder = observed().get(worker_id, {})
		if not check(phase.label + " uses live builder", not builder.is_empty() and builder.state == "build" and builder.target == house_id and not house().built and game._snapshot().wood == initial.wood - 50 and game.economy.audit().ok): return
		await capture(phase.label)
		if failed: return
	if not check("normal builder completes same house", await wait_progress(1.0, 600), {"house": house_id}): return
	if not check("completion raises capacity without another charge", house().id == house_id and house().built and house().progress == 1.0 and game._snapshot().capacity == initial.capacity + 5 and game._snapshot().wood == initial.wood - 50 and game._snapshot().built == initial.built + 1 and game.economy.audit().ok): return
	await capture("completed-house-capacity-fifteen")
	if failed: return
	game._select([house_id]); await frames(6)
	if not check("completed house remains selected and paid once", house().built and game.selected == [house_id] and game._snapshot().wood == initial.wood - 50 and game._snapshot().capacity == 15 and game._snapshot().own_pending_commands == 0 and game.economy.audit().ok): return
	await capture("completed-house-selected")
	if failed: return
	var report := {"passed": not failed, "scope": "native_software_rendered_source",
		"build": build, "frame_count": records.size(), "frames": records, "commands": commands,
		"scenario": "house_preview_cancel_confirm_complete", "checks": checks,
		"passed_checks": checks.size(), "failed_checks": 0, "worker": worker_id, "house": house_id,
		"simulation": "Unmodified game _process and ordinary command queue; --fixed-fps 30; no test_mode or manual ticks",
		"interface_inspection": "Existing UI handlers for selection, preview, cancellation and confirmation; actual paid construction completion",
		"not_verified": ["unit training", "combat", "gather/deposit", "Web", "touch UX", "iPhone", "performance", "visual quality acceptance"]}
	var file := FileAccess.open(destination.path_join("capture-report.json"), FileAccess.WRITE)
	if file == null:
		fail("Cannot write gameplay report.")
		return
	file.store_string(JSON.stringify(report, "  ")); file.close()
	quit(0)

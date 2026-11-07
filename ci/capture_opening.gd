extends SceneTree
## External QA harness. PNG bytes come directly from the real root viewport.
## No UI overlays, image synthesis, resource grants, teleportation or hidden-state reads.
var game
var destination: String
var build: String
var records: Array = []
const SCENARIO := "native_original_ground_opening_v1"
const FIXED_FPS := 20
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

func pose_evidence():
	# Controllers may be RefCounted, not scene nodes. The game's explicit
	# observational API filters actual rigs through is_visible_in_tree().
	if game.has_method("visual_evidence_snapshot"):
		return [{"node": ".", "snapshot": game.visual_evidence_snapshot()}]
	return []  # The accepted baseline has no skeletal controller hook.

func capture(label: String):
	await RenderingServer.frame_post_draw
	if not running() or not is_equal_approx(game.get_process_delta_time(),0.05) or DisplayServer.get_name() != "X11":
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
		"scenario":SCENARIO,"fixed_fps":FIXED_FPS,"observed_process_delta_seconds":game.get_process_delta_time(),
		"snapshot":game._snapshot(),"test_mode":game.test_mode,"ai_enabled":game.ai_enabled,"game_frame_counter":game.frame_counter,
		"ground_sha256":FileAccess.get_sha256("res://assets/mature/terrain/ground.gdshader"),
		"visible_draw_calls":root.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME),
		"visible_primitives":root.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME),
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
		"limitations": ["Native Linux software OpenGL, not Web/iPhone", "Normal opening only; no input, commands or camera changes", "Fixed engine delta, not performance evidence"]}
	records.append(item)
	var file := FileAccess.open(destination.path_join(filename + ".json"), FileAccess.WRITE)
	if file == null:
		fail("Cannot write framebuffer provenance.")
		return
	file.store_string(JSON.stringify(item, "  "))
	file.close()
	print("NATIVE_FRAME ", filename, " tick=", game.tick_count)

func running() -> bool:
	return not game.test_mode and game.ai_enabled and not game.paused and not game.game_over and game.application_focused and not game.application_suspended

func run():
	var args := OS.get_cmdline_user_args()
	if args.size()!=4:
		fail("Expected output directory, build ID, width and height."); return
	destination=args[0];build=args[1];width=int(args[2]);height=int(args[3])
	if build not in ["vc-43276605e0fb","vc-8bf358474c6a"] or Vector2i(width,height) not in [Vector2i(390,844),Vector2i(844,390)]:
		fail("Wrong frozen opening identity or dimensions.");return
	root.size=Vector2i(width,height);root.content_scale_factor=1.0
	game=load("res://main.tscn").instantiate();root.add_child(game)
	if game.Rules.BUILD_ID!=build:
		fail("Runtime build identity differs from frozen source.");return
	await frames(12)
	for index in 10:
		if index>0:await frames(1)
		await capture("opening-%02d" % index)
		if failed:return
	var report := {"passed":true,"scope":"native_software_rendered_source","build":build,"scenario":SCENARIO,
		"fixed_fps":FIXED_FPS,"frame_count":records.size(),"frames":records,"commands":[],"input_events":[],
		"simulation":"Fresh normal seeded game, unchanged AI/process; ten consecutive opening samples at fixed20",
		"not_verified":["touch UX","camera motion","later gameplay","Web/Safari","physical iPhone","performance","visual quality acceptance"]}
	var file := FileAccess.open(destination.path_join("capture-report.json"),FileAccess.WRITE)
	if file==null:
		fail("Cannot save opening report.");return
	file.store_string(JSON.stringify(report,"  ")+"\n");file.close();quit(0)

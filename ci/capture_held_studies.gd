extends SceneTree
## Genuine native framebuffer of three paused skeletal samples, NOT gameplay.
## Hosted Compatibility renderer only; no local Blender/Godot execution.
const Controller = preload("res://scripts/action_character.gd")
const Rules = preload("res://scripts/rules.gd")
const CAPTURE_KIND := "native_controlled_held_spear_study"
const VALIDATED_NATIVE_SHA256 := "12bb1dad426360ad7cbbe9b782b221bccd9cb66f21577f754696996ed1611f96"
var output: String
var world: Node3D
var caption: Label
var samples_label: Label
var studies: Array = []
var checks: Array = []

func _initialize():
	if configure_evidence(Vector2i(844,390)): call_deferred("run")

func check(label: String, ok: bool) -> void:
	checks.append({"name":label,"pass":ok})
	if not ok: push_error(label)

func run() -> void:
	assert(Rules.BUILD_ID == "vc-e2002b3a168a", "Exact accepted base required")
	if FileAccess.get_sha256("res://assets/mature/models/spearman_action.scn") != VALIDATED_NATIVE_SHA256:
		push_error("Validated held-only native output required"); quit(1); return
	DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(844,390)
	world = Node3D.new(); root.add_child(world)
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color("454b42")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("b6bec5")
	settings.ambient_light_energy = .36
	environment.environment = settings; world.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48,-32,0)
	sun.light_color = Color("ffedce"); sun.light_energy = .95
	sun.shadow_enabled = true; world.add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new(); plane.size = Vector2(20,12)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("68705a"); material.roughness = 1.0
	ground.mesh = plane; ground.material_override = material; world.add_child(ground)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL; camera.size = 4.2
	camera.position = Vector3(0,2.7,6); world.add_child(camera)
	camera.look_at(Vector3(0,.7,0)); camera.current = true
	var canvas := CanvasLayer.new(); root.add_child(canvas)
	caption = Label.new(); caption.position = Vector2(12,8)
	caption.add_theme_font_size_override("font_size",18); canvas.add_child(caption)
	samples_label = Label.new(); samples_label.position = Vector2(12,362)
	samples_label.add_theme_font_size_override("font_size",15); canvas.add_child(samples_label)
	for clip in ["idle","walk","attack","hit"]:
		await capture_study("spearman", clip)
	check("exactly four held spear clips captured", studies.size() == 4)
	var failed := checks.filter(func(c): return not c.pass).size()
	var report := {"scope":"Untouched native framebuffer, controlled three-pose rig fixture. Not gameplay, browser, phone performance or artistic acceptance.",
		"passed":failed==0,"frame_count":evidence_frames.size(),"frames":evidence_frames,"mode":"held_spear_studies",
		"build":Rules.BUILD_ID,"renderer":RenderingServer.get_current_rendering_method(),
		"checks":checks,"failed":failed,"studies":studies,
		"validated_native_sha256":VALIDATED_NATIVE_SHA256,
		"known_issue":"Death remains unchanged and excluded; finite rig samples are not gameplay or continuous clearance acceptance."}
	var file := FileAccess.open(output+"/capture-report.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  ")+"\n"); file.close()
	print("ACTION_RENDER_FIXTURE ",studies.size()," failed=",failed)
	world.free(); canvas.free(); quit(1 if failed else 0)

func capture_study(kind: String, clip: String) -> void:
	var bodies: Array[Node3D] = []
	var controllers: Array = []
	# Hammering has two repeated cycles; .5 aliases the start pose. Use .35 for
	# ordinary motion studies and .5 for the death collapse/contact progression.
	var middle: float = Controller.IMPACT_FRACTION[kind] if clip=="attack" else .35
	var fractions := [0.0,middle,1.0]
	var evidence: Array = []
	var requested_times: Array = []
	var actual_positions: Array = []
	var assigned_clips: Array = []
	var paused_states: Array = []
	var clip_length_seconds: float = 0.0
	for index in 3:
		var body := Node3D.new(); world.add_child(body)
		body.position = Vector3((index-1)*2.4,0,0); bodies.append(body)
		var controller = Controller.new()
		var bound: bool = controller.bind(body,kind,Color("435d6c"))
		check(kind+" "+clip+" sample "+str(index)+" bound reviewed native rig",bound)
		if not bound:
			for other in controllers: other.release()
			for other in bodies: other.free()
			return
		controllers.append(controller)
		controller.occlusion.set_authorized(false)
		var length: float = controller.player.get_animation(clip).length
		clip_length_seconds = length
		var nominal: float = length * fractions[index]
		var requested: float = minf(nominal, length - 0.000001) if controller.player.get_animation(clip).loop_mode != Animation.LOOP_NONE else nominal
		controller._start(clip,requested,false,false)
		requested_times.append(requested)
		evidence.append(controller.visual_evidence_snapshot())
	caption.text = "HELD SPEAR "+clip+" | "+Rules.BUILD_ID+" | SCN"+VALIDATED_NATIVE_SHA256.substr(0,12)+" | NOT GAMEPLAY"
	samples_label.text = "0%%: %.3fs | %d%%: %.3fs | 100%%: %.3fs%s | paused native poses" % [float(requested_times[0]), roundi(middle*100), float(requested_times[1]), float(requested_times[2]), " (clamped)" if clip in ["idle","walk"] else ""]
	await process_frame; await process_frame; await RenderingServer.frame_post_draw
	for index in 3:
		var player: AnimationPlayer = controllers[index].player
		actual_positions.append(player.current_animation_position)
		assigned_clips.append(str(player.assigned_animation))
		paused_states.append(not player.is_playing())
		check(kind+" "+clip+" sample "+str(index)+" exact paused native seek", str(player.assigned_animation)==clip and player.current_animation.is_empty() and not player.is_playing() and absf(player.current_animation_position-float(requested_times[index]))<=0.0000001)
	var frame: Dictionary = await evidence_frame(kind+"-"+clip,evidence,{"kind":kind,"clip":clip,"fractions":fractions,"clip_length_seconds":clip_length_seconds,"requested_times":requested_times,"actual_positions":actual_positions,"assigned_clips":assigned_clips,"paused_states":paused_states,"loop_endpoint_policy":"nominal100% clamped length-1e-6 for idle/walk","caption_text":caption.text,"samples_text":samples_label.text,"unit_state":"controlled_paused_clip_samples"})
	check(kind+" "+clip+" framebuffer saved",not frame.is_empty())
	check(kind+" "+clip+" bone poses change",evidence[0].pose_sha256!=evidence[1].pose_sha256 or evidence[1].pose_sha256!=evidence[2].pose_sha256)
	studies.append({"kind":kind,"clip":clip,"fractions":fractions,"png":frame.get("image",""),
		"png_sha256":frame.get("image_sha256",""),"size":[844,390],"poses":evidence,"caption_text":caption.text,"samples_text":samples_label.text,"requested_times":requested_times,"actual_positions":actual_positions,"assigned_clips":assigned_clips,"paused_states":paused_states})
	for controller in controllers: controller.release()
	for body in bodies: body.free()


# External evidence writer: untouched framebuffer, no source-tree writes.
var evidence_frames: Array = []
var expected_build: String
var evidence_size: Vector2i
func configure_evidence(required_size: Vector2i) -> bool:
	var args := OS.get_cmdline_user_args()
	if args.size() != 4:
		push_error("Expected output/build/width/height"); quit(1); return false
	output = args[0]; expected_build = args[1]
	evidence_size = Vector2i(int(args[2]),int(args[3]))
	if evidence_size != required_size or expected_build != "vc-e2002b3a168a" or load("res://scripts/rules.gd").BUILD_ID != expected_build:
		push_error("Wrong fixture identity or phone viewport"); quit(1); return false
	root.size = evidence_size; root.content_scale_factor = 1.0
	return true
func evidence_frame(label: String, poses: Array, details: Dictionary = {}) -> Dictionary:
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	if DisplayServer.get_name() != "X11" or image == null or image.is_empty() or image.get_size() != evidence_size:
		push_error("Invalid real framebuffer"); quit(1); return {}
	var filename := "%03d-%s.png" % [evidence_frames.size(),label]
	var path: String = output.path_join(filename)
	if image.save_png(path) != OK:
		push_error("Cannot save raw framebuffer"); quit(1); return {}
	var frame := {"image":filename,"image_sha256":FileAccess.get_sha256(path),"label":label,
		"capture_kind":CAPTURE_KIND,"build":expected_build,
		"utc":Time.get_datetime_string_from_system(true,true),"unix_time":Time.get_unix_time_from_system(),
		"monotonic_usec":Time.get_ticks_usec(),"process_frame":Engine.get_process_frames(),
		"engine":Engine.get_version_info(),"display":DisplayServer.get_name(),
		"rendering_method":RenderingServer.get_current_rendering_method(),
		"rendering_driver":RenderingServer.get_current_rendering_driver_name(),
		"adapter_name":RenderingServer.get_video_adapter_name(),"adapter_vendor":RenderingServer.get_video_adapter_vendor(),
		"framebuffer":[image.get_width(),image.get_height()],"game_tick":null,"game_seconds":null,
		"game_sha256":FileAccess.get_sha256("res://scripts/game.gd"),"rules_sha256":FileAccess.get_sha256("res://scripts/rules.gd"),
		"animation_poses":poses,"limitations":["Controlled rig fixture, not gameplay", "Native software renderer, not Web/iPhone/performance", "Held spear only; death and other props excluded"]}
	frame.merge(details,false); evidence_frames.append(frame)
	var sidecar := FileAccess.open(path+".json",FileAccess.WRITE)
	if sidecar == null:
		push_error("Cannot save sidecar"); quit(1); return {}
	sidecar.store_string(JSON.stringify(frame,"  ")+"\n"); sidecar.close()
	print("NATIVE_FRAME ", filename)
	return frame

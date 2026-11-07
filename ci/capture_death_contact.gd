extends SceneTree
## Controlled paused samples of accepted native death equipment. NOT gameplay.
const Controller = preload("res://scripts/action_character.gd")
const Rules = preload("res://scripts/rules.gd")
const CAPTURE_KIND := "native_controlled_death_contact"
const SCENARIO := "native_death_contact_milestones_v1"
const EXPECTED_BUILD := "vc-470d98d0c3ee"
const ORIGINAL_FIXTURE_SHA256 := "c3bbcbf740babe5d60d5d3565e01ddf856b7403071d5ba64c2e9f36595576040"
const STUDIES := [{"kind":"spearman","label":"spearman-held-release-terminal","seconds":[0.25,0.333333333333333,1.5],"sample_labels":["held","release","terminal"],"props":["prop_spear","prop_shield"]},{"kind":"spearman","label":"spearman-contacts-shield-settle","seconds":[0.687274043031757,0.85986199877582,0.927274043031756],"sample_labels":["shield contact","spear contact","shield settle"],"props":["prop_spear","prop_shield"]},{"kind":"spearman","label":"spearman-settle-terminal","seconds":[1.09986199877582,1.5,1.5],"sample_labels":["spear settle","terminal","terminal reference"],"props":["prop_spear","prop_shield"]},{"kind":"archer","label":"archer-held-release-contact","seconds":[0.25,0.333333333333333,0.675266394176888],"sample_labels":["held","release","bow contact"],"props":["prop_bow"]},{"kind":"archer","label":"archer-settle-terminal","seconds":[0.915266394176888,1.5,1.5],"sample_labels":["bow settle","terminal","terminal reference"],"props":["prop_bow"]},{"kind":"scout","label":"scout-held-release-contact","seconds":[0.25,0.333333333333333,0.760425288309763],"sample_labels":["held","release","sword contact"],"props":["prop_sword"]},{"kind":"scout","label":"scout-settle-terminal","seconds":[1.00042528830976,1.5,1.5],"sample_labels":["sword settle","terminal","terminal reference"],"props":["prop_sword"]}]
var output: String
var expected_build: String
var evidence_size: Vector2i
var world: Node3D
var camera: Camera3D
var caption: Label
var samples_label: Label
var evidence_frames: Array = []
var checks: Array = []

func _initialize():
	if configure_evidence(Vector2i(844,390)): call_deferred("run")

func fail(message: String) -> void:
	push_error(message); quit(1)

func run() -> void:
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
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL; camera.size = 4.2
	camera.position = Vector3(0,2.7,6); world.add_child(camera)
	camera.look_at(Vector3(0,.7,0)); camera.current = true
	var canvas := CanvasLayer.new(); root.add_child(canvas)
	caption = Label.new(); caption.position = Vector2(12,8)
	caption.add_theme_font_size_override("font_size",18); canvas.add_child(caption)
	samples_label = Label.new(); samples_label.position = Vector2(12,362)
	samples_label.add_theme_font_size_override("font_size",15); canvas.add_child(samples_label)
	for study in STUDIES:
		var captured: bool = await capture_study(study)
		if not captured: return
	var report := {"passed":true,"frame_count":evidence_frames.size(),"frames":evidence_frames,
		"mode":"death_contact","scenario":SCENARIO,"fixed_fps":20,"build":Rules.BUILD_ID,
		"checks":checks,"failed":0,"distinct_class_time_samples":17,
		"scope":"Untouched controlled native triptychs. Existing camera/floor only. Not gameplay or artistic approval.",
		"not_verified":["release velocity continuity or smoothness","continuous or swept clearance","physical stability","side/rear visibility","normal gameplay death","Web/iPhone/performance"]}
	var file := FileAccess.open(output.path_join("capture-report.json"),FileAccess.WRITE)
	if file==null:fail("Cannot save final capture report");return
	file.store_string(JSON.stringify(report,"  ")+"\n");file.close()
	world.free();canvas.free();quit(0)

func capture_study(study: Dictionary) -> bool:
	var kind: String = study.kind
	var bodies: Array[Node3D] = []
	var controllers: Array = []
	var evidence: Array = []
	var paused: Array = []
	var positions: Array = []
	for index in 3:
		var body := Node3D.new();world.add_child(body)
		body.position = Vector3((index-1)*2.4,0,0);bodies.append(body)
		var controller = Controller.new()
		if not controller.bind(body,kind,Color("435d6c")):
			fail("Unable to bind reviewed death rig");return false
		controllers.append(controller)
		controller.occlusion.set_authorized(false)
		var length: float = controller.player.get_animation("death").length
		if not is_equal_approx(length,1.5):fail("Death clip length differs");return false
		for prop: String in study.props:
			if controller.skeleton.find_bone(prop)<0:fail("Required equipment bone absent");return false
		controller._start("death",float(study.seconds[index]),false,false)
	caption.text = "CONTROLLED DEATH STUDY, NOT GAMEPLAY | "+kind
	var labels := PackedStringArray()
	for index in 3:
		labels.append("%s %.3fs" % [study.sample_labels[index],study.seconds[index]])
	samples_label.text = "   |   ".join(labels)
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	for index in 3:
		var controller = controllers[index]
		evidence.append(controller.visual_evidence_snapshot())
		paused.append(not controller.player.is_playing())
		positions.append([bodies[index].position.x,bodies[index].position.y,bodies[index].position.z])
	var forward: Vector3 = -camera.global_basis.z
	var details := {"scenario":SCENARIO,"fixed_fps":20,"kind":kind,"clip":"death","clip_length_seconds":1.5,
		"sample_seconds":study.seconds,"sample_labels":study.sample_labels,"props":study.props,
		"sample_players_paused":paused,"body_positions":positions,"unit_state":"controlled_paused_death_milestones",
		"original_fixture_sha256":ORIGINAL_FIXTURE_SHA256,
		"camera":{"projection":camera.projection,"size":camera.size,
			"position":[camera.position.x,camera.position.y,camera.position.z],"forward":[forward.x,forward.y,forward.z]},
		"floor":{"y":0,"size":[20,12]}}
	var frame: Dictionary = await evidence_frame(study.label,evidence,details)
	if frame.is_empty():return false
	checks.append({"name":study.label+" framebuffer saved","pass":true})
	for controller in controllers:controller.release()
	for body in bodies:body.free()
	return true

func configure_evidence(required_size: Vector2i) -> bool:
	var args := OS.get_cmdline_user_args()
	if args.size() != 4:
		push_error("Expected output/build/width/height"); quit(1); return false
	output = args[0]; expected_build = args[1]
	evidence_size = Vector2i(int(args[2]),int(args[3]))
	if evidence_size != required_size or expected_build != EXPECTED_BUILD or load("res://scripts/rules.gd").BUILD_ID != expected_build:
		push_error("Wrong fixture identity or phone viewport"); quit(1); return false
	root.size = evidence_size; root.content_scale_factor = 1.0
	return true
func evidence_frame(label: String, poses: Array, details: Dictionary = {}) -> Dictionary:
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	if DisplayServer.get_name() != "X11" or image == null or image.is_empty() or image.get_size() != evidence_size:
		push_error("Invalid real framebuffer"); quit(1); return {}
	var filename := "%03d-%s.png" % [evidence_frames.size(),label.replace("_","-")]
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
		"animation_poses":poses,"limitations":["Controlled rig fixture, not gameplay", "Native software renderer, not Web/iPhone/performance", "Paused finite milestones; no continuous-motion or stability acceptance"]}
	frame.merge(details,false); evidence_frames.append(frame)
	var sidecar := FileAccess.open(path+".json",FileAccess.WRITE)
	if sidecar == null:
		push_error("Cannot save sidecar"); quit(1); return {}
	sidecar.store_string(JSON.stringify(frame,"  ")+"\n"); sidecar.close()
	print("NATIVE_FRAME ", filename)
	return frame

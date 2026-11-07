extends SceneTree
## Real rendered isolated rig fixture, not a gameplay screenshot or phone claim.
## Run only in the reviewed hosted native renderer with Xvfb/Mesa Compatibility.
const Controller = preload("res://scripts/action_character.gd")
var world: Node3D
var controller
var camera: Camera3D
var occluder: MeshInstance3D
var checks: Array=[]
const CAPTURE_KIND := "native_controlled_occlusion_fixture"
var output: String
var capture_failures: int = 0
func _initialize():
	if configure_evidence(Vector2i(390,844)): call_deferred("run")
func require_check(label: String, pass_value: bool, detail={}) -> void:
	checks.append({"name":label,"pass":pass_value,"detail":detail})
	if not pass_value: print("FIXTURE_FINDING ",label," ",str(detail))
func capture(label: String) -> Image:
	await process_frame; await process_frame; await RenderingServer.frame_post_draw
	var poses: Array = []
	var rig_visible: bool = controller != null and is_instance_valid(controller.rig) and controller.rig.is_visible_in_tree()
	if rig_visible: poses.append(controller.visual_evidence_snapshot())
	var frame: Dictionary = await evidence_frame(label,poses,{"unit_state":"controlled_depth_comparison","rig_visible_in_tree":rig_visible})
	if frame.is_empty(): capture_failures += 1
	require_check(label+" framebuffer saved",not frame.is_empty())
	return root.get_texture().get_image()
func difference(a: Image,b: Image) -> int:
	assert(a.get_size()==b.get_size())
	var count:=0
	for y in a.get_height():
		for x in a.get_width():
			var p:=a.get_pixel(x,y);var q:=b.get_pixel(x,y)
			if absf(p.r-q.r)+absf(p.g-q.g)+absf(p.b-q.b)>.05: count+=1
	return count
func run() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	root.size=Vector2i(390,844)
	world=Node3D.new();root.add_child(world)
	var environment:=WorldEnvironment.new();var settings:=Environment.new()
	settings.background_mode=Environment.BG_COLOR;settings.background_color=Color("373d36")
	settings.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;settings.ambient_light_energy=.7
	environment.environment=settings;world.add_child(environment)
	var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-45,-20,0);world.add_child(light)
	camera=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=2.9
	camera.position=Vector3(2,2.2,4);world.add_child(camera);camera.look_at(Vector3(0,.9,0));camera.current=true
	var body:=Node3D.new();world.add_child(body)
	controller=Controller.new()
	var bound: bool = controller.bind(body,"spearman",Color("435d6c"))
	require_check("fixture bound real exported rig",bound)
	if not bound:
		push_error("Cannot bind reviewed rig"); quit(1); return
	controller._start("idle",.5,false,false)
	controller.occlusion.set_authorized(false);var normal_off:Image=await capture("01-normal-overlay-off")
	controller.occlusion.set_authorized(true);var normal_on:Image=await capture("02-normal-overlay-on")
	require_check("normal visible mesh unchanged",difference(normal_off,normal_on)==0,{"changed_pixels":difference(normal_off,normal_on)})
	occluder=MeshInstance3D.new();var box:=BoxMesh.new();box.size=Vector3(.9,1.5,.35);occluder.mesh=box
	var mat:=StandardMaterial3D.new();mat.albedo_color=Color("665a46");mat.roughness=1;occluder.material_override=mat
	world.add_child(occluder);occluder.position=Vector3(.35,.78,.8)
	controller.occlusion.set_authorized(false);var hidden_off:Image=await capture("03-object-occluded-overlay-off")
	controller.occlusion.set_authorized(true);var hidden_on:Image=await capture("04-object-occluded-overlay-on")
	require_check("occluded authorized unit receives silhouette",difference(hidden_off,hidden_on)>30,{"changed_pixels":difference(hidden_off,hidden_on)})
	body.hide();var fog_hidden:Image=await capture("05-fog-hidden-parent")
	controller.release();var absent:Image=await capture("06-no-unit-reference")
	require_check("hidden ancestor silhouette is absent",difference(fog_hidden,absent)==0,{"changed_pixels":difference(fog_hidden,absent)})
	var failed=checks.filter(func(c):return not c.pass).size()
	var file:=FileAccess.open(output+"/capture-report.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"passed":capture_failures==0 and evidence_frames.size()==6,"frame_count":evidence_frames.size(),"frames":evidence_frames,"mode":"occlusion","functional_checks_passed":failed==0,"scope":"Real native controlled rig/depth fixture, not gameplay or phone acceptance","build":load("res://scripts/rules.gd").BUILD_ID,"checks":checks,"failed":failed,"renderer":RenderingServer.get_current_rendering_method()},"  ")+"\n");file.close()
	world.free();quit(1 if capture_failures>0 or evidence_frames.size()!=6 else 0)


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
	if evidence_size != required_size or expected_build != "vc-6f4dddc33ec2" or load("res://scripts/rules.gd").BUILD_ID != expected_build:
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
		"animation_poses":poses,"limitations":["Controlled rig fixture, not gameplay", "Native software renderer, not Web/iPhone/performance", "Contact markers provisional; visible defects are not corrected"]}
	frame.merge(details,false); evidence_frames.append(frame)
	var sidecar := FileAccess.open(path+".json",FileAccess.WRITE)
	if sidecar == null:
		push_error("Cannot save sidecar"); quit(1); return {}
	sidecar.store_string(JSON.stringify(frame,"  ")+"\n"); sidecar.close()
	print("NATIVE_FRAME ", filename)
	return frame

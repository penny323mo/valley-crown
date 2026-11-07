extends "res://tests/occlusion_render_fixture.gd"
## Thin hosted adapter of the reviewed pixel fixture. Capture admission and
## functional acceptance stay separate; the subsequent strict pixel gate must pass.
const CAPTURE_KIND := "native_controlled_occlusion_fixture"
const EXPECTED_BUILD := "vc-c7211e1083c8"
const EVIDENCE_SIZE := Vector2i(390,844)
func _initialize():
	var args:=OS.get_cmdline_user_args()
	if args.size()!=4 or args[1]!=EXPECTED_BUILD or Vector2i(int(args[2]),int(args[3]))!=EVIDENCE_SIZE or load("res://scripts/rules.gd").BUILD_ID!=EXPECTED_BUILD:
		push_error("Expected exact output/build/width/height"); quit(1); return
	output=args[0]
	if not output.is_absolute_path() or output.begins_with("res://") or output.begins_with("user://"):
		push_error("Evidence output must be external absolute path"); quit(1); return
	call_deferred("run")
func require_check(label: String, pass_value: bool, detail={}) -> void:
	checks.append({"name":label,"pass":pass_value,"detail":detail})
	if not pass_value: print("FIXTURE_FINDING ",label," ",str(detail))
func setup() -> void:
	super.setup()
	root.size=EVIDENCE_SIZE; root.content_scale_factor=1.0
func capture(label: String) -> Image:
	await process_frame; await process_frame; await RenderingServer.frame_post_draw
	var image: Image=root.get_texture().get_image()
	var filename: String="%03d-%s.png" % [frames.size(),label]
	var path: String=output.path_join(filename)
	var error:=image.save_png(path)
	require_check(label+" framebuffer saved",error==OK)
	frames.append({"file":filename,"sha256":FileAccess.get_sha256(path),"width":image.get_width(),"height":image.get_height(),
		"visible_draw_calls":root.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME),
		"visible_primitives":root.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME)})
	require_check(label+" real framebuffer",DisplayServer.get_name()=="X11" and image!=null and not image.is_empty() and image.get_size()==EVIDENCE_SIZE)
	var poses: Array=[]
	var rig_visible: bool=controller!=null and is_instance_valid(controller.rig) and controller.rig.is_visible_in_tree()
	if rig_visible: poses.append(controller.visual_evidence_snapshot())
	var frame: Dictionary=frames[-1]
	frame.merge({"image":frame.file,"image_sha256":frame.sha256,"label":label,
		"capture_kind":CAPTURE_KIND,"build":EXPECTED_BUILD,
		"utc":Time.get_datetime_string_from_system(true,true),"unix_time":Time.get_unix_time_from_system(),
		"monotonic_usec":Time.get_ticks_usec(),"process_frame":Engine.get_process_frames(),
		"engine":Engine.get_version_info(),"display":DisplayServer.get_name(),
		"rendering_method":RenderingServer.get_current_rendering_method(),
		"rendering_driver":RenderingServer.get_current_rendering_driver_name(),
		"adapter_name":RenderingServer.get_video_adapter_name(),"adapter_vendor":RenderingServer.get_video_adapter_vendor(),
		"framebuffer":[image.get_width(),image.get_height()],"game_tick":null,"game_seconds":null,
		"game_sha256":FileAccess.get_sha256("res://scripts/game.gd"),"rules_sha256":FileAccess.get_sha256("res://scripts/rules.gd"),
		"animation_poses":poses,"rig_visible_in_tree":rig_visible,"unit_state":"controlled_depth_comparison",
		"limitations":["Controlled rig fixture, not gameplay", "Native software renderer, not Web/iPhone/performance", "Accepted 6f4 material defects remain unchanged"]})
	var sidecar:=FileAccess.open(output.path_join(frame.file)+".json",FileAccess.WRITE)
	require_check(label+" sidecar opened",sidecar!=null)
	if sidecar!=null:
		sidecar.store_string(JSON.stringify(frame,"  ")+"\n"); sidecar.close()
	print("NATIVE_FRAME ",frame.file)
	return image
func finish() -> void:
	var failed:=checks.filter(func(c): return not c.pass).size()
	var hashes: Dictionary={}
	for path in ["scripts/observed_occlusion.gd","assets/mature/shaders/observed_visibility_mask.gdshader","assets/mature/shaders/observed_occlusion.gdshader","tests/occlusion_render_fixture.gd","tests/occlusion_stencil_contract.gd"]:
		hashes[path]=FileAccess.get_sha256("res://"+path)
	var critical_failures: int=checks.filter(func(c): return not c.pass and (c.name.ends_with("framebuffer saved") or c.name.ends_with("real framebuffer") or c.name.ends_with("sidecar opened") or c.name=="Compatibility renderer" or c.name=="fixture bound real exported rig" or c.name=="fixture rig supports exact visibility mask")).size()
	var complete: bool=critical_failures==0 and frames.size()==6
	var report:=FileAccess.open(output.path_join("capture-report.json"),FileAccess.WRITE)
	if report==null:
		push_error("Cannot save pixel gate report"); world.free(); quit(1); return
	report.store_string(JSON.stringify({"passed":complete,"functional_checks_passed":failed==0,"failed":failed,"frame_count":frames.size(),"frames":frames,"checks":checks,
		"mode":"occlusion","build":EXPECTED_BUILD,"engine":Engine.get_version_info(),"source_sha256":hashes,"renderer":RenderingServer.get_current_rendering_method(),
		"scope":"Six-frame native stencil evidence; strict external pixel gate required; no gameplay, phone, material-quality or performance acceptance"},"  ")+"\n")
	report.close(); world.free(); quit(0 if complete else 1)

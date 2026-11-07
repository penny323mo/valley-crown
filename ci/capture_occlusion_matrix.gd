extends "res://tests/occlusion_stencil_matrix.gd"
## External evidence adapter. Prepared fixture logic/assertions remain inherited.
const EXPECTED_BUILD := "vc-c7211e1083c8"
const CAPTURE_KIND := "native_controlled_occlusion_matrix"
const CAPTURE_MODE := "occlusion_matrix"
const EXPECTED_FRAMES := 67
var evidence_output: String
func _initialize():
	var args:=OS.get_cmdline_user_args()
	if args.size()!=4 or args[1]!=EXPECTED_BUILD or Vector2i(int(args[2]),int(args[3]))!=Vector2i(390,600) or load("res://scripts/rules.gd").BUILD_ID!=EXPECTED_BUILD:
		push_error("Expected exact output/build/width/height"); quit(1); return
	evidence_output=args[0]
	if not evidence_output.is_absolute_path() or evidence_output.begins_with("res://") or evidence_output.begins_with("user://"):
		push_error("Evidence output must be external absolute path"); quit(1); return
	call_deferred("run")
func setup() -> void:
	# Parent run assigns its local default immediately before virtual setup().
	output=evidence_output; super.setup()
func require_check(label: String, okay: bool, detail={}) -> void:
	checks.append({"name":label,"pass":okay,"detail":detail})
	if not okay: print("occlusion_stencil_matrix.gd_FINDING ",label," ",str(detail))
func visible_poses() -> Array:
	var result: Array=[]
	for rig: Node3D in world.find_children("ObservedActionRig","Node3D",true,false):
		if not rig.is_visible_in_tree(): continue
		var skeletons:=rig.find_children("*","Skeleton3D",true,false)
		var players:=rig.find_children("*","AnimationPlayer",true,false)
		if skeletons.size()!=1 or players.size()!=1: continue
		var skeleton: Skeleton3D=skeletons[0]; var player: AnimationPlayer=players[0]
		var poses: Array=[]
		for bone in skeleton.get_bone_count(): poses.append({"bone":skeleton.get_bone_name(bone),"pose":str(skeleton.get_bone_pose(bone))})
		var asset: String=rig.scene_file_path
		result.append({"kind":asset.get_file().trim_suffix("_action.scn"),"clip":player.assigned_animation,"seek_seconds":player.current_animation_position,
			"asset_path":asset,"asset_sha256":FileAccess.get_sha256(asset),"bone_count":skeleton.get_bone_count(),"poses":poses,"pose_sha256":JSON.stringify(poses).sha256_text(),
			"occlusion_authorized":bool(rig.get_meta("occlusion_authorized",false)),"overlay_enabled":rig.find_children("ObservedOcclusionOnly","MeshInstance3D",true,false).any(func(n): return n.visible)})
	return result
func capture(label: String) -> Image:
	await process_frame; await process_frame; await RenderingServer.frame_post_draw
	var image: Image=root.get_texture().get_image()
	var filename: String="%03d-%s.png" % [frames.size(),label]
	var path: String=output.path_join(filename)
	var error:=image.save_png(path); require_check(label+" framebuffer saved",error==OK)
	var frame: Dictionary={"file":filename,"sha256":FileAccess.get_sha256(path),"width":image.get_width(),"height":image.get_height(),
		"image":filename,"image_sha256":FileAccess.get_sha256(path),"label":label,"capture_kind":CAPTURE_KIND,"build":EXPECTED_BUILD,
		"utc":Time.get_datetime_string_from_system(true,true),"unix_time":Time.get_unix_time_from_system(),"monotonic_usec":Time.get_ticks_usec(),"process_frame":Engine.get_process_frames(),
		"capture_timing":"settled_two_process_frames_then_post_draw","engine":Engine.get_version_info(),"display":DisplayServer.get_name(),"rendering_method":RenderingServer.get_current_rendering_method(),
		"rendering_driver":RenderingServer.get_current_rendering_driver_name(),"adapter_name":RenderingServer.get_video_adapter_name(),"adapter_vendor":RenderingServer.get_video_adapter_vendor(),
		"framebuffer":[image.get_width(),image.get_height()],"game_tick":null,"game_seconds":null,
		"game_sha256":FileAccess.get_sha256("res://scripts/game.gd"),"rules_sha256":FileAccess.get_sha256("res://scripts/rules.gd"),
		"fixture_sha256":FileAccess.get_sha256("res://tests/occlusion_stencil_matrix.gd"),"animation_poses":visible_poses(),
		"visible_draw_calls":root.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME),
		"visible_primitives":root.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME),
		"limitations":["Controlled presentation fixture, not normal gameplay", "Native software renderer, not Web/iPhone/performance", "Accepted material defects unchanged"]}
	frames.append(frame)
	require_check(label+" real framebuffer",DisplayServer.get_name()=="X11" and image!=null and not image.is_empty())
	var sidecar:=FileAccess.open(path+".json",FileAccess.WRITE); require_check(label+" sidecar opened",sidecar!=null)
	if sidecar!=null: sidecar.store_string(JSON.stringify(frame,"  ")+"\n"); sidecar.close()
	print("NATIVE_FRAME ",filename)
	return image
func finish() -> void:
	var failed: int=checks.filter(func(c): return not c.pass).size()
	var critical: int=checks.filter(func(c): return not c.pass and (c.name.ends_with("framebuffer saved") or c.name.ends_with("real framebuffer") or c.name.ends_with("sidecar opened") or c.name.ends_with("matrix bound") or c.name.ends_with("exact requested framebuffer") or c.name.begins_with("cost fixture rig ") or c.name in ["Compatibility renderer","overlap second rig bound","viewport fixture supports exact rig","extra fixture source identity recorded"])).size()
	var complete: bool=critical==0 and frames.size()==EXPECTED_FRAMES
	var hashes: Dictionary={}
	for path in ["scripts/observed_occlusion.gd","scripts/observed_character_presenter.gd","scripts/action_character.gd","assets/mature/shaders/observed_visibility_mask.gdshader","assets/mature/shaders/observed_occlusion.gdshader","tests/occlusion_render_fixture.gd","tests/occlusion_stencil_matrix.gd"]:
		hashes[path]=FileAccess.get_sha256("res://"+path)
	var file:=FileAccess.open(output.path_join("capture-report.json"),FileAccess.WRITE)
	if file==null: push_error("Cannot save capture report"); world.free(); quit(1); return
	file.store_string(JSON.stringify({"passed":complete,"functional_checks_passed":failed==0,"failed":failed,"frame_count":frames.size(),"frames":frames,"checks":checks,
		"mode":CAPTURE_MODE,"build":EXPECTED_BUILD,"source_sha256":hashes,"engine":Engine.get_version_info(),"renderer":RenderingServer.get_current_rendering_method(),
		"scope":"Controlled matrix evidence; separate strict raw-pixel acceptance required; not phone/performance/art acceptance"},"  ")+"\n")
	file.close(); world.free(); quit(0 if complete else 1)

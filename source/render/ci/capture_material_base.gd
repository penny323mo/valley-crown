extends SceneTree
# External observation harness. No edits to authoritative game data.
const Controller = preload("res://scripts/action_character.gd")
const Rules = preload("res://scripts/rules.gd")
var mode=""
var capture_kind=""
var output=""
var build=""
var size=Vector2i.ZERO
var game
var frames=[]
var inputs=[]
var checks=[]
var lighting={}
var opening_camera={}
var material_binding={"native_scene_sha256":{},"atlas_sha256":{},"atlas_rgba8_sha256":{}}
var source_sha256={}
var worker_id=-1
func _initialize():call_deferred("run")
func settle(count=4):
	for i in count:await process_frame
func v3(v):return [v.x,v.y,v.z]
func basis(b):return [v3(b.x),v3(b.y),v3(b.z)]
func camera_data(camera):return {"basis":basis(camera.global_basis),"position":v3(camera.global_position),"size":camera.size,"projection":camera.projection,"keep_aspect":camera.keep_aspect,"near":camera.near,"far":camera.far}
func check(name,okay):
	checks.append({"name":name,"pass":bool(okay)})
	if not okay:push_error("MATERIAL_CAPTURE_CHECK_FAILED")
func inventory(path):
	var dir=DirAccess.open(path)
	dir.include_hidden=true
	for file in dir.get_files():source_sha256[path.path_join(file).trim_prefix("res://")]=FileAccess.get_sha256(path.path_join(file))
	for child in dir.get_directories():
		if path!="res://" or child!=".godot":inventory(path.path_join(child))
func initialize_scene():
	var args=OS.get_cmdline_user_args()
	if args.size()!=4:return false
	output=args[0];build=args[1];size=Vector2i(int(args[2]),int(args[3]))
	if build!=Rules.BUILD_ID or DisplayServer.get_name()!="X11" or size not in [Vector2i(390,844),Vector2i(844,390)]:return false
	root.size=size;root.content_scale_factor=1.0
	game=load("res://main.tscn").instantiate();root.add_child(game)
	await settle()
	check("genuine seeded main scene",game.test_mode==false)
	opening_camera=camera_data(game.camera)
	var env=game.find_children("*","WorldEnvironment",false,false)[0].environment
	var sun=game.find_children("*","DirectionalLight3D",false,false)[0]
	lighting={"source":"main.tscn runtime unmodified","background_color":env.background_color.to_html(),"ambient_color":env.ambient_light_color.to_html(),"ambient_energy":env.ambient_light_energy,"tonemap":env.tonemap_mode,"sun_color":sun.light_color.to_html(),"sun_energy":sun.light_energy,"sun_rotation_degrees":v3(sun.rotation_degrees),"sun_shadow":sun.shadow_enabled,"shadow_distance":sun.directional_shadow_max_distance}
	for kind in Controller.KINDS:
		var scene="assets/mature/models/"+kind+"_action.scn"
		material_binding.native_scene_sha256[scene]=FileAccess.get_sha256("res://"+scene)
		var atlas="art/action_characters/textures/"+kind+"_atlas.png"
		material_binding.atlas_sha256[atlas]=FileAccess.get_sha256("res://"+atlas)
		var image=Image.load_from_file("res://"+atlas)
		if image==null or image.is_empty():return false
		image.convert(Image.FORMAT_RGBA8)
		var hash=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(image.get_data())
		material_binding.atlas_rgba8_sha256[atlas]=hash.finish().hex_encode()
	inventory("res://")
	return true
func own_units():
	var result=[]
	for r in game.faction_views[0].records().values():
		if r.owned and r.alive and r.category=="unit":result.append({"id":r.id,"kind":r.kind,"state":r.state,"pos":v3(r.pos),"dest":v3(r.dest)})
	result.sort_custom(func(a,b):return a.id<b.id)
	return result
func pick_point(id):
	for y in range(70,size.y-20,6):
		for x in range(12,size.x-12,6):
			var point=Vector2(x,y)
			if game._box_point_in_world(point) and game._pick(point,false)==id:return point
	return Vector2.INF
func tap(point,action):
	for pressed in [true,false]:
		var e=InputEventScreenTouch.new();e.index=0;e.pressed=pressed;e.position=point
		inputs.append({"route":"root.push_input InputEventScreenTouch","action":action,"pressed":pressed,"position":[point.x,point.y],"tick":game.tick_count,"frame":Engine.get_process_frames(),"touch_command_before":game.touch_command,"selected_before":game.selected.duplicate()})
		root.push_input(e,false);await process_frame
	await settle()
func texture_hash(texture):
	if texture==null:return ""
	var original=texture.get_image()
	if original==null:return ""
	var image=original.duplicate()
	if image==null or image.is_empty():return ""
	if image.is_compressed():image.decompress()
	image.clear_mipmaps();image.convert(Image.FORMAT_RGBA8)
	var hash=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(image.get_data())
	return hash.finish().hex_encode()
func materials(rig):
	var result=[]
	for mesh in rig.find_children("*","MeshInstance3D",true,false):
		for surface in mesh.mesh.get_surface_count():
			var m=mesh.get_active_material(surface)
			if m is StandardMaterial3D:result.append({"mesh":str(rig.get_path_to(mesh)),"surface":surface,"name":m.resource_name,"albedo":m.albedo_color.to_html(),"roughness":m.roughness,"metallic":m.metallic,"vertex_color":m.vertex_color_use_as_albedo,"texture_rgba8_sha256":texture_hash(m.albedo_texture),"texture_path":m.albedo_texture.resource_path if m.albedo_texture!=null else ""})
	return result
func capture(label,camera,extra):
	await RenderingServer.frame_post_draw
	var image=root.get_texture().get_image();var name="%03d-%s.png"%[frames.size(),label];var path=output.path_join(name)
	if image==null or image.is_empty() or image.get_size()!=size or image.save_png(path)!=OK:check("raw framebuffer saved",false);return
	var f={"label":label,"image":name,"image_sha256":FileAccess.get_sha256(path),"capture_kind":capture_kind,"build":build,"game_sha256":FileAccess.get_sha256("res://scripts/game.gd"),"rules_sha256":FileAccess.get_sha256("res://scripts/rules.gd"),"main_scene_sha256":FileAccess.get_sha256("res://main.tscn"),"action_controller_sha256":FileAccess.get_sha256("res://scripts/action_character.gd"),"material_binding":material_binding,"lighting":lighting,"camera":camera_data(camera),"engine":Engine.get_version_info(),"display":DisplayServer.get_name(),"rendering_method":RenderingServer.get_current_rendering_method(),"rendering_driver":RenderingServer.get_current_rendering_driver_name(),"adapter_name":RenderingServer.get_video_adapter_name(),"adapter_vendor":RenderingServer.get_video_adapter_vendor(),"utc":Time.get_datetime_string_from_system(true,true),"unix_time":Time.get_unix_time_from_system(),"monotonic_usec":Time.get_ticks_usec(),"process_frame":Engine.get_process_frames(),"fixed_fps":20,"observed_process_delta_seconds":root.get_process_delta_time(),"framebuffer":[size.x,size.y]}
	f.merge(extra);var file=FileAccess.open(path+".json",FileAccess.WRITE);file.store_string(JSON.stringify(f,"  ")+"\n");file.close();frames.append(f)
func finish(expected):
	check("complete frame count",frames.size()==expected)
	var failed=checks.filter(func(c):return not c.pass).size()
	var report={"passed":failed==0,"failed":failed,"checks":checks,"build":build,"mode":mode,"frame_count":frames.size(),"frames":frames,"inputs":inputs,"worker_id":worker_id,"fixed_fps":20,"lighting":lighting,"opening_camera":opening_camera,"source_sha256":source_sha256,"scope":"Raw native llvmpipe framebuffer at fixed20fps simulation; not physical phone, measured performance, or automatic material quality approval"}
	var file=FileAccess.open(output.path_join("capture-report.json"),FileAccess.WRITE);file.store_string(JSON.stringify(report,"  ")+"\n");file.close();quit(0 if failed==0 else 1)

extends SceneTree
## Genuine native framebuffer fixture. Hosted renderer only, not phone proof.
const Controller = preload("res://scripts/action_character.gd")
var world: Node3D
var controller
var camera: Camera3D
var occluder: MeshInstance3D
var checks: Array=[]
var frames: Array=[]
var output:="res://reports/occlusion-fixture"
func _initialize(): call_deferred("run")
func require_check(label: String, pass_value: bool, detail={}) -> void:
	checks.append({"name":label,"pass":pass_value,"detail":detail})
	if not pass_value: push_error(label+" "+str(detail))
func capture(label: String) -> Image:
	await process_frame; await process_frame; await RenderingServer.frame_post_draw
	var image:=root.get_texture().get_image()
	var error:=image.save_png(output+"/"+label+".png")
	require_check(label+" framebuffer saved",error==OK)
	frames.append({"file":label+".png","sha256":FileAccess.get_sha256(output+"/"+label+".png"),
		"width":image.get_width(),"height":image.get_height(),
		"visible_draw_calls":root.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME),
		"visible_primitives":root.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME)})
	return image
func rgb(image: Image) -> PackedByteArray:
	var copy:=image.duplicate() as Image; copy.convert(Image.FORMAT_RGB8); return copy.get_data()
func difference(a: Image,b: Image) -> int:
	assert(a.get_size()==b.get_size())
	var aa:=rgb(a); var bb:=rgb(b); var count:=0
	for i in range(0,aa.size(),3):
		if aa[i]!=bb[i] or aa[i+1]!=bb[i+1] or aa[i+2]!=bb[i+2]: count+=1
	return count
func partial_stats(off: Image,on: Image,object_only: Image) -> Dictionary:
	# No fixture shadows, AA, changing lighting or animation: pixels changed by
	# adding the unit are exactly its normally visible fragments, not world pixels.
	var a:=rgb(off); var b:=rgb(on); var world_pixels:=rgb(object_only)
	var visible:=0; var changed_visible:=0; var silhouette:=0; var colors: Dictionary={}
	for i in range(0,a.size(),3):
		var unit_pixel: bool=a[i]!=world_pixels[i] or a[i+1]!=world_pixels[i+1] or a[i+2]!=world_pixels[i+2]
		var changed: bool=a[i]!=b[i] or a[i+1]!=b[i+1] or a[i+2]!=b[i+2]
		if unit_pixel:
			visible+=1
			if changed: changed_visible+=1
		elif changed:
			silhouette+=1; colors[Vector3i(b[i],b[i+1],b[i+2])]=true
	return {"visible_unit_pixels":visible,"changed_visible_unit_pixels":changed_visible,"silhouette_pixels":silhouette,"silhouette_colors":colors.size()}
func setup() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	root.size=Vector2i(390,600); root.msaa_3d=Viewport.MSAA_DISABLED
	root.screen_space_aa=Viewport.SCREEN_SPACE_AA_DISABLED; root.use_taa=false
	world=Node3D.new();root.add_child(world)
	var environment:=WorldEnvironment.new();var settings:=Environment.new()
	settings.background_mode=Environment.BG_COLOR;settings.background_color=Color("373d36")
	settings.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;settings.ambient_light_energy=.7
	environment.environment=settings;world.add_child(environment)
	var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-45,-20,0);light.shadow_enabled=false;world.add_child(light)
	camera=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=2.9
	camera.position=Vector3(2,2.2,4);world.add_child(camera);camera.look_at(Vector3(0,.9,0));camera.current=true
func finish() -> void:
	var failed:=checks.filter(func(c):return not c.pass).size()
	var hashes: Dictionary={}
	for path in ["scripts/observed_occlusion.gd","assets/mature/shaders/observed_visibility_mask.gdshader","assets/mature/shaders/observed_occlusion.gdshader","tests/occlusion_render_fixture.gd","tests/occlusion_stencil_contract.gd","tests/occlusion_stencil_matrix.gd"]:
		hashes[path]=FileAccess.get_sha256("res://"+path)
	FileAccess.open(output+"/report.json",FileAccess.WRITE).store_string(JSON.stringify({
		"scope":"Genuine native controlled framebuffer and draw-call fixture; not gameplay or physical-phone acceptance",
		"build":load("res://scripts/rules.gd").BUILD_ID,"engine":Engine.get_version_info(),"source_sha256":hashes,
		"checks":checks,"failed":failed,"frames":frames,"renderer":RenderingServer.get_current_rendering_method()},"  ")+"\n")
	world.free();quit(1 if failed else 0)
func run() -> void:
	setup()
	require_check("Compatibility renderer",RenderingServer.get_current_rendering_method()=="gl_compatibility")
	var body:=Node3D.new();world.add_child(body)
	controller=Controller.new();var bound: bool=controller.bind(body,"spearman",Color("435d6c"))
	require_check("fixture bound real exported rig",bound)
	if not bound: finish();return
	require_check("fixture rig supports exact visibility mask",controller.occlusion.supported)
	controller._start("idle",.5,false,false)
	controller.occlusion.set_authorized(false);var normal_off:Image=await capture("01-normal-overlay-off")
	controller.occlusion.set_authorized(true);var normal_on:Image=await capture("02-normal-overlay-on")
	require_check("normal visible mesh unchanged",difference(normal_off,normal_on)==0,{"changed_pixels":difference(normal_off,normal_on)})
	var delta_calls: int=frames[1].visible_draw_calls-frames[0].visible_draw_calls
	require_check("only two local geometry passes added",delta_calls==controller.occlusion.stats().extra_surface_draws_max,{"measured_delta":delta_calls,"contract":controller.occlusion.stats()})
	occluder=MeshInstance3D.new();var box:=BoxMesh.new();box.size=Vector3(.9,1.5,.35);occluder.mesh=box
	var mat:=StandardMaterial3D.new();mat.albedo_color=Color("665a46");mat.roughness=1;occluder.material_override=mat
	world.add_child(occluder);occluder.position=Vector3(.35,.78,.8)
	controller.occlusion.set_authorized(false);var hidden_off:Image=await capture("03-object-occluded-overlay-off")
	controller.occlusion.set_authorized(true);var hidden_on:Image=await capture("04-object-occluded-overlay-on")
	require_check("occluded authorized unit receives silhouette",difference(hidden_off,hidden_on)>30,{"changed_pixels":difference(hidden_off,hidden_on)})
	body.hide();var fog_hidden:Image=await capture("05-fog-hidden-parent")
	var partial:=partial_stats(hidden_off,hidden_on,fog_hidden)
	require_check("partially visible unit fragments unchanged",partial.visible_unit_pixels>30 and partial.changed_visible_unit_pixels==0,partial)
	require_check("occluded limbs use one flat silhouette color",partial.silhouette_pixels>30 and partial.silhouette_colors==1,partial)
	controller.release();var absent:Image=await capture("06-no-unit-reference")
	require_check("hidden ancestor silhouette is absent",difference(fog_hidden,absent)==0,{"changed_pixels":difference(fog_hidden,absent)})
	finish()

extends "res://tests/occlusion_render_fixture.gd"
## PREPARED ONLY. Native pixel regression, not gameplay/phone performance.
const Presenter=preload("res://scripts/observed_character_presenter.gd")
var body: Node3D
var cover: MeshInstance3D
func capture(label: String) -> Image:
	# Unlike the settled v2 study, capture the FIRST presented frame after the
	# caller's change. A one-frame fog leak or stale resized mask must not hide
	# behind two warm-up frames. No simulation/animation is advanced here.
	await RenderingServer.frame_post_draw
	var image:=root.get_texture().get_image()
	var error:=image.save_png(output+"/"+label+".png")
	require_check(label+" framebuffer saved",error==OK)
	frames.append({"file":label+".png","sha256":FileAccess.get_sha256(output+"/"+label+".png"),
		"width":image.get_width(),"height":image.get_height(),"process_frame":Engine.get_process_frames(),
		"capture_timing":"first_post_draw_after_state_change",
		"visible_draw_calls":root.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME),
		"visible_primitives":root.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME)})
	return image
func make_cover() -> MeshInstance3D:
	var result:=MeshInstance3D.new(); var quad:=QuadMesh.new(); quad.size=Vector2(12,12)
	result.mesh=quad; var mat:=StandardMaterial3D.new()
	mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color=Color("665a46"); mat.cull_mode=BaseMaterial3D.CULL_DISABLED
	result.material_override=mat; world.add_child(result)
	result.global_transform=Transform3D(camera.global_basis,camera.global_position-camera.global_basis.z*(camera.near+.2))
	return result
func coverage_delta(a: Image,b: Image,c: Image,d: Image) -> int:
	var aa:=rgb(a); var bb:=rgb(b); var cc:=rgb(c); var dd:=rgb(d); var result:=0
	for i in range(0,aa.size(),3):
		var expected: bool=aa[i]!=bb[i] or aa[i+1]!=bb[i+1] or aa[i+2]!=bb[i+2]
		var actual: bool=cc[i]!=dd[i] or cc[i+1]!=dd[i+1] or cc[i+2]!=dd[i+2]
		if expected!=actual: result+=1
	return result
func run() -> void:
	output="res://reports/occlusion-viewport-lifecycle"; setup()
	root.content_scale_factor=1.0
	require_check("extra fixture source identity recorded",true,{"tests/occlusion_viewport_lifecycle.gd":FileAccess.get_sha256("res://tests/occlusion_viewport_lifecycle.gd")})
	require_check("Compatibility renderer",RenderingServer.get_current_rendering_method()=="gl_compatibility")
	body=Node3D.new(); world.add_child(body); controller=Controller.new()
	var bound: bool=controller.bind(body,"spearman",Color("435d6c"))
	require_check("viewport fixture supports exact rig",bound and controller.occlusion.supported)
	if not bound or not controller.occlusion.supported: finish();return
	controller._start("attack",controller.player.get_animation("attack").length*.56,false,false)
	cover=make_cover(); cover.hide()
	# Reallocate the framebuffer in both orientations, then restore portrait. Each
	# size independently checks normal pixels and complete occluded coverage.
	var sizes: Array=[Vector2i(390,844),Vector2i(844,390),Vector2i(390,600),Vector2i(390,844)]
	for index in sizes.size():
		root.size=sizes[index]; body.hide(); cover.hide()
		var prefix: String="resize-"+str(index)
		var empty: Image=await capture(prefix+"-empty")
		require_check(prefix+" exact requested framebuffer",empty.get_size()==sizes[index],{"expected":str(sizes[index]),"actual":str(empty.get_size())})
		body.show(); controller.occlusion.set_authorized(false)
		var off: Image=await capture(prefix+"-normal-off")
		controller.occlusion.set_authorized(true); var on: Image=await capture(prefix+"-normal-on")
		require_check(prefix+" nonempty normal mesh unchanged",difference(off,empty)>30 and difference(off,on)==0)
		cover.show(); var covered: Image=await capture(prefix+"-covered-on")
		controller.occlusion.set_authorized(false); var covered_off: Image=await capture(prefix+"-covered-off")
		body.hide(); var wall_only: Image=await capture(prefix+"-wall-only"); body.show()
		var stats:=partial_stats(covered_off,covered,wall_only)
		require_check(prefix+" full coverage verified",stats.visible_unit_pixels==0 and stats.silhouette_pixels>30 and stats.silhouette_colors==1,stats)
		require_check(prefix+" no stale resized stencil footprint",coverage_delta(off,empty,covered,wall_only)==0,{"mismatch_pixels":coverage_delta(off,empty,covered,wall_only)})
		cover.hide(); controller.occlusion.set_authorized(true)
		var restored: Image=await capture(prefix+"-normal-restored")
		require_check(prefix+" original pixels restored",difference(off,restored)==0)
	await camera_layer_exclusion()
	await near_clip_alignment()
	controller.release(); body.free(); cover.free()
	await observation_pixels()
	finish()
func camera_layer_exclusion() -> void:
	var source:=controller.occlusion.overlays[0].get_parent() as MeshInstance3D
	var old_layers: int=source.layers; var old_camera: int=camera.cull_mask
	# Layers are a bind-time contract, unlike inherited Node3D transforms. Rebind
	# explicitly after changing them; current game code never mutates these values.
	source.layers=2; controller.occlusion.bind(controller.rig,Color("435d6c"))
	require_check("overlay copies source camera layer exactly",controller.occlusion.overlays[0].layers==source.layers)
	cover.layers=1; cover.show(); camera.cull_mask=1
	var excluded: Image=await capture("camera-layer-excluded-unit")
	body.hide(); var absent: Image=await capture("camera-layer-excluded-reference"); body.show()
	require_check("camera culling source cannot leave silhouette",difference(excluded,absent)==0)
	camera.cull_mask=3
	var included: Image=await capture("camera-layer-included-unit")
	require_check("same layer becomes visible when camera allows it",difference(included,absent)>30)
	source.layers=old_layers; controller.occlusion.bind(controller.rig,Color("435d6c")); camera.cull_mask=old_camera; cover.hide()
func near_clip_alignment() -> void:
	var before_near: float=camera.near
	controller.occlusion.set_authorized(false); var whole: Image=await capture("clip-original-unit")
	camera.near=-camera.to_local(Vector3(0,.9,0)).z
	body.hide(); var empty: Image=await capture("clip-empty-reference"); body.show()
	var off: Image=await capture("clip-unit-off")
	controller.occlusion.set_authorized(true); var on: Image=await capture("clip-unit-on")
	require_check("near clip actually cuts a nonempty unit",difference(off,empty)>30 and difference(whole,off)>30)
	require_check("near clipped source pixels remain exact",difference(off,on)==0)
	camera.near=before_near
func observation_record(tick: int) -> Dictionary:
	return {"id":77,"kind":"spearman","category":"unit","owned":false,"team":1,"remembered":false,"last_seen_tick":tick,"pos":Vector3.ZERO,"visual_action":"idle","visual_attack_tick":-1,"visual_hit_tick":-1}
func observation_pixels() -> void:
	var presenter=Presenter.new(); var holder:=Node3D.new(); world.add_child(holder)
	var wall:=make_cover()
	var absent: Image=await capture("observation-absent-reference")
	presenter.present(observation_record(1),holder,Color("813d32"),0.0,false)
	var first: Image=await capture("observation-visible-enemy-behind-wall")
	require_check("currently observed enemy silhouette is nonempty",difference(first,absent)>30)
	presenter.reconcile({}); var hidden: Image=await capture("observation-enemy-enters-fog")
	require_check("record removal leaves no fog-hidden silhouette",difference(hidden,absent)==0 and presenter.controllers.is_empty())
	presenter.present(observation_record(40),holder,Color("813d32"),0.0,false)
	var returned: Image=await capture("observation-enemy-reappears")
	require_check("reappearance is fresh and exactly same legal pose",difference(first,returned)==0)
	presenter.reconcile({})
	presenter.consume_deaths([{"witnessed":false}],world,Color("435d6c"),Color("813d32"))
	var unwitnessed: Image=await capture("observation-unwitnessed-death")
	require_check("unwitnessed death never draws",difference(unwitnessed,absent)==0 and presenter.corpses.is_empty())
	presenter.consume_deaths([{"witnessed":true,"id":77,"kind":"spearman","team":1,"pos":Vector3.ZERO,"yaw":0.0}],world,Color("435d6c"),Color("813d32"))
	var corpse: Image=await capture("observation-witnessed-corpse-behind-wall")
	require_check("corpse behind wall has no xray",difference(corpse,absent)==0 and presenter.corpses.size()==1 and not presenter.corpses[0].controller.occlusion.enabled)
	presenter.update_deaths(0.0,false,func(_p): return false)
	var corpse_fog: Image=await capture("observation-corpse-enters-fog")
	require_check("fog removes witnessed enemy corpse",difference(corpse_fog,absent)==0 and presenter.corpses.is_empty())
	presenter.clear(); holder.free(); wall.free()

func finish() -> void:
	var failed:=checks.filter(func(c): return not c.pass).size()
	var hashes: Dictionary={}
	for path in ["scripts/observed_occlusion.gd","scripts/observed_character_presenter.gd","scripts/action_character.gd","assets/mature/shaders/observed_visibility_mask.gdshader","assets/mature/shaders/observed_occlusion.gdshader","tests/occlusion_render_fixture.gd","tests/occlusion_viewport_lifecycle.gd"]:
		hashes[path]=FileAccess.get_sha256("res://"+path)
	FileAccess.open(output+"/report.json",FileAccess.WRITE).store_string(JSON.stringify({"scope":"Controlled native first-presented-frame pixel regression, not normal gameplay/Web/phone acceptance","checks":checks,"passed":checks.size()-failed,"failed":failed,"frames":frames,"frame_count":frames.size(),"source_sha256":hashes,"engine":Engine.get_version_info(),"renderer":RenderingServer.get_current_rendering_method()},"  ")+"\n")
	world.free(); quit(1 if failed else 0)

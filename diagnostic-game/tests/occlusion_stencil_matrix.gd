extends "res://tests/occlusion_render_fixture.gd"
## Extended hosted-only matrix. Exact source and frame identities in inherited report.
const Visuals=preload("res://assets/mature/visual_library.gd")
var body: Node3D
func make_controller(kind: String, color:=Color("435d6c")) -> bool:
	body=Node3D.new(); world.add_child(body); controller=Controller.new()
	var okay: bool=controller.bind(body,kind,color)
	require_check(kind+" matrix bound",okay and controller.occlusion.supported)
	return okay and controller.occlusion.supported
func clear_controller() -> void:
	controller.release(); body.free()
func pair(label: String) -> Array:
	controller.occlusion.set_authorized(false); var off: Image=await capture(label+"-off")
	controller.occlusion.set_authorized(true); var on: Image=await capture(label+"-on")
	return [off,on]
func obstacle_case(label: String, obstacle: Node3D) -> void:
	world.add_child(obstacle)
	var toward_camera:=camera.global_basis.z*1.3; toward_camera.y=0.0
	obstacle.position=toward_camera+camera.global_basis.x*.20
	var images: Array=await pair(label)
	body.hide(); var object_only: Image=await capture(label+"-object-only"); body.show()
	var stats:=partial_stats(images[0],images[1],object_only)
	require_check(label+" produces silhouette",stats.silhouette_pixels>30,stats)
	require_check(label+" nonvacuous partial coverage",stats.visible_unit_pixels>30 and stats.silhouette_pixels>30,stats)
	require_check(label+" preserves normally visible limbs",stats.visible_unit_pixels>30 and stats.changed_visible_unit_pixels==0,stats)
	require_check(label+" no alpha accumulation stripes",stats.silhouette_colors==1,stats)
	obstacle.free()
func run() -> void:
	output="res://reports/occlusion-stencil-matrix"; setup()
	require_check("Compatibility renderer",RenderingServer.get_current_rendering_method()=="gl_compatibility")
	# Static exact poses cover crossed limbs, long weapons and moving legs.
	for kind in Controller.KINDS:
		if not make_controller(kind): finish(); return
		for clip in ["idle","walk","attack"]:
			controller._start(clip,controller.player.get_animation(clip).length*.56,false,false)
			var images: Array=await pair(kind+"-"+clip+"-unoccluded")
			require_check(kind+" "+clip+" original pixels exact",difference(images[0],images[1])==0,{"changed_pixels":difference(images[0],images[1])})
		clear_controller()
	if not make_controller("spearman"): finish(); return
	controller._start("attack",controller.player.get_animation("attack").length*.56,false,false)
	# These are genuine existing world assets. This remains controlled presentation,
	# not a gameplay screenshot or proof of natural-map placement/phone performance.
	await obstacle_case("pine-cutout",Visuals.instantiate_asset("pine",0))
	await obstacle_case("oak-cutout",Visuals.instantiate_asset("oak",0))
	await obstacle_case("house-opaque",Visuals.instantiate_asset("house"))
	# Current map has no standalone large rock resource. Use labeled opaque rock
	# geometry to test that occlusion is material/geometry based, never entity based.
	var rock:=MeshInstance3D.new(); var stone:=SphereMesh.new()
	stone.radius=.72; stone.height=1.25; stone.radial_segments=8; stone.rings=4
	rock.mesh=stone; var rock_material:=StandardMaterial3D.new(); rock_material.albedo_color=Color("737875"); rock.material_override=rock_material
	var rock_root:=Node3D.new(); rock_root.add_child(rock); rock.position.y=.63
	await obstacle_case("procedural-rock-opaque",rock_root)
	# A world object behind the unit is not an occluder and may not trigger x-ray.
	var behind:=MeshInstance3D.new(); var box:=BoxMesh.new(); box.size=Vector3(2,3,.3)
	behind.mesh=box; behind.material_override=rock_material; world.add_child(behind)
	behind.position=Vector3(0,1,-2)
	var behind_images: Array=await pair("object-behind-unit")
	require_check("object behind unit leaves original exact",difference(behind_images[0],behind_images[1])==0)
	behind.free()
	await full_and_temporal_coverage()
	# Other units protect visible fragments too. Never turn a visible nearby ally
	# into an x-ray window for a more distant rig.
	var near_body:=Node3D.new(); world.add_child(near_body)
	near_body.position=camera.global_basis.z*.65; near_body.position.y=0; near_body.position.x+=.10
	var near_controller=Controller.new(); var near_bound: bool=near_controller.bind(near_body,"archer",Color("813d32"))
	require_check("overlap second rig bound",near_bound)
	if not near_bound: finish(); return
	controller.occlusion.set_authorized(false); near_controller.occlusion.set_authorized(false)
	var overlap_off: Image=await capture("overlapping-units-off")
	controller.occlusion.set_authorized(true); near_controller.occlusion.set_authorized(true)
	var overlap_on: Image=await capture("overlapping-units-on")
	require_check("overlapping observed units unchanged without world obstacle",difference(overlap_off,overlap_on)==0)
	for step in [1,-1]:
		near_body.position+=camera.global_basis.x*float(step)*.32
		controller.occlusion.set_authorized(false); near_controller.occlusion.set_authorized(false)
		var moving_off: Image=await capture("moving-overlap-"+str(step)+"-off")
		controller.occlusion.set_authorized(true); near_controller.occlusion.set_authorized(true)
		var moving_on: Image=await capture("moving-overlap-"+str(step)+"-on")
		require_check("moving overlapping unit pixels exact "+str(step),difference(moving_off,moving_on)==0)
	near_controller.release(); near_body.free()
	# Local source mesh animation and tool visibility are inherited by the child
	# overlay, not copied once at bind. Keep a pixel gate as well as API assertions.
	var source_mesh:=controller.occlusion.overlays[0].get_parent() as MeshInstance3D
	var original_transform: Transform3D=source_mesh.transform
	source_mesh.position+=Vector3(.12,.06,0); source_mesh.rotate_y(.15)
	var transformed: Array=await pair("animated-source-local-trs")
	require_check("animated source mesh and overlay stay pixel-aligned",difference(transformed[0],transformed[1])==0)
	source_mesh.transform=original_transform
	source_mesh.hide(); var tool_hidden: Image=await capture("source-tool-hidden")
	body.hide(); var whole_hidden: Image=await capture("source-tool-absent-reference"); body.show(); source_mesh.show()
	require_check("hidden tool geometry cannot leave overlay",difference(tool_hidden,whole_hidden)==0)
	controller.start_death(); controller.occlusion.set_authorized(false)
	var corpse_off: Image=await capture("corpse-overlay-off")
	controller.occlusion.set_authorized(true); var corpse_on: Image=await capture("corpse-reenable-denied")
	require_check("corpse toggle cannot restore silhouette",not controller.occlusion.enabled and difference(corpse_off,corpse_on)==0)
	clear_controller()
	await draw_budget()
	finish()
func coverage_delta(a: Image,b: Image,c: Image,d: Image) -> int:
	# Compare DIFFERENCE MASKS, not colors: visible-source footprint versus the
	# complete flat silhouette footprint behind a solid wall. No tolerance.
	var aa:=rgb(a); var bb:=rgb(b); var cc:=rgb(c); var dd:=rgb(d); var changed:=0
	for i in range(0,aa.size(),3):
		var expected: bool=aa[i]!=bb[i] or aa[i+1]!=bb[i+1] or aa[i+2]!=bb[i+2]
		var actual: bool=cc[i]!=dd[i] or cc[i+1]!=dd[i+1] or cc[i+2]!=dd[i+2]
		if expected!=actual: changed+=1
	return changed
func full_and_temporal_coverage() -> void:
	var position_a: Vector3=body.position
	var position_b: Vector3=position_a+camera.global_basis.x*.32
	controller.occlusion.set_authorized(false)
	body.hide(); var empty: Image=await capture("temporal-empty-reference"); body.show()
	var reference_a: Image=await capture("temporal-unit-a-reference")
	body.position=position_b; var reference_b: Image=await capture("temporal-unit-b-reference")
	require_check("temporal source footprints are nonempty and actually moved",difference(reference_a,empty)>30 and difference(reference_b,empty)>30 and difference(reference_a,reference_b)>30)
	body.position=position_a; controller.occlusion.set_authorized(true)
	var visible_a: Image=await capture("temporal-a-visible-mask-written")
	require_check("temporal initial normal pixels exact",difference(reference_a,visible_a)==0)
	# Camera-facing cover is larger than the whole viewport: explicit full
	# occlusion, independent of tree/building bounds and natural placement.
	var cover:=MeshInstance3D.new(); var quad:=QuadMesh.new(); quad.size=Vector2(8,8)
	cover.mesh=quad; var cover_material:=StandardMaterial3D.new()
	cover_material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	cover_material.albedo_color=Color("665a46"); cover_material.cull_mode=BaseMaterial3D.CULL_DISABLED
	cover.material_override=cover_material; world.add_child(cover)
	cover.global_transform=Transform3D(camera.global_basis,camera.global_position-camera.global_basis.z*(camera.near+.2))
	body.position=position_b
	var full_b_on: Image=await capture("temporal-b-fully-occluded-on")
	controller.occlusion.set_authorized(false); var full_b_off: Image=await capture("temporal-b-fully-occluded-off")
	body.hide(); var wall_only: Image=await capture("temporal-wall-only"); body.show()
	var full_stats:=partial_stats(full_b_off,full_b_on,wall_only)
	require_check("full occlusion is genuinely complete and nonempty",full_stats.visible_unit_pixels==0 and full_stats.silhouette_pixels>30 and difference(full_b_off,wall_only)==0,full_stats)
	require_check("full silhouette has exactly the whole moving unit footprint",coverage_delta(reference_b,empty,full_b_on,wall_only)==0,{"footprint_mismatch_pixels":coverage_delta(reference_b,empty,full_b_on,wall_only)})
	require_check("full silhouette stays one color",full_stats.silhouette_colors==1,full_stats)
	# Return over A's previous visible stencil footprint. Stale per-frame stencil
	# would punch holes here or at overlapping B; exact coverage must recover.
	body.position=position_a; controller.occlusion.set_authorized(true)
	var full_a: Image=await capture("temporal-return-a-fully-occluded")
	require_check("A to B to A has no stale stencil holes",coverage_delta(reference_a,empty,full_a,wall_only)==0,{"footprint_mismatch_pixels":coverage_delta(reference_a,empty,full_a,wall_only)})
	cover.hide(); body.position=position_b
	var visible_b: Image=await capture("temporal-b-visible-again")
	require_check("moving out of cover restores original texture exactly",difference(reference_b,visible_b)==0)
	body.hide(); var empty_after: Image=await capture("temporal-all-units-hidden")
	require_check("empty frame leaves no moving silhouette trail",difference(empty,empty_after)==0)
	cover.show(); body.position=position_a; body.show()
	var after_empty: Image=await capture("temporal-occluded-after-empty-frame")
	require_check("empty frame clears previous visibility mask",coverage_delta(reference_a,empty,after_empty,wall_only)==0,{"footprint_mismatch_pixels":coverage_delta(reference_a,empty,after_empty,wall_only)})
	cover.free(); body.position=position_a

func draw_budget() -> void:
	# Many unrelated world surfaces make an accidentally forced world depth
	# prepass observable. Extra draws must still be EXACTLY two per unit surface.
	camera.position=Vector3(0,9,12); camera.look_at(Vector3(0,.8,0)); camera.size=13
	var objects:=Node3D.new(); world.add_child(objects)
	var mat:=StandardMaterial3D.new(); mat.albedo_color=Color("665a46")
	for i in 40:
		var mesh:=MeshInstance3D.new(); var box:=BoxMesh.new(); box.size=Vector3(.24,.3,.25)
		mesh.mesh=box; mesh.material_override=mat; mesh.position=Vector3((i%10-4.5)*.8,.15,-3.5-floorf(i/10.0)*.4)
		objects.add_child(mesh)
	for count in [1,12,24]:
		var controllers: Array=[]; var bodies: Array=[]; var budget:=0
		for i in count:
			var node:=Node3D.new(); world.add_child(node)
			node.position=Vector3((i%6-2.5)*1.4,0,(floorf(i/6.0)-1.5)*1.5)
			var c=Controller.new(); var okay: bool=c.bind(node,Controller.KINDS[i%4],Color("435d6c"))
			require_check("cost fixture rig "+str(i)+" bound for "+str(count),okay and c.occlusion.supported)
			if not okay: finish(); return
			c._start("idle",.5,false,false); c.occlusion.set_authorized(false)
			controllers.append(c); bodies.append(node); budget+=c.occlusion.stats().extra_surface_draws_max
		await capture("cost-"+str(count)+"-off")
		var before: int=frames[-1].visible_draw_calls
		for c in controllers: c.occlusion.set_authorized(true)
		await capture("cost-"+str(count)+"-on")
		var after: int=frames[-1].visible_draw_calls
		require_check("bounded measured draw increase at "+str(count)+" units",after-before==budget,{"units":count,"unrelated_world_meshes":40,"off":before,"on":after,"delta":after-before,"expected":budget})
		for c in controllers: c.release()
		for node in bodies: node.free()
	objects.free()

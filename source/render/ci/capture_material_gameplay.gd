extends "capture_material_base.gd"
var candidate_checks=[]
func visibility_probe(include_materials=false):
	var result={"method":"conservative visible-mesh world-AABB rays at three torso/head heights; not pixel proof","sample_count":0,"blocker_count":0,"samples":[],"projected_body_bounds":[],"clear":false,"overlay":{},"overlay_nodes":[],"materials":[]}
	if worker_id<0 or not game.character_presenter.controllers.has(worker_id):return result
	var controller=game.character_presenter.controllers[worker_id]
	result.overlay=controller.occlusion.stats()
	if include_materials:result.materials=materials(controller.rig)
	for node in controller.occlusion.overlays:result.overlay_nodes.append({"visible":node.visible,"visible_in_tree":node.is_visible_in_tree(),"shader_sha256":FileAccess.get_sha256("res://assets/mature/shaders/observed_occlusion.gdshader")})
	var bounds_points=[]
	for mesh in controller.rig.find_children("*","MeshInstance3D",true,false):
		if not mesh.is_visible_in_tree() or mesh.get_meta("occlusion_overlay",false):continue
		var box=mesh.get_aabb()
		for index in 8:
			var point=game.camera.unproject_position(mesh.global_transform*box.get_endpoint(index))
			bounds_points.append(point)
	if not bounds_points.is_empty():
		var bounds=Rect2(bounds_points[0],Vector2.ZERO)
		for point in bounds_points:bounds=bounds.expand(point)
		result.projected_body_bounds=[bounds.position.x,bounds.position.y,bounds.size.x,bounds.size.y]
	var meshes=game.find_children("*","MeshInstance3D",true,false)
	for height in [0.7,1.1,1.5]:
		var target=controller.body.global_position+Vector3(0,height,0)
		var screen=game.camera.unproject_position(target)
		if game.camera.is_position_behind(target) or not game._box_point_in_world(screen):continue
		result.sample_count+=1
		var origin=game.camera.project_ray_origin(screen)
		result.samples.append({"world":v3(target),"screen":[screen.x,screen.y],"ray_origin":v3(origin),"height":height})
		for mesh in meshes:
			if not mesh.is_visible_in_tree() or controller.body.is_ancestor_of(mesh):continue
			var bounds=mesh.global_transform*mesh.get_aabb()
			if bounds.intersects_segment(origin,target)!=null:result.blocker_count+=1
	result.clear=result.sample_count==3 and result.blocker_count==0
	return result
func game_extra():
	return {"candidate_checks":candidate_checks,"visibility_probe":visibility_probe(true),"test_mode":game.test_mode,"economy_audit_ok":game.economy.audit().ok,"game_tick":game.tick_count,"selected":game.selected.duplicate(),"worker_visible":worker_id>=0 and pick_point(worker_id).is_finite(),"own_units":own_units(),"animation_poses":[{"node":".","snapshot":game.visual_evidence_snapshot()}]}
func run():
	mode="material_gameplay";capture_kind="genuine_native_material_game_viewport"
	if not await initialize_scene():quit(2);return
	for r in game.faction_views[0].records().values():
		if r.owned and r.alive and r.kind=="villager" and pick_point(r.id).is_finite():
			worker_id=r.id
			var probe=visibility_probe()
			candidate_checks.append({"worker_id":r.id,"probe":probe})
			if probe.clear:break
			worker_id=-1
	await capture("opening",game.camera,game_extra())
	check("ordinary visible worker available",worker_id>=0)
	if worker_id<0:finish(2);return
	await tap(pick_point(worker_id),"worker-select")
	check("worker selected by routed touch",game.selected==[worker_id])
	if game.selected!=[worker_id]:finish(2);return
	var button=game.touch_button
	var reachable=button!=null and button.is_visible_in_tree() and not button.disabled and root.get_visible_rect().encloses(button.get_global_rect())
	check("normal command button reachable",reachable)
	if not reachable:finish(2);return
	await tap(button.get_global_rect().get_center(),"command-enter")
	check("command targeting entered by touch",game.touch_command)
	if not game.touch_command:finish(2);return
	var destination=Vector2.INF
	var worker=game.faction_views[0].get_record(worker_id)
	for y in range(80,size.y-20,12):
		if destination.is_finite():break
		for x in range(16,size.x-16,12):
			var point=Vector2(x,y)
			if not game._box_point_in_world(point) or game._pick(point,true)>=0:continue
			var ground=game._point(game._cell(game._world_at(point)))
			var distance=ground.distance_to(worker.pos)
			if distance>=2 and distance<=5 and game.visible_cells[0][game._cell_index(ground)]>0 and not game.work_memory[0].grid.is_point_solid(game._cell(ground)):
				destination=point;break
	check("ordinary visible ground target available",destination.is_finite())
	if not destination.is_finite():finish(2);return
	await tap(destination,"worker-move")
	var walking=false
	for i in 40:
		await process_frame
		var pose=game.visual_evidence_snapshot().live.get(str(worker_id),{})
		if pose.get("clip","")=="walk" and game.faction_views[0].get_record(worker_id).state=="move" and pick_point(worker_id).is_finite() and visibility_probe().clear:walking=true;break
	check("ordinary walking worker visible",walking)
	if walking:await capture("worker-walking",game.camera,game_extra())
	finish(2)

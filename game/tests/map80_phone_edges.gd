extends SceneTree
# Map80 port; baseline phone_input_edges_ci.gd SHA256 281f2dc799797965b30914a9111cdb10a25df9111f6f49dd81b3aaf7ac558c37
# Native physical-coordinate input regressions.
# Run with: godot --headless --path PROJECT --script TEST -- OUTPUT_JSON
# These tests do not establish browser or physical-phone acceptance.
var game
var dpr=1.0
var checks=[]
var journal
func _initialize(): call_deferred("run")
func check(label,passed,detail={}):
	var row={"label":label,"passed":bool(passed),"detail":detail}
	checks.append(row)
	journal.store_line(JSON.stringify(row)); journal.flush()
	print("REVIEW_EDGE ",JSON.stringify(row))
func settle(n=3):
	for i in n: await process_frame
func send_touch(p,pressed,id=0,canceled=false):
	var e=InputEventScreenTouch.new(); e.position=p*dpr;e.index=id;e.pressed=pressed;e.canceled=canceled
	root.push_input(e,false)
func send_drag(a,b,id=0):
	var e=InputEventScreenDrag.new();e.index=id;e.position=b*dpr;e.relative=(b-a)*dpr;root.push_input(e,false)
func tap(p):
	send_touch(p,true);await process_frame;send_touch(p,false);await settle()
func anchor(ent):return game.camera.unproject_position(ent.pos+Vector3(0,0.6 if ent.category=="unit" else 1.0,0))
func find_button(prefix):
	for button in game.ui.find_children("*","Button",true,false):
		if button.is_visible_in_tree() and button.text.begins_with(prefix):return button
	return null
func worker():
	for ent in game.faction_views[0].records().values():
		if ent.owned and ent.kind=="villager" and game._box_point_in_world(anchor(ent)) and game._pick(anchor(ent),false)==ent.id:return ent
	return {}
func reset_and_select():
	game._cancel_mode();game._test_reset();game.camera_focus=game.MapRoutes.home(0);game._camera_update();await settle()
	check("Translated Map80 home and camera",game.camera_focus==Vector3(-25,0,24) and game._first(0,"town_center").pos==game.camera_focus)
	var ent=worker()
	check("Initial worker can be touched",not ent.is_empty(),{"logical":str(root.get_visible_rect())})
	if not ent.is_empty():await tap(anchor(ent))
	return ent
func run():
	var paths=OS.get_cmdline_user_args()
	if paths.is_empty():
		push_error("Provide an output JSON path after --.");quit(2);return
	journal=FileAccess.open(paths[0]+".progress.jsonl",FileAccess.WRITE)
	if journal==null:
		push_error("Cannot open the output journal; create its parent directory first.");quit(2);return
	root.size=Vector2i(390,844);game=load("res://main.tscn").instantiate();root.add_child(game);game.test_mode=true;await settle()
	journal.store_line(JSON.stringify({"source_sha256":FileAccess.get_sha256("res://scripts/game.gd"),"suite_sha256":FileAccess.get_sha256(get_script().resource_path),"scope":"Native physical-coordinate synthetic edge tests; no simulation advance, browser or physical phone."}));journal.flush()
	for css in [Vector2i(320,693),Vector2i(375,812),Vector2i(390,844),Vector2i(844,390)]:
		for ratio in [1.0,2.0,3.0]:
			dpr=ratio
			root.size=Vector2i(Vector2(css)*dpr);root.content_scale_factor=dpr;await settle()
			check(str(css)+" DPR"+str(dpr)+" logical viewport",root.get_visible_rect().size.is_equal_approx(Vector2(css)),{"actual":str(root.get_visible_rect()),"physical":str(root.size)})
			var ent=await reset_and_select()
			if ent.is_empty():continue
			var before=game.commands.size()
			check(str(css)+" DPR"+str(dpr)+" selected owns worker",ent.id in game.selected)
			check(str(css)+" DPR"+str(dpr)+" physical event became logical",game.pointer_screen.distance_to(anchor(ent))<0.01,{"pointer":str(game.pointer_screen),"expected":str(anchor(ent))})
			var button=game.touch_button
			check(str(css)+" DPR"+str(dpr)+" command full CSS target",button.size.x>=44 and button.size.y>=44 and game.hud_bottom.get_global_rect().encloses(button.get_global_rect()) and root.get_visible_rect().encloses(button.get_global_rect()))
			await tap(button.get_global_rect().get_center())
			check(str(css)+" DPR"+str(dpr)+" targeting activated",game.touch_command and game.compact_cancel_button.is_visible_in_tree())
			check(str(css)+" DPR"+str(dpr)+" cancel full CSS target",game.compact_cancel_button.size.x>=44 and game.compact_cancel_button.size.y>=44 and game.hud_bottom.get_global_rect().encloses(game.compact_cancel_button.get_global_rect()) and root.get_visible_rect().encloses(game.compact_cancel_button.get_global_rect()))
			check(str(css)+" DPR"+str(dpr)+" scroller retains full building width",game.action_scroll.size.x>=90,{"width":game.action_scroll.size.x})
			await tap(game.compact_cancel_button.get_global_rect().get_center())
			check(str(css)+" DPR"+str(dpr)+" visible cancel preserves selection without order",not game.touch_command and ent.id in game.selected and game.commands.size()==before)
	# Focused interrupted-stream tests use one bounded portrait configuration.
	dpr=3.0;root.size=Vector2i(1170,2532);root.content_scale_factor=dpr;await settle()
	var ent=await reset_and_select()
	if ent.is_empty():finish(paths[0]);return
	var point=anchor(ent)
	await tap(game.touch_button.get_global_rect().get_center())
	send_touch(point,true);send_touch(point,false,0,true);await settle()
	check("Native canceled release creates no order",game.commands.is_empty() and not game.touch_command and game.all_touch_ids.is_empty())
	await tap(game.touch_button.get_global_rect().get_center())
	send_touch(point,true);send_touch(game.pause_button.get_global_rect().get_center(),true,1)
	send_touch(point,false);send_touch(game.pause_button.get_global_rect().get_center(),false,1);await settle()
	check("Second finger cancels targeting without activating Pause",game.commands.is_empty() and not game.touch_command and not game.paused and game.all_touch_ids.is_empty())
	await tap(game.touch_button.get_global_rect().get_center())
	send_touch(point,true);game._on_web_touch_cancel([]);send_touch(point,false);await settle()
	check("Cancel bridge game handler suppresses following ordinary release",game.commands.is_empty() and not game.touch_command and game.all_touch_ids.is_empty())
	# This directly calls the game handler; it does not exercise JS listener ordering.
	await tap(game.touch_button.get_global_rect().get_center())
	send_touch(point,true);root.size=Vector2i(1170,2400);await settle();send_touch(point,false);await settle()
	check("Viewport interruption leaves no order or held stream",game.commands.is_empty() and not game.touch_command and game.all_touch_ids.is_empty())
	root.size=Vector2i(1170,2532);await settle();ent=await reset_and_select();point=anchor(ent)
	var command_point=game.touch_button.get_global_rect().get_center()
	send_touch(command_point,true);send_drag(command_point,command_point+Vector2(20,0));send_touch(command_point+Vector2(20,0),false);await settle()
	check("Command drag is not a tap",not game.touch_command and game.commands.is_empty())
	# Two complete presses before a deferred cleanup: old lifetime may not delete new ownership.
	send_touch(command_point,true);send_touch(command_point,false);send_touch(command_point,true)
	await process_frame
	send_touch(command_point,false);await settle()
	check("Reused touch index can complete a new command-button press",not game.touch_command and game.commands.is_empty() and game.all_touch_ids.is_empty())
	await tap(game.touch_button.get_global_rect().get_center())
	send_touch(point,true)
	game.test_mode=false;game._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT);game.test_mode=true
	send_touch(point,false);await settle()
	check("Focus loss cancels and pauses without an order",game.paused and not game.application_focused and not game.touch_command and game.commands.is_empty() and game.all_touch_ids.is_empty())
	game.test_mode=false;game._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN);game.test_mode=true
	await tap(game.pause_button.get_global_rect().get_center())
	check("Returning focus permits explicit Continue",not game.paused and game.application_focused and game.commands.is_empty())
	var house=find_button("民居")
	check("House action present",house!=null)
	check("Initial house button is fully reachable",house!=null and game.action_scroll.get_global_rect().encloses(house.get_global_rect()))
	if house!=null and game.action_scroll.get_global_rect().encloses(house.get_global_rect()):
		await tap(house.get_global_rect().get_center());await settle()
		check("Suggested ghost remains unpaid and unconfirmed",game.build_mode=="house" and not game.build_preview_held and game.build_confirm.disabled and game.commands.is_empty() and game.stocks[0].wood==200)
		var castle=game._first(0,"town_center");var bad=game.camera.unproject_position(castle.pos)
		check("Invalid-site test target is in the battlefield",game._box_point_in_world(bad))
		if game._box_point_in_world(bad):
			await tap(bad)
			check("Explicit invalid site stays invalid",game.build_preview_held and not game.placement_ok and game.build_confirm.disabled and game.selection_detail.text.contains("不可建造"))
			check("Invalid-site Confirm remains reachable",root.get_visible_rect().encloses(game.build_confirm.get_global_rect()))
			await tap(game.build_confirm.get_global_rect().get_center())
			check("Disabled confirmation does not pay or queue",game.commands.is_empty() and game.stocks[0].wood==200)
			await tap(find_button("取消建造").get_global_rect().get_center())
			check("Cancel clears invalid held preview",game.build_mode.is_empty() and not game.build_preview_held and game.commands.is_empty())
	# Hidden authority is used only as a negative test oracle, never in production picking.
	var hidden=game._first(1,"town_center")
	check("Hidden enemy is absent from selectable projection",game.faction_views[0].get_record(hidden.id).is_empty() and game._pick(anchor(hidden))!=hidden.id)
	var observed_resource={}
	for record in game.faction_views[0].records().values():
		if record.category=="resource" and not record.remembered:
			observed_resource=record;break
	check("Observed resource exists for memory negative",not observed_resource.is_empty())
	if not observed_resource.is_empty():
		# Deliberate visibility fixture: no command or economy state is advanced.
		game.visible_cells[0].fill(0);game._publish_faction_views();game._update_visuals(0)
		var remembered=game.faction_views[0].get_record(observed_resource.id)
		check("Resource memory fixture is genuinely remembered",not remembered.is_empty() and remembered.remembered)
		check("Remembered resource is not picked",game._pick(anchor(observed_resource))!=observed_resource.id)
		check("Resource geometry helper is available",game.has_method("_resource_ray_distance"))
		if game.has_method("_resource_ray_distance") and not remembered.is_empty():
			var ray=game.camera.project_ray_normal(anchor(observed_resource));var origin=game.camera.project_ray_origin(anchor(observed_resource))
			check("Remembered resource cannot contribute mesh geometry",not is_finite(game._resource_ray_distance(remembered,origin,ray)))
	finish(paths[0])
func map_edge_geometry():
	# Read-only projection/minimap geometry fixture, separate from routed touch
	# cases above. These coordinates used to clamp at22/19 on the48-cell map.
	for point in [Vector3(-39.5,0,-39.5),Vector3(-39.5,0,39.5),Vector3(39.5,0,-39.5),Vector3(39.5,0,39.5)]:
		game.camera_focus=point;game._camera_update() # Keep every tested ground point in front of the camera.
		var projected=game.camera.unproject_position(point)
		var picked=game._world_at(projected)
		var expected=Vector3(signf(point.x)*38,0,signf(point.z)*38)
		check("Map80 far-ground ray clamps to expanded world "+str(point),picked.distance_to(expected)<0.001,{"actual":str(picked),"expected":str(expected)})
	for uv in [Vector2.ZERO,Vector2(0,1),Vector2(1,0),Vector2.ONE]:
		var click=InputEventScreenTouch.new();click.pressed=true;click.position=Vector2(9,9)+uv*(game.minimap.size-Vector2(18,18))
		game.minimap._gui_input(click);game._camera_update()
		var expected=Vector3(-35 if uv.x==0 else 35,0,-35 if uv.y==0 else 35)
		check("Map80 minimap corner reaches expanded camera limit "+str(uv),game.camera_focus.distance_to(expected)<0.001,{"actual":str(game.camera_focus),"expected":str(expected)})
	game.camera_focus=game.MapRoutes.home(0);game._camera_update()
func finish(path):
	map_edge_geometry()
	var failed=checks.filter(func(c):return not c.passed).size()
	var report={"passed":checks.size()-failed,"failed":failed,"checks":checks,"source_sha256":FileAccess.get_sha256("res://scripts/game.gd"),"build":game.Rules.BUILD_ID,"scope":"Map80 translated-home synthetic physical-coordinate UI/interruption checks, direct focus/cancel/visibility-memory fixtures and four-corner world/minimap geometry. Not browser or physical phone."}
	FileAccess.open(path,FileAccess.WRITE).store_string(JSON.stringify(report,"  "));journal.close();quit(0 if failed==0 else 1)

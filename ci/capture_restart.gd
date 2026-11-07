extends SceneTree
# External controlled portrait probe. Victory is an explicit synthetic terminal
# fixture. Defeat is actual routed UI surrender, not a natural combat defeat.
# The real restart callback and scene lifecycle are never replaced or invoked directly.
const EXPECTED_BUILD="vc-d99ac5d19247"
const SCENARIO="native_match_restart_portrait_v1"
const CAPTURE_KIND="native_controlled_match_restart"
var game
var checks=[]
var inputs=[]
var frames=[]
var destination=""
var reload_events=0
var fresh={}
func _initialize(): call_deferred("run")
func check(name,value): checks.append({"name":name,"pass":bool(value)})
func settle(count=4):
	for i in count: await process_frame
func state():
	return {"snapshot":game._snapshot().duplicate(true),"records":game.faction_views[0].records().duplicate(true),"bank":game.economy.bank_milli(0).duplicate(true),"selected":game.selected.duplicate(),"commands":game.commands.duplicate(true),"title":game.selection_title.text,"detail":game.selection_detail.text,"queue":game.queue_label.text,"ai":game.ai_enabled,"over":game.game_over,"panel":game.end_panel.visible,"touch_command":game.touch_command,"touches":game.all_touch_ids.duplicate(),"gui_presses":game.gui_touch_press.size(),"touch_points":game.touch_points.duplicate(true),"touch_epochs":game.touch_press_epochs.duplicate(true),"action_touch_scroll":game.action_touch_scroll.duplicate(true),"box_cancel_press":game.box_cancel_press.duplicate(true),"box_cancel_repeat":game.box_cancel_repeat.duplicate(true),"touch_gesture":game.touch_gesture,"canceled_touches":game.canceled_touch_ids.duplicate(true),"path_requests":game.path_requests.duplicate(true),"processed_commands":game.processed_command_ids.duplicate(true),"command_sequence":game.command_sequence,"next_queue_id":game.next_queue_id,"spawn_commits":game.spawn_commit_order.duplicate(true),"resources_hud":game.top_resources.text,"time_hud":game.time_label.text,"actions_empty":game.unit_action_cues==[{},{}] and game.pending_visual_deaths.is_empty(),"corpses_empty":game.character_presenter.corpses.is_empty()}
func on_scene_changed():
	reload_events+=1
	game=current_scene
	game.test_mode=true
	fresh=state()
func event_at(p,pressed,viewport=null,canceled=false,double_tap=false):
	if viewport==null: viewport=root
	var event=InputEventScreenTouch.new()
	event.position=p;event.index=0;event.pressed=pressed;event.canceled=canceled;event.double_tap=double_tap
	inputs.append({"x":p.x,"y":p.y,"pressed":pressed,"canceled":canceled,"double_tap":double_tap,"viewport":"root" if viewport==root else "surrender_dialog","tick":game.tick_count,"reloads":reload_events,"frame":Engine.get_process_frames()})
	viewport.push_input(event,false)
	await process_frame
func tap(p,viewport=null):
	await event_at(p,true,viewport)
	await event_at(p,false,viewport)
	await settle()
func button_named(parent,text):
	for b in parent.find_children("*","Button",true,false):
		if b.text==text and b.is_visible_in_tree(): return b
	return null
func rect_data(node):
	var r=node.get_global_rect();return [r.position.x,r.position.y,r.size.x,r.size.y]
func v3(v: Vector3) -> Array:return [v.x,v.y,v.z]
func xform(t: Transform3D) -> Array:return [v3(t.basis.x),v3(t.basis.y),v3(t.basis.z),v3(t.origin)]
func capture(label):
	await settle();await RenderingServer.frame_post_draw
	var image=root.get_texture().get_image()
	var filename="%03d-%s.png"%[frames.size(),label.replace("_","-")]
	check(label+" image",image!=null and image.get_size()==Vector2i(390,844) and image.save_png(destination.path_join(filename))==OK)
	var button=button_named(game.end_panel,"再開一局")
	var data={"label":label,"image":filename,"image_sha256":FileAccess.get_sha256(destination.path_join(filename)),"build":game.Rules.BUILD_ID,"source_sha256":FileAccess.get_sha256("res://scripts/game.gd"),"viewport":[root.size.x,root.size.y],"tick":game.tick_count,"reloads":reload_events,"input_count":inputs.size(),"state":state(),"panel":rect_data(game.end_panel),"title":{"text":game.end_title.text,"rect":rect_data(game.end_title)},"body":{"text":game.end_body.text,"rect":rect_data(game.end_body),"minimum_height":game.end_body.get_minimum_size().y,"lines":game.end_body.get_line_count()},"restart":{} if button==null else {"text":button.text,"rect":rect_data(button),"disabled":button.disabled},"engine":Engine.get_version_info(),"display":DisplayServer.get_name(),"frame":Engine.get_process_frames()}
	data.merge({"scenario":SCENARIO,"capture_kind":CAPTURE_KIND,"game_sha256":data.source_sha256,"rules_sha256":FileAccess.get_sha256("res://scripts/rules.gd"),
		"rendering_method":RenderingServer.get_current_rendering_method(),"rendering_driver":RenderingServer.get_current_rendering_driver_name(),"adapter_name":RenderingServer.get_video_adapter_name(),"adapter_vendor":RenderingServer.get_video_adapter_vendor(),
		"utc":Time.get_datetime_string_from_system(true,true),"unix_time":Time.get_unix_time_from_system(),"monotonic_usec":Time.get_ticks_usec(),"process_frame":Engine.get_process_frames(),
		"fixed_fps":20,"observed_process_delta_seconds":game.get_process_delta_time(),"framebuffer":[root.size.x,root.size.y],"logical_viewport":[root.get_visible_rect().size.x,root.get_visible_rect().size.y],"content_scale_factor":root.content_scale_factor,"test_mode":game.test_mode,
		"animation_poses":[{"node":".","snapshot":game.visual_evidence_snapshot()}],
		"camera":{"focus":v3(game.camera_focus),"zoom":game.camera_zoom,"projection":game.camera.projection,"keep_aspect":game.camera.keep_aspect,"size":game.camera.size,"near":game.camera.near,"far":game.camera.far,"transform":xform(game.camera.global_transform)}})
	frames.append(data)
	print("RESTART_FRAME ",label," tick=",game.tick_count," reloads=",reload_events)
	var file=FileAccess.open(destination.path_join(filename+".json"),FileAccess.WRITE);file.store_string(JSON.stringify(data,"  ")+"\n");file.close()
func find_point(id):
	for y in range(90,684,8):
		for x in range(16,374,8):
			var p=Vector2(x,y)
			if game._box_point_in_world(p) and game._pick(p,false)==id and (id>=0 or game._pick(p,true)<0):return p
	return Vector2.INF
func run():
	var args=OS.get_cmdline_user_args()
	if args.size()!=4 or args[1]!=EXPECTED_BUILD or args[2]!="390" or args[3]!="844" or DisplayServer.get_name()!="X11":quit(2);return
	destination=args[0];root.size=Vector2i(390,844);root.content_scale_factor=1.0
	game=load("res://main.tscn").instantiate();root.add_child(game);current_scene=game;game.test_mode=true
	if game.Rules.BUILD_ID!=EXPECTED_BUILD:quit(2);return
	await settle()
	var initial=state()
	check("portrait viewport",root.get_visible_rect().size==Vector2(390,844))
	# Synthetic setup ONLY: exercise the same irrecoverable terminal display as
	# accepted natural victory42366187767. Never claim a natural victory here.
	var saved_recovery=game.recovery_ticks.duplicate()
	game.recovery_ticks[1]=game.EndRules.IRRECOVERABLE_TICKS
	game._check_end()
	check("synthetic victory semantics",game.outcome=="victory" and game.end_reason=="irrecoverable" and game.end_panel.visible)
	await capture("synthetic_victory")
	# Restore only the explicitly synthetic terminal fixture, before genuine UI flow.
	game.recovery_ticks=saved_recovery;game.game_over=false;game.victory=false;game.outcome="";game.end_reason="";game.end_panel.hide()
	await tap(game.compact_menu_button.get_global_rect().get_center())
	var surrender=button_named(game.compact_menu,"投降")
	check("surrender menu touch target",surrender!=null)
	if surrender==null:await finish(initial,{});return
	await tap(surrender.get_global_rect().get_center())
	var dialog=null
	for child in game.ui.get_children():
		if child is ConfirmationDialog and child.visible: dialog=child
	check("routed surrender dialog",dialog!=null and dialog.title=="退出這場戰役")
	if dialog==null:await finish(initial,{});return
	await tap(dialog.get_ok_button().get_global_rect().get_center(),dialog)
	check("one surrender command",game.commands.size()==1 and game.commands[0].type=="surrender")
	# One normal rendered process frame consumes the UI-issued command.
	# Open after draw and close after next draw, so this is not a direct tick call.
	await RenderingServer.frame_post_draw
	var before_tick=game.tick_count
	game.test_mode=false
	await process_frame
	await RenderingServer.frame_post_draw
	game.test_mode=true
	check("one normal process tick consumes surrender",game.tick_count==before_tick+1 and is_equal_approx(game.get_process_delta_time(),0.05))
	check("actual surrender defeat",game.game_over and game.outcome=="defeat" and game.end_reason=="surrender")
	await capture("routed_surrender_defeat")
	var restart=button_named(game.end_panel,"再開一局")
	check("restart fit and hit target",restart!=null and not restart.disabled and root.get_visible_rect().encloses(restart.get_global_rect()) and restart.size.x>=44 and restart.size.y>=44)
	if restart==null:await finish(initial,{});return
	var p=restart.get_global_rect().get_center()
	var old_ref=weakref(game);var old_id=game.get_instance_id()
	scene_changed.connect(on_scene_changed)
	await event_at(p,true);await settle(20)
	check("held press does not restart",reload_events==0 and old_ref.get_ref()!=null)
	await event_at(p,false);await settle(8)
	check("release reloads once and frees old scene",reload_events==1 and old_ref.get_ref()==null and current_scene.get_instance_id()!=old_id)
	check("fresh exact initial state",fresh==initial)
	await capture("fresh_restart")
	var before=state()
	# Repeat same location in the new scene: may select an owned unit, but must
	# not restart, order, recruit, or debit. Selection is intentionally not equated.
	await event_at(p,true,null,false,true);await event_at(p,false);await settle(8)
	check("repeat tap no extra restart payment queue or command",reload_events==1 and game.commands.is_empty() and game.economy.bank_milli(0)==before.bank and game._first(0,"town_center").queue.is_empty())
	var worker_id=-1;var worker_point=Vector2.INF
	for record in game.faction_views[0].records().values():
		if record.owned and record.kind=="villager":
			var point=find_point(record.id)
			if point!=Vector2.INF:worker_id=record.id;worker_point=point;break
	check("fresh worker available",worker_id>=0)
	if worker_id>=0:
		await tap(worker_point)
		check("fresh worker selects",game.selected==[worker_id])
		await tap(game.touch_button.get_global_rect().get_center())
		var ground=find_point(-1)
		check("fresh command targets",game.touch_command and ground!=Vector2.INF)
		if ground!=Vector2.INF:await tap(ground)
		check("fresh touch submits exactly one order",game.commands.size()==1 and game.commands[0].type=="order" and game.commands[0].ids==[worker_id] and not game.touch_command)
	await capture("fresh_touch_order")
	await finish(initial,fresh)
func finish(initial,restarted):
	var failed=0
	for item in checks:
		if not item.pass:failed+=1
	var report={"scope":"native controlled portrait ScreenTouch; synthetic victory fixture, actual UI surrender defeat, genuine scene reload; not natural phone match or physical device","scenario":SCENARIO,"fixed_fps":20,"frame_count":frames.size(),"build":EXPECTED_BUILD,"passed":failed==0,"failed":failed,"checks":checks,"inputs":inputs,"frames":frames,"initial":initial,"fresh":restarted,"reload_events":reload_events,"harness_sha256":FileAccess.get_sha256(get_script().resource_path)}
	var file=FileAccess.open(destination.path_join("capture-report.json"),FileAccess.WRITE);file.store_string(JSON.stringify(report,"  ")+"\n");file.close();quit(0 if failed==0 else 1)

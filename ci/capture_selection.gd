extends SceneTree
# Controlled fixed-portrait native ScreenTouch probe, not physical-phone evidence.
# External harness; no direct selection, order, camera or simulation-tick calls.
var game
var checks=[]
var input_trace=[]
var captures=[]
var destination=""
const EXPECTED_BUILD="vc-c09af531eecf"
const SCENARIO="native_selection_preview_portrait_v1"
const CAPTURE_KIND="native_controlled_selection_preview"
var build=""
var start_snapshot={}
var start_bank={}
var initial_tick=-1
var worker_id=-1
var home_worker_id=-1
var army_ids=[]
var menu_proofs=[]
var preview_refs=[]
func _initialize(): call_deferred("run")
const CHECK_NAMES=["fixed portrait logical viewport", "normal seeded targets", "army worker target", "army worker selected", "army_house reachable", "army unheld preview", "army guided plot reachable", "army held legal preview", "held_preview_before_army raw screenshot saved", "army_menu reachable", "army menu preserves preview", "army_target reachable", "army selected and closed", "army preview fully retired", "army actions restored", "army_actions_restored raw screenshot saved", "home worker target", "home worker selected", "home_house reachable", "home unheld preview", "home guided plot reachable", "home held legal preview", "held_preview_before_home raw screenshot saved", "home_menu reachable", "home menu preserves preview", "home_target reachable", "home selected and closed", "home preview fully retired", "home actions restored", "home_actions_restored raw screenshot saved", "unchanged authority economy and frozen tick"]
func check(name,ok):
	checks.append({"name":name,"pass":bool(ok)})
	if not bool(ok):
		# Fixed source-known labels only; never emit arbitrary state or report values.
		var index=CHECK_NAMES.find(name)
		if index>=0:
			push_error("SELECTION_CHECK_FAILED %02d %s" % [index,CHECK_NAMES[index]])
		else:
			push_error("SELECTION_CHECK_FAILED unknown_check")
func settle():
	for i in 4: await process_frame
func tap(p,action,target_rect=[]):
	for pressed in [true,false]:
		var event=InputEventScreenTouch.new(); event.position=p; event.index=0; event.pressed=pressed
		input_trace.append({"x":p.x,"y":p.y,"pressed":pressed,"tick":game.tick_count,"action":action,"target_rect":target_rect,"frame":Engine.get_process_frames()})
		root.push_input(event,false); await process_frame
	await settle()
func find_point(id):
	# Bounded pixel scan, using the same own-selection picker as the tap route.
	var size=root.get_visible_rect().size
	for y in range(90,int(size.y)-160,8):
		for x in range(16,int(size.x)-16,8):
			var p=Vector2(x,y)
			if game._box_point_in_world(p) and game._pick(p,false)==id and (id>=0 or game._pick(p,true)<0): return p
	return Vector2.INF
func rect_data(node):
	var r=node.get_global_rect()
	return [r.position.x,r.position.y,r.size.x,r.size.y]
func v3(v: Vector3) -> Array: return [v.x,v.y,v.z]
func xform(t: Transform3D) -> Array: return [v3(t.basis.x),v3(t.basis.y),v3(t.basis.z),v3(t.origin)]
func label_data(node: Label) -> Dictionary:
	return {"text":node.text,"rect":rect_data(node),"minimum_size":[node.get_minimum_size().x,node.get_minimum_size().y],"visible":node.is_visible_in_tree(),"line_count":node.get_line_count()}
func actions_data() -> Array:
	var result=[]
	for button in game.actions.get_children():
		if button is Button: result.append({"text":button.text,"rect":rect_data(button),"visible":button.is_visible_in_tree(),"disabled":button.disabled})
	return result
func commands_data() -> Array:
	var result=[]
	for command in game.commands:
		var row=command.duplicate(true)
		if row.has("position"): row.position=v3(row.position)
		result.append(row)
	return result
func capture(label):
	await settle()
	await RenderingServer.frame_post_draw
	# Read all metadata and framebuffer after the same completed rendered frame.
	var image: Image=root.get_texture().get_image()
	var name="%03d-%s.png"%[captures.size(),label.replace("_","-")]
	var path=destination.path_join(name)
	var okay=image!=null and not image.is_empty() and image.get_size()==Vector2i(390,844)
	var saved=okay and image.save_png(path)==OK
	check(label+" raw screenshot saved",saved)
	if not saved: return
	var keep=game._first(0,"town_center")
	var record={"label":label,"image":name,"image_sha256":FileAccess.get_sha256(path),"capture_kind":CAPTURE_KIND,"scenario":SCENARIO,
		"build":build,"version":game.Rules.VERSION,"game_sha256":FileAccess.get_sha256("res://scripts/game.gd"),"rules_sha256":FileAccess.get_sha256("res://scripts/rules.gd"),
		"engine":Engine.get_version_info(),"display":DisplayServer.get_name(),"rendering_method":RenderingServer.get_current_rendering_method(),"rendering_driver":RenderingServer.get_current_rendering_driver_name(),"adapter_name":RenderingServer.get_video_adapter_name(),"adapter_vendor":RenderingServer.get_video_adapter_vendor(),
		"utc":Time.get_datetime_string_from_system(true,true),"unix_time":Time.get_unix_time_from_system(),"monotonic_usec":Time.get_ticks_usec(),"process_frame":Engine.get_process_frames(),
		"fixed_fps":20,"observed_process_delta_seconds":game.get_process_delta_time(),"framebuffer":[390,844],"logical_viewport":[root.get_visible_rect().size.x,root.get_visible_rect().size.y],"content_scale_factor":root.content_scale_factor,
		"game_tick":game.tick_count,"game_frame_counter":game.frame_counter,"test_mode":game.test_mode,"snapshot":game._snapshot().duplicate(true),"selected":game.selected.duplicate(),"commands":commands_data(),"bank":game.economy.bank_milli(0).duplicate(true),"producer_queue":keep.queue.duplicate(true),"input_count":input_trace.size(),"touch_command":game.touch_command,"build_mode":game.build_mode,"preview_held":game.build_preview_held,"ghost_valid":is_instance_valid(game.ghost),"ghost_count":ghost_count(),"pointer_world":v3(game.pointer_world),"placement_ok":game.placement_ok,"build_confirm_valid":is_instance_valid(game.build_confirm),"menu_visible":game.compact_menu.is_visible_in_tree(),"menu_dismiss_visible":game.compact_menu_dismiss.is_visible_in_tree(),"pointer_counts":{"all":game.all_touch_ids.size(),"points":game.touch_points.size(),"gui":game.gui_touch_press.size(),"epochs":game.touch_press_epochs.size()},
		"animation_poses":[{"node":".","snapshot":game.visual_evidence_snapshot()}],
		"camera":{"focus":v3(game.camera_focus),"zoom":game.camera_zoom,"projection":game.camera.projection,"keep_aspect":game.camera.keep_aspect,"size":game.camera.size,"near":game.camera.near,"far":game.camera.far,"transform":xform(game.camera.global_transform)},
		"hud":{"toast_build_guidance":game.toast_build_guidance,"toast_time":game.toast_time,"selection_title":label_data(game.selection_title),"detail":label_data(game.selection_detail),"queue":label_data(game.queue_label),"toast":label_data(game.toast_label),"bottom_rect":rect_data(game.hud_bottom),"top_rect":rect_data(game.hud_top),"unit_tools_visible":game.compact_unit_tools.is_visible_in_tree(),"command_visible":game.touch_button.is_visible_in_tree(),"command_rect":rect_data(game.touch_button),"actions":actions_data(),"action_scroll_rect":rect_data(game.action_scroll),"action_scroll_horizontal":game.action_scroll.scroll_horizontal},
		"scope":"frozen normal seeded world; native ScreenTouch preview and menu selection, not paid construction or physical phone"}
	var sidecar=FileAccess.open(path+".json",FileAccess.WRITE)
	if sidecar==null: quit(2); return
	sidecar.store_string(JSON.stringify(record,"  ")+"\n");sidecar.close()
	captures.append(record)
	print("SELECTION_FRAME ",label," tick=",game.tick_count," inputs=",input_trace.size())
func ghost_count() -> int:
	var count=0
	for ref in preview_refs:
		if ref.get_ref()!=null: count+=1
	return count
func find_button(node,text):
	for child in node.get_children():
		if child is Button and child.text.begins_with(text) and child.is_visible_in_tree(): return child
		var found=find_button(child,text)
		if found!=null: return found
	return null
func tap_button(node,text,action) -> bool:
	var button=find_button(node,text)
	if button==null or button.disabled or not root.get_visible_rect().encloses(button.get_global_rect()):
		check(action+" reachable",false);return false
	check(action+" reachable",true)
	await tap(button.get_global_rect().get_center(),action,rect_data(button))
	return true
func begin_preview(prefix) -> bool:
	# Army's ordinary callback changes the view. Choose a public pickable worker
	# in that current view rather than reusing a now-offscreen startup target.
	if prefix=="home":
		for record in game.faction_views[0].records().values():
			if record.owned and record.alive and record.kind=="villager" and find_point(record.id)!=Vector2.INF:
				home_worker_id=record.id;break
	var target_worker=home_worker_id if prefix=="home" else worker_id
	var point=find_point(target_worker) if target_worker>=0 else Vector2.INF
	check(prefix+" worker target",point!=Vector2.INF)
	if point==Vector2.INF: return false
	await tap(point,prefix+"_worker")
	check(prefix+" worker selected",game.selected==[target_worker] and game.build_mode.is_empty())
	if not await tap_button(game.actions,"民居",prefix+"_house"): return false
	check(prefix+" unheld preview",game.build_mode=="house" and not game.build_preview_held and is_instance_valid(game.ghost))
	if not is_instance_valid(game.ghost): return false
	preview_refs.append(weakref(game.ghost))
	# Only read the game's existing public suggested plot; touch its screen projection.
	var plot=game.pointer_world
	point=game.camera.unproject_position(plot)
	var legal=game._box_point_in_world(point) and game._placement_reason("house",plot,0,target_worker).is_empty()
	check(prefix+" guided plot reachable",legal)
	if not legal: return false
	await tap(point,prefix+"_plot")
	check(prefix+" held legal preview",game.build_mode=="house" and game.build_preview_held and is_instance_valid(game.ghost) and game.placement_ok and is_instance_valid(game.build_confirm) and not game.build_confirm.disabled)
	return true
func choose_menu(prefix,text,expected) -> bool:
	if not await tap_button(game.hud_top,"選單",prefix+"_menu"): return false
	var preserved=game.compact_menu.is_visible_in_tree() and game.build_mode=="house" and game.build_preview_held and is_instance_valid(game.ghost)
	check(prefix+" menu preserves preview",preserved)
	menu_proofs.append({"action":prefix,"input_count":input_trace.size(),"selected":game.selected.duplicate(),"build_mode":game.build_mode,"held":game.build_preview_held,"ghost_valid":is_instance_valid(game.ghost),"menu_visible":game.compact_menu.is_visible_in_tree(),"tick":game.tick_count})
	if not preserved: return false
	if not await tap_button(game.compact_menu,text,prefix+"_target"): return false
	check(prefix+" selected and closed",game.selected==expected and not game.compact_menu.visible and not game.compact_menu_dismiss.visible)
	check(prefix+" preview fully retired",game.build_mode.is_empty() and not game.build_preview_held and not game.touch_command and not is_instance_valid(game.ghost) and ghost_count()==0 and not is_instance_valid(game.build_confirm))
	return true
func run():
	var args=OS.get_cmdline_user_args()
	if args.size()!=4 or args[1]!=EXPECTED_BUILD or args[2]!="390" or args[3]!="844" or DisplayServer.get_name()!="X11":
		push_error("Unbound selection source or fixed portrait renderer");quit(2);return
	destination=args[0];build=args[1]
	root.size=Vector2i(390,844);root.content_scale_factor=1.0
	game=load("res://main.tscn").instantiate();root.add_child(game);game.test_mode=true
	if game.Rules.BUILD_ID!=build: quit(2);return
	await settle()
	check("fixed portrait logical viewport",root.get_visible_rect().size==Vector2(390,844))
	initial_tick=game.tick_count;start_snapshot=game._snapshot().duplicate(true);start_bank=game.economy.bank_milli(0).duplicate(true)
	for record in game.faction_views[0].records().values():
		if record.owned and record.kind=="villager" and worker_id<0 and find_point(record.id)!=Vector2.INF: worker_id=record.id
		if record.alive and record.team==0 and record.category=="unit" and record.kind!="villager": army_ids.append(record.id)
	check("normal seeded targets",worker_id in [1,2,3,4,5] and army_ids==[6] and game.selected==[0])
	if worker_id<0: finish();return
	if not await begin_preview("army"): finish();return
	await capture("held_preview_before_army")
	if not await choose_menu("army","全軍",army_ids): finish();return
	check("army actions restored",game.compact_unit_tools.is_visible_in_tree() and game.touch_button.is_visible_in_tree() and find_button(game.actions,"停止")!=null and not game.selection_title.text.begins_with("建造"))
	await capture("army_actions_restored")
	if not await begin_preview("home"): finish();return
	await capture("held_preview_before_home")
	if not await choose_menu("home","主堡",[0]): finish();return
	check("home actions restored",not game.compact_unit_tools.is_visible_in_tree() and find_button(game.actions,"訓練村民")!=null and game.selection_title.text=="主堡")
	await capture("home_actions_restored")
	check("unchanged authority economy and frozen tick",game.test_mode and game.tick_count==initial_tick and initial_tick==0 and game.commands.is_empty() and game.economy.bank_milli(0)==start_bank and game._first(0,"town_center").queue.is_empty() and game.entities.size()==78)
	finish()
func finish():
	var failed=0
	for item in checks:
		if not item.pass: failed+=1
	var output=FileAccess.open(destination.path_join("capture-report.json"),FileAccess.WRITE)
	if output==null: quit(2);return
	output.store_string(JSON.stringify({"passed":failed==0,"build":build,"scope":"frozen normal seeded world; native ScreenTouch preview and menu selection, not paid construction or physical phone","scenario":SCENARIO,"frame_count":captures.size(),"frames":captures,"fixed_fps":20,"checks":checks,"failed":failed,"inputs":input_trace,"worker_id":worker_id,"home_worker_id":home_worker_id,"army_ids":army_ids,"initial_tick":initial_tick,"initial_snapshot":start_snapshot,"initial_bank":start_bank,"final_bank":game.economy.bank_milli(0).duplicate(true),"final_tick":game.tick_count,"final_commands":commands_data(),"menu_proofs":menu_proofs},"  ")+"\n");output.close()
	quit(0 if failed==0 else 1)

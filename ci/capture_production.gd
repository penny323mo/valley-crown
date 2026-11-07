extends SceneTree
# Controlled fixed-portrait native ScreenTouch probe, not physical-phone evidence.
# External harness; no direct selection, order, camera or simulation-tick calls.
var game
var checks=[]
var input_trace=[]
var captures=[]
var destination=""
const EXPECTED_BUILD="vc-d99ac5d19247"
const SCENARIO="native_production_guidance_portrait_v1"
const CAPTURE_KIND="native_controlled_production_guidance"
var build=""
var start_snapshot={}
var start_bank={}
var initial_tick=-1
func _initialize(): call_deferred("run")
func check(name,ok): checks.append({"name":name,"pass":bool(ok)})
func settle():
	for i in 4: await process_frame
func tap(p):
	for pressed in [true,false]:
		var event=InputEventScreenTouch.new(); event.position=p; event.index=0; event.pressed=pressed
		input_trace.append({"x":p.x,"y":p.y,"pressed":pressed,"tick":game.tick_count})
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
		"game_tick":game.tick_count,"game_frame_counter":game.frame_counter,"test_mode":game.test_mode,"snapshot":game._snapshot().duplicate(true),"selected":game.selected.duplicate(),"commands":commands_data(),"bank":game.economy.bank_milli(0).duplicate(true),"producer_queue":keep.queue.duplicate(true),"input_count":input_trace.size(),"touch_command":game.touch_command,
		"animation_poses":[{"node":".","snapshot":game.visual_evidence_snapshot()}],
		"camera":{"focus":v3(game.camera_focus),"zoom":game.camera_zoom,"projection":game.camera.projection,"keep_aspect":game.camera.keep_aspect,"size":game.camera.size,"near":game.camera.near,"far":game.camera.far,"transform":xform(game.camera.global_transform)},
		"hud":{"selection_title":label_data(game.selection_title),"detail":label_data(game.selection_detail),"queue":label_data(game.queue_label),"toast":label_data(game.toast_label),"bottom_rect":rect_data(game.hud_bottom),"top_rect":rect_data(game.hud_top),"unit_tools_visible":game.compact_unit_tools.is_visible_in_tree(),"command_visible":game.touch_button.is_visible_in_tree(),"command_rect":rect_data(game.touch_button),"actions":actions_data(),"action_scroll_rect":rect_data(game.action_scroll),"action_scroll_horizontal":game.action_scroll.scroll_horizontal},
		"scope":"frozen simulation and synthetic completed queue; routed native ScreenTouch, not natural production or physical phone"}
	var sidecar=FileAccess.open(path+".json",FileAccess.WRITE)
	if sidecar==null: quit(2); return
	sidecar.store_string(JSON.stringify(record,"  ")+"\n");sidecar.close()
	captures.append(record)
	print("PRODUCTION_FRAME ",label," tick=",game.tick_count," inputs=",input_trace.size())
func run():
	var args=OS.get_cmdline_user_args()
	if args.size()!=4 or args[1]!=EXPECTED_BUILD or args[2]!="390" or args[3]!="844" or DisplayServer.get_name()!="X11":
		push_error("Unbound production source or fixed portrait renderer");quit(2);return
	destination=args[0];build=args[1]
	root.size=Vector2i(390,844);root.content_scale_factor=1.0
	game=load("res://main.tscn").instantiate();root.add_child(game);game.test_mode=true
	if game.Rules.BUILD_ID!=build: quit(2);return
	await settle()
	check("fixed portrait logical viewport",root.get_visible_rect().size==Vector2(390,844))
	initial_tick=game.tick_count;start_snapshot=game._snapshot().duplicate(true);start_bank=game.economy.bank_milli(0).duplicate(true)
	var start_tick=game.tick_count
	# _ready preselects the keep; first select a different unit by touch.
	var initial_worker={}; var initial_point=Vector2.INF
	for record in game.faction_views[0].records().values():
		if record.owned and record.kind=="villager":
			var point=find_point(record.id)
			if point!=Vector2.INF: initial_worker=record; initial_point=point; break
	check("initial worker target exists",not initial_worker.is_empty())
	if not initial_worker.is_empty():
		await tap(initial_point)
		check("initial routed touch changes keep selection to worker",game.selected==[initial_worker.id])
	var keep=game._first(0,"town_center")
	var keep_point=find_point(keep.id); check("producer touch target exists",keep_point!=Vector2.INF)
	if keep_point!=Vector2.INF: await tap(keep_point)
	check("routed touch selects producer",game.selected==[keep.id])
	check("producer waiting guidance",game.selection_detail.text.contains("新單位在出口待命"))
	check("no producer command controls",not game.compact_unit_tools.visible)
	await capture("producer_selected")
	var ground=find_point(-1); check("ground target exists",ground!=Vector2.INF)
	if ground!=Vector2.INF:
		var before=game.commands.duplicate(true)
		var queue_before=keep.queue.duplicate(true)
		var bank_before=game.economy.bank_milli(0).duplicate(true)
		await tap(ground)
		check("touch gives building-specific guidance",game.toast_label.text.begins_with("已選取建築"))
		check("touch preserves selection and queued commands",game.selected==[keep.id] and game.commands==before and not game.touch_command)
		check("no accidental recruitment or payment",keep.queue==queue_before and game.economy.bank_milli(0)==bank_before)
		await capture("producer_ground_hint")
	# Controlled HUD fixture: not a paid-production, natural congestion or routing test.
	var original=keep.queue.duplicate(true)
	keep.queue=[{"remaining_ticks":0}]; game._publish_faction_views(); game._update_hud()
	check("ready exit guidance actionable",game.queue_label.text.contains("選取門口單位，再按指令移開"))
	await capture("synthetic_blocked_queue")
	keep.queue=original; game._publish_faction_views(); game._update_hud()
	var worker={}; var worker_point=Vector2.INF
	for record in game.faction_views[0].records().values():
		if record.owned and record.kind=="villager":
			var point=find_point(record.id)
			if point!=Vector2.INF: worker=record; worker_point=point; break
	check("visible worker touch target exists",not worker.is_empty())
	if not worker.is_empty():
		await tap(worker_point)
		check("routed touch selects worker",game.selected==[worker.id])
		ground=find_point(-1)
		if ground!=Vector2.INF:
			var count=game.commands.size()
			await tap(ground)
			check("unit guidance retained without implicit order",game.toast_label.text.begins_with("先按下方指令") and game.commands.size()==count and game.selected==[worker.id])
			check("unit command button visible and in viewport",game.touch_button.is_visible_in_tree() and root.get_visible_rect().encloses(game.touch_button.get_global_rect()))
			await tap(game.touch_button.get_global_rect().get_center())
			check("routed command button enters targeting",game.touch_command)
			await tap(ground)
			check("routed ground tap submits one move",game.commands.size()==count+1 and game.commands.back().type=="order" and game.commands.back().target==-1 and game.commands.back().ids==[worker.id] and not game.touch_command)
			await capture("unit_move_submitted")
	check("test mode blocks all simulation ticks",game.test_mode and game.tick_count==start_tick)
	var failed=0
	for item in checks:
		if not item.pass: failed+=1
	var output=FileAccess.open(destination.path_join("capture-report.json"),FileAccess.WRITE)
	if output==null: quit(2);return
	output.store_string(JSON.stringify({"passed":failed==0,"build":build,"scope":"frozen native ScreenTouch and synthetic queue UI; not production replay or physical phone","scenario":SCENARIO,"frame_count":captures.size(),"frames":captures,"fixed_fps":20,"checks":checks,"failed":failed,"inputs":input_trace,"producer_id":keep.id,"worker_id":worker.get("id",-1),"initial_worker_id":initial_worker.get("id",-1),"initial_tick":initial_tick,"initial_snapshot":start_snapshot,"initial_bank":start_bank,"final_commands":commands_data(),"final_queue":keep.queue.duplicate(true),"final_bank":game.economy.bank_milli(0).duplicate(true),"final_tick":game.tick_count},"  ")+"\n");output.close()
	quit(0 if failed==0 else 1)

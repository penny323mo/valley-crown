extends SceneTree
## Ordinary seeded game; only viewport-routed synthetic touch changes player intent.
## No reset, direct commands, authority ticks, camera edits or resource grants.
const SCENARIO := "native_routed_touch_gather_build_v1"
const EXPECTED_BUILD := "vc-c7211e1083c8"
var game
var destination: String
var records: Array = []
var events: Array = []
var actions: Array = []
var observations: Array = []
var failed := false
var worker_id := -1
var resource_id := -1
var house_id := -1
var deposit_start := 0.0
var house_ids: Array = []
var confirm_bank: Dictionary = {}
var plot := Vector3.ZERO

func _initialize(): call_deferred("run")
func require_ok(ok: bool, message: String) -> bool:
	if not ok:
		failed = true; push_error(message); quit(1)
	return ok
func settle(count: int = 4):
	for index in count: await process_frame
func observed() -> Dictionary: return game.faction_views[0].records()
func public_state() -> Dictionary: return game._snapshot().duplicate(true)
func running() -> bool:
	return not failed and not game.test_mode and game.ai_enabled and not game.paused and not game.game_over and game.application_focused and not game.application_suspended
func screen(record: Dictionary) -> Vector2:
	return game.camera.unproject_position(record.pos + Vector3(0,0.6 if record.category=="unit" else 1.0,0))
func pickable(record: Dictionary, resources: bool) -> bool:
	var point: Vector2 = screen(record)
	return game._box_point_in_world(point) and game._pick(point,resources)==record.id
func choose_worker() -> Dictionary:
	for record in observed().values():
		if record.owned and record.kind=="villager" and record.alive and pickable(record,false): return record
	return {}
func choose_wood(worker: Dictionary) -> Dictionary:
	var chosen: Dictionary = {}; var distance := INF
	for record in observed().values():
		if record.kind not in ["pine","oak"] or record.get("remembered",false) or not record.alive or not pickable(record,true): continue
		var candidate: float = worker.pos.distance_to(record.pos)
		if candidate<distance: distance=candidate; chosen=record
	return chosen
func pose_evidence() -> Array:
	return [{"node":".","snapshot":game.visual_evidence_snapshot()}]
func worker_pose() -> Dictionary:
	return game.visual_evidence_snapshot().get("live",{}).get(str(worker_id),{})
func rect_values(rect: Rect2) -> Array: return [rect.position.x,rect.position.y,rect.size.x,rect.size.y]
func widget(button: Button) -> Dictionary:
	if not is_instance_valid(button): return {}
	return {"text":button.text,"rect":rect_values(button.get_global_rect()),"visible":button.is_visible_in_tree(),"disabled":button.disabled}
func current_site() -> Dictionary:
	for record in observed().values():
		if record.owned and record.kind=="house" and record.id not in house_ids: return record
	return {}

func route_touch(point: Vector2, pressed: bool, role: String):
	var event := InputEventScreenTouch.new()
	event.position=point; event.index=0; event.pressed=pressed; event.canceled=false
	events.append({"sequence":events.size(),"type":"InputEventScreenTouch","role":role,"position":[point.x,point.y],"pressed":pressed,"index":0,"canceled":false,"tick":game.tick_count,"process_frame":Engine.get_process_frames()})
	root.push_input(event,false)
func tap(point: Vector2, role: String, target_id: int = -1, control: Dictionary = {}):
	if not require_ok(root.get_visible_rect().has_point(point) and running(),"Touch point or normal running state invalid"): return
	var before: Dictionary = public_state(); var first: int = events.size()
	route_touch(point,true,role); await process_frame
	route_touch(point,false,role)
	actions.append({"kind":"tap","role":role,"target_id":target_id,"widget":control,"events":[first,events.size()-1],"before":before,"after":public_state()})
	await settle()
	require_ok(game.all_touch_ids.is_empty() and game.touch_points.is_empty(),"Touch stream did not finish")
func tap_button(button: Button, role: String):
	if not require_ok(is_instance_valid(button) and button.is_visible_in_tree() and not button.disabled and root.get_visible_rect().encloses(button.get_global_rect()) and button.size.x>=44 and button.size.y>=44,"Visible touch button missing or clipped"): return
	await tap(button.get_global_rect().get_center(),role,-1,widget(button))
func find_house_button() -> Button:
	for button in game.ui.find_children("*","Button",true,false):
		if button.text.begins_with("民居") and button.is_visible_in_tree(): return button
	return null
func reveal_house(button: Button) -> bool:
	for attempt in 5:
		var area: Rect2 = game.action_scroll.get_global_rect()
		if area.encloses(button.get_global_rect()): return true
		var point: Vector2 = area.position+Vector2(area.size.x-12,area.size.y/2)
		var end: Vector2 = point-Vector2(minf(110,area.size.x-24),0)
		route_touch(point,true,"reveal-house"); await process_frame
		var event := InputEventScreenDrag.new(); event.position=end; event.relative=end-point; event.index=0
		events.append({"sequence":events.size(),"type":"InputEventScreenDrag","role":"reveal-house","position":[end.x,end.y],"relative":[end.x-point.x,end.y-point.y],"index":0,"tick":game.tick_count,"process_frame":Engine.get_process_frames()})
		root.push_input(event,false); route_touch(end,false,"reveal-house"); await settle()
	return game.action_scroll.get_global_rect().encloses(button.get_global_rect())

func note_carry():
	if not observations.is_empty(): return
	var worker: Dictionary = observed().get(worker_id,{})
	if worker.get("carry",0)>0 and worker.get("carry_type","")=="wood":
		observations.append({"stage":"carry-observed","tick":game.tick_count,"worker_id":worker_id,"state":worker.state,"carry":worker.carry,"carry_type":worker.carry_type,"snapshot":public_state()})
func await_stage(stage: String, maximum_frames: int) -> bool:
	for index in maximum_frames:
		await process_frame
		if not running(): return false
		note_carry()
		var worker: Dictionary = observed().get(worker_id,{})
		var site: Dictionary = current_site()
		var pose: Dictionary = worker_pose()
		if stage=="wood" and worker.get("state","")=="gather" and worker.get("target",-1)==resource_id and pose.get("clip","")=="gather_wood": return true
		if stage=="deposit" and public_state().delivered>deposit_start and not observations.is_empty(): return true
		if stage=="site" and not site.is_empty() and not site.built: house_id=site.id; return true
		if stage=="construction" and not site.is_empty() and site.id==house_id and not site.built and site.progress>0 and worker.get("state","")=="build" and worker.get("target",-1)==house_id and pose.get("clip","")=="build": return true
		if stage=="complete" and not site.is_empty() and site.id==house_id and site.built: return true
	return false

func capture(label: String):
	await RenderingServer.frame_post_draw
	if not require_ok(running() and DisplayServer.get_name()=="X11","Capture requires the normal native running scene"): return
	var image: Image = root.get_texture().get_image()
	if not require_ok(image!=null and not image.is_empty() and image.get_size()==Vector2i(390,844),"Invalid real phone framebuffer"): return
	var name := "%03d-%s.png" % [records.size(),label]
	var path: String = destination.path_join(name)
	if not require_ok(image.save_png(path)==OK,"Cannot save raw framebuffer"): return
	var own: Array = []; var buildings: Array = []
	for record in observed().values():
		if not record.owned: continue
		if record.category=="unit": own.append({"id":record.id,"kind":record.kind,"state":record.state,"target":record.target,"position":[record.pos.x,record.pos.y,record.pos.z],"carry":record.carry,"carry_type":record.carry_type,"path_points":record.path.size()})
		if record.category=="building": buildings.append({"id":record.id,"kind":record.kind,"built":record.built,"progress":record.progress,"hp":record.hp,"position":[record.pos.x,record.pos.y,record.pos.z]})
	var frame := {"image":name,"image_sha256":FileAccess.get_sha256(path),"capture_kind":"genuine_native_game_viewport","scenario":SCENARIO,"label":label,
		"utc":Time.get_datetime_string_from_system(true,true),"unix_time":Time.get_unix_time_from_system(),"monotonic_usec":Time.get_ticks_usec(),"process_frame":Engine.get_process_frames(),
		"build":game.Rules.BUILD_ID,"game_sha256":FileAccess.get_sha256("res://scripts/game.gd"),"rules_sha256":FileAccess.get_sha256("res://scripts/rules.gd"),
		"engine":Engine.get_version_info(),"display":DisplayServer.get_name(),"rendering_method":RenderingServer.get_current_rendering_method(),"rendering_driver":RenderingServer.get_current_rendering_driver_name(),"adapter_name":RenderingServer.get_video_adapter_name(),"adapter_vendor":RenderingServer.get_video_adapter_vendor(),
		"framebuffer":[390,844],"logical_viewport":[root.get_visible_rect().size.x,root.get_visible_rect().size.y],"content_scale_factor":root.content_scale_factor,
		"game_tick":game.tick_count,"game_seconds":game.game_time,"camera_focus":[game.camera_focus.x,game.camera_focus.y,game.camera_focus.z],"camera_zoom":game.camera_zoom,
		"test_mode":game.test_mode,"ai_enabled":game.ai_enabled,"selected":game.selected.duplicate(),"economy_audit_ok":game.economy.audit().ok,"snapshot":public_state(),
		"own_units":own,"own_buildings":buildings,"animation_poses":pose_evidence(),"input_event_count":events.size(),
		"ui":{"toast":game.toast_label.text,"toast_visible":game.toast_label.is_visible_in_tree(),"touch_command":game.touch_command,"build_mode":game.build_mode,"held":game.build_preview_held,"placement_ok":game.placement_ok,"confirm":widget(game.build_confirm),"pointer_world":[game.pointer_world.x,game.pointer_world.y,game.pointer_world.z],"preview_position":[game.ghost.position.x,game.ghost.position.y,game.ghost.position.z] if is_instance_valid(game.ghost) else []},
		"limitations":["Synthesized viewport-routed native ScreenTouch, not physical iPhone or Web","Normal game process at fixed engine delta, not performance evidence","Known gray atlas/material defect remains","No defeat or restart coverage in this slice"]}
	records.append(frame)
	var file := FileAccess.open(path+".json",FileAccess.WRITE)
	if not require_ok(file!=null,"Cannot save touch frame provenance"): return
	file.store_string(JSON.stringify(frame,"  ")+"\n"); file.close(); print("NATIVE_FRAME ",name)

func run():
	var args := OS.get_cmdline_user_args()
	if not require_ok(args.size()==4 and args[1]==EXPECTED_BUILD and args[2]=="390" and args[3]=="844","Wrong frozen touch scenario identity or viewport"): return
	destination=args[0]; root.size=Vector2i(390,844); root.content_scale_factor=1.0
	game=load("res://main.tscn").instantiate(); root.add_child(game); await settle(12)
	if not require_ok(game.Rules.BUILD_ID==EXPECTED_BUILD and running(),"Ordinary accepted runtime did not start"): return
	for record in observed().values():
		if record.owned and record.kind=="house": house_ids.append(record.id)
	deposit_start=public_state().delivered
	await capture("opening"); if failed: return
	var worker: Dictionary = choose_worker(); var resource: Dictionary = choose_wood(worker) if not worker.is_empty() else {}
	if not require_ok(not worker.is_empty() and not resource.is_empty(),"Touchable opening worker or visible wood missing"): return
	worker_id=worker.id; resource_id=resource.id
	await tap(screen(worker),"select-worker",worker_id)
	if not require_ok(worker_id in game.selected,"Routed worker touch did not select"): return
	await capture("worker-selected"); if failed: return
	await tap(screen(resource),"target-guidance",resource_id)
	if not require_ok(worker_id in game.selected and not game.touch_command and game.toast_label.text.contains("指令") and actions.back().after.own_pending_commands==0,"Target guidance or explicit-command separation failed"): return
	await capture("target-guidance"); if failed: return
	await tap_button(game.touch_button,"command-button")
	if not require_ok(game.touch_command,"Command button touch did not enter targeting"): return
	await capture("command-mode"); if failed: return
	await tap(screen(resource),"order-wood",resource_id)
	if not require_ok(actions.back().after.own_pending_commands==1 and not game.touch_command,"Resource touch did not queue one ordinary order"): return
	if not require_ok(await await_stage("wood",1800),"Normal touch order did not reach woodcutting"): return
	await capture("woodcutting"); if failed: return
	if not require_ok(await await_stage("deposit",2700),"Normal worker did not carry and deposit wood"): return
	await capture("deposit-complete"); if failed: return
	var house_button: Button = find_house_button()
	if not require_ok(house_button!=null and await reveal_house(house_button),"House action cannot be reached through touch strip"): return
	await tap_button(house_button,"house-button")
	if not require_ok(game.build_mode=="house" and not game.build_preview_held and actions.back().after.own_pending_commands==0,"House action was not preview-only"): return
	plot=game.pointer_world
	var plot_screen: Vector2 = game.camera.unproject_position(plot)
	if not require_ok(game._box_point_in_world(plot_screen),"Suggested public building plot is not visible"): return
	await tap(plot_screen,"hold-building-plot")
	if not require_ok(game.build_preview_held and game.placement_ok and not game.build_confirm.disabled and actions.back().after.own_pending_commands==0,"Legal held preview was not confirmed separately"): return
	plot=game.ghost.position
	await capture("build-preview"); if failed: return
	confirm_bank=public_state().bank_milli.duplicate()
	await tap_button(game.build_confirm,"confirm-build")
	if not require_ok(actions.back().after.own_pending_commands==1 and game.build_mode.is_empty(),"Confirm touch did not queue exactly one build"): return
	if not require_ok(await await_stage("site",180),"Confirmed paid house site was not created"): return
	if not require_ok(public_state().bank_milli.wood==confirm_bank.wood-50000,"House did not pay its exact ordinary wood cost"): return
	await capture("build-confirmed"); if failed: return
	if not require_ok(await await_stage("construction",1800),"Paid site did not reach visible natural construction"): return
	await capture("construction-active"); if failed: return
	if not require_ok(await await_stage("complete",1800),"House did not complete through ordinary construction"): return
	await capture("house-complete"); if failed: return
	var report := {"passed":true,"build":EXPECTED_BUILD,"scenario":SCENARIO,"frame_count":records.size(),"frames":records,"events":events,"actions":actions,"observations":observations,
		"worker_id":worker_id,"resource_id":resource_id,"house_id":house_id,"initial_house_ids":house_ids,"initial_delivered":deposit_start,"confirm_bank_milli":confirm_bank,"plot":[plot.x,plot.y,plot.z],
		"simulation":"Normal seeded game and AI; normal _process with --fixed-fps 30; no test reset or direct authority ticks",
		"not_verified":["physical iPhone","Web/Safari","FPS/performance","all UI flows","victory/defeat/restart","material/visual maturity"]}
	var file := FileAccess.open(destination.path_join("capture-report.json"),FileAccess.WRITE)
	if not require_ok(file!=null,"Cannot save touch sequence report"): return
	file.store_string(JSON.stringify(report,"  ")+"\n"); file.close(); quit(0)

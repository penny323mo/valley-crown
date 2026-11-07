extends SceneTree
# Normal seeded simulation, actual routed native touch. Not physical-phone FPS.
const EXPECTED_BUILD="vc-c9aad346e872"
const SCENARIO="native_ground_rally_portrait_v1"
const CAPTURE_KIND="native_controlled_ground_rally"
var game
var destination=""
var captures=[]
var inputs=[]
var actions=[]
var checks=[]
var producer_id=0
var worker_id=-1
var newborn_id=-1
var target=Vector3.INF
var initial={}
var birth={}
var training={}
var movement=[]
func _initialize():call_deferred("run")
func check(name,ok):
	checks.append({"name":name,"pass":bool(ok)})
	if not bool(ok):push_error("RALLY_CHECK_FAILED "+name)
func settle(count=4):
	for i in count:await process_frame
func v3(v:Vector3):return [v.x,v.y,v.z]
func xform(t:Transform3D):return [v3(t.basis.x),v3(t.basis.y),v3(t.basis.z),v3(t.origin)]
func rect_data(node):
	var r=node.get_global_rect();return [r.position.x,r.position.y,r.size.x,r.size.y]
func label_data(node):return {"text":node.text,"visible":node.is_visible_in_tree(),"rect":rect_data(node),"minimum_size":[node.get_minimum_size().x,node.get_minimum_size().y],"line_count":node.get_line_count()}
func observed():return game.faction_views[0].records()
func producer():return game.faction_views[0].get_record(producer_id)
func rally_data():
	var p:Vector3=producer().get("rally_point",Vector3.INF)
	return v3(p) if p.is_finite() else null
func own_units():
	var result=[]
	for r in observed().values():
		if r.owned and r.alive and r.category=="unit":result.append({"id":r.id,"kind":r.kind,"pos":v3(r.pos),"state":r.state,"mode":r.mode,"target":r.target,"dest":v3(r.dest),"motion_tick":r.get("last_native_motion_tick",-1),"motion_position":v3(r.get("last_native_motion_position",r.pos))})
	result.sort_custom(func(a,b):return a.id<b.id)
	return result
func commands_data():
	var result=[]
	for c in game.commands:
		if c.get("team",-1)!=0:continue
		var row=c.duplicate(true)
		if row.has("position"):row.position=v3(row.position)
		result.append(row)
	return result
func own_spawns():
	var result=[]
	for row in game.spawn_commit_order:
		if row.building==producer_id:result.append(row.duplicate(true))
	return result
func ui_state():
	return {"tick":game.tick_count,"selected":game.selected.duplicate(),"rally_building":game.rally_building,"touch_command":game.touch_command,"rally_point":rally_data(),"bank":game.economy.bank_milli(0).duplicate(true),"queue":producer().queue.duplicate(true),"commands":commands_data()}
func tap(point,action,target_rect=[]):
	var before=ui_state()
	for pressed in [true,false]:
		var e=InputEventScreenTouch.new();e.index=0;e.pressed=pressed;e.position=point
		inputs.append({"action":action,"pressed":pressed,"position":[point.x,point.y],"tick":game.tick_count,"frame":Engine.get_process_frames(),"target_rect":target_rect})
		root.push_input(e,false)
		if not pressed:actions.append({"action":action,"before":before,"after_release":ui_state()})
		await process_frame
	await settle()
func find_button(node,text):
	for child in node.get_children():
		if child is Button and child.text.begins_with(text) and child.is_visible_in_tree():return child
		var found=find_button(child,text)
		if found!=null:return found
	return null
func tap_button(text,action):
	var b=find_button(game.actions,text)
	var okay=b!=null and not b.disabled and b.get_global_rect().size.y>=44 and root.get_visible_rect().encloses(b.get_global_rect()) and game.action_scroll.get_global_rect().encloses(b.get_global_rect())
	check(action+" reachable",okay)
	if not okay:return false
	await tap(b.get_global_rect().get_center(),action,rect_data(b));return true
func find_point(id):
	for y in range(90,680,8):
		for x in range(16,374,8):
			var p=Vector2(x,y)
			if game._box_point_in_world(p) and game._pick(p,false)==id:return p
	return Vector2.INF
func find_ground():
	# Read only faction-visible empty cells in the current camera's foreground.
	var anchor:Vector2=game.camera.unproject_position(producer().pos)
	for y in range(int(anchor.y)+70,int(game.hud_bottom.position.y)-20,12):
		for x in range(70,330,12):
			var screen=Vector2(x,y)
			if not game._box_point_in_world(screen) or game._pick(screen,true)>=0:continue
			var p=game._point(game._cell(game._world_at(screen)))
			var distance=p.distance_to(producer().pos)
			if distance<4 or distance>7 or game.visible_cells[0][game._cell_index(p)]==0 or game.work_memory[0].grid.is_point_solid(game._cell(p)):continue
			var occupied=false
			for r in observed().values():
				if r.alive and r.category=="unit" and r.pos.distance_to(p)<1:occupied=true
			var exact:Vector2=game.camera.unproject_position(p)
			if not occupied and game._box_point_in_world(exact) and game._pick(exact,true)<0:return p
	return Vector3.INF
func newborn_screen():
	if newborn_id<0:return null
	var p:Vector2=game.camera.unproject_position(game.faction_views[0].get_record(newborn_id).pos)
	return [p.x,p.y]
func actions_data():
	var result=[]
	for b in game.actions.get_children():
		if b is Button:result.append({"text":b.text,"rect":rect_data(b),"visible":b.is_visible_in_tree(),"disabled":b.disabled})
	return result
func capture(label):
	await settle();await RenderingServer.frame_post_draw
	var image:Image=root.get_texture().get_image();var name="%03d-%s.png"%[captures.size(),label.replace("_","-")];var path=destination.path_join(name)
	var saved=image!=null and not image.is_empty() and image.get_size()==Vector2i(390,844) and image.save_png(path)==OK
	check(label+" raw screenshot saved",saved)
	if not saved:return
	var f={"label":label,"image":name,"image_sha256":FileAccess.get_sha256(path),"capture_kind":CAPTURE_KIND,"scenario":SCENARIO,"build":game.Rules.BUILD_ID,"version":game.Rules.VERSION,"game_sha256":FileAccess.get_sha256("res://scripts/game.gd"),"rules_sha256":FileAccess.get_sha256("res://scripts/rules.gd"),"engine":Engine.get_version_info(),"display":DisplayServer.get_name(),"rendering_method":RenderingServer.get_current_rendering_method(),"rendering_driver":RenderingServer.get_current_rendering_driver_name(),"adapter_name":RenderingServer.get_video_adapter_name(),"adapter_vendor":RenderingServer.get_video_adapter_vendor(),"utc":Time.get_datetime_string_from_system(true,true),"unix_time":Time.get_unix_time_from_system(),"monotonic_usec":Time.get_ticks_usec(),"process_frame":Engine.get_process_frames(),"fixed_fps":20,"observed_process_delta_seconds":game.get_process_delta_time(),"framebuffer":[390,844],"logical_viewport":[root.get_visible_rect().size.x,root.get_visible_rect().size.y],"content_scale_factor":root.content_scale_factor,"test_mode":game.test_mode,"snapshot":game._snapshot().duplicate(true),"ui_state":ui_state(),"own_units":own_units(),"input_count":inputs.size(),"newborn_screen":newborn_screen(),"marker":{"visible":game.order_marker.is_visible_in_tree(),"position":v3(game.order_marker.global_position)},"animation_poses":[{"node":".","snapshot":game.visual_evidence_snapshot()}],"camera":{"focus":v3(game.camera_focus),"zoom":game.camera_zoom,"projection":game.camera.projection,"keep_aspect":game.camera.keep_aspect,"size":game.camera.size,"near":game.camera.near,"far":game.camera.far,"transform":xform(game.camera.global_transform)},"hud":{"title":label_data(game.selection_title),"detail":label_data(game.selection_detail),"queue":label_data(game.queue_label),"toast":label_data(game.toast_label),"bottom_rect":rect_data(game.hud_bottom),"actions":actions_data(),"action_scroll_rect":rect_data(game.action_scroll)}}
	var file=FileAccess.open(path+".json",FileAccess.WRITE);file.store_string(JSON.stringify(f,"  ")+"\n");file.close();captures.append(f)
func run():
	var args=OS.get_cmdline_user_args()
	if args.size()!=4 or args[1]!=EXPECTED_BUILD or args[2]!="390" or args[3]!="844" or DisplayServer.get_name()!="X11":quit(2);return
	destination=args[0];root.size=Vector2i(390,844);root.content_scale_factor=1.0
	game=load("res://main.tscn").instantiate();root.add_child(game)
	if game.Rules.BUILD_ID!=EXPECTED_BUILD:quit(2);return
	await settle();initial={"state":ui_state(),"units":own_units(),"spawn_commits":own_spawns()}
	check("normal seeded initial state",not game.test_mode and game.selected==[0] and initial.units.size()==6 and rally_data()==null and producer().queue.is_empty())
	for r in observed().values():
		if r.owned and r.alive and r.kind=="villager" and find_point(r.id)!=Vector2.INF:worker_id=r.id;break
	check("worker target exists",worker_id>=0)
	if worker_id<0:finish();return
	await tap(find_point(worker_id),"worker_select")
	var point=find_point(producer_id);check("producer target exists",point!=Vector2.INF)
	if point==Vector2.INF:finish();return
	await tap(point,"producer_select");check("producer selected by touch",game.selected==[producer_id])
	if not await tap_button("集合點","rally_enter"):finish();return
	check("explicit rally targeting",game.rally_building==producer_id and game.touch_command and rally_data()==null)
	await capture("rally_targeting")
	target=find_ground();check("visible empty ground exists",target.is_finite())
	if not target.is_finite():finish();return
	await tap(game.camera.unproject_position(target),"rally_target")
	check("rally accepted normally",rally_data()==v3(target) and game.rally_building==-1 and not game.touch_command and commands_data().is_empty())
	await capture("rally_set")
	if not await tap_button("集合點","rally_reenter"):finish();return
	if not await tap_button("取消集合點","rally_cancel"):finish();return
	check("cancel preserves previous rally",rally_data()==v3(target) and game.rally_building==-1 and not game.touch_command and commands_data().is_empty())
	await capture("rally_cancel_preserved")
	if not await tap_button("訓練村民","train"):finish();return
	check("normal paid train queued",producer().queue.size()==1 and game.economy.bank_milli(0).food==initial.state.bank.food-50000)
	if producer().queue.size()!=1:finish();return
	training={"observed_tick":game.tick_count,"queue":producer().queue[0].duplicate(true),"paid_receipt":game.economy.receipt_view(producer().queue[0].receipt_id)}
	for i in 360:
		await process_frame
		for u in own_units():
			var known=false
			for old in initial.units:
				if old.id==u.id:known=true
			if not known:
				newborn_id=u.id;birth={"tick":game.tick_count,"unit":u.duplicate(true),"spawn_commits":own_spawns()};break
		if newborn_id>=0:break
	check("paid newborn observed",newborn_id>=0)
	if newborn_id<0:finish();return
	for i in 30:
		await process_frame
		var u=game.faction_views[0].get_record(newborn_id)
		movement.append({"tick":game.tick_count,"pos":v3(u.pos),"state":u.state,"mode":u.mode,"dest":v3(u.dest),"target":u.target,"motion_tick":u.get("last_native_motion_tick",-1),"motion_position":v3(u.get("last_native_motion_position",u.pos))})
		if u.pos.distance_to(Vector3(birth.unit.pos[0],birth.unit.pos[1],birth.unit.pos[2]))>=0.5 and u.state=="move":break
	var u=game.faction_views[0].get_record(newborn_id)
	check("newborn ordinary move progresses",u.kind=="villager" and u.state=="move" and u.mode=="MOVE" and u.target==-1 and u.pos.distance_to(Vector3(birth.unit.pos[0],birth.unit.pos[1],birth.unit.pos[2]))>=0.5 and u.dest.distance_to(target)<0.01)
	check("original paid receipt fulfilled",game.economy.receipt_view(training.queue.receipt_id).get("state","")=="fulfilled" and producer().queue.is_empty())
	await capture("newborn_rally_move")
	finish()
func finish():
	var failed=0
	for c in checks:
		if not c.pass:failed+=1
	var report={"passed":failed==0,"build":game.Rules.BUILD_ID,"scenario":SCENARIO,"frame_count":captures.size(),"frames":captures,"fixed_fps":20,"checks":checks,"failed":failed,"inputs":inputs,"actions":actions,"worker_id":worker_id,"producer_id":producer_id,"newborn_id":newborn_id,"target":v3(target) if target.is_finite() else null,"initial":initial,"training":training,"final_receipt":game.economy.receipt_view(training.queue.receipt_id) if not training.is_empty() else {},"birth":birth,"movement":movement,"final":ui_state(),"final_units":own_units(),"scope":"normal seeded simulation with routed synthetic native touch; not physical phone or measured frame rate"}
	var f=FileAccess.open(destination.path_join("capture-report.json"),FileAccess.WRITE);f.store_string(JSON.stringify(report,"  ")+"\n");f.close();quit(0 if failed==0 else 1)

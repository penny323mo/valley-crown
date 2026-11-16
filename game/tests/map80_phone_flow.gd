extends SceneTree
# Map80 port of phone_phased_contract.gd; baseline SHA256 93599a82a83fffc6aca507627e78581640c386f9dd66c514c8198f4802840b22
# Prepare only locally. Synthetic native input, not physical-phone/browser acceptance.
var game
var checks=[]
var cases=[]
var dpr=1.0
var journal:FileAccess
var phase="inputs"
func _initialize(): call_deferred("run")
func check(name,ok,detail={}):
	var record={"name":name,"pass":bool(ok),"detail":detail.duplicate(true)}
	checks.append(record)
	print("CHECK ",JSON.stringify(record))
	if journal:
		journal.store_line(JSON.stringify(record));journal.flush()
	if not ok: print("FAIL ",name," ",detail)
func settle(frames=4):
	for i in frames: await process_frame
func touch(p,pressed,index=0):
	# False is intentional: real Web input starts in physical backing pixels.
	var e=InputEventScreenTouch.new();e.position=p*dpr;e.index=index;e.pressed=pressed;root.push_input(e,false)
func tap(p,jitter=Vector2.ZERO):
	touch(p,true); await process_frame
	if jitter!=Vector2.ZERO:
		var e=InputEventScreenDrag.new();e.position=(p+jitter)*dpr;e.relative=jitter*dpr;e.index=0;root.push_input(e,false)
	touch(p+jitter,false);await settle()
func screen(ent): return game.camera.unproject_position(ent.pos+Vector3(0,0.6 if ent.category=="unit" else 1.0,0))
func clear(p): return game._box_point_in_world(p)
func find_button(prefix):
	for b in game.ui.find_children("*","Button",true,false):
		if b.text.begins_with(prefix) and b.is_visible_in_tree():return b
	return null
func visible_worker():
	for ent in game.faction_views[0].records().values():
		if ent.team==0 and ent.kind=="villager" and clear(screen(ent)) and game._pick(screen(ent),false)==ent.id:return ent
	return {}
func resource(kind):
	for ent in game.faction_views[0].records().values():
		if ent.kind in kind and clear(screen(ent)) and game._pick(screen(ent))==ent.id:return ent
	return {}
func advance_until_deposit(limit=1200):
	for i in limit:
		game._tick(game.Rules.TICK)
		if game.delivered_total[0]>0:return i+1
		if i%40==0:await process_frame
	return -1
func advance_until_built(kind,limit=1500):
	for i in limit:
		game._tick(game.Rules.TICK)
		var building=game._first(0,kind)
		if not building.is_empty() and building.built:return i+1
		if i%40==0:await process_frame
	return -1
func reveal_action(button):
	# Reach a hidden build action using actual finger scrolling, not a scrollbar assignment.
	for attempt in 5:
		if game.action_scroll.get_global_rect().encloses(button.get_global_rect()):return true
		var rect=game.action_scroll.get_global_rect();var p=rect.position+Vector2(rect.size.x-12,rect.size.y/2)
		touch(p,true);await process_frame
		var q=p-Vector2(minf(110,rect.size.x-24),0)
		var e=InputEventScreenDrag.new();e.position=q*dpr;e.relative=(q-p)*dpr;e.index=0;root.push_input(e,false)
		touch(q,false);await settle()
	return false
func reset_home():
	game._cancel_mode(); game._test_reset()
	game.camera_focus=game.MapRoutes.home(0); game._camera_update()
	check("Map80 reset frames translated keep",game.camera_focus==Vector3(-25,0,24) and game._first(0,"town_center").pos==game.camera_focus)
func run():
	var args=OS.get_cmdline_user_args()
	if args.size()!=2 or args[1] not in ["inputs","food","wood","house"]:
		push_error("Provide OUTPUT_JSON and one phase: inputs, food, wood, house."); quit(2); return
	phase=args[1]
	journal=FileAccess.open(args[0]+".progress.jsonl",FileAccess.WRITE)
	if journal==null:
		push_error("Output directory must exist before the guarded run."); quit(2); return
	print("PHASE ",phase)
	root.size=Vector2i(390,844);game=load("res://main.tscn").instantiate();root.add_child(game);game.test_mode=true;await settle()
	for css in [Vector2i(390,844),Vector2i(844,390)]:
		for ratio in [3.0]:
			dpr=ratio;root.size=Vector2i(Vector2(css)*dpr);root.content_scale_factor=dpr;await settle()
			var label="Map80 "+str(css)+" DPR"+str(dpr)
			check(label+" logical CSS viewport",root.get_visible_rect().size.is_equal_approx(Vector2(css)),{"logical":str(root.get_visible_rect()),"physical":str(root.size),"transform":str(root.get_final_transform())})
			var resources=[["berry"],["pine","oak"]] if phase=="inputs" else ([["berry"]] if phase=="food" else ([["pine","oak"]] if phase=="wood" else []))
			for resource_kinds in resources:
				reset_home();await settle()
				var worker=visible_worker();var target=resource(resource_kinds)
				check(label+str(resource_kinds)+" initial world targets visible",not worker.is_empty() and not target.is_empty())
				if worker.is_empty() or target.is_empty():continue
				await tap(screen(worker),Vector2(6,0))
				check(label+" six CSS pixel touch selects worker",worker.id in game.selected,{"selected":game.selected})
				check(label+" command always reachable CSS44",game.hud_bottom.get_global_rect().encloses(game.touch_button.get_global_rect()) and root.get_visible_rect().encloses(game.touch_button.get_global_rect()) and game.touch_button.size.x>=44 and game.touch_button.size.y>=44 and not game.action_scroll.is_ancestor_of(game.touch_button),{"command":str(game.touch_button.get_global_rect())})
				await tap(screen(target))
				check(label+" natural target tap guides without losing selection or ordering",worker.id in game.selected and game.commands.is_empty() and game.toast_label.text.contains("指令"),{"selection":game.selected,"message":game.toast_label.text})
				await tap(game.touch_button.get_global_rect().get_center(),Vector2(6,0))
				check(label+" command touch enters targeting",game.touch_command and game.compact_cancel_button.visible)
				check(label+" cancel always reachable",root.get_visible_rect().encloses(game.compact_cancel_button.get_global_rect()))
				var p=screen(target);await tap(p)
				check(label+" physical input maps to logical resource command",game.commands.size()==1 and game.commands[0].target==target.id and game.pointer_screen.distance_to(p)<0.01,{"commands":game.commands,"pointer":str(game.pointer_screen),"expected":str(p)})
				if phase=="inputs":continue
				var ticks=await advance_until_deposit()
				check(label+str(resource_kinds)+" actual gather carry deposit",ticks>0 and game.delivered_total[0]>0 and game.economy.audit().ok,{"ticks":ticks,"delivered":game.delivered_total[0],"bank":game.stocks[0]})
				cases.append({"case":label,"resource":resource_kinds,"deposit_ticks":ticks})
			if phase!="house":continue
			# Independent normal opening fixture for build: no gifts, moves or resource edits.
			reset_home();await settle();var worker=visible_worker()
			check(label+" home worker touchable for house",not worker.is_empty())
			if worker.is_empty():continue
			await tap(screen(worker));var button=find_button("民居")
			check(label+" building accessible through touch strip",button!=null and await reveal_action(button))
			if button==null:continue
			await tap(button.get_global_rect().get_center())
			check(label+" build tap enters preview only",game.build_mode=="house" and not game.build_preview_held and game.commands.is_empty() and game.stocks[0].wood==200)
			var plot=game.pointer_world if game._placement_reason("house",game.pointer_world,0,worker.id).is_empty() and clear(game.camera.unproject_position(game.pointer_world)) else Vector3.INF
			check(label+" legal visible building plot exists",plot!=Vector3.INF)
			if plot==Vector3.INF:continue
			var p=game.camera.unproject_position(plot);await tap(p)
			check(label+" touch selects valid green preview",game.build_preview_held and game.placement_ok and not game.build_confirm.disabled and game._world_at(p).distance_to(plot)<0.01 and game.commands.is_empty(),{"plot":str(plot),"pointer":str(game.pointer_world),"reason":game.selection_detail.text})
			var cancel=find_button("取消建造")
			check(label+" confirm cancel separation",cancel!=null and cancel.get_global_rect().position.x-game.build_confirm.get_global_rect().end.x>=8)
			await tap(game.build_confirm.get_global_rect().get_center())
			check(label+" explicit confirm queues one build",game.commands.size()==1 and game.commands[0].type=="build" and game.stocks[0].wood==200)
			var ticks=await advance_until_built("house")
			check(label+" paid house finishes normally",ticks>0 and game._count(0,"house")==1 and game.stocks[0].wood==150 and game.economy.audit().ok,{"ticks":ticks,"bank":game.stocks[0]})
	var failed=checks.filter(func(c):return not c.pass).size()
	var report={"phase":phase,"build":game.Rules.BUILD_ID,"source_sha256":FileAccess.get_sha256("res://scripts/game.gd"),"passed":checks.size()-failed,"failed":failed,"checks":checks,"cases":cases,"scope":"Map80 translated-home native routed physical-coordinate ScreenTouch at portrait/landscape DPR3; normal deterministic authority ticks. Not browser/physical-phone validation."}
	FileAccess.open(OS.get_cmdline_user_args()[0],FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("PHONE_FLOW_CONTRACT ",checks.size()-failed,"/",checks.size());quit(0 if failed==0 else 1)

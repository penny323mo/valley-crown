extends SceneTree
# Routed synthetic touch on actual game HUD, not physical-device acceptance.
var game
var checks=[]
func _initialize(): call_deferred("run")
func check(label,ok):
	checks.append({"name":label,"passed":bool(ok)})
	if not ok: push_error(label)
func settle():
	for i in 4: await process_frame
func touch(point,pressed,index=0,canceled=false):
	var event=InputEventScreenTouch.new(); event.position=point; event.index=index; event.pressed=pressed; event.canceled=canceled
	root.push_input(event,false)
func drag(point,relative,index=0):
	var event=InputEventScreenDrag.new(); event.position=point; event.relative=relative; event.index=index
	root.push_input(event,false)
func tap(point):
	touch(point,true); await process_frame; touch(point,false); await settle()
func run():
	root.size=Vector2i(390,844)
	game=load("res://main.tscn").instantiate(); root.add_child(game)
	game.set_process(false); game.test_mode=true; game._test_reset(); await settle()
	var worker=game._first(0,"villager")
	game._select([worker.id]); await settle()
	check("villager exposes building actions directly",game.actions.get_children().any(func(b): return b is Button and b.text.begins_with("民居\n")))
	var point=Vector2.ZERO
	for y in range(180,460,25):
		for x in range(45,345,25):
			var candidate=Vector2(x,y)
			if game._pick(candidate)<0: point=candidate; break
		if point!=Vector2.ZERO: break
	check("empty world point available",point!=Vector2.ZERO)
	if point==Vector2.ZERO: finish(); return
	await tap(point)
	check("one normal touch queues one move without command button",game.commands.size()==1 and game.commands[0].type=="order" and game.commands[0].target==-1 and game.commands[0].ids==[worker.id] and game.selected==[worker.id] and not game.touch_command)
	game.commands.clear()
	touch(point,true); drag(point+Vector2(35,0),Vector2(35,0)); drag(point,Vector2(-35,0)); touch(point,false); await settle()
	check("drag returning to origin cannot leak order",game.commands.is_empty() and game.selected==[worker.id])
	touch(point,true); touch(point+Vector2(50,0),true,1); touch(point+Vector2(50,0),false,1); touch(point,false); await settle()
	check("pinch final finger cannot leak order",game.commands.is_empty())
	touch(point,true); touch(point,false,0,true); await settle()
	check("canceled release cannot order",game.commands.is_empty())
	touch(point,true); game._select([worker.id]); touch(point,false); await settle()
	check("selection change retires held world press",game.commands.is_empty())
	touch(point,true); game._submit_selected_stance("stop"); touch(point,false); await settle()
	check("Stop retires normal held world press",game.commands.size()==1 and game.commands[0].type=="stop")
	game.commands.clear()
	var clear=null
	for b in game.actions.get_children():
		if b is Button and b.text=="取消選取": clear=b
	check("separate clear selection control exists",is_instance_valid(clear))
	if is_instance_valid(clear): clear.pressed.emit()
	check("clear selection does not stop or move",game.selected.is_empty() and game.commands.is_empty())
	await check_action_scroll_release()
	finish()
func check_action_scroll_release():
	# Separate controlled setup after the ten original contextual checks.
	game._test_reset(); await settle()
	var keep=game._first(0,"town_center")
	var worker=game._first(0,"villager")
	game._select([keep.id]); await settle()
	var train=null
	var scout=null
	for button in game.actions.get_children():
		if button is Button and button.text.begins_with("訓練村民\n"): train=button
		if button is Button and button.text.begins_with("訓練斥候\n"): scout=button
	var worker_point=game.camera.unproject_position(worker.pos+Vector3(0,0.6,0))
	var fixture=is_instance_valid(train) and is_instance_valid(scout) and game._box_point_in_world(worker_point) and game._pick(worker_point)==worker.id
	if fixture: fixture=game.action_scroll.get_global_rect().encloses(train.get_global_rect()) and game.action_scroll.get_global_rect().encloses(scout.get_global_rect())
	check("actual producer controls and worker are visible",fixture)
	if not fixture: return
	var bank_before=game.economy.bank_milli(0).duplicate(true)
	var population_before=game._population(0)
	await tap(train.get_global_rect().get_center())
	check("ordinary train tap queues exactly one villager command",game.commands.size()==1 and game.commands[0].type=="train" and game.commands[0].kind=="villager")
	game._tick(game.Rules.TICK); game._update_hud(); await settle()
	var bank=game.economy.bank_milli(0).duplicate(true)
	var population=game._population(0)
	check("ordinary training command pays and reserves population",bank.food==bank_before.food-50000 and population==population_before+1 and keep.queue.size()==1 and keep.queue[0].kind=="villager" and game.commands.is_empty())
	# Queue rebuild replaced controls. Start on an actual visible producer button.
	scout=null
	for button in game.actions.get_children():
		if button is Button and button.text.begins_with("訓練斥候\n"): scout=button
	if not is_instance_valid(scout): return
	var start=scout.get_global_rect().get_center()
	var end=start-Vector2(216,0)
	var offset=game.action_scroll.scroll_horizontal
	var queue=keep.queue.duplicate(true)
	touch(start,true); await process_frame
	for step in range(1,7):
		drag(start+(end-start)*float(step)/6.0,(end-start)/6.0); await process_frame
	touch(end,false); await settle()
	check("actual routed producer swipe scrolls the action strip",game.action_scroll.scroll_horizontal==offset+216)
	check("swipe emits no button or world command",game.commands.is_empty() and keep.queue==queue and game.economy.bank_milli(0)==bank and game._population(0)==population and game.selected==[keep.id] and game.build_mode.is_empty() and not game.touch_command)
	check("swipe retires game-owned pointer state",game.all_touch_ids.is_empty() and game.touch_points.is_empty() and game.gui_touch_press.is_empty() and game.action_touch_scroll.is_empty() and not game.touch_gesture)
	# No mode/selection/scroll setter, reset, or second tap may repair the stream.
	# This very first reused-index world press/release must reach ordinary _tap.
	await tap(worker_point)
	check("first same-index world tap after swipe selects worker",game.selected==[worker.id])
	check("first worker selection emits no command or economic change",game.commands.is_empty() and keep.queue==queue and game.economy.bank_milli(0)==bank and game._population(0)==population and not game.touch_command and game.build_mode.is_empty())
	# Independent controlled starting selections/scroll positions, only before
	# each case. Never repair state between a tested release and first world tap.
	game._select([keep.id]); await settle()
	await tap(worker_point)
	check("tap without a preceding swipe selects worker",game.selected==[worker.id])
	check("tap without swipe emits no command",game.commands.is_empty() and keep.queue==queue and game.economy.bank_milli(0)==bank)
	game._select([keep.id]); game.action_scroll.scroll_horizontal=0; await settle()
	var canceled_start=Vector2(312,game.action_scroll.get_global_rect().get_center().y)
	var canceled_end=canceled_start-Vector2(216,0)
	touch(canceled_start,true); await process_frame
	drag(canceled_end,canceled_end-canceled_start); await process_frame
	touch(canceled_end,false,0,true); await settle()
	check("canceled active swipe cannot activate old button or world order",game.commands.is_empty() and keep.queue==queue and game.selected==[keep.id] and game.economy.bank_milli(0)==bank and game.build_mode.is_empty() and not game.touch_command)
	await tap(worker_point)
	check("first world tap after canceled swipe selects worker",game.selected==[worker.id])
	check("canceled swipe and next tap leave no pointer ownership",game.all_touch_ids.is_empty() and game.touch_points.is_empty() and game.gui_touch_press.is_empty() and game.action_touch_scroll.is_empty() and game.commands.is_empty())
	game._select([keep.id]); game.action_scroll.scroll_horizontal=0; await settle()
	# Back-to-back ordinary gestures on real producer buttons, same touch ID.
	# First starts on Scout at x312; after 216px scroll Scout is at x36..156.
	var repeated_y=game.action_scroll.get_global_rect().get_center().y
	for pair in [[Vector2(312,repeated_y),Vector2(96,repeated_y)],[Vector2(96,repeated_y),Vector2(312,repeated_y)]]:
		touch(pair[0],true); await process_frame
		for step in range(1,7):
			drag(pair[0]+(pair[1]-pair[0])*float(step)/6.0,(pair[1]-pair[0])/6.0); await process_frame
		touch(pair[1],false); await settle()
	check("repeated swipes return strip without any old button command",game.action_scroll.scroll_horizontal==0 and game.commands.is_empty() and keep.queue==queue and game.selected==[keep.id] and game.economy.bank_milli(0)==bank and not game.touch_command and game.build_mode.is_empty())
	await tap(worker_point)
	check("first world tap after repeated swipes selects worker",game.selected==[worker.id])
	check("repeated gestures leave no pointer or command residue",game.all_touch_ids.is_empty() and game.touch_points.is_empty() and game.gui_touch_press.is_empty() and game.action_touch_scroll.is_empty() and game.commands.is_empty() and keep.queue==queue)
func finish():
	print("CONTEXTUAL_TOUCH_PHONE "+JSON.stringify(checks))
	quit(0 if checks.size()==26 and checks.all(func(c): return c.passed) else 1)

extends SceneTree
# Actual HUD layout and routed synthetic input over controlled selections.
# Pending guarded engine execution; not browser pixels or physical-iPhone QA.
var game
var checks=[]
var events=0
func _initialize(): call_deferred("run")
func check(label,ok):
	checks.append({"name":label,"passed":bool(ok)})
	if not ok: push_error(label)
func settle():
	for i in 4: await process_frame
func touch(point,pressed,index=0,canceled=false):
	var event=InputEventScreenTouch.new(); event.position=point; event.index=index; event.pressed=pressed; event.canceled=canceled
	root.push_input(event,false); events+=1
func tap(point):
	touch(point,true); await process_frame; touch(point,false); await settle()
func mouse(point,pressed):
	var event=InputEventMouseButton.new(); event.position=point; event.button_index=MOUSE_BUTTON_LEFT; event.pressed=pressed
	root.push_input(event,false); events+=1
func action(prefix):
	for button in game.actions.get_children():
		if button is Button and button.text.begins_with(prefix): return button
	return null
func visible(button):
	return is_instance_valid(button) and button.is_visible_in_tree() and root.get_visible_rect().encloses(button.get_global_rect())
func reset():
	game._cancel_mode(); game._test_reset(); game._home(); game._update_hud(); await settle()
func run():
	root.size=Vector2i(390,844)
	game=load("res://main.tscn").instantiate(); root.add_child(game)
	game.set_process(false); game.test_mode=true; game._test_reset(); await settle()
	for size in [Vector2i(320,640),Vector2i(390,844),Vector2i(844,390)]:
		root.size=size; await settle(); await reset()
		var worker=game._first(0,"villager")
		game._select([worker.id]); await settle()
		var label="%dx%d" % [size.x,size.y]
		var stop_id=game.stop_button.get_instance_id()
		var house=action("民居\n")
		check(label+" Stop visible without scrolling",visible(game.stop_button) and game.stop_button.get_parent()==game.compact_unit_tools and game.action_scroll.scroll_horizontal==0)
		check(label+" full first build target remains reachable",visible(house) and game.action_scroll.get_global_rect().encloses(house.get_global_rect()) and house.size.x>=90)
		check(label+" only two pinned targets",game.compact_unit_tools.get_children().filter(func(child): return child.is_visible_in_tree()).size()==2 and not game.compact_cancel_button.visible)
		var bank=game.economy.bank_milli(0).duplicate()
		await tap(game.stop_button.get_global_rect().get_center())
		check(label+" one tap queues one ordinary Stop",game.commands.size()==1 and game.commands[0].type=="stop" and game.commands[0].ids==[worker.id])
		# Never dereference a cached Control across an awaited action. Check the
		# production lifetime separately, then repeat through the current button.
		check(label+" ordinary Stop preserves live repeat target",visible(game.stop_button) and game.stop_button.get_instance_id()==stop_id)
		if not visible(game.stop_button): finish(); return
		await tap(game.stop_button.get_global_rect().get_center())
		check(label+" repeated tap cannot build or refund",game.commands.size()==2 and game.commands.all(func(command): return command.type=="stop"))
		while not game.commands.is_empty(): game._execute(game.commands.pop_front())
		game._publish_faction_views(); game._update_hud(); await settle()
		check(label+" repeated Stop idles without economy mutation",worker.mode=="STOP" and worker.state=="idle" and game.economy.bank_milli(0)==bank and game.economy.audit().ok)
		await tap(game.touch_button.get_global_rect().get_center())
		check(label+" targeting restores ordinary Cancel slot",game.touch_command and visible(game.compact_cancel_button) and game.stop_button.get_parent()==game.actions)
		await tap(game.compact_cancel_button.get_global_rect().get_center())
		check(label+" Cancel never submits Stop",not game.touch_command and game.commands.is_empty() and game.stop_button.get_parent()==game.compact_unit_tools)
		await tap(action("民居\n").get_global_rect().get_center())
		check(label+" build mode hides pinned unit controls",game.build_mode=="house" and not game.compact_unit_tools.visible and not is_instance_valid(game.stop_button))
		await tap(action("取消建造").get_global_rect().get_center())
		check(label+" build Cancel preserved",game.build_mode.is_empty() and game.commands.is_empty() and visible(game.stop_button))
		game._start_box_select(); await settle()
		check(label+" box mode has original Cancel",not game.compact_unit_tools.visible and not is_instance_valid(game.stop_button) and visible(action("取消框選")))
		await tap(action("取消框選").get_global_rect().get_center())
		check(label+" box Cancel preserved",not game.box_select_mode and game.commands.is_empty())
		var keep=game._first(0,"town_center")
		game._select([keep.id]); game._start_ground_rally(keep.id); await settle()
		check(label+" rally mode has original Cancel",not is_instance_valid(game.stop_button) and visible(action("取消集合點")))
		await tap(action("取消集合點").get_global_rect().get_center())
		check(label+" rally Cancel preserved",game.rally_building<0 and not game.touch_command and game.commands.is_empty())
	root.size=Vector2i(390,844); await settle(); await reset()
	var workers=[]
	for record in game.faction_views[0].records().values():
		if record.owned and record.alive and record.kind=="villager": workers.append(record.id)
	check("two owned workers for selection interruption",workers.size()>=2)
	if workers.size()<2: finish(); return
	game._select([workers[0]]); await settle()
	for source in ["touch","mouse"]:
		game.commands.clear(); game._select([workers[0]]); await settle()
		var old_id=game.stop_button.get_instance_id(); var point=game.stop_button.get_global_rect().get_center()
		if source=="touch": touch(point,true)
		else: mouse(point,true)
		await process_frame
		game._select([workers[1]]); await settle()
		if source=="touch": touch(point,false)
		else: mouse(point,false)
		await settle()
		check(source+" held Stop cannot target replacement selection",game.commands.is_empty() and game.selected==[workers[1]] and game.stop_button.get_instance_id()!=old_id)
	# The ordinary targeting entry cancels the held Stop before showing Cancel.
	game._select([workers[0]]); await settle()
	var point=game.stop_button.get_global_rect().get_center()
	touch(point,true); await process_frame; game._start_unit_command(); await settle()
	touch(point,false); await settle()
	check("held Stop cannot become Cancel after entering targeting",game.touch_command and game.commands.is_empty() and game.compact_cancel_button.visible)
	point=game.compact_cancel_button.get_global_rect().get_center()
	touch(point,true); await process_frame; game._cancel_mode(); await settle()
	touch(point,false); await settle()
	check("held Cancel cannot become Stop after mode cancellation",not game.touch_command and game.commands.is_empty())
	# Controlled same-instance move isolates release ownership independently of
	# the ordinary mode entry, which rebuilds controls and retires all pointers.
	for source in ["touch","mouse"]:
		game._cancel_mode(); await settle()
		var same=game.stop_button; point=same.get_global_rect().get_center()
		if source=="touch": touch(point,true)
		else: mouse(point,true)
		await process_frame
		game.touch_command=true; game._update_hud(); await settle()
		check(source+" same-instance reparent clears held press",game.stop_button==same and game.gui_touch_press.is_empty() and not same.button_pressed)
		if source=="touch": touch(game.compact_cancel_button.get_global_rect().get_center(),false)
		else: mouse(game.compact_cancel_button.get_global_rect().get_center(),false)
		await settle()
		check(source+" same-instance reparent release cannot issue Stop or Cancel",game.commands.is_empty() and game.touch_command)
	game._cancel_mode(); await settle()
	for interruption in ["canceled","multitouch","drag"]:
		point=game.stop_button.get_global_rect().get_center()
		touch(point,true); await process_frame
		if interruption=="multitouch": touch(Vector2(200,400),true,1)
		if interruption=="drag":
			var drag=InputEventScreenDrag.new(); drag.index=0; drag.position=point+Vector2(20,0); drag.relative=Vector2(20,0); root.push_input(drag,false); events+=1
		touch(point,false,0,interruption=="canceled")
		if interruption=="multitouch": touch(Vector2(200,400),false,1)
		await settle(); game._update_hud(); await settle()
		check(interruption+" cannot activate Stop",game.commands.is_empty())
	for blocked in ["paused","game_over"]:
		game.set(blocked,true); game._update_hud(); await settle()
		check(blocked+" disables compact Stop",game.stop_button.disabled)
		await tap(game.stop_button.get_global_rect().get_center())
		check(blocked+" touch cannot submit",game.commands.is_empty())
		game.set(blocked,false); game._update_hud(); await settle()
	point=game.stop_button.get_global_rect().get_center()
	touch(point,true); await process_frame
	game._kill(game._get_entity(workers[0])); game._publish_faction_views(); game._update_hud(); await settle()
	touch(point,false); await settle()
	check("last selected death retires Stop and held release",game.selected.is_empty() and not is_instance_valid(game.stop_button) and game.commands.is_empty())
	game._select([workers[1]]); await settle()
	await tap(game.stop_button.get_global_rect().get_center())
	check("fresh press after interruptions still works",game.commands.size()==1 and game.commands[0].ids==[workers[1]])
	root.size=Vector2i(1280,800); await settle(); game._update_hud(); await settle()
	check("desktop retains original action-strip Stop",not game.compact_ui and game.stop_button.get_parent()==game.actions and visible(game.stop_button))
	finish()
func finish():
	var failed=checks.filter(func(item): return not item.passed).size()
	print(JSON.stringify({"suite":"mobile_stop_control_phone","build":game.Rules.BUILD_ID,"checks":checks,"failed":failed,"input_events":events,"source_sha256":FileAccess.get_sha256("res://scripts/game.gd"),"scope":"Controlled actual HUD geometry and synthetic viewport input; not browser pixels, natural play or physical-iPhone acceptance"}))
	game.free(); quit(1 if failed else 0)

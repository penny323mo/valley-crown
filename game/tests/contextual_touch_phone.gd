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
	finish()
func finish():
	print("CONTEXTUAL_TOUCH_PHONE "+JSON.stringify(checks))
	quit(0 if checks.all(func(c): return c.passed) else 1)

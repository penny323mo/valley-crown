extends SceneTree
# Native routed-touch contract. Synthetic initial selection, real HUD
# buttons, viewport touch dispatch and ordinary queued authority application.
# Not physical-phone, browser/WebGL, frame-rate or full-match acceptance.
var game
var checks=[]
var events=0
func _initialize(): call_deferred("run")
func check(label,ok):
	checks.append({"name":label,"passed":bool(ok)})
	if not ok: push_error(label)
func settle():
	for i in 4: await process_frame
func touch(p,pressed):
	var event=InputEventScreenTouch.new(); event.position=p; event.index=0; event.pressed=pressed
	root.push_input(event,false); events+=1
func tap(p):
	touch(p,true); await process_frame; touch(p,false); await settle()
func action(label):
	for child in game.actions.get_children():
		if child is Button and child.text==label: return child
	return null
func reveal(button):
	for attempt in 6:
		if game.action_scroll.get_global_rect().encloses(button.get_global_rect()): return true
		var rect=game.action_scroll.get_global_rect()
		var p=rect.position+Vector2(rect.size.x-12,rect.size.y*0.5)
		var q=p-Vector2(minf(110,rect.size.x-24),0)
		touch(p,true); await process_frame
		var event=InputEventScreenDrag.new(); event.index=0; event.position=q; event.relative=q-p
		root.push_input(event,false); events+=1
		touch(q,false); await settle()
	return false
func empty_world_point():
	for y in range(100,int(root.size.y)-180,30):
		for x in range(30,int(root.size.x)-30,30):
			var p=Vector2(x,y)
			if game._box_point_in_world(p) and game._pick(p)==-1: return p
	return Vector2.INF
func run():
	var args=OS.get_cmdline_user_args()
	if args.size()!=1: push_error("Provide one existing-directory OUTPUT_JSON path"); quit(2); return
	root.size=Vector2i(390,844)
	game=load("res://main.tscn").instantiate(); root.add_child(game); game.test_mode=true
	await settle()
	for size in [Vector2i(390,844),Vector2i(844,390)]:
		root.size=size; await settle()
		for pair in [["停止","stop","STOP"],["守備","defend","DEFEND"]]:
			game._cancel_mode(); game._test_reset(); game._home()
			var scout=game._first(0,"scout")
			check("fixture has scout",not scout.is_empty())
			if scout.is_empty(): continue
			game._select([scout.id]); await settle()
			var label=str(size)+" "+pair[1]
			var button=action(pair[0])
			check(label+" stance button exists",is_instance_valid(button))
			if not is_instance_valid(button): continue
			var reachable=await reveal(button)
			check(label+" action reachable by touch scrolling",reachable)
			if not reachable: continue
			await tap(game.touch_button.get_global_rect().get_center())
			check(label+" touch command armed",game.touch_command)
			# Arming targeting rebuilds the action strip. Resolve the live control
			# again instead of retaining a freed Button across awaited frames.
			button=action(pair[0])
			check(label+" current stance button exists after mode change",is_instance_valid(button))
			if not is_instance_valid(button): continue
			reachable=await reveal(button)
			reachable=reachable and is_instance_valid(button) and button.is_visible_in_tree() and game.action_scroll.get_global_rect().encloses(button.get_global_rect()) and root.get_visible_rect().encloses(button.get_global_rect())
			check(label+" current stance button reachable after mode change",reachable)
			if not reachable: continue
			await tap(button.get_global_rect().get_center())
			check(label+" one ordinary stance queued",game.commands.size()==1 and game.commands[0].type==pair[1] and game.commands[0].ids==[scout.id])
			check(label+" targeting and cancel control retired",not game.touch_command and not game.compact_cancel_button.visible and game.selected==[scout.id])
			game._tick(game.Rules.TICK)
			check(label+" authority applies explicit stance",scout.mode==pair[2] and scout.state=="idle")
			var p=empty_world_point()
			check(label+" empty world probe available",p!=Vector2.INF)
			if p==Vector2.INF: continue
			var sequence=game.command_sequence
			await tap(p)
			check(label+" next world tap leaves stance and selection intact",game.command_sequence==sequence and game.commands.is_empty() and scout.mode==pair[2] and game.selected==[scout.id])
			await tap(game.touch_button.get_global_rect().get_center()); await tap(p)
			check(label+" explicit rearm still queues move",game.commands.size()==1 and game.commands[0].type=="order" and game.commands[0].target==-1)
		# X may interrupt an already-held world touch. Its canceled release
		# must not become a target, and the same finger index must work again.
		game._cancel_mode(); game._test_reset(); game._home()
		var scout=game._first(0,"scout")
		game._select([scout.id]); await settle()
		var point=empty_world_point()
		check(str(size)+" held pointer probe exists",point!=Vector2.INF)
		if point!=Vector2.INF:
			await tap(game.touch_button.get_global_rect().get_center())
			touch(point,true); await process_frame
			var key=InputEventKey.new(); key.physical_keycode=KEY_X; key.pressed=true
			root.push_input(key,false); await settle()
			check(str(size)+" X retires held touch",game.commands.size()==1 and game.commands[0].type=="stop" and not game.touch_command and game.canceled_touch_ids.has(0))
			key.echo=true; root.push_input(key,false); await settle()
			check(str(size)+" X echo does not repeat submission",game.commands.size()==1)
			key.echo=false; key.pressed=false; root.push_input(key,false)
			touch(point,false); await settle()
			check(str(size)+" late world release cannot replace Stop",game.commands.size()==1 and not game.canceled_touch_ids.has(0))
			await tap(game.touch_button.get_global_rect().get_center()); await tap(point)
			check(str(size)+" reused finger works after explicit rearm",game.commands.size()==2 and game.commands[1].type=="order")
	var passed=true
	for item in checks: passed=passed and item.passed
	var output=FileAccess.open(args[0],FileAccess.WRITE)
	if output==null: push_error("Cannot write OUTPUT_JSON"); quit(2); return
	output.store_string(JSON.stringify({"build":game.Rules.BUILD_ID,"checks":checks,"touch_events":events,"pass":passed,"scope":"native routed synthetic touch; not physical-phone or Web acceptance"},"\t")); output.close()
	quit(0 if passed else 1)

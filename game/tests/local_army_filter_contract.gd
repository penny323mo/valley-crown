extends SceneTree
## Test-only controlled owned roster/diverse viewports. Separate external
## journey runs fresh paid production and ordinary box from real user input.
var game
var checks=[]
var widths={}
var suffix=""
func _initialize():call_deferred("run")
func ck(n:String,ok:bool):
	checks.append({"name":n+suffix,"passed":ok})
	if not ok:push_error(n+suffix)
	return ok
func frames():
	for i in 5:await process_frame
func settle():
	game._update_hud();game._layout_ui();await frames()
func touch(p,down,canceled=false,index=0):
	var e=InputEventScreenTouch.new();e.position=p;e.pressed=down;e.canceled=canceled;e.index=index
	root.push_input(e);await process_frame
func tap(p):
	await touch(p,true);await touch(p,false);await settle()
func drag(a,b):
	await touch(a,true)
	var e=InputEventScreenDrag.new();e.position=b;e.relative=b-a;e.index=0
	root.push_input(e);await process_frame
	await touch(b,false);await settle()
func fits(b):
	if not is_instance_valid(b) or not b.is_visible_in_tree() or b.disabled:return false
	var q=b.get_global_rect()
	return q.size.x>=44 and q.size.y>=44 and game.action_scroll.get_global_rect().encloses(q) and root.get_visible_rect().encloses(q)
func action():
	return game.actions.get_node_or_null("FilterSelectedMilitary")
func same_metrics():
	return [game.commands.duplicate(true),game.command_sequence,game.economy.bank_milli(0),game.camera.global_transform]
func worker_facts(w):
	return [w.state,w.work_epoch,w.target,w.dest,w.pos,game._cargo_amount(w)]
func case_at(size):
	root.size=size;suffix=" "+str(size);await frames()
	var worker=game._first(0,"villager");var scout=game._first(0,"scout")
	var spear=game._first(0,"spearman");var archer=game._first(0,"archer");var barracks=game._first(0,"barracks")
	var mixed=[archer.id,worker.id,spear.id]
	game._select(mixed);await settle()
	if size.x>=1000:
		ck("desktop preserves existing action row without new mobile affordance",not is_instance_valid(action()) and game.selected==mixed)
		return
	var button=action()
	if not ck("mixed group has one full first-position 44px filter",fits(button) and game.actions.get_child(0)==button and game.action_scroll.scroll_horizontal==0 and button.text=="只選軍隊"):return
	ck("filter center is owned by HUD, not a world order target",not game._box_point_in_world(button.get_global_rect().get_center()))
	widths[str(size)]=[button.size.x,button.size.y]
	var world=same_metrics();var work=worker_facts(worker)
	await tap(game.pause_button.get_global_rect().get_center())
	button=action()
	var pending_context=game.selected.duplicate()
	if not ck("real Pause visibly disables the retained filter target",game.paused and is_instance_valid(button) and button.disabled):return
	await tap(button.get_global_rect().get_center())
	if not ck("tap on disabled filter cannot replace army selection or issue a world order",game.paused and game.selected==pending_context and same_metrics()==world and worker_facts(worker)==work):return
	await tap(game.pause_button.get_global_rect().get_center())
	button=action()
	if not ck("real Resume re-enables the same first-page filter",not game.paused and fits(button) and game.selected==mixed and same_metrics()==world):return
	var click=button.get_global_rect().get_center()
	await touch(click,true);await touch(click,false,true);await settle()
	if not ck("canceled press leaves original mixed selected units and authority intact",game.selected==mixed and same_metrics()==world and worker_facts(worker)==work):return
	button=action();click=button.get_global_rect().get_center()
	await drag(click,click-Vector2(27,0))
	if not ck("drag from filter scrolls without activating it, no command or bank change",game.action_scroll.scroll_horizontal>0 and game.selected==mixed and same_metrics()==world and worker_facts(worker)==work):return
	var lane=game.action_scroll.get_global_rect();var start=lane.position+Vector2(32,lane.size.y*.5)
	await drag(start,start+Vector2(32,0))
	button=action()
	if not ck("return to lane start restores fully tappable filter",fits(button) and game.action_scroll.scroll_horizontal==0):return
	click=button.get_global_rect().get_center()
	await touch(click,true)
	game._select([worker.id,scout.id]);await settle()
	await touch(click,false);await settle()
	if not ck("old held selection press cannot filter replacement group",game.selected==[worker.id,scout.id] and same_metrics()==world and worker_facts(worker)==work):return
	game._select(mixed);await settle();button=action()
	await tap(button.get_global_rect().get_center())
	if not ck("single true tap keeps current military in original order, never adds scout",game.selected==[archer.id,spear.id] and not is_instance_valid(action()) and worker_facts(worker)==work and same_metrics()==world):return
	var advance=game.actions.get_node_or_null("PrimaryTacticalAdvance")
	ck("pure mixed army keeps first-page 44px Advance reachable",fits(advance) and game.action_scroll.scroll_horizontal==0)
	if size.x>=390:
		var clear=null
		for b in game.actions.get_children():
			if b is Button and b.text=="取消選取":clear=b
		ck("normal-phone mixed pure army retains first-page cancel",fits(clear))
	game._select([worker.id]);await settle()
	var house=null
	for b in game.actions.get_children():
		if b is Button and b.get_meta("command_icon_kind","")=="house":house=b
	ck("single civilian actions unchanged and House remains initial priority",not is_instance_valid(action()) and fits(house))
	game._select([barracks.id]);await settle()
	var train=null
	for b in game.actions.get_children():
		if b is Button and b.get_meta("primary_train",false):train=b
	ck("single production selection keeps first training fully fit and filter absent",not is_instance_valid(action()) and fits(train) and same_metrics()==world)
	game._select([worker.id,scout.id]);await settle()
	button=action()
	if ck("a scout already in the current mix remains eligible",fits(button)):
		await tap(button.get_global_rect().get_center())
		ck("existing selected scout is kept and unselected army is never added",game.selected==[scout.id] and same_metrics()==world)
func run():
	root.size=Vector2i(568,320)
	game=load("res://main.tscn").instantiate();game.skirmish_mode="practice";root.add_child(game);game.set_process(false);game.ai_enabled=false
	# Roster only, never an earned-event claim; natural journey is separate.
	var origin=game.MapRoutes.home(0)
	game._spawn("spearman",0,origin+Vector3(2,0,5))
	game._spawn("archer",0,origin+Vector3(4,0,5))
	game._spawn("barracks",0,origin+Vector3(7,0,3))
	game._navigation_rebuild();game._update_vision();game._publish_faction_views()
	await frames()
	for size in [Vector2i(320,568),Vector2i(390,844),Vector2i(568,320),Vector2i(844,390),Vector2i(1440,900)]:
		await case_at(size)
	var fail=checks.filter(func(x):return not x.passed).size()
	print(JSON.stringify({"suite":"local_army_filter_contract","checks":checks,"failed":fail,"filter_dimensions":widths,"scope":"Real native viewport synthetic touches, controlled own roster; no physical phone or render."}))
	game.free()
	quit(1 if fail else 0)

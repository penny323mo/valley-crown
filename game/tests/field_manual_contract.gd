extends SceneTree
const Manual=preload("res://scripts/field_manual.gd")
const Rules=preload("res://scripts/rules.gd")
var checks=[]
func check(name,ok):
	checks.append({"name":name,"passed":bool(ok)})
	if not ok:push_error(name)
func _initialize():call_deferred("run")
func button(shell,id):return shell.buttons.get_node(NodePath(id))
func frames():
	await process_frame
	await process_frame
func run():
	check("catalogue covers every current troop",Manual.entries(0)==Rules.UNIT_KINDS)
	check("catalogue covers keep and every buildable",Manual.entries(1)==["town_center"]+Rules.BUILDABLE_KINDS)
	check("catalogue covers all current technology",Manual.entries(2)==["age2"]+Rules.MILITARY_TECHS)
	for section in 3:
		for i in Manual.entries(section).size():
			var item=Manual.entry(section,i)
			check("title and index "+item.kind,item.title==Rules.NAMES[item.kind] and item.index==i and item.count==Manual.entries(section).size())
			if Rules.COSTS.has(item.kind):check("live rule cost "+item.kind,Rules.cost_label(item.kind) in item.body)
			if section==0:check("producer "+item.kind,Rules.NAMES[Manual.producer(item.kind)] in item.body and "基礎攻擊 %d" % Rules.DAMAGE[item.kind] in item.body)
		check("index wraps section "+str(section),Manual.entry(section,Manual.entries(section).size()).kind==Manual.entries(section)[0])
	check("spear cavalry net damage", "命中 16 傷害" in Manual.entry(0,2).body)
	check("archer spear net damage", "命中 7 傷害" in Manual.entry(0,3).body)
	check("cavalry archer net damage", "命中 15 傷害" in Manual.entry(0,4).body)
	check("siege keep net damage", "命中 28 傷害" in Manual.entry(0,5).body)
	var shell=load("res://scripts/main_menu.gd").new();root.add_child(shell)
	await frames()
	button(shell,"HelpButton").pressed.emit();await frames()
	button(shell,"FieldManualButton").pressed.emit();await frames()
	check("real help button opens manual",shell.page=="manual" and "村民" in shell.heading.text and not is_instance_valid(shell.match_node))
	for size in [Vector2i(390,844),Vector2i(320,568),Vector2i(568,320),Vector2i(1280,800)]:
		root.size=size;shell._layout();await frames()
		for control in shell.buttons.get_children():
			var rect=control.get_global_rect()
			check("action contained "+str(size)+" "+control.name,root.get_visible_rect().encloses(rect) and shell.card.get_global_rect().encloses(rect) and rect.size.y>=54 and rect.size.x>=44)
		check("reading pane separate "+str(size),shell.scroll.get_global_rect().end.y<=shell.buttons.get_global_rect().position.y and shell.scroll.size.y>1)
	# The exact old controls touch machinery must also scroll this new page.
	root.size=Vector2i(320,568);shell._layout();await frames()
	var begin=shell.scroll.get_global_rect().get_center()
	var touch=InputEventScreenTouch.new();touch.index=0;touch.position=begin;touch.pressed=true
	shell.active_touches[0]=true;shell._help_touch(touch)
	var drag=InputEventScreenDrag.new();drag.index=0;drag.position=begin-Vector2(0,180)
	shell._help_touch(drag)
	check("manual supports single finger prose scrolling",shell.scroll.scroll_vertical>0)
	shell._cancel_menu_touches()
	button(shell,"ManualNextButton").pressed.emit();await frames()
	check("next entry is scout and resets scroll", "斥候" in shell.heading.text and shell.scroll.scroll_vertical==0)
	button(shell,"ManualSectionButton").pressed.emit();await frames()
	check("category opens buildings at keep",shell.manual_section==1 and "主堡" in shell.heading.text)
	button(shell,"ManualSectionButton").pressed.emit();await frames()
	check("category opens technology",shell.manual_section==2 and "城防時代" in shell.heading.text)
	button(shell,"ManualBackButton").pressed.emit();await frames()
	button(shell,"BackButton").pressed.emit();await frames()
	button(shell,"StartMatchButton").pressed.emit();await frames()
	button(shell,"LaunchMatchButton").pressed.emit();await frames()
	var game=shell.match_node;game.set_process(false);game.test_mode=true
	game._tick(Rules.TICK);var before_tick=game.tick_count;var before_bank=game.economy.bank_milli(0).duplicate();var before_ids=game.entities.map(func(e):return e.id)
	game.main_menu_requested.emit();await frames()
	button(shell,"HelpButton").pressed.emit();await frames()
	button(shell,"FieldManualButton").pressed.emit();await frames()
	check("manual keeps current battle paused unchanged",game.paused and game.tick_count==before_tick and game.economy.bank_milli(0)==before_bank and game.entities.map(func(e):return e.id)==before_ids)
	button(shell,"ManualBackButton").pressed.emit();await frames();button(shell,"BackButton").pressed.emit();await frames();button(shell,"ResumeMatchButton").pressed.emit();await frames()
	check("resume returns same battle without new commands",shell.match_node==game and not game.paused and game.tick_count==before_tick and game.commands.is_empty())
	var failed=checks.filter(func(c):return not c.passed).size()
	print(JSON.stringify({"suite":"field_manual_contract","checks":checks,"failed":failed,"scope":"native catalogue values, real button signals, synthetic touch-handler drag, viewport geometry and battle continuity; not rendered/browser/physical-device acceptance"}))
	shell.queue_free();quit(1 if failed else 0)

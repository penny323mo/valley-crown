extends SceneTree
## Actual native menu and routed synthetic touches, not visual/device acceptance.
const Rules=preload("res://scripts/rules.gd")
var checks=[]
var game

func _initialize():call_deferred("run")
func check(name:String,passed:bool) -> bool:
	checks.append({"name":name,"passed":passed})
	if not passed:push_error(name)
	return passed
func settle():
	for i in 4:await process_frame
func fits(button) -> bool:
	if not is_instance_valid(button) or not button.is_visible_in_tree() or button.disabled:return false
	var r=button.get_global_rect()
	if r.size.x<44 or r.size.y<44 or not root.get_visible_rect().encloses(r):return false
	var parent=button.get_parent()
	while parent is Control:
		if parent.clip_contents and not parent.get_global_rect().encloses(r):return false
		parent=parent.get_parent()
	return true
func touch(p:Vector2,down:bool,canceled:bool=false) -> void:
	var e=InputEventScreenTouch.new()
	e.index=17;e.position=p;e.pressed=down;e.canceled=canceled
	root.push_input(e)
func tap(button):
	if not fits(button):return false
	var p=button.get_global_rect().get_center()
	touch(p,true);await process_frame
	touch(p,false);await settle()
	return true
func state():
	return [game.command_sequence,game.commands.duplicate(true),game.economy.bank_milli(0),game.tick_count]
func launch(size:Vector2i,mode:String):
	root.size=size
	var menu=load("res://main_menu.tscn").instantiate()
	menu.history_path="user://short-landscape-idle-contract-history.json"
	root.add_child(menu);await settle()
	var group="BattleGroup0" if mode=="standard" else "BattleGroup3"
	for key in ["StartMatchButton",group,"ChooseBattle_"+mode,"LaunchMatchButton"]:
		if not await tap(menu.buttons.get_node_or_null(key)):break
	game=menu.match_node
	if is_instance_valid(game):game.set_process(false);game._update_hud();await settle()
	return menu
func exercise(size:Vector2i,mode:String,expect_direct:bool):
	var label=str(size)+" "+mode+" "
	var menu=await launch(size,mode)
	if not check(label+"ordinary new match through menu",is_instance_valid(game) and game.skirmish_mode==mode and not game.test_mode and not game.game_over):
		menu.free();return
	var direct=game.ui.find_child("InlineIdleWorker",true,false)
	if not check(label+"honest 44px Menu and Pause fit; direct availability is deliberate",fits(game.compact_menu_button) and fits(game.pause_button) and game.compact_menu_button.text=="選單" and is_instance_valid(direct) and fits(direct)==expect_direct):
		menu.free();return
	var before=state()
	var selected=game.selected.duplicate()
	var focus=game.camera_focus
	if expect_direct:
		var direct_rect=direct.get_global_rect()
		check(label+"idle, tutorial and essential controls do not overlap",game.hud_top.size.y==54 and not direct_rect.intersects(game.tutorial_entry.get_global_rect()) and not direct_rect.intersects(game.pause_button.get_global_rect()) and not direct_rect.intersects(game.compact_menu_button.get_global_rect()))
		var center=direct_rect.get_center()
		touch(center,true);await process_frame
		touch(center,false,true);await settle()
		check(label+"actually canceled contact cannot select, move or spend",game.selected==selected and game.camera_focus==focus and state()==before)
		var expected=direct.get_meta("idle_target",-1)
		var target=game.faction_views[0].get_record(expected)
		check(label+"one fresh tap selects and locates exactly one owned idle worker",await tap(direct) and game.selected==[expected] and not target.is_empty() and target.owned and target.kind=="villager" and game.camera_focus==target.pos and state()==before and not game.compact_menu.visible)
		selected=game.selected.duplicate()
	check(label+"real Pause does not reroute as an order or idle action",await tap(game.pause_button) and game.paused and not direct.visible and game.selected==selected and state()==before)
	check(label+"real Pause again resumes",await tap(game.pause_button) and not game.paused and state()==before)
	if expect_direct:
		# A live alert occupies its existing priority and explicitly retires a
		# touch which began on the idle shortcut before the layout changed.
		var center=direct.get_global_rect().get_center()
		touch(center,true);await process_frame
		game.battle_alerts.record_hit(game._first(0,"town_center"),1,game.tick_count)
		game._update_hud();await settle()
		touch(center,false);await settle()
		check(label+"alert retires held idle press; remains separate and available",not direct.visible and fits(game.battle_jump_button) and game.battle_alerts.pending(game.tick_count).size()==1 and game.selected==selected and state()==before)
	check(label+"actual Menu opens without selecting or issuing commands",await tap(game.compact_menu_button) and game.compact_menu.visible and game.selected==selected and state()==before)
	check(label+"any Settings category still exposes separate pinned worker",await tap(game.shortcut_category_buttons["settings"]) and game.shortcut_category=="settings" and fits(game.idle_worker_button) and not game.shortcut_scroll.is_ancestor_of(game.idle_worker_button))
	var worker=game.idle_worker_button.get_meta("idle_target",-1)
	check(label+"pinned fallback selects only, closes drawer and remembers Settings",await tap(game.idle_worker_button) and game.selected==[worker] and not game.compact_menu.visible and game.shortcut_category=="settings" and state()==before)
	check(label+"subsequent actual Menu restores Settings without acting",await tap(game.compact_menu_button) and game.compact_menu.visible and game.shortcut_category=="settings" and game.selected==[worker] and state()==before)
	menu.free();game=null;await settle()
func run():
	await exercise(Vector2i(480,270),"standard",true)
	await exercise(Vector2i(512,288),"standard",true)
	await exercise(Vector2i(568,320),"survival",false)
	var failed=checks.filter(func(row):return not row.passed).size()
	print(JSON.stringify({"suite":"short_landscape_idle_worker_contract","build":Rules.BUILD_ID,"checks":checks,"failed":failed,"scope":"Native routed first-match controls from ordinary menu; controlled alert validity, no physical-phone or pixel acceptance."}))
	quit(1 if failed else 0)

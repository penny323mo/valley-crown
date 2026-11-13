extends SceneTree
# ENGINE_UNRUN. Direct real GUI-helper calls, not routed touch or natural training.
const Rules=preload("res://scripts/rules.gd")
var game
var checks=[]
func check(label,ok):
	checks.append({"name":label,"passed":bool(ok)})
	if not ok: push_error(label)
func _initialize(): call_deferred("run")
func run():
	game=load("res://main.tscn").instantiate(); root.add_child(game)
	game.set_process(false); game.test_mode=true; game.ai_enabled=false
	game._test_reset(); game.set_process(false)
	await process_frame
	var scout=game._first(0,"scout"); var worker=game._first(0,"villager")
	# Deliberate setup spawn, not paid production or real progression evidence.
	var spear=game._spawn("spearman",0,scout.pos+Vector3(2,0,0))
	game._update_vision(); game._select([worker.id,spear.id,scout.id])
	game.compact_menu.show(); game._refresh_squad_buttons()
	var commands_before=game.commands.size(); var scout_mode=scout.mode; var spear_mode=spear.mode
	game._activate_squad(0,true)
	var expected=[scout.id,spear.id]; expected.sort()
	check("save excludes civilian and stores both military",game.squad_selection.members(0,game.faction_views[0].records())==expected)
	check("save emits no command or stance change",game.commands.size()==commands_before and scout.mode==scout_mode and spear.mode==spear_mode)
	game._select([worker.id]); game.compact_menu.show(); game._refresh_squad_buttons()
	game._activate_squad(0,false)
	check("recall selects saved military only",game.selected==expected and game.commands.size()==commands_before)
	game.compact_menu.show(); game._refresh_squad_buttons(); game._kill(spear); game._update_vision()
	# Rebind on refresh or reject stale metadata at activation; neither can add IDs.
	game._refresh_squad_buttons(); game._activate_squad(0,false)
	check("recall filters actual casualty",game.selected==[scout.id])
	game.paused=true; game.compact_menu.show(); game._refresh_squad_buttons(); game._activate_squad(1,true)
	check("paused save does not write a slot",game.squad_selection.members(1,game.faction_views[0].records()).is_empty())
	game.paused=false; game._test_reset(); game._refresh_squad_buttons()
	check("new match clears all local groups",game.squad_selection.groups==[[],[],[]])
	check("economy ledger remains conserved",game.economy.audit().ok)
	# Real container layout at phone width; pending until engine execution.
	root.size=Vector2i(320,568); game.compact_menu.show(); game._layout_ui()
	await process_frame
	await process_frame
	var menu_scroll=game.compact_menu.get_child(0)
	var box=menu_scroll.get_child(0)
	var bounds_ok=game.compact_menu.get_global_rect().end.x<=320.1
	for row in box.get_children():
		bounds_ok=bounds_ok and row.get_global_rect().end.x<=box.get_global_rect().end.x+0.1
		for button in row.get_children():
			if button is Button: bounds_ok=bounds_ok and button.get_global_rect().end.x<=box.get_global_rect().end.x+0.1
	check("320px whole menu rows fit content width",bounds_ok)
	check("long shortcut menu exposes vertical scroll",menu_scroll.get_v_scroll_bar().max_value>menu_scroll.get_v_scroll_bar().page)
	var failed=checks.filter(func(item): return not item.passed).size()
	print(JSON.stringify({"suite":"squad_selection_contract","build":Rules.BUILD_ID,"checks":checks,"failed":failed,"status":"ENGINE_UNRUN","scope":"Controlled spawned army and GUI helpers; not routed touch, real training or a match"}))
	game.queue_free(); quit(1 if failed else 0)

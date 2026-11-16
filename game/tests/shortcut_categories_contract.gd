extends SceneTree
var checks=[]
func check(label,ok):
	checks.append({"name":label,"passed":bool(ok)})
	if not ok:push_error(label)
func _initialize():call_deferred("run")
func run():
	var g=load("res://main.tscn").instantiate();root.add_child(g);g.set_process(false);g.test_mode=true;g.ai_enabled=false;g._test_reset();g.set_process(false);await process_frame
	g.compact_menu.show();g._update_hud()
	check("default all retains existing discoverability",g.shortcut_category=="all" and g.shortcut_category_buttons.size()==5)
	var before=g.commands.duplicate(true);var selected=g.selected.duplicate();var bank=g.economy.bank_milli(0).duplicate(true)
	for page in ["economy","army","production","settings","all"]:
		g.shortcut_category_buttons[page].pressed.emit()
		var correct=true
		for section in g.shortcut_sections:
			for control in g.shortcut_sections[section]:correct=correct and control.visible==(page=="all" or section==page)
		check("exact category visibility "+page,correct)
		check("one selected tab "+page,g.shortcut_category_buttons.values().filter(func(b):return b.button_pressed).size()==1 and g.shortcut_category_buttons[page].button_pressed)
	check("browsing has no gameplay effects",g.commands==before and g.selected==selected and g.economy.bank_milli(0)==bank)
	g._set_shortcut_category("economy");g._toggle_compact_menu();g._toggle_compact_menu()
	check("last category survives close reopen",g.shortcut_category=="economy" and g.workforce_label.is_visible_in_tree() and not g.idle_army_button.is_visible_in_tree())
	g.gui_touch_press={4:{"button":weakref(g.idle_dispatch_buttons.food),"origin":Vector2.ZERO,"valid":true}}
	g._set_shortcut_category("army")
	check("switch retires held control instead of dispatching",g.gui_touch_press.is_empty() and g.commands==before)
	g._set_shortcut_category("invalid");check("unknown category rejected",g.shortcut_category=="army")
	for size in [Vector2i(320,568),Vector2i(390,844),Vector2i(844,390)]:
		root.size=size;g._layout_ui();await process_frame;await process_frame
		for page in ["all","economy","army","production","settings"]:
			g._set_shortcut_category(page);await process_frame;await process_frame
			var fits=true;var menu=g.compact_menu.get_global_rect()
			for tab in g.shortcut_category_buttons.values():fits=fits and tab.get_global_rect().position.x>=menu.position.x and tab.get_global_rect().end.x<=menu.end.x+0.1 and tab.size.y>=44
			check("category tabs fit "+str(size)+" "+page,fits)
	g._set_shortcut_category("production");var center=g._first(0,"town_center");g._focus_production("town_center")
	check("real production selection still works from category",g.selected==[center.id] and g.commands==before)
	g.compact_menu.show();g._set_shortcut_category("economy");g._refresh_idle_dispatch_buttons()
	check("real economy dispatch reachable from category",g.idle_dispatch_buttons.food.is_visible_in_tree() and not g.idle_dispatch_buttons.food.disabled)
	check("ledger conserved",g.economy.audit().ok)
	var failed=checks.filter(func(c):return not c.passed).size()
	print(JSON.stringify({"suite":"shortcut_categories_contract","checks":checks,"failed":failed,"scope":"Native UI visibility geometry and existing actions; not physical-phone acceptance"}))
	g.queue_free();quit(1 if failed else 0)

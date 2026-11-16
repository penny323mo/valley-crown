extends SceneTree
var checks=[]
func check(label,ok):
	checks.append({"name":label,"passed":bool(ok)})
	if not ok:push_error(label)
func _initialize():call_deferred("run")
func run():
	var g=load("res://main.tscn").instantiate();root.add_child(g);g.set_process(false);g.test_mode=true;g.ai_enabled=false;g._test_reset();g.set_process(false);await process_frame
	# Controlled farm inventory for navigation, not naturally built farms.
	var a=g._spawn("farm",0,Vector3(32.5,0,32.5),true)
	var b=g._spawn("farm",0,Vector3(28.5,0,32.5),true)
	var incomplete=g._spawn("farm",0,Vector3(40.5,0,32.5),false)
	var enemy=g._spawn("farm",1,Vector3(44.5,0,32.5),true)
	g._update_vision();g.compact_menu.show();g._set_shortcut_category("economy");g._refresh_workforce_buttons()
	var bank=g.economy.bank_milli(0).duplicate()
	check("only completed own vacant farms listed",g._vacant_farm_ids()==[a.id,b.id])
	g.vacant_farm_button.pressed.emit()
	check("first farm selected with dispatch available",g.selected==[a.id] and is_instance_valid(g.farm_dispatch_button) and not g.farm_dispatch_button.disabled)
	check("first farm camera focus",g.camera_focus==a.pos and not g.compact_menu.visible)
	g.compact_menu.show();g._refresh_workforce_buttons();g.vacant_farm_button.pressed.emit()
	check("cycle visits second farm",g.selected==[b.id] and g.camera_focus==b.pos)
	g.compact_menu.show();g._refresh_workforce_buttons();g.vacant_farm_button.pressed.emit()
	check("cycle wraps to first farm",g.selected==[a.id])
	check("navigation does not create orders or resources",g.commands.is_empty() and g.economy.bank_milli(0)==bank)
	g.farm_dispatch_button.pressed.emit()
	check("selected farm dispatch still uses normal order",g.commands.size()==1 and g.commands[0].get("farm_dispatch",false))
	g.compact_menu.show();g._refresh_workforce_buttons()
	check("pending own target excludes farm",g._vacant_farm_ids()==[b.id])
	g._execute(g.commands.pop_front());g._update_vision();g._refresh_workforce_buttons()
	check("occupied farm excluded after assignment",g._vacant_farm_ids()==[b.id])
	g._select([]);g._submit("order",{"ids":[g._first(0,"villager").id],"target":b.id});g._focus_vacant_farm()
	check("stale inventory cannot select",g.selected.is_empty())
	g.commands.clear();g.paused=true;g._refresh_workforce_buttons();g._focus_vacant_farm()
	check("pause disables farm locator",g.vacant_farm_button.disabled and g.selected.is_empty())
	g.paused=false;g._refresh_workforce_buttons();g._set_shortcut_category("army");g._focus_vacant_farm()
	check("hidden category cannot activate",g.selected.is_empty())
	g._set_shortcut_category("economy")
	for width in [320,390,844]:
		root.size=Vector2i(width,600);g._layout_ui();await process_frame;await process_frame
		check("farm locator fits "+str(width),g.vacant_farm_button.get_global_rect().end.x<=g.compact_menu.get_global_rect().end.x)
	check("ledger conservation",g.economy.audit().ok)
	var failed=checks.filter(func(c):return not c.passed).size()
	print(JSON.stringify({"suite":"vacant_farms_contract","checks":checks,"failed":failed,"scope":"Controlled farm inventory and native UI; no natural construction or physical phone acceptance"}))
	g.queue_free();quit(1 if failed else 0)

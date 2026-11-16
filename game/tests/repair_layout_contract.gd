extends SceneTree
var checks=[]
func check(label,ok):
	checks.append({"name":label,"passed":bool(ok)})
	if not ok: push_error(label)
func _initialize(): call_deferred("run")
func settle():
	for i in 4: await process_frame
func run():
	root.size=Vector2i(390,844)
	var g=load("res://main.tscn").instantiate();root.add_child(g);g.set_process(false);g.test_mode=true;g._test_reset();await settle()
	var keep=g._first(0,"town_center");g._select([keep.id]);await settle()
	check("healthy keep has no repair control",not is_instance_valid(g.repair_dispatch_button))
	keep.hp-=10;keep.last_damage_tick=-1000;g._update_vision();g._update_hud();await settle()
	check("damage creates contextual repair control",is_instance_valid(g.repair_dispatch_button))
	var train=null;var scout=null
	for b in g.actions.get_children():
		if b is Button and b.text.begins_with("訓練村民\n"):train=b
		if b is Button and b.text.begins_with("訓練斥候\n"):scout=b
	check("damaged keep retains both visible producers",is_instance_valid(train) and is_instance_valid(scout) and g.action_scroll.get_global_rect().encloses(train.get_global_rect()) and g.action_scroll.get_global_rect().encloses(scout.get_global_rect()))
	check("repair follows core production",g.repair_dispatch_button.get_index()>scout.get_index())
	keep.hp=keep.max_hp;g._update_vision();g._update_hud();await settle()
	check("healing removes repair control without reselection",not is_instance_valid(g.repair_dispatch_button) and g.selected==[keep.id])
	var failed=checks.filter(func(c):return not c.passed).size()
	print(JSON.stringify({"suite":"repair_layout_contract","checks":checks,"failed":failed,"scope":"Actual 390px HUD rectangles, not physical phone acceptance"}));g.queue_free();quit(1 if failed else 0)

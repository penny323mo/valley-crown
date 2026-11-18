extends SceneTree
const Rules=preload("res://scripts/rules.gd")
var checks=[]
func c(name,passed):
	checks.append({"name":name,"passed":bool(passed)})
	if not passed:push_error(name)
func touch(index: int,point: Vector2,pressed: bool,cancelled: bool=false):
	var event=InputEventScreenTouch.new();event.index=index;event.position=point;event.pressed=pressed;event.canceled=cancelled;root.push_input(event,false)
func _initialize():call_deferred("run")
func run():
	root.size=Vector2i(390,844)
	var g=load("res://main.tscn").instantiate();root.add_child(g);g.set_process(false);g.test_mode=true;g.ai_enabled=false
	var stock={"food":0,"wood":180,"stone":0,"iron":900}
	g._test_reset([stock,stock.duplicate(true)]);g.set_process(false);await process_frame
	var worker=g._first(0,"villager");var home=g._first(0,"town_center")
	g._update_vision();g._select([worker.id]);g._start_build("house");g._update_hud()
	var bank=g.economy.bank_milli(0).duplicate(true);var commands=g.commands.duplicate(true);var selected=g.selected.duplicate()
	var nav=g.actions.get_node_or_null("ShortfallWorkforce")
	c("build preview has explicit economy navigation",nav!=null and nav.text.contains("退出建造預覽"))
	# Actual GUI-routed touch uses shared ownership/cancellation, not callback-only success.
	var scroll=g.actions.get_parent()
	while scroll!=null and not scroll is ScrollContainer:scroll=scroll.get_parent()
	if scroll!=null:scroll.ensure_control_visible(nav)
	await process_frame;await process_frame
	var center=nav.get_global_rect().get_center()
	touch(89,center,true);await process_frame
	touch(90,center+Vector2(3,0),true);await process_frame
	touch(90,center+Vector2(3,0),false);touch(89,center,false);await process_frame
	c("second finger cancels held economy navigation",not g.compact_menu.visible and g.commands==commands and g.economy.bank_milli(0)==bank)
	# Multi-touch may safely cancel the placement mode. Re-arm via the ordinary UI API.
	g._start_build("house");g._update_hud();await process_frame;await process_frame
	nav=g.actions.get_node("ShortfallWorkforce")
	if scroll!=null:scroll.ensure_control_visible(nav)
	await process_frame;center=nav.get_global_rect().get_center()
	touch(89,center,true);await process_frame;touch(89,center,false,true);await process_frame
	c("canceled touch does not navigate",not g.compact_menu.visible)
	touch(89,center,true);await process_frame;touch(89,center,false);await process_frame;await process_frame
	c("navigation opens existing economy page",g.compact_menu.visible and g.shortcut_category=="economy" and g.workforce_buttons.size()==4)
	c("navigation cancels armed preview explicitly",g.build_mode.is_empty() and g.shortfall_label.text.contains("預覽已取消"))
	c("navigation preserves selection orders and bank",g.selected==selected and g.commands==commands and g.economy.bank_milli(0)==bank)
	for size in [Vector2i(320,568),Vector2i(844,390),Vector2i(390,844)]:
		root.size=size;g._layout_ui();await process_frame;await process_frame
		g.shortcut_scroll.ensure_control_visible(g.shortfall_label);await process_frame
		c("shortfall text reachable "+str(size),g.shortcut_scroll.get_global_rect().encloses(g.shortfall_label.get_global_rect()))
	g._toggle_compact_menu();g._select([home.id]);g._update_hud()
	c("recruit exact food shortage visible",g._shortfall_lines().contains("缺食50") and g.selection_detail.text.contains("缺食50"))
	var old=g._shortfall_context();g._select([worker.id]);g._open_shortfall_workforce(old)
	c("stale selection cannot navigate",not g.compact_menu.visible)
	g._select([home.id]);g._update_hud();old=g._shortfall_context()
	g.application_focused=false;g._open_shortfall_workforce(old)
	c("focus loss blocks navigation",not g.compact_menu.visible)
	g.application_focused=true
	var producer=g._spawn("barracks",0,Vector3(-10,0,10));producer.repeat_kind="spearman"
	g._update_vision();g._select([producer.id]);g._update_hud()
	c("empty automatic queue diagnoses exact next cost",g._shortfall_lines().contains("自動待產") and g._shortfall_lines().contains("缺食"))
	old=g._shortfall_context();producer.repeat_kind="";producer.repeat_generation=producer.get("repeat_generation",0)+1;g._update_vision()
	g._open_shortfall_workforce(old)
	c("changed repeat recipe invalidates held navigation",not g.compact_menu.visible)
	# Controlled paid-ready representation: display must retain existing birth cause,
	# and label only the next unpurchased recruit, not demand repayment.
	producer.queue=[{"kind":"spearman","remaining_ticks":0,"queue_id":999,"receipt_id":"fixture","started":true}]
	g._update_vision();g._update_hud()
	c("paid ready order keeps birth cause not shortage",g.queue_label.text.contains("訓練完成") and not g.queue_label.text.contains("缺食") and g._shortfall_lines().contains("加訓"))
	producer.queue.clear();g._update_vision()
	c("unseen resource positions not exposed",not g._shortfall_lines().contains("Vector") and not g._shortfall_lines().contains("900"))
	c("inspection never pays or submits",g.commands==commands and g.economy.bank_milli(0)==bank)
	c("economy audit conserved",g.economy.audit().ok)
	var failed=checks.filter(func(x):return not x.passed).size()
	print(JSON.stringify({"suite":"production_shortfall_contract","checks":checks,"failed":failed,"scope":"Controlled stock fixture; contextual shortage and navigation with cancellation and phone-size layout. Not physical phone or natural economy match."}))
	g.queue_free();quit(1 if failed else 0)

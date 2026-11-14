extends SceneTree
const Retry=preload("res://scripts/retry_gather_action.gd")
var checks=[]
func check(label,ok):
	checks.append({"name":label,"passed":bool(ok)})
	if not ok: push_error(label)
func worker(): return {"id":1,"owned":true,"alive":true,"team":0,"category":"unit","kind":"villager","state":"idle","mode":"WORK","path_request_kind":"work","path_status":"NO_PATH","path_request_target":2,"gather_type":"wood","cargo_milli":0}
func _initialize(): call_deferred("run")
func run():
	var w=worker();var t={"id":2,"kind":"oak","category":"resource","alive":true,"remembered":false}
	check("eligible original visible resource",Retry.orders({1:w,2:t},[1],[]).size()==1)
	check("duplicate selection one order",Retry.orders({1:w,2:t},[1,1],[]).size()==1)
	check("pending orders not overridden",Retry.orders({1:w,2:t},[1],[{"type":"order","team":0,"ids":[1]}]).is_empty())
	for patch in [{"state":"gather"},{"cargo_milli":1000},{"mode":"DEFEND"},{"path_status":"IDLE"},{"path_request_kind":"point"},{"owned":false},{"gather_type":"stone"}]:
		var changed=w.duplicate();changed.merge(patch,true)
		check("worker excluded "+str(patch),Retry.orders({1:changed,2:t},[1],[]).is_empty())
	for patch in [{"remembered":true},{"alive":false},{"kind":"house"},{"category":"building"}]:
		var changed=t.duplicate();changed.merge(patch,true)
		check("target excluded "+str(patch),Retry.orders({1:w,2:changed},[1],[]).is_empty())
	var g=load("res://main.tscn").instantiate();root.add_child(g);g.set_process(false);g.test_mode=true;g.ai_enabled=false;g._test_reset();g.set_process(false);await process_frame
	var real=g._first(0,"villager");var source={}
	for r in g.faction_views[0].records().values():
		if r.kind in ["oak","pine"] and not r.remembered: source=r;break
	check("real visible source exists",not source.is_empty())
	if source.is_empty():finish(g);return
	g._order(real,"gather",source.id)
	real.state="idle";real.path.clear();real.path_pending=false;real.path_request_kind="work";real.path_status="NO_PATH";real.path_request_target=source.id
	g._update_vision()
	var scout=g._first(0,"scout")
	g._select([scout.id]);g.compact_menu.show();g._set_shortcut_category("economy");g._refresh_workforce_buttons()
	var bank=g.economy.bank_milli(0).duplicate();var target=real.target
	check("failed worker discoverable without selecting it",g._blocked_worker_ids()==[real.id] and not g.blocked_workers_button.disabled)
	g.blocked_workers_button.pressed.emit()
	check("real button selects failed worker and closes menu",g.selected==[real.id] and not g.compact_menu.visible)
	check("camera locates failed worker",g.camera_focus==real.pos)
	check("selection preserves existing work and economy",g.commands.is_empty() and real.target==target and g.economy.bank_milli(0)==bank)
	check("selected worker exposes existing retry control",is_instance_valid(g.retry_gather_button) and not g.retry_gather_button.disabled)
	g._retry_selected_gather();check("existing retry submits one normal guarded order",g.commands.size()==1 and g.commands[0].get("retry_gather",false))
	g.compact_menu.show();g._refresh_workforce_buttons()
	check("pending retry removes worker from problem count",g.blocked_workers_button.disabled and g._blocked_worker_ids().is_empty())
	var command=g.commands.pop_front();g._execute(command);g._update_vision();g._refresh_workforce_buttons()
	check("ordinary gather resumed and removed from list",real.state=="gather" and g._blocked_worker_ids().is_empty())
	# Controlled stale/paused/UI cases. No authority bypass in production code.
	real.state="idle";real.path.clear();real.path_pending=false;real.path_request_kind="work";real.path_status="NO_PATH";real.path_request_target=source.id
	g._update_vision();g._select([scout.id]);g.compact_menu.show();g._refresh_workforce_buttons()
	g._submit("stop",{"ids":[real.id]});g._select_blocked_workers()
	check("stale click does not select pending unit",g.selected==[scout.id])
	g.commands.clear();g.paused=true;g._refresh_workforce_buttons();g._select_blocked_workers()
	check("paused action disabled",g.blocked_workers_button.disabled and g.selected==[scout.id])
	g.paused=false;g._refresh_workforce_buttons();g._set_shortcut_category("army");g._select_blocked_workers()
	check("hidden category cannot activate",not g.blocked_workers_button.visible and g.selected==[scout.id])
	g._set_shortcut_category("economy")
	for width in [320,390,844]:
		root.size=Vector2i(width,600);g._layout_ui();await process_frame;await process_frame
		check("problem button fits width "+str(width),g.blocked_workers_button.get_global_rect().end.x<=g.compact_menu.get_global_rect().end.x)
	check("economy conserved",g.economy.audit().ok and g.economy.bank_milli(0)==bank)
	finish(g)
func finish(g):
	var failed=checks.filter(func(c):return not c.passed).size();print(JSON.stringify({"suite":"blocked_workers_contract","checks":checks,"failed":failed,"scope":"Controlled terminal route fixture plus normal order execution; not natural route recovery or phone acceptance"}));g.queue_free();quit(1 if failed else 0)

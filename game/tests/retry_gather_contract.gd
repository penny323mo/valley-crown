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
	g._update_vision();g._select([real.id]);g._update_hud()
	check("failed work offers retry",not g.retry_gather_button.disabled)
	var bank=g.economy.bank_milli(0).duplicate();g._retry_selected_gather()
	check("one guarded retry queued",g.commands.size()==1 and g.commands[0].get("retry_gather",false))
	g._retry_selected_gather();check("repeat click deduplicated",g.commands.size()==1)
	var command=g.commands.pop_front();g._execute(command)
	check("ordinary gather resumed",real.state=="gather" and real.target==source.id)
	check("retry does not gift resources",g.economy.bank_milli(0)==bank)
	g._execute({"type":"order","team":0,"ids":[real.id],"target":source.id,"retry_gather":true})
	check("stale retry cannot restart working unit",real.state=="gather")
	check("economy conserved",g.economy.audit().ok)
	finish(g)
func finish(g):
	var failed=checks.filter(func(c):return not c.passed).size();print(JSON.stringify({"suite":"retry_gather_contract","checks":checks,"failed":failed,"scope":"Controlled terminal route fixture plus normal order execution; not natural route recovery or phone acceptance"}));g.queue_free();quit(1 if failed else 0)

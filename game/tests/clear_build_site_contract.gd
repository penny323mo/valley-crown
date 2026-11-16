extends SceneTree
const Rules=preload("res://scripts/rules.gd")
var checks=[]
func check(label,ok):
	checks.append({"name":label,"passed":bool(ok)})
	if not ok:push_error(label)
func _initialize():call_deferred("run")
func run():
	var g=load("res://main.tscn").instantiate();root.add_child(g);g.set_process(false);g.test_mode=true;g.ai_enabled=false;g._test_reset();g.set_process(false);await process_frame
	var worker=g._first(0,"villager");g._select([worker.id]);g._start_build("house")
	var site=Vector3.INF;var distance=INF
	for y in Rules.MAP_SIZE:
		for x in Rules.MAP_SIZE:
			var point=g._point(Vector2i(x,y));var d=point.distance_squared_to(worker.pos)
			if d<distance and g._placement_reason("house",point,0,worker.id).is_empty():site=point;distance=d
	g.pointer_world=site
	var bank=g.economy.bank_milli(0).duplicate(true)
	check("controlled visible empty site valid",g._placement_reason("house",site,0,worker.id).is_empty())
	g.build_preview_held=true
	var blocker=g._spawn("scout",0,site)
	g._update_vision();g._update_hud()
	check("unit obstruction identified",g._placement_reason("house",site,0,worker.id)=="地點有單位")
	var plan=g._clear_site_plan()
	check("only blocking owned unit included",plan.size()==1 and plan[0].ids==[blocker.id])
	check("clear action available",is_instance_valid(g.clear_site_button) and not g.clear_site_button.disabled)
	g._clear_build_site()
	check("one ordinary move and no build order",g.commands.size()==1 and g.commands[0].type=="order" and g.commands[0].target==-1)
	check("preview remains held for later confirmation",g.build_mode=="house" and g.build_preview_held and g.pointer_world==site)
	g._clear_build_site();check("rapid repeated press does not duplicate",g.commands.size()==1)
	for i in 240:
		g._tick(Rules.TICK)
		if g._placement_reason("house",site,0,worker.id).is_empty():break
	check("native movement clears footprint",g._placement_reason("house",site,0,worker.id).is_empty())
	check("no building purchased or payment taken",g.economy.bank_milli(0)==bank and g._count(0,"house")==0)
	var outsider=g._spawn("scout",0,site+Vector3(10,0,0))
	g._update_vision();g._update_hud()
	check("outside units never displaced",g._clear_site_plan().is_empty())
	blocker.pos=site;g._update_vision();g._update_hud()
	g.clear_site_button.set_meta("site_identity",["house",Vector3.INF,[worker.id]])
	g._clear_build_site();check("stale preview identity rejected",g.commands.is_empty())
	g.paused=true;g._update_hud();g._clear_build_site();check("paused action cannot command",g.commands.is_empty() and g.clear_site_button.disabled)
	g.paused=false;g.build_preview_held=false;g._update_hud();check("unconfirmed hover cannot displace units",g.clear_site_button.disabled)
	check("no automatic construction",g._count(0,"house")==0)
	blocker.team=1;g.build_preview_held=true;g._update_vision();g._update_hud()
	check("enemy blocker never given move orders",g._clear_site_plan().is_empty())
	blocker.team=0;blocker.pos=plan[0].position;g._update_vision();g._update_hud()
	g._confirm_build()
	check("separate explicit confirmation still required",g.commands.size()==1 and g.commands[0].type=="build")
	if not g.commands.is_empty():g._execute(g.commands.pop_front())
	check("ordinary build applies after clearance and confirmation",g._count(0,"house")==1 and g.economy.bank_milli(0)!=bank)
	check("ledger conservation",g.economy.audit().ok)
	var failed=checks.filter(func(c):return not c.passed).size()
	print(JSON.stringify({"suite":"clear_build_site_contract","checks":checks,"failed":failed,"scope":"Controlled native clear route; no claim that all blockers or unreachable plots can be cleared"}))
	g.queue_free();quit(1 if failed else 0)

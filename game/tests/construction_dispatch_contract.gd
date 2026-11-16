extends SceneTree
const Dispatch=preload("res://scripts/construction_dispatch.gd")
var checks=[]
func check(label,ok):
	checks.append({"name":label,"passed":bool(ok)})
	if not ok: push_error(label)
func _initialize(): call_deferred("run")
func run():
	var g=load("res://main.tscn").instantiate(); root.add_child(g); g.set_process(false); g.test_mode=true; g.ai_enabled=false; g._test_reset(); g.set_process(false)
	await process_frame
	var w=g._first(0,"villager"); var point=Vector3.INF
	for z in range(-6,7):
		for x in range(-6,7):
			var p=g._snap_build_position("house",g.MapRoutes.PLAYER_HOME+Vector3(x,0,z))
			if g._placement_reason("house",p,0,w.id).is_empty(): point=p; break
		if point!=Vector3.INF: break
	check("legal paid construction location",point!=Vector3.INF)
	if point==Vector3.INF: finish(g); return
	var site=g._place_building("house",point,w.id,0)
	check("ordinary purchase succeeds",not site.is_empty())
	if site.is_empty(): finish(g); return
	g._update_vision(); g._select([site.id]); g._update_hud()
	check("active builder not replaced",g.construction_dispatch_button.disabled)
	g._set_stance(w,"STOP"); g._update_vision(); g._update_hud()
	check("abandoned site offers resume",not g.construction_dispatch_button.disabled)
	var plan=Dispatch.plan(g.faction_views[0].records(),g.commands,site.id)
	check("idle worker identified",plan.worker>=0)
	var bank=g.economy.bank_milli(0).duplicate(); var ticks=site.build_ticks
	g._request_construction_dispatch(site.id)
	check("one explicit construction order",g.commands.size()==1 and g.commands[0].get("construction_dispatch",false))
	g._request_construction_dispatch(site.id)
	check("repeat click no duplicate",g.commands.size()==1)
	check("resume never charges or instant builds",g.economy.bank_milli(0)==bank and site.build_ticks==ticks)
	var cmd=g.commands.pop_front(); g._execute(cmd); var chosen=g._get_entity(plan.worker)
	check("normal construction assigned",chosen.state=="build" and chosen.target==site.id)
	var approach=g._free_adjacent(site,chosen.pos,false,0,chosen)
	check("controlled work point",approach!=Vector3.INF)
	if approach!=Vector3.INF:
		chosen.pos=approach; chosen.path.clear(); chosen.path_pending=false; g._update_unit(chosen,g.Rules.TICK)
		check("real construction work advances original progress",site.build_ticks==ticks+1 and g.economy.bank_milli(0)==bank)
	g._set_stance(chosen,"STOP"); site.built=true
	g._execute({"type":"order","team":0,"target":site.id,"ids":[chosen.id],"construction_dispatch":true})
	check("completed site never becomes movement",chosen.state=="idle")
	site.built=false; chosen.state="gather"
	g._execute({"type":"order","team":0,"target":site.id,"ids":[chosen.id],"construction_dispatch":true})
	check("new worker job preserved",chosen.state=="gather")
	check("economy conserved",g.economy.audit().ok)
	finish(g)
func finish(g):
	var failed=checks.filter(func(c):return not c.passed).size()
	print(JSON.stringify({"suite":"construction_dispatch_contract","checks":checks,"failed":failed,"scope":"Controlled paid site and real work tick; no routed touch/iPhone acceptance"}))
	g.queue_free(); quit(1 if failed else 0)

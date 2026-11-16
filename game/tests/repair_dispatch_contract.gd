extends SceneTree
const Dispatch=preload("res://scripts/repair_dispatch.gd")
var checks=[]
func check(label,ok):
	checks.append({"name":label,"passed":bool(ok)})
	if not ok: push_error(label)
func worker(id,pos): return {"id":id,"owned":true,"alive":true,"team":0,"category":"unit","kind":"villager","state":"idle","pos":pos,"cargo_milli":0,"carry":0.0}
func _initialize(): call_deferred("run")
func run():
	var b={"id":10,"owned":true,"alive":true,"team":0,"category":"building","kind":"house","built":true,"hp":100,"max_hp":250,"last_damage_tick":0,"pos":Vector3.ZERO}
	var records={10:b,1:worker(1,Vector3(8,0,0)),2:worker(2,Vector3(2,0,0))}
	check("closest idle worker",Dispatch.plan(records,[],10,100).worker==2)
	check("damage cooldown",Dispatch.plan(records,[],10,99).worker==-1)
	check("pending worker not stolen",Dispatch.plan(records,[{"type":"stop","team":0,"ids":[2]}],10,100).worker==1)
	check("target request not duplicated",Dispatch.plan(records,[{"type":"order","team":0,"target":10,"ids":[1]}],10,100).worker==-1)
	records[2].cargo_milli=1000
	check("cargo preserved",Dispatch.plan(records,[],10,100).worker==1)
	records[2].cargo_milli=0; records[2].state="gather"
	check("gatherers not stolen",Dispatch.plan(records,[],10,100).worker==1)
	records[2].state="repair"; records[2].target=10
	check("existing repair not duplicated",Dispatch.plan(records,[],10,100).worker==-1)
	for change in [{"owned":false},{"alive":false},{"remembered":true},{"team":1},{"built":false},{"hp":250}]:
		var copy=b.duplicate(); copy.merge(change,true)
		check("reject target "+str(change),Dispatch.plan({10:copy,1:worker(1,Vector3.ZERO)},[],10,100).worker==-1)
	var g=load("res://main.tscn").instantiate(); root.add_child(g); g.set_process(false); g.test_mode=true; g.ai_enabled=false; g._test_reset(); g.set_process(false)
	await process_frame
	var center=g._first(0,"town_center"); center.hp-=100; center.last_damage_tick=-1000
	g._update_vision(); g._select([center.id]); g._update_hud()
	var plan=Dispatch.plan(g.faction_views[0].records(),g.commands,center.id,g.tick_count)
	check("real dispatch available",plan.worker>=0 and not g.repair_dispatch_button.disabled)
	var hp=center.hp; var bank=g.economy.bank_milli(0).duplicate()
	g._request_repair_dispatch(center.id)
	check("one explicit order queued",g.commands.size()==1 and g.commands[0].get("repair_dispatch",false))
	g._request_repair_dispatch(center.id)
	check("repeat click no duplicate",g.commands.size()==1)
	check("no premature heal or charge",center.hp==hp and g.economy.bank_milli(0)==bank)
	var cmd=g.commands.pop_front(); var w=g._get_entity(plan.worker)
	g._execute(cmd)
	check("ordinary repair started",w.state=="repair" and w.target==center.id)
	var adjacent=g._free_adjacent(center,w.pos,false,0,w)
	check("controlled repair work point exists",adjacent!=Vector3.INF)
	if adjacent!=Vector3.INF:
		w.pos=adjacent; w.path.clear(); w.path_pending=false
		var spent=g.economy.stats_view(0).repaired.wood
		for i in 20:
			g.tick_count+=1; g._update_unit(w,0.05)
		check("real paid repair restores five HP",center.hp==hp+5 and g.economy.stats_view(0).repaired.wood==spent+1000)
	w.state="idle"; w.path.clear(); w.path_pending=false; center.hp=center.max_hp
	g._execute({"type":"order","team":0,"ids":[w.id],"target":center.id,"repair_dispatch":true})
	check("healed target never becomes move",w.state=="idle")
	center.hp-=20; w.state="gather"
	g._execute({"type":"order","team":0,"ids":[w.id],"target":center.id,"repair_dispatch":true})
	check("worker changed job preserved",w.state=="gather")
	check("economy conserved",g.economy.audit().ok)
	var failed=checks.filter(func(c):return not c.passed).size()
	print(JSON.stringify({"suite":"repair_dispatch_contract","checks":checks,"failed":failed,"scope":"Controlled engine/direct GUI calls, not routed touch or iPhone acceptance"}))
	g.queue_free(); quit(1 if failed else 0)

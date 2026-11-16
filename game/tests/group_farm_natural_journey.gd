extends SceneTree
# Ordinary starting funds, natural sight, construction timing and paid births.
# AI disabled for a repeatable economy journey, not match/phone/rendered acceptance.
var checks={}
func _init():call_deferred("run")
func plot(g,worker,anchor):
	var best=Vector3.INF;var distance=INF
	for y in g.Rules.MAP_SIZE:
		for x in g.Rules.MAP_SIZE:
			var p=g._point(Vector2i(x,y));var d=p.distance_squared_to(worker.pos)
			if anchor.is_finite() and p.distance_squared_to(anchor)>64.0:continue
			if d<distance and g._placement_reason("farm",p,0,worker.id).is_empty():best=p;distance=d
	return best
func run():
	var g=load("res://main.tscn").instantiate();root.add_child(g);g.test_mode=true;g.ai_enabled=false;g._test_reset();g.set_process(false);await process_frame
	var worker=g._first(0,"villager");var farms=[];var anchor=Vector3.INF
	var wood_before=g.economy.bank_milli(0).wood
	for n in 2:
		var p=plot(g,worker,anchor);checks["legal visible farm plot "+str(n)]=p.is_finite()
		if not p.is_finite():break
		g._select([worker.id]);g._start_build("farm");g.pointer_world=p;g.build_preview_held=true;g._update_ghost()
		checks["ordinary green preview "+str(n)]=g.placement_ok
		g._confirm_build();g._tick(g.Rules.TICK)
		var site={}
		for ent in g.entities:
			if ent.alive and ent.team==0 and ent.kind=="farm" and not ent.built:site=ent
		for i in 1200:
			if site.is_empty() or site.built:break
			g._tick(g.Rules.TICK)
		checks["physical construction completed "+str(n)]=not site.is_empty() and site.built
		if site.is_empty() or not site.built:break
		farms.append(site);anchor=farms[0].pos
	checks["two farms paid ordinary 120 wood"]=farms.size()==2 and g.economy.bank_milli(0).wood==wood_before-120000
	if farms.size()==2:
		g._submit("stop",{"ids":[worker.id]});g._tick(g.Rules.TICK)
		checks["normal stop frees builder farm"]=g.economy.farm_view(farms[1].id).worker_id==-1
		var town=g._first(0,"town_center");var count=g._count(0,"villager");var food_before=g.economy.bank_milli(0).food
		var initial_ids=[]
		for ent in g.entities:
			if ent.alive and ent.team==0 and ent.kind=="villager":initial_ids.append(ent.id)
		g._submit("train",{"building":town.id,"kind":"villager"});g._submit("train",{"building":town.id,"kind":"villager"});g._tick(g.Rules.TICK)
		checks["two queued villagers cost ordinary 100 food"]=g.economy.bank_milli(0).food==food_before-100000 and town.queue.size()==2
		for i in 1600:
			g._tick(g.Rules.TICK)
			if g._count(0,"villager")==count+2:break
		var group=[]
		for ent in g.entities:
			if ent.alive and ent.team==0 and ent.kind=="villager" and ent.id not in initial_ids:group.append(ent.id)
		g._submit("order",{"ids":group,"target":farms[0].id,"position":farms[0].pos,"farm_gather":true});g._tick(g.Rules.TICK)
		var a=g.economy.farm_view(farms[0].id).worker_id;var b=g.economy.farm_view(farms[1].id).worker_id
		checks["both paid villagers born"]=g._count(0,"villager")==count+2 and town.queue.is_empty()
		checks["newborns own separate nearby farms"]=a>=0 and b>=0 and a!=b and a!=worker.id and b!=worker.id
		var delivered=g.delivered_total[0]
		for i in 1600:
			g._tick(g.Rules.TICK)
			if g.delivered_total[0]>delivered:break
		checks["group-commanded farms really produce delivered food"]=g.delivered_total[0]>delivered
	checks["economy conserved"]=g.economy.audit().ok
	var failed=0
	for value in checks.values():if not value:failed+=1
	print(JSON.stringify({"suite":"group_farm_natural_journey","build":g.Rules.BUILD_ID,"checks":checks,"failed":failed,"ticks":g.tick_count,"scope":"normal starting funds and sight, full construction and paid production, AI off; no phone/render acceptance"}));g.queue_free();quit(1 if failed else 0)

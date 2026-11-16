extends SceneTree
## Scripted player using only own public observations, bank and ordinary commands.
const Rules=preload("res://scripts/rules.gd")
var game
var samples=[]
var scout_stage=0
var policy_log=[]
var milestones={}
var dispatched={}
func _initialize():call_deferred("run")
func submit(kind,data):
	game._submit(kind,data,0)
	policy_log.append({"tick":game.tick_count,"type":kind,"data":data.duplicate(true)})
func afford(kind,bank):
	for resource in Rules.COSTS[kind]:
		if bank.get(resource,0)<Rules.COSTS[kind][resource]:return false
	return true
func player_turn():
	var records=game.faction_views[0].records().values()
	var own=[];var workers=[];var army=[];var buildings=[];var keep={};var capacity=0;var population=0;var food_workers=0;var bank=game.economy.bank_units_floor(0)
	for e in records:
		if not e.get("owned",false) or not e.alive:continue
		own.append(e)
		if e.category=="unit":
			population+=1
			if e.kind=="villager":
				workers.append(e)
				if e.get("gather_type","")=="food" and e.state in ["gather","deliver"]:food_workers+=1
			else:army.append(e)
		else:
			buildings.append(e)
			for q in e.queue:
				if not q.get("research",false):population+=1
			if e.kind=="town_center":keep=e
			if e.built:capacity+=10 if e.kind=="town_center" else (5 if e.kind=="house" else 0)
	if keep.is_empty():return
	var wanted=""
	var have={}
	for b in buildings:have[b.kind]=true
	if capacity-population<=2 and capacity<Rules.POP_LIMIT and buildings.all(func(b):return b.built or b.kind!="house"):wanted="house"
	elif not have.has("barracks"):wanted="barracks"
	elif not have.has("range"):wanted="range"
	var builder_id=-1
	if wanted!="" and afford(wanted,bank):
		for worker in workers:
			if worker.state in ["build","repair"] or worker.get("gather_type","")=="food":continue
			for offset in [Vector3(4,0,0),Vector3(0,0,5),Vector3(-5,0,0),Vector3(4,0,5),Vector3(0,0,-5),Vector3(-5,0,5),Vector3(8,0,0)]:
				var point=keep.pos+offset
				if game._placement_reason(wanted,point,0,worker.id).is_empty():
					submit("build",{"kind":wanted,"position":point,"builder":worker.id});builder_id=worker.id
					for resource in Rules.COSTS[wanted]:bank[resource]-=Rules.COSTS[wanted][resource]
					break
			if builder_id>=0:break
	for worker in workers:
		if worker.id==builder_id or worker.state!="idle":continue
		var desired="food" if food_workers<3 else "wood"
		var choices=[]
		for resource in records:
			if resource.category=="resource" and not resource.remembered and ((desired=="food" and resource.kind=="berry") or (desired=="wood" and resource.kind in ["pine","oak"])):choices.append(resource)
		choices.sort_custom(func(a,b):return a.pos.distance_squared_to(worker.pos)<b.pos.distance_squared_to(worker.pos))
		if not choices.is_empty():
			submit("order",{"ids":[worker.id],"target":choices[0].id,"position":choices[0].pos})
			if desired=="food":food_workers+=1
	var queued_workers=0
	for q in keep.queue:
		if q.kind=="villager":queued_workers+=1
	if workers.size()+queued_workers<8 and keep.queue.size()<2 and population<capacity and afford("villager",bank):
		submit("train",{"building":keep.id,"kind":"villager"});bank.food-=50;population+=1
	for b in buildings:
		if not b.built or b.kind not in ["barracks","range"] or b.queue.size()>=2:continue
		var product=Rules.products_for(b.kind)[0]
		if population<capacity and afford(product,bank):
			submit("train",{"building":b.id,"kind":product});population+=1
			for resource in Rules.COSTS[product]:bank[resource]-=Rules.COSTS[product][resource]
	for soldier in army:
		if soldier.kind=="scout" and scout_stage<2 and soldier.state=="idle":
			submit("advance",{"ids":[soldier.id],"position":Vector3.ZERO if scout_stage==0 else Vector3(25,0,-24)})
			scout_stage+=1
	# Ordinary attack-move from home toward the public centre, never hidden targets.
	if game.game_time>=95:
		var departures=[]
		for soldier in army:
			if soldier.kind!="scout" and not dispatched.has(soldier.id):
				departures.append(soldier.id);dispatched[soldier.id]=true
		if not departures.is_empty():submit("advance",{"ids":departures,"position":Vector3.ZERO})
func record():
	var troops=[{},{}];var buildings=[{},{}];var details=[]
	for e in game.entities:
		if not e.alive or e.team not in [0,1]:continue
		if e.category=="unit":troops[e.team][e.kind]=troops[e.team].get(e.kind,0)+1
		elif e.built:buildings[e.team][e.kind]=buildings[e.team].get(e.kind,0)+1
		var row={}
		for key in ["id","team","kind","state","target","hp","built","pos","dest","gather_type","resource_target","work_epoch","path_status","path_reason","path_next_attempt_tick","path_failures","mode","advance_engaged","auto_target","last_damage_tick","last_attack_tick"]:row[key]=e.get(key,null)
		row.queue=e.queue.duplicate(true);row.cargo_milli=game.economy.worker_view(e.id).get("cargo_milli",0) if e.kind=="villager" else 0
		details.append(row)
	var s={"tick":game.tick_count,"seconds":game.game_time,"troops":troops,"buildings":buildings,"banks":[game.economy.bank_units_floor(0),game.economy.bank_units_floor(1)],"delivered":game.delivered_total.duplicate(),"trained":game.trained_total.duplicate(),"ai":game.ai_status.duplicate(true),"raids":game.ai_raids,"settled_attacks":game.attack_ledger._settled_through,"outcome":game.outcome,"paused":game.paused,"toast":game.toast_label.text,"ledger_ok":game.economy.audit().ok,"entities":details}
	samples.append(s);print("SAMPLE "+JSON.stringify(s))
func run():
	game=load("res://main.tscn").instantiate();root.add_child(game);game.set_process(false);game.test_mode=true
	game._test_reset();game.set_process(false);game.ai_enabled=true;game.skirmish_mode="pressure"
	await process_frame
	record()
	for i in 3200:
		if i%20==0:player_turn()
		game._tick(Rules.TICK)
		if (i+1)%20==0:
			var observed_keep=false
			for known in game.faction_views[1].records().values():
				if known.team==0 and known.kind=="town_center":observed_keep=true
			if observed_keep and not milestones.has("enemy_keep_known"):milestones.enemy_keep_known=game.tick_count
			if game.ai_raids>0 and not milestones.has("raid_departure"):milestones.raid_departure=game.tick_count
		if (i+1)%200==0:record()
		if game.game_over or game.paused:record();break
	record()
	print("MILESTONES "+JSON.stringify(milestones))
	var attacks=[]
	for attack_id in range(1,game.attack_ledger._settled_through+1):
		var event=game.attack_ledger.event(attack_id)
		var attacker=game._get_entity(event.attacker_id);var target=game._get_entity(event.target_id)
		event.attacker_kind=attacker.get("kind","");event.attacker_team=attacker.get("team",-1)
		event.target_kind=target.get("kind","");event.target_team=target.get("team",-1)
		attacks.append(event)
	var f=FileAccess.open("res://reports/active-opening.json",FileAccess.WRITE);f.store_string(JSON.stringify({"settled_events":attacks,"samples":samples,"player_commands":policy_log,"milestones_ticks":milestones,"scope":"160 seconds ordinary commands and natural authority, pressure AI vs scripted economy with military advance to public centre after 95 seconds; no health/resources/units grants"},"  "));f.close()
	game.queue_free();quit()

extends SceneTree
# External command policy, not product content. No engine run is authorized by this file.
var game
var output := ""
var build := ""
var started := 0
var phases := {}
var events := []
var commands := []
var previous := {}
var last_order := {}
var last_tick := -100
var last_build := -100
var assault := false
var scout_sent := false
var last_keep_hp := -1
var samples := []
var last_sample_tick := -100
var evidence_limit := false
var scout_returning := false

func _initialize(): call_deferred("run")
func records(): return game.faction_views[0].records().values()
func own(kind):
	var result := []
	for r in records():
		if r.owned and r.alive and r.kind == kind: result.append(r)
	result.sort_custom(func(a,b): return a.id < b.id)
	return result
func row(r):
	var result := {}
	for key in ["id","kind","team","owned","hp","max_hp","built","progress","remembered","cargo_milli","state","target","visual_attack_tick","visual_hit_tick"]:
		if r.has(key): result[key] = r[key]
	result.position = [r.pos.x,r.pos.y,r.pos.z]
	if r.owned:
		for key in ["path_status","path_reason","path_pending","gather_type","carry_type","queue"]:
			if r.has(key): result[key]=r[key]
		if r.has("path"): result.path_points=r.path.size()
		if r.has("dest"): result.destination=[r.dest.x,r.dest.y,r.dest.z]
	return result
func current_public():
	var result := []
	for r in records(): result.append(row(r))
	return result
func sample_public():
	if samples.size()>=64: return
	var units := []
	for r in records():
		if r.owned or (r.team==1 and not r.remembered): units.append(row(r))
	samples.append({"tick":game.tick_count,"snapshot":game._snapshot(),"public_records":units})
func save(reason):
	var passed := true
	for key in ["menu_started","cargo_collected","cargo_deposited","house_complete","barracks_complete","range_complete","spearman_produced","archer_produced","enemy_attack_observed","own_health_loss","enemy_health_loss","enemy_keep_damaged","normal_victory"]:
		if not phases.has(key): passed = false
	var report := {"schema":"vc-normal-full-match-v1","passed":passed,"stop_reason":reason,"build":build,
		"game_sha256":FileAccess.get_sha256("res://scripts/game.gd"),"rules_sha256":FileAccess.get_sha256("res://scripts/rules.gd"),
		"phases":phases,"events":events,"commands":commands,"final":game._snapshot(),
		"policy_version":"ordinary-policy-v2","public_samples":samples,"final_public_records":current_public(),
		"wall_seconds":(Time.get_ticks_msec()-started)/1000.0,"engine_time_scale":Engine.time_scale,
		"scope":"headless normal _process, fixed-fps30, ordinary command policy; not realtime or touch",
		"not_verified":["screenshots","Web","physical touch","iPhone","realtime performance"]}
	var file := FileAccess.open(output,FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(report,"  ")); file.close()
	return passed
func finish(reason): quit(0 if save(reason) else 1)
func phase(label, detail = {}):
	if phases.has(label): return
	phases[label] = game.tick_count
	var public := []
	for r in records(): public.append(row(r))
	events.append({"label":label,"tick":game.tick_count,"detail":detail,"snapshot":game._snapshot(),"public_records":public})
	print("FULL_MATCH_PHASE ",label," tick=",game.tick_count)
	save("in_progress")
func submit(kind, payload):
	if commands.size()>=2048: evidence_limit=true; return
	game._submit(kind,payload)
	var copy: Dictionary = payload.duplicate(true)
	if copy.has("position"):
		var p: Vector3 = copy.position
		copy.position = [p.x,p.y,p.z]
	var evidence := {}
	if kind=="order" and payload.get("target",-1)>=0:
		var target = game.faction_views[0].records().get(payload.target,{})
		if not target.is_empty(): evidence=row(target)
	commands.append({"type":kind,"tick":game.tick_count,"payload":copy,"public_target_at_submit":evidence})
func order(unit, target, point):
	var signature := "target:"+str(target) if target>=0 else "ground:"+str(point)
	if last_order.get(unit.id,"") == signature and unit.state != "idle": return
	if target<0 and unit.state=="idle" and unit.pos.distance_to(point)<=3.0: return
	submit("order",{"ids":[unit.id],"target":target,"position":point})
	last_order[unit.id] = signature
func observe():
	for r in records():
		if r.remembered: continue
		if r.owned and r.kind in ["spearman","archer"]: phase(r.kind+"_produced",row(r))
		if r.owned and r.built and r.kind in ["house","barracks","range"]: phase(r.kind+"_complete",row(r))
		if r.owned and r.get("cargo_milli",0)>0: phase("cargo_collected",row(r))
		if r.team == 1 and r.get("visual_attack_tick",-1)>=0: phase("enemy_attack_observed",row(r))
		if previous.has(r.id) and r.hp < previous[r.id].hp and (r.owned or r.team == 1):
			phase("own_health_loss" if r.owned else "enemy_health_loss",{"before":previous[r.id],"after":row(r)})
		if r.team == 1 and r.kind == "town_center":
			last_keep_hp = r.hp
			if r.hp<r.max_hp: phase("enemy_keep_damaged",row(r))
		previous[r.id] = row(r)
	if game._snapshot().delivered>0: phase("cargo_deposited")
func resource_for(worker, food):
	var best := {}; var distance := INF
	for r in records():
		if r.category != "resource" or r.remembered or (r.kind == "berry") != food: continue
		var d: float = worker.pos.distance_squared_to(r.pos)
		if d<distance: distance=d; best=r
	return best
func afford(kind,budget):
	for key in game.Rules.COSTS[kind]:
		if budget.get(key,0)<game.Rules.COSTS[kind][key]: return false
	return true
func spend(kind,budget):
	for key in game.Rules.COSTS[kind]: budget[key]-=game.Rules.COSTS[kind][key]
func decide():
	var workers = own("villager"); var snapshot = game._snapshot()
	var budget := {"food":snapshot.food,"wood":snapshot.wood}
	var kind := ""; var claimed := -1
	for candidate in ["barracks","range"]:
		if own(candidate).is_empty(): kind=candidate; break
	if kind.is_empty() and snapshot.capacity<20 and snapshot.capacity-snapshot.population<=2:
		var house_pending := false
		for house in own("house"):
			if not house.built: house_pending=true
		if not house_pending: kind="house"
	if not kind.is_empty() and afford(kind,budget) and game.tick_count-last_build>=100:
		last_build=game.tick_count
		for worker in workers:
			if worker.state=="build": continue
			for point in game.MapRoutes.build_plots(0,game.Rules.FOOTPRINT[kind]):
				# Only the ordinary player-preview validator; never inspect hidden entities.
				if game._placement_reason(kind,point,0,worker.id).is_empty():
					submit("build",{"kind":kind,"position":point,"builder":worker.id})
					claimed=worker.id; spend(kind,budget); break
			if claimed>=0: break
	for index in workers.size():
		var worker = workers[index]
		if worker.id==claimed or worker.state=="build" or worker.state=="deliver" or worker.get("cargo_milli",0)>0: continue
		var desired := "wood" if index<mini(4,maxi(2,workers.size()-2)) else "food"
		if worker.state!="idle" and (worker.state!="gather" or worker.get("gather_type","")==desired): continue
		var target = resource_for(worker,index>=mini(4,maxi(2,workers.size()-2)))
		if not target.is_empty(): order(worker,target.id,target.pos)
	# HUD population already includes all queued reservations.
	var slots: int = snapshot.capacity-snapshot.population
	var archers_committed: int = own("archer").size()
	for range_site in own("range"): archers_committed+=range_site.queue.size()
	for producer_kind in ["town_center","range","barracks"]:
		for producer in own(producer_kind):
			if not producer.built or producer.queue.size()>=1 or slots<=0: continue
			var unit_kind: String = game.Rules.PRODUCES[producer_kind]
			if unit_kind=="villager" and workers.size()+producer.queue.size()>=7: continue
			if unit_kind=="archer" and archers_committed>=2 and own("spearman").size()<4: continue
			if not afford(unit_kind,budget): continue
			# Reserve the next producer, then the first archer. Spend only earned bank.
			if unit_kind=="spearman":
				var reserve_wood := 120 if own("range").is_empty() else (45 if archers_committed==0 else 0)
				if budget.wood-20<reserve_wood or (archers_committed==0 and budget.food-50<25): continue
			submit("train",{"building":producer.id,"kind":unit_kind}); spend(unit_kind,budget); slots-=1
			if unit_kind=="archer": archers_committed+=1
	var army: Array = own("spearman")+own("archer")
	var home := {}; var threat := {}; var enemy_keep := {}
	var castles = own("town_center")
	if not castles.is_empty(): home=castles[0]
	for r in records():
		if r.team!=1: continue
		if r.kind=="town_center": enemy_keep=r
		if not r.remembered and r.category=="unit" and not home.is_empty() and r.pos.distance_to(home.pos)<15:
			if threat.is_empty() or r.hp<threat.hp: threat=r
	if not scout_sent:
		for unit in own("scout"): order(unit,-1,Vector3(22,0,-22)); scout_sent=true
	if not enemy_keep.is_empty(): scout_returning=true
	if scout_returning and not assault and threat.is_empty() and not home.is_empty():
		for unit in own("scout"): order(unit,-1,home.pos+Vector3(5,0,-5))
	if army.size()>=5 and phases.has("archer_produced") and phases.has("spearman_produced"): assault=true
	if scout_returning: army+=own("scout")
	var defenders := []
	if not threat.is_empty():
		phase("home_defense",row(threat))
		var by_home: Array = army.duplicate()
		by_home.sort_custom(func(a,b): return a.pos.distance_squared_to(home.pos)<b.pos.distance_squared_to(home.pos))
		# Preserve a committed assault while new/local reinforcements defend.
		# If none are near home, recall the closest two. Never ignore a threat.
		for unit in by_home:
			if not assault or unit.pos.distance_to(home.pos)<=20 or defenders.size()<2:
				defenders.append(unit.id); order(unit,threat.id,threat.pos)
	for unit in army:
		if unit.id in defenders: continue
		if assault:
			phase("army_marches")
			if enemy_keep.is_empty(): order(unit,-1,Vector3(22,0,-22))
			else: order(unit,-1 if enemy_keep.remembered else enemy_keep.id,enemy_keep.pos)
		elif unit.state=="idle" and not home.is_empty(): order(unit,-1,home.pos+Vector3(5,0,-5))
func run():
	var args := OS.get_cmdline_user_args()
	if args.size()!=2: quit(2); return
	output=args[0]; build=args[1]
	if FileAccess.file_exists(output): quit(2); return
	started=Time.get_ticks_msec()
	if DisplayServer.get_name()!="headless" or not is_equal_approx(Engine.time_scale,1.0): quit(2); return
	root.size=Vector2i(390,844)
	var shell=load("res://main_menu.tscn").instantiate(); root.add_child(shell)
	for i in 3: await process_frame
	var start_button = shell.buttons.get_node("StartMatchButton")
	if shell.match_node != null or not start_button.is_visible_in_tree(): quit(2); return
	start_button.pressed.emit()
	for i in 2: await process_frame
	game=shell.match_node
	if not is_instance_valid(game) or game.Rules.BUILD_ID!=build: quit(2); return
	await play()
func play():
	phase("menu_started")
	if game.tutorial_skip.is_visible_in_tree(): game.tutorial_skip.pressed.emit()
	while true:
		await process_frame
		if Time.get_ticks_msec()-started>=100000: finish("bounded_100s_wall_incomplete"); return
		if evidence_limit: finish("bounded_command_evidence_limit"); return
		if game.tick_count-last_sample_tick>=100:
			last_sample_tick=game.tick_count; sample_public()
		if game.test_mode or not game.ai_enabled or not is_equal_approx(Engine.time_scale,1.0): finish("invalid_runtime_mode"); return
		observe()
		if game.game_over:
			if game.outcome=="victory" and game.end_reason=="keep_destroyed" and last_keep_hp>=0:
				phase("normal_victory",{"reason":game.end_reason,"title":game.end_title.text,"last_public_keep_hp":last_keep_hp})
			finish("match_ended_"+game.outcome); return
		if game.tick_count-last_tick>=20: last_tick=game.tick_count; decide()

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
var builder_sites := {}
var recovery_seen := {}
var recovery_counts := {}
var recovery_next_tick := {}
var recovery_workers := {}
var cargo_returns := {}
var recovery_events := []
var process_frames_seen := 0
var observation_calls := 0
var observation_usec := 0
var decision_calls := 0
var decision_usec := 0
var last_observed_tick := -1
var coverage := {}
var throughput_samples := []
var last_throughput_ms := 0

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
	for key in ["id","kind","team","owned","alive","hp","max_hp","built","progress","remembered","cargo_milli","state","target","visual_attack_tick","visual_hit_tick"]:
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
	samples.append({"tick":game.tick_count,"wall_ms":Time.get_ticks_msec()-started,"snapshot":game._snapshot(),"public_records":units})
func save(reason):
	var passed := true
	for key in ["menu_started","cargo_collected","cargo_deposited","house_complete","barracks_complete","range_complete","spearman_produced","archer_produced","enemy_attack_observed","own_health_loss","enemy_health_loss","enemy_keep_damaged","normal_victory"]:
		if not phases.has(key): passed = false
	var report := {"schema":"vc-normal-full-match-v1","passed":passed,"stop_reason":reason,"build":build,
		"game_sha256":FileAccess.get_sha256("res://scripts/game.gd"),"rules_sha256":FileAccess.get_sha256("res://scripts/rules.gd"),
		"phases":phases,"events":events,"commands":commands,"final":game._snapshot(),
		"policy_version":"ordinary-integrated-270-v1","public_samples":samples,"final_public_records":current_public(),"recovery_events":recovery_events,
		"wall_seconds":(Time.get_ticks_msec()-started)/1000.0,"engine_time_scale":Engine.time_scale,
		"scope":"headless normal _process, fixed-fps30, ordinary command policy; not realtime or touch",
		"throughput":{"process_frames_observed":process_frames_seen,"simulation_ticks":game.tick_count,"game_seconds":game.tick_count*game.Rules.TICK,"observation_calls":observation_calls,"observation_usec":observation_usec,"decision_calls":decision_calls,"decision_usec":decision_usec,"samples":throughput_samples,"interpretation":"Normal _process including presentation and AI; fixed-fps30 hosted throughput, not realtime/mobile frame rate; fixture overhead included"},
		"additional_coverage":coverage,"strategy":"Paid eight-worker spear/archer assault; no forced all-types checklist or advanced-content acceptance claim",
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
		if r.owned:
			var coverage_key: String = ("building:" if r.category=="building" else "unit:")+r.kind
			if r.built and not coverage.has(coverage_key): coverage[coverage_key]={"tick":game.tick_count,"actor":row(r)}
		if r.owned and r.kind=="villager" and r.get("state","")=="build" and r.get("target",-1)>=0:
			builder_sites[r.id]=r.target
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
func resource_for(worker, desired: String):
	var best := {}; var distance := INF
	var kinds: Array = {"food":["berry"],"wood":["pine","oak"],"stone":["stone"],"iron":["iron"]}.get(desired,[])
	for r in records():
		if r.category!="resource" or r.remembered or not r.alive or r.kind not in kinds: continue
		var d: float = worker.pos.distance_squared_to(r.pos)
		if d<distance: distance=d; best=r
	return best
func population_queue(queue: Array) -> int:
	var count := 0
	for item in queue:
		if not item.get("research",false): count+=1
	return count
func throughput_sample():
	var elapsed: int = Time.get_ticks_msec()-started
	if elapsed-last_throughput_ms<10000 or throughput_samples.size()>=10: return
	last_throughput_ms=elapsed
	throughput_samples.append({"wall_ms":elapsed,"tick":game.tick_count,"process_frames":process_frames_seen,"observation_calls":observation_calls,"observation_usec":observation_usec,"decision_calls":decision_calls,"decision_usec":decision_usec})
func afford(kind,budget):
	for key in game.Rules.COSTS[kind]:
		if budget.get(key,0)<game.Rules.COSTS[kind][key]: return false
	return true
func spend(kind,budget):
	for key in game.Rules.COSTS[kind]: budget[key]-=game.Rules.COSTS[kind][key]
func recovery_event(kind, detail):
	if recovery_events.size()>=64: evidence_limit=true; return
	recovery_events.append({"kind":kind,"tick":game.tick_count,"detail":detail})
func recover_work(workers):
	var claimed := []
	var public = game.faction_views[0].records()
	for stopped in workers:
		if stopped.get("state","")!="idle" or stopped.get("path_status","") not in ["NO_PATH","LIMIT_REACHED"]: continue
		var site_id: int = builder_sites.get(stopped.id,-1)
		var site = public.get(site_id,{})
		if site.is_empty() or not site.get("alive",false) or not site.owned or site.remembered or site.built: continue
		var signature := str(stopped.id)+":"+str(site_id)+":"+str(stopped.get("work_epoch",-1))
		if recovery_seen.has(signature) or recovery_counts.get(site_id,0)>=3 or game.tick_count<recovery_next_tick.get(site_id,0): continue
		var attended := false
		for worker in workers:
			if worker.state=="build" and worker.target==site_id: attended=true
		if attended: continue
		var candidates: Array = workers.duplicate()
		candidates.sort_custom(func(a,b):
			var da: float = a.pos.distance_squared_to(site.pos)
			var db: float = b.pos.distance_squared_to(site.pos)
			return a.id<b.id if is_equal_approx(da,db) else da<db)
		var used: Array = recovery_workers.get(site_id,[])
		for replacement in candidates:
			if replacement.id==stopped.id or replacement.id in claimed or replacement.id in used: continue
			if replacement.state not in ["idle","gather"]: continue
			# Same ordinary visible-own-foundation target order as a player takeover.
			submit("order",{"ids":[replacement.id],"target":site_id,"position":site.pos})
			claimed.append(replacement.id); used.append(replacement.id)
			recovery_workers[site_id]=used; recovery_seen[signature]=true
			recovery_counts[site_id]=recovery_counts.get(site_id,0)+1; recovery_next_tick[site_id]=game.tick_count+100
			recovery_event("construction_takeover",{"actor":row(replacement),"site":row(site),"terminal_builder":row(stopped),"reason":stopped.get("path_reason",""),"terminal_signature":signature})
			break
	for worker in workers:
		if worker.id in claimed or worker.state!="idle" or worker.get("cargo_milli",0)<=0: continue
		var prior: Dictionary = cargo_returns.get(worker.id,{"count":0,"next_tick":0})
		if prior.count>=3 or game.tick_count<prior.next_tick: continue
		# Use the existing ReturnCargoAction planner and its normal order payload.
		# No pending own order exists for this actor because claimed IDs are skipped.
		for payload in game.ReturnCargoAction.orders(public,[worker.id],[]):
			submit("order",payload); claimed.append(worker.id)
			cargo_returns[worker.id]={"count":prior.count+1,"next_tick":game.tick_count+100}
			recovery_event("return_idle_cargo",{"actor":row(worker),"dropoff":row(public[payload.target]),"reason":"idle_with_earned_cargo","cargo_milli_before":worker.cargo_milli})
	return claimed
func decide():
	var workers = own("villager"); var snapshot = game._snapshot()
	var budget := {"food":snapshot.food,"wood":snapshot.wood,"stone":snapshot.stone,"iron":snapshot.iron}
	var recovery_claimed: Array = recover_work(workers)
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
			if worker.state=="build" or worker.id in recovery_claimed: continue
			for point in game.MapRoutes.build_plots(0,game.Rules.FOOTPRINT[kind]):
				# Only the ordinary player-preview validator; never inspect hidden entities.
				if game._placement_reason(kind,point,0,worker.id).is_empty():
					submit("build",{"kind":kind,"position":point,"builder":worker.id})
					claimed=worker.id; spend(kind,budget); break
			if claimed>=0: break
	for index in workers.size():
		var worker = workers[index]
		if worker.id==claimed or worker.id in recovery_claimed or worker.state=="build" or worker.state=="deliver" or worker.get("cargo_milli",0)>0: continue
		var desired := "wood" if index<mini(4,maxi(2,workers.size()-2)) else "food"
		if worker.state!="idle" and (worker.state!="gather" or worker.get("gather_type","")==desired): continue
		var target = resource_for(worker,desired)
		if not target.is_empty(): order(worker,target.id,target.pos)
	# HUD population already includes all queued reservations.
	var slots: int = snapshot.capacity-snapshot.population
	var archers_committed: int = own("archer").size()
	for range_site in own("range"): archers_committed+=population_queue(range_site.queue)
	for producer_kind in ["town_center","range","barracks"]:
		for producer in own(producer_kind):
			if not producer.built or producer.queue.size()>=1 or slots<=0: continue
			var unit_kind: String = game.Rules.PRODUCES[producer_kind]
			if unit_kind=="villager" and workers.size()+population_queue(producer.queue)>=8: continue
			if unit_kind=="archer" and archers_committed>=2 and own("spearman").size()<4: continue
			if not afford(unit_kind,budget): continue
			if unit_kind!="villager" and snapshot.capacity<20 and slots<=2:
				var pending_house := false
				for house in own("house"):
					if not house.built: pending_house=true
				if not pending_house and budget.wood-game.Rules.COSTS[unit_kind].get("wood",0)<50: continue
			# Reserve the next producer, then the first archer. Spend only earned bank.
			if unit_kind=="spearman":
				var reserve_wood := 120 if own("range").is_empty() else (45 if archers_committed==0 else 0)
				if snapshot.capacity<20 and slots<=2: reserve_wood=maxi(reserve_wood,50)
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
			phase("assault_orders_begin")
			if enemy_keep.is_empty(): order(unit,-1,Vector3(22,0,-22))
			else:
				var close_enemy := {}; var close_distance := 36.0
				for visible in records():
					if visible.team!=1 or visible.remembered or not visible.alive or visible.category!="unit": continue
					var distance: float = unit.pos.distance_squared_to(visible.pos)
					if distance<close_distance: close_distance=distance; close_enemy=visible
				if not close_enemy.is_empty(): order(unit,close_enemy.id,close_enemy.pos)
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
		process_frames_seen+=1
		if Time.get_ticks_msec()-started>=270000: finish("bounded_270s_wall_incomplete"); return
		if evidence_limit: finish("bounded_command_evidence_limit"); return
		if game.tick_count-last_sample_tick>=200:
			last_sample_tick=game.tick_count; sample_public()
		if game.test_mode or not game.ai_enabled or not is_equal_approx(Engine.time_scale,1.0): finish("invalid_runtime_mode"); return
		throughput_sample()
		if game.tick_count!=last_observed_tick:
			last_observed_tick=game.tick_count
			var observation_start: int = Time.get_ticks_usec()
			observe(); observation_calls+=1; observation_usec+=Time.get_ticks_usec()-observation_start
		if game.game_over:
			if game.outcome=="victory" and game.end_reason=="keep_destroyed" and last_keep_hp>=0:
				phase("normal_victory",{"reason":game.end_reason,"title":game.end_title.text,"last_public_keep_hp":last_keep_hp})
			finish("match_ended_"+game.outcome); return
		if game.tick_count-last_tick>=20:
			last_tick=game.tick_count
			var decision_start: int = Time.get_ticks_usec()
			decide(); decision_calls+=1; decision_usec+=Time.get_ticks_usec()-decision_start

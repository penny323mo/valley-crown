extends SceneTree
## NEW RECONSTRUCTION, ENGINE_UNRUN. Controlled command/lifecycle boundaries.
## Synthetic setup: paid completed farm, damaged HP, route statuses, selected
## projections and arrival teleports. No full match, path reachability or device proof.
const Rules=preload("res://scripts/rules.gd")
class BoundaryGame:
	extends "res://scripts/game.gd"
	var picked=-1
	func _pick(_screen,_allow_enemy=true): return picked
	func _world_at(_screen): return _get_entity(picked).get("pos",Vector3.ZERO)
	func _update_hud(): pass
var game
var checks=[]
var label=""
var started=0
func _initialize(): call_deferred("run")
func check(name,ok):
	checks.append({"name":label+name,"passed":bool(ok)})
	if not ok: push_error(label+name)
func execute_pending():
	var pending=game.commands.duplicate(true); game.commands.clear()
	pending.sort_custom(func(a,b): return a.sequence<b.sequence)
	for command in pending: game._execute(command)
func command(worker,target,tagged=false):
	var order={"ids":[worker.id],"target":target.id,"position":target.pos}
	if tagged: order.farm_gather=true
	game._submit("order",order,worker.team); execute_pending()
func protected(worker):
	var result={}
	for name in ["path_status","path_reason","path_has_attempt","path_retry_ticks","path_failures","path_next_attempt_tick","path_searches","path_initial_searches","path_retry_searches","path_expanded"]:
		var value=worker.get(name)
		result[name]=value.duplicate(true) if value is Array or value is Dictionary else value
	return result
func boundary(worker):
	return {"worker":worker.duplicate(true),"economy":game.economy.snapshot(),"sequence":game.economy_sequence,"requests":game.path_requests.duplicate(),"priority":game.traffic_priority_order.duplicate(),"segments":game.traffic_tick_segments.duplicate(true),"budget":[game.path_budget_tick,game.last_path_queries,game.last_path_expansions,game.path_expansion_budget]}
func seed_route(worker,status):
	game._path_state(worker)
	worker.mode="MOVE"; worker.state="move"; worker.path_status=status
	worker.path_reason="controlled_terminal" if status in [game.BoundedPath.NO_PATH,game.BoundedPath.LIMIT_REACHED] else "controlled_route"
	worker.path=PackedVector3Array([worker.pos+Vector3(1,0,0)])
	worker.path_pending=status=="QUEUED"; worker.path_request_epoch=7; worker.work_epoch=7
	worker.path_retry_ticks=[1,2,3]; worker.path_failures=3; worker.path_next_attempt_tick=80
	worker.path_searches=4; worker.path_retry_searches=3; worker.path_initial_searches=1; worker.path_has_attempt=true
	worker.traffic_replans=2; worker.traffic_route=true
	if worker.path_pending and worker.id not in game.path_requests: game.path_requests.append(worker.id)
func workers(team):
	var out=[]
	for ent in game.entities:
		if ent.alive and ent.team==team and ent.kind=="villager": out.append(ent)
	out.sort_custom(func(a,b): return a.id<b.id)
	return out
func setup(team,remaining_wood=0):
	label="team "+str(team)+" / "
	game._test_reset([{"food":200,"wood":60+remaining_wood,"stone":100,"iron":0},{"food":200,"wood":60+remaining_wood,"stone":100,"iron":0}])
	game.set_process(false); game.ai_enabled=false
	await process_frame
	var own=workers(team); var keep=game._first(team,"town_center"); var point=Vector3.INF
	for z in range(-8,9):
		for x in range(-8,9):
			var p=game._snap_build_position("farm",keep.pos+Vector3(x,0,z))
			if game._placement_reason("farm",p,team,own[0].id).is_empty(): point=p; break
		if point!=Vector3.INF: break
	check("funded legal farm setup found",point!=Vector3.INF)
	if point==Vector3.INF: return {}
	var payment=game._pay(Rules.COSTS.farm,team)
	check("ordinary exact farm payment",payment.applied)
	if not payment.applied: return {}
	# Disclosed completion shortcut only; no free farm or invented cargo.
	var farm=game._spawn("farm",team,point,true); farm.cost_receipt_id=payment.receipt_id
	check("ordinary payment fulfillment",game.economy.fulfill_cost("fulfilled:"+payment.receipt_id,payment.receipt_id,team).applied)
	game._navigation_rebuild(); game._update_vision(false); game._publish_faction_views()
	check("requested zero/one wood remains",game.economy.bank_milli(team).wood==remaining_wood*1000 and game.economy.audit().ok)
	return {"farm":farm,"a":own[0],"b":own[1],"keep":keep}
func arrive(worker,target):
	var point=game._free_adjacent(target,worker.pos,false,worker.team,worker)
	check("controlled arrival has actual clear perimeter",point!=Vector3.INF)
	if point==Vector3.INF: return false
	worker.pos=point; worker.node.position=point
	game._update_vision(false); game._refresh_work_memory()
	check("arrival passes actual work approach",game._at_work_approach(worker,target,true))
	return game._at_work_approach(worker,target,true)
func lease_only(before,worker,farm):
	var after=game.economy.snapshot(); var expected=before.duplicate(true)
	expected.farms[farm.id].worker_id=-1; expected.worker_farms.erase(worker.id)
	after.transactions=before.transactions
	return after==expected
func atomicity(team):
	var s=await setup(team)
	if s.is_empty(): return
	command(s.a,s.farm)
	check("ordinary owner acquires farm",s.a.farm_id==s.farm.id)
	for status in ["QUEUED","FOUND",game.BoundedPath.NO_PATH,game.BoundedPath.LIMIT_REACHED]:
		seed_route(s.b,status)
		game._submit("order",{"ids":[s.b.id],"target":s.farm.id,"position":s.farm.pos},team)
		var before=boundary(s.b); execute_pending()
		check("occupied farm preserves full route/traffic/economy "+status,boundary(s.b)==before)
	var before_b=boundary(s.b)
	game._submit("order",{"ids":[s.a.id,s.b.id],"target":s.farm.id,"position":s.farm.pos},team); execute_pending()
	check("group keeps accepted current owner and rejected member",s.a.state=="gather" and s.a.farm_id==s.farm.id and s.b==before_b.worker and game.economy.farm_view(s.farm.id).worker_id==s.a.id)
	game._set_stance(s.a,"STOP"); game._path_new_command(s.a); game._path_new_command(s.b)
	game._submit("order",{"ids":[s.b.id,s.a.id],"target":s.farm.id,"position":s.farm.pos},team); execute_pending()
	check("vacant group first accepted farmer owns lease",s.b.farm_id==s.farm.id and s.a.farm_id==-1)
	game._submit("order",{"ids":[s.b.id],"target":-1,"position":s.b.pos+Vector3(2,0,0)},team); execute_pending()
	check("ordinary ground move still releases farm",s.b.mode=="MOVE" and s.b.farm_id==-1 and game.economy.farm_view(s.farm.id).worker_id==-1)
func lease_cleanup(team):
	for ending in ["traffic","cargo_idle","terminal_gather","known_empty"]:
		var s=await setup(team)
		if s.is_empty(): return
		command(s.a,s.farm)
		game.tick_count=10; check("real ledger initial farm generation",game.economy.farm_tick(s.a.id,s.farm.id,10).applied)
		game._project_economy_entity(s.a)
		s.a.path_retry_ticks=[1,2,3]; s.a.path_failures=3; s.a.path_searches=4; s.a.path_next_attempt_tick=80
		var budgets=protected(s.a); var before=game.economy.snapshot()
		if ending=="traffic": game._traffic_stop(s.a,"controlled_timeout")
		elif ending=="cargo_idle": game._cargo_idle(s.a)
		elif ending=="terminal_gather":
			s.a.path_status=game.BoundedPath.LIMIT_REACHED; budgets=protected(s.a); game._update_work(s.a)
		else:
			# Explicit empty remembered-work projection, not hidden-world deletion.
			game.work_memory[team].resources.clear(); game.work_memory[team].structures.clear(); game._resume_gather(s.a)
		check(ending+" releases lease only",s.a.state=="idle" and s.a.farm_id==-1 and lease_only(before,s.a,s.farm))
		var after_budget=protected(s.a)
		if ending=="traffic":
			budgets.path_status=game.BoundedPath.LIMIT_REACHED; budgets.path_reason="controlled_timeout"
		check(ending+" retains rolling retry/search history",after_budget==budgets)
		game._refresh_work_memory(); game._path_new_command(s.b); command(s.b,s.farm)
		check("replacement can take released lease",s.b.farm_id==s.farm.id)
		var unchanged=game.economy.snapshot()
		check("same-tick replacement cannot double generate",not game.economy.farm_tick(s.b.id,s.farm.id,10).applied and game.economy.snapshot()==unchanged)
		game._release_farm(s.a)
		check("repeat release cannot evict replacement",game.economy.snapshot()==unchanged)
		s.a.farm_id=s.farm.id; game._release_farm(s.a)
		check("stale bound release cannot evict replacement",game.economy.farm_view(s.farm.id).worker_id==s.b.id and game.economy.audit().ok)
		command(s.a,s.keep)
		if arrive(s.a,s.keep):
			game.tick_count+=1; game._update_work(s.a)
			check("return cargo cannot steal occupied farm",s.a.farm_id!=s.farm.id and game.economy.farm_view(s.farm.id).worker_id==s.b.id and game.economy.audit().ok)
			if team==0 or ending in ["cargo_idle","known_empty"]: check("nonterminal return deposits cargo",game._cargo_amount(s.a)==0)
	var s=await setup(team)
	if s.is_empty(): return
	command(s.a,s.farm); s.a.path_status="WAIT_SLOT"; s.a.path_next_attempt_tick=100
	var lease=game.economy.farm_view(s.farm.id).worker_id
	game._move_work(s.a,Rules.TICK)
	check("WAIT_SLOT retains active farm lease",s.a.farm_id==s.farm.id and game.economy.farm_view(s.farm.id).worker_id==lease)
	# Ledger-only controlled generation fills the owned worker; no travel claim.
	var fill_ticks=ceili(float(game.Economy.CARGO_CAP)/game.Economy.FARM_PER_TICK)
	for t in range(1,fill_ticks+1): game.economy.farm_tick(s.a.id,s.farm.id,t)
	game._project_economy_entity(s.a); game.tick_count=fill_ticks+1; game._update_work(s.a)
	check("full-load delivery retains lease",game._cargo_amount(s.a)==game.Economy.CARGO_CAP and s.a.state=="deliver" and s.a.farm_id==s.farm.id)
func contextual_farm(s,team):
	if team==0:
		game._publish_faction_views(); game.selected=[s.a.id]; game.picked=s.farm.id; game.touch_command=false
		game._tap(Vector2.ZERO,true)
	else:
		game._publish_faction_views()
		var records=game.faction_views[team].records()
		# Controlled read-only projection subset makes the food choice explicit.
		game.faction_views[team].current=game.FactionView.freeze({s.a.id:records[s.a.id],s.farm.id:records[s.farm.id]})
		game.ai_claimed_workers.clear(); game._assign_worker(game.faction_views[team].get_record(s.a.id),"food")
	check("actual contextual/AI producer marks farm gather",game.commands.size()==1 and game.commands[0].get("farm_gather",false) and game.commands[0].target==s.farm.id)
	execute_pending()
func damaged_intent(team):
	for elapsed in [0,101]:
		var s=await setup(team)
		if s.is_empty(): return
		s.farm.hp-=20; s.farm.last_damage_tick=0; game.tick_count=elapsed
		var before=boundary(s.a)
		command(s.a,s.farm)
		if elapsed==0: check("fresh explicit repair is still refused",boundary(s.a)==before)
		else:
			check("untagged explicit target remains repair",s.a.state=="repair")
			game._update_unit(s.a,Rules.TICK)
			check("zero-wood repair stops without payment",s.a.state=="idle" and game.economy.bank_milli(team).wood==0)
		contextual_farm(s,team)
		check("damaged farm contextual order gathers",s.a.state=="gather" and s.a.farm_id==s.farm.id)
		var hp=s.farm.hp
		if arrive(s.a,s.farm):
			game.tick_count+=1; game._update_work(s.a)
			check("actual work generates food without repairing/spending wood",game._cargo_amount(s.a)>0 and s.farm.hp==hp and game.economy.bank_milli(team).wood==0 and game.economy.audit().ok)
		for bad in [false,1,"true",null]:
			seed_route(s.b,"QUEUED"); var snap=boundary(s.b)
			game._submit("order",{"ids":[s.b.id],"target":s.farm.id,"position":s.farm.pos,"farm_gather":bad},team); execute_pending()
			check("malformed marker rejected before mutation "+str(bad),boundary(s.b)==snap)
		for change in ["dead","unfinished","enemy","ground"]:
			seed_route(s.b,"QUEUED")
			if change=="dead": s.farm.alive=false
			if change=="unfinished": s.farm.built=false
			if change=="enemy": s.farm.team=1-team
			var snap=boundary(s.b)
			game._submit("order",{"ids":[s.b.id],"target":-1 if change=="ground" else s.farm.id,"position":s.farm.pos,"farm_gather":true},team); execute_pending()
			check("stale/wrong farm marker rejected "+change,boundary(s.b)==snap)
			s.farm.alive=true; s.farm.built=true; s.farm.team=team
	var s=await setup(team,1)
	if s.is_empty(): return
	s.farm.hp-=20; s.farm.last_damage_tick=-1000; command(s.a,s.farm)
	if arrive(s.a,s.farm):
		for i in 20: game.tick_count+=1; game._update_unit(s.a,Rules.TICK)
		check("explicit repair spends exactly one wood for five HP",s.farm.hp==s.farm.max_hp-15 and game.economy.bank_milli(team).wood==0)
func ai_terminal_workers():
	label="team 1 / "
	game._test_reset([{"food":0,"wood":0,"stone":0,"iron":0},{"food":0,"wood":0,"stone":0,"iron":0}]); game.set_process(false); await process_frame
	game.ai_opening_assigned=true
	var own=workers(1)
	for i in 2:
		game._path_state(own[i]); own[i].mode="WORK"; own[i].state="idle"
		own[i].path_status=game.BoundedPath.NO_PATH if i==0 else game.BoundedPath.LIMIT_REACHED
		own[i].path_retry_ticks=[1,2,3]; own[i].path_failures=3; own[i].path_searches=4; own[i].path_next_attempt_tick=80
	game._publish_faction_views()
	var bad=[own[0].duplicate(true),own[1].duplicate(true)]; var economy=game.economy.snapshot()
	game._ai_update()
	check("terminal low-ID workers are not false food commitments",not game.ai_claimed_workers.has(own[0].id) and not game.ai_claimed_workers.has(own[1].id) and game._ai_food_count(game._ai_records())>=2)
	check("policy preserves terminal authority and economy",own[0]==bad[0] and own[1]==bad[1] and game.economy.snapshot()==economy)
	check("no order uses terminal worker as builder/gatherer",game.commands.all(func(c): return (not c.has("ids") or (own[0].id not in c.ids and own[1].id not in c.ids)) and c.get("builder",-1) not in [own[0].id,own[1].id]))
	execute_pending()
	check("accepted healthy food workers actually enter gather",own.slice(2).filter(func(w): return w.state=="gather" and w.gather_type=="food").size()>=2)
	# Recurrent post-opening turn: prove terminal premise survived ordinary
	# observations, then isolate policy mutations with a fresh full snapshot.
	var terminal_budget=[protected(bad[0]),protected(bad[1])]
	var epochs=[bad[0].work_epoch,bad[1].work_epoch]
	game._publish_faction_views()
	check("second-turn terminal premise retained",own[0].path_status==game.BoundedPath.NO_PATH and own[1].path_status==game.BoundedPath.LIMIT_REACHED and protected(own[0])==terminal_budget[0] and protected(own[1])==terminal_budget[1] and own[0].work_epoch==epochs[0] and own[1].work_epoch==epochs[1])
	var later_bad=[own[0].duplicate(true),own[1].duplicate(true)]
	game.tick_count+=20; game._ai_update()
	check("later policy still does not mutate or claim terminal workers",own[0]==later_bad[0] and own[1]==later_bad[1] and not game.ai_claimed_workers.has(own[0].id) and not game.ai_claimed_workers.has(own[1].id))
	game.commands.clear()
	var builder=game.faction_views[1].get_record(own[0].id).duplicate(true)
	builder.path_status="NO_WORK"; builder.state="idle"; game.ai_claimed_workers.clear()
	check("NO_WORK is still eligible for a new building goal",game._ai_builder([builder]).get("id",-1)==builder.id)
func ai_cargo_handoff_controls():
	var cases=[
		["NO_PATH","food",0,false,false],
		["NO_PATH","food",1,false,false],
		["NO_PATH","wood",1,false,true],
		["NO_PATH","food",250,false,true],
		["NO_PATH","wood",250,false,true],
		["NO_PATH","food",250,true,false],
		["LIMIT_REACHED","wood",250,false,false],
		["NO_WORK","wood",250,false,false]]
	for item in cases:
		var s=await setup(1)
		if s.is_empty(): return
		label="AI cargo "+str(item)+" / "
		# Controlled registered ledger node creates honest cargo accounting;
		# no claim of world travel/harvest proximity during this setup.
		game.economy.register_node(100000,item[1],20000)
		for t in range(1,item[2]+1): game.economy.gather_tick(s.a.id,100000,t)
		game._project_economy_entity(s.a); game.tick_count=300
		game._path_state(s.a); s.a.state="idle"; s.a.mode="WORK"; s.a.path_status=item[0]; s.a.path_reason="controlled_failure"
		s.a.path_retry_ticks=[280,281,282]; s.a.path_failures=3; s.a.path_searches=4; s.a.path_next_attempt_tick=320
		game._publish_faction_views()
		var records=game.faction_views[1].records()
		var food=records[s.farm.id].duplicate(true); food.remembered=item[3]
		game.faction_views[1].current=game.FactionView.freeze({s.a.id:records[s.a.id],s.farm.id:food})
		game.ai_claimed_workers.clear()
		var before=boundary(s.a); var budget=protected(s.a)
		var accepted=game._assign_worker(game.faction_views[1].get_record(s.a.id),"food")
		check("eligibility matches actual continuation",accepted==item[4])
		check("policy alone never mutates worker/route/economy",boundary(s.a)==before)
		if not item[4]:
			check("rejected claim adds no command",game.commands.is_empty() and not game.ai_claimed_workers.has(s.a.id))
			continue
		check("accepted food claim has ordinary tagged target",game.commands.size()==1 and game.commands[0].target==s.farm.id and game.commands[0].get("farm_gather",false))
		execute_pending()
		if item[1]=="food": game._update_work(s.a)
		var after=protected(s.a); after.erase("path_status"); after.erase("path_reason")
		budget.erase("path_status"); budget.erase("path_reason")
		check("existing delivery handoff preserves rolling budget",s.a.state=="deliver" and s.a.path_status!="NO_PATH" and after==budget and game.economy.audit().ok)
		if item[1]=="wood":
			check("foreign cargo does not reserve farm before delivery",s.a.farm_id==-1 and game.economy.farm_view(s.farm.id).worker_id==-1)
			command(s.b,s.farm,true)
			if arrive(s.a,s.keep):
				game.tick_count+=1; game._update_work(s.a)
				check("foreign cargo resumes without stealing replacement lease",game._cargo_amount(s.a)==0 and s.a.farm_id!=s.farm.id and game.economy.farm_view(s.farm.id).worker_id==s.b.id and game.economy.audit().ok)
func run():
	started=Time.get_ticks_msec(); root.size=Vector2i(390,844)
	game=BoundaryGame.new(); root.add_child(game); game.set_process(false)
	for team in 2:
		if Time.get_ticks_msec()-started>100000: break
		await atomicity(team); await lease_cleanup(team); await damaged_intent(team)
	await ai_terminal_workers(); await ai_cargo_handoff_controls()
	var failed=checks.filter(func(row): return not row.passed).size()
	var timeout=Time.get_ticks_msec()-started>100000
	print(JSON.stringify({"suite":"reconstructed_economy_control_contract","build":Rules.BUILD_ID,"scope":"ENGINE_UNRUN at authoring; synthetic setup and controlled actual command/ledger/lifecycle boundaries, not a natural match or touch/render acceptance","checks":checks,"failure_count":failed,"timed_out":timeout,"game_sha256":FileAccess.get_sha256("res://scripts/game.gd")}))
	quit(2 if timeout else (1 if failed else 0))

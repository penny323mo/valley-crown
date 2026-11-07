extends SceneTree
var game
var trace=[]
var previews=[]
var checkpoints=[]
var budget={}
var claimed={}
var attempts={}
var strategy=1
var milestones={}
const EXPECTED_BUILD="vc-c7211e1083c8"
const MAX_TICKS=48000
var attack_started=false
func issue(kind,data,actor,target={}):
	assert(actor.owned and actor.alive)
	assert(target.is_empty() or not target.remembered)
	game._submit(kind,data,0)
	trace.append({"tick":game.tick_count,"command":game.commands.back().duplicate(true),"actor":actor,"target":target})
func can_pay(kind):
	for r in game.Rules.COSTS[kind]:
		if budget[r]<game.Rules.COSTS[kind][r]: return false
	return true
func spend(kind):
	for r in game.Rules.COSTS[kind]: budget[r]-=game.Rules.COSTS[kind][r]
func build(kind,workers):
	if not can_pay(kind): return false
	var builder={}
	for w in workers:
		if w.state!="build" and not claimed.has(w.id): builder=w; break
	if builder.is_empty(): return false
	for p in game.MapRoutes.build_plots(0,game.Rules.FOOTPRINT[kind]):
		var reason=game._placement_reason(kind,p,0,builder.id)
		previews.append({"tick":game.tick_count,"kind":kind,"position":p,"builder":builder.id,"reason":reason})
		if reason=="":
			issue("build",{"kind":kind,"position":p,"builder":builder.id},builder)
			claimed[builder.id]=true; spend(kind); return true
	return false
func scout(unit):
	if unit.state!="idle": return
	var point=Vector3.INF; var distance=INF; var chosen=-1
	for y in range(game.Rules.MAP_BORDER,game.Rules.MAP_SIZE-game.Rules.MAP_BORDER):
		for x in range(game.Rules.MAP_BORDER,game.Rules.MAP_SIZE-game.Rules.MAP_BORDER):
			var index=y*game.Rules.MAP_SIZE+x
			if game.explored_cells[0][index]!=0 or attempts.has(index): continue
			var p=Vector3(x-game.Rules.MAP_HALF+0.5,0,y-game.Rules.MAP_HALF+0.5); var d=unit.pos.distance_squared_to(p)
			if d<distance: point=p; distance=d; chosen=index
	if chosen>=0:
		attempts[chosen]=true; issue("order",{"ids":[unit.id],"target":-1,"position":point},unit)
func policy():
	var records=game.faction_views[0].records().values()
	var workers=[]; var army=[]; var buildings=[]; var enemies=[]; var castle={}; var enemy_keep={}
	var reserved=0; var queued_workers=0; var houses=0; var producers=0
	var snapshot=game._snapshot()
	budget={"food":snapshot.food,"wood":snapshot.wood}; claimed={}
	for e in records:
		if e.owned:
			if e.kind=="villager": workers.append(e)
			elif e.category=="unit": army.append(e)
			if e.category=="building":
				buildings.append(e); reserved+=e.queue.size()
				for item in e.queue:
					if item.kind=="villager": queued_workers+=1
				if e.kind=="town_center": castle=e
				if e.kind=="house": houses+=1
				if e.kind=="range": producers+=1
		elif not e.remembered and e.team==1:
			enemies.append(e)
			if e.kind=="town_center": enemy_keep=e
	if castle.is_empty(): return
	var built_now=false
	if producers<1: built_now=build("range",workers)
	elif houses<2 and snapshot.capacity-snapshot.population<=3: built_now=build("house",workers)
	elif producers<2 and houses>=1: built_now=build("range",workers)
	# Recover any own site whose builder died or stopped.
	for b in buildings:
		if b.built: continue
		var attended=false
		for w in workers:
			if w.state=="build" and w.target==b.id: attended=true
		if not attended and not built_now:
			for w in workers:
				if w.state!="build" and not claimed.has(w.id):
					issue("order",{"ids":[w.id],"target":b.id,"position":b.pos},w,b); claimed[w.id]=true; break
	var free=snapshot.capacity-snapshot.population
	if workers.size()+queued_workers<7 and castle.queue.is_empty() and free>0 and can_pay("villager"):
		issue("train",{"building":castle.id,"kind":"villager"},castle); spend("villager"); free-=1
	for b in buildings:
		if b.kind=="range" and b.built and b.queue.size()<2 and free>0 and can_pay("archer"):
			issue("train",{"building":b.id,"kind":"archer"},b); spend("archer"); free-=1
	for i in workers.size():
		var w=workers[i]
		if claimed.has(w.id) or w.state!="idle": continue
		var want_food=i<3; var source={}
		for r in records:
			if r.category!="resource" or r.remembered: continue
			if (r.kind=="berry")!=want_food: continue
			if source.is_empty() or w.pos.distance_squared_to(r.pos)<w.pos.distance_squared_to(source.pos): source=r
		if not source.is_empty(): issue("order",{"ids":[w.id],"target":source.id,"position":source.pos},w,source)
	if army.size()>=9: attack_started=true
	for u in army:
		var target={}; var best=INF
		for e in enemies:
			if e.category!="unit": continue
			var d=u.pos.distance_squared_to(e.pos)
			if d<best and d<144: target=e; best=d
		if target.is_empty() and attack_started and not enemy_keep.is_empty(): target=enemy_keep
		if not target.is_empty():
			if u.state!="attack" or u.target!=target.id: issue("order",{"ids":[u.id],"target":target.id,"position":target.pos},u,target)
		elif u.kind=="scout" or attack_started:
			scout(u)
func checkpoint():
	return {"snapshot":game._snapshot().duplicate(true),"records":game.faction_views[0].records().duplicate(true),"ai_enabled":game.ai_enabled,"toast":game.toast_label.text}
func _initialize(): call_deferred("run")
func observe_milestones():
	var snapshot=game._snapshot()
	for key in ["delivered","built","trained"]:
		if snapshot[key]>0 and not milestones.has(key): milestones[key]=game.tick_count
	# Reporting only. No hidden state is consulted, and this does not steer policy.
	for e in game.faction_views[0].records().values():
		if e.owned and e.category=="unit" and e.state=="attack" and not milestones.has("combat_state"):
			milestones["combat_state"]=game.tick_count
	if game.game_over and not milestones.has("terminal"): milestones.terminal=game.tick_count
func run():
	var args=OS.get_cmdline_user_args()
	if args.size()!=1:
		push_error("Expected one absolute output JSON path; no smoke-test flag."); quit(2); return
	game=load("res://main.tscn").instantiate(); root.add_child(game); game.set_process(false)
	if game.Rules.BUILD_ID!=EXPECTED_BUILD or game.Rules.MAP_SIZE!=80 or not game.ai_enabled or game.test_mode:
		push_error("Wrong candidate or non-ordinary startup; refusing replay."); quit(2); return
	var start=Time.get_ticks_msec(); checkpoints.append(checkpoint())
	var invariant_failures=[]
	var capacity_loss_overcap=[]
	for i in MAX_TICKS:
		if game.tick_count%40==0: policy()
		var previous=game.tick_count
		game._tick(game.Rules.TICK)
		observe_milestones()
		var snap=game._snapshot()
		if not game.ai_enabled or snap.food<0 or snap.wood<0 or snap.population>game.Rules.POP_LIMIT:
			invariant_failures.append({"tick":game.tick_count,"snapshot":snap.duplicate(true),"ai_enabled":game.ai_enabled}); break
		if snap.population>snap.capacity and (capacity_loss_overcap.is_empty() or capacity_loss_overcap[-1].capacity!=snap.capacity or capacity_loss_overcap[-1].population!=snap.population):
			capacity_loss_overcap.append({"tick":game.tick_count,"population":snap.population,"capacity":snap.capacity})
		if previous%40==0:
			checkpoints.append({"post_command_tick":game.tick_count,"toast":game.toast_label.text,"snapshot":snap.duplicate(true),"ai_enabled":game.ai_enabled})
		if game.tick_count%1200==0:
			print("REPLAY_PROGRESS ",game.tick_count," ",JSON.stringify(snap))
		if game.game_over or game.paused: break
	var audit=game.economy.audit()
	var coverage_complete=game.game_over and game.outcome in ["victory","defeat"] and milestones.has("delivered") and milestones.has("built") and milestones.has("trained") and milestones.has("combat_state")
	var passed=coverage_complete and invariant_failures.is_empty() and audit.ok
	var report={"scope":"Accelerated native ordinary-command simulation only; no selection/touch/render/fog-pixel/restart/performance acceptance", "status":"PASS_CORE_SIMULATION" if passed else "INCOMPLETE_OR_FAILED", "strategy":strategy,"build":game.Rules.BUILD_ID,"seed":824613,"map_size":game.Rules.MAP_SIZE,"source_sha256":FileAccess.get_sha256("res://scripts/game.gd"),"harness_sha256":FileAccess.get_sha256(get_script().resource_path),"input_trace":trace,"placement_previews":previews,"checkpoints":checkpoints,"milestones":milestones,"invariant_failures":invariant_failures,"capacity_loss_overcap":capacity_loss_overcap,"population_limit":game.Rules.POP_LIMIT,"terminal":checkpoint(),"end_reason":game.end_reason,"wall_ms":Time.get_ticks_msec()-start,"bound_ticks":MAX_TICKS,"economy_audit":audit,"engine":Engine.get_version_info().string}
	var file=FileAccess.open(args[0],FileAccess.WRITE)
	if file==null: push_error("Cannot write output report."); quit(2); return
	file.store_string(JSON.stringify(report,"\t")); file.close()
	print("REPLAY_RESULT ",report.status," ",game.outcome," ",game.end_reason," tick=",game.tick_count)
	quit(0 if passed else 1)

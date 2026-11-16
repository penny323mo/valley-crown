extends SceneTree
## Controlled actual-game route/command integration, not natural full-match or art acceptance.
## Funded resets and explicit spawned attack targets are disclosed below.
## The test never teleports workers to work, writes bank stock, shortens production,
## grants age, or directly changes combat HP after its reset.
const Rules=preload("res://scripts/rules.gd")
const SCOPE="Controlled funded route and command integration, not natural full-match, rendered Web, release-template or art acceptance"
const WALL_LIMIT_MS=100000
var game
var checks=[]
var started_ms=0
var timed_out=false
var maximum_path_queries=0
var maximum_path_expansions=0
var observations={}
func _initialize(): call_deferred("run")
func check(name: String,value: bool):
	checks.append({"name":name,"passed":value})
	if not value: push_error(name)
func deadline() -> bool:
	if Time.get_ticks_msec()-started_ms<WALL_LIMIT_MS: return true
	if not timed_out: check("fixture completes within 100 seconds",false)
	timed_out=true
	return false
func tick() -> bool:
	if not deadline() or game.game_over: return false
	game._tick(Rules.TICK)
	maximum_path_queries=maxi(maximum_path_queries,game.last_path_queries)
	maximum_path_expansions=maxi(maximum_path_expansions,game.last_path_expansions)
	return true
func reset():
	game._test_reset([{"food":2000,"wood":3000,"stone":1000,"iron":1000},{"food":2000,"wood":3000,"stone":1000,"iron":1000}])
	game.set_process(false); game.test_mode=true; game.ai_enabled=false
	await process_frame
func wait_until(predicate: Callable,budget: int) -> bool:
	for i in budget:
		if predicate.call(): return true
		if not tick(): return false
	return predicate.call()
func plot(kind: String,worker: Dictionary,require_travel: bool=false) -> Vector3:
	var best=Vector3.INF; var distance=INF
	for dz in range(-8,9):
		for dx in range(-8,9):
			var point=game._snap_build_position(kind,worker.pos+Vector3(dx,0,dz))
			if not game._placement_reason(kind,point,worker.team,worker.id).is_empty(): continue
			if require_travel:
				var approach=game._free_adjacent({"kind":kind,"pos":point},worker.pos,false,worker.team,worker)
				if approach==Vector3.INF or worker.pos.distance_to(approach)<=1.0: continue
			var d=point.distance_squared_to(worker.pos)
			if d<distance: best=point; distance=d
	return best
func vector(value: Vector3):
	return [value.x,value.y,value.z] if value.is_finite() else null
func observe(unit: Dictionary,target: Dictionary) -> Dictionary:
	var record=game.faction_views[unit.team].get_record(target.id)
	return {"tick":game.tick_count,"position":vector(unit.pos),"radius":unit.radius,"state":unit.state,"path_status":unit.get("path_status",""),"path_reason":unit.get("path_reason",""),"path_goal":vector(unit.get("path_request_goal",unit.pos)),"destination":vector(unit.dest),"work_approach":vector(unit.get("work_approach",Vector3.INF)),"target_position":vector(target.pos),"target_authority_visible":game._visible_to(target,unit.team),"target_projection_visible":not record.is_empty() and not record.get("remembered",false),"attack_distance":game._attack_distance(unit.pos,target),"attack_range":Rules.RANGE[unit.kind],"target_alive":target.alive,"target_hp":target.hp,"target_built":target.built,"target_build_ticks":target.build_ticks}
func run():
	started_ms=Time.get_ticks_msec(); root.size=Vector2i(390,844)
	game=load("res://main.tscn").instantiate(); root.add_child(game)
	game.set_process(false); game.test_mode=true; game.ai_enabled=false
	await test_farm_routes()
	if deadline(): await test_large_attack_routes()
	if deadline(): await test_age_commands()
	if deadline(): await test_ai_payments()
	check("shared path query gate remains four",maximum_path_queries<=4)
	check("shared expansion budget remains bounded",maximum_path_expansions<=16384)
	var failed=0
	for row in checks:
		if not row.passed: failed+=1
	var report={"suite":"military_runtime_edges","build":Rules.BUILD_ID,"scope":SCOPE,"checks":checks,"failed":failed,"total":checks.size(),"elapsed_ms":Time.get_ticks_msec()-started_ms,"max_path_queries":maximum_path_queries,"max_path_expansions":maximum_path_expansions,"observations":observations}
	print("MILITARY_RUNTIME_EDGES ",JSON.stringify(report))
	quit(0 if failed==0 and not timed_out else 1)
func test_farm_routes():
	await reset()
	var worker=game._first(0,"villager"); var origin=worker.pos
	var site=plot("farm",worker,true); check("farm has ordinary visible paid plot",site!=Vector3.INF)
	if site==Vector3.INF: return
	var initial_approach=game._free_adjacent({"kind":"farm","pos":site},origin,false,worker.team,worker)
	observations.farm_setup={"position":vector(origin),"site":vector(site),"approach":vector(initial_approach),"distance":origin.distance_to(initial_approach)}
	check("farm setup requires more than one cell of real travel",initial_approach!=Vector3.INF and origin.distance_to(initial_approach)>1.0)
	var bank=game.economy.bank_milli(0)
	game._submit("build",{"kind":"farm","position":site,"builder":worker.id},0); tick()
	var farm=game._first(0,"farm")
	check("queued farm purchase creates unfinished paid site",not farm.is_empty() and not farm.built and game.economy.bank_milli(0).wood==bank.wood-60000)
	if farm.is_empty(): return
	var built=wait_until(func(): return farm.built,1200)
	observations.farm_final=observe(worker,farm)
	check("worker reaches and completes farm without teleport",built and worker.pos!=origin and farm.build_ticks==300)
	check("completed farm is registered in actual ledger",not game.economy.farm_view(farm.id).is_empty() and game.economy.farm_view(farm.id).get("alive",false))
	if not built: return
	game._submit("order",{"ids":[worker.id],"target":farm.id,"position":farm.pos},0); tick()
	check("ordinary farm command reserves actual worker",game.economy.farm_view(farm.id).get("worker_id",-1)==worker.id)
	var first=wait_until(func(): return game.economy.bank_milli(0).food>=bank.food+10000,1600)
	check("full farm cargo reaches ordinary dropoff without teleport",first)
	var resumed=wait_until(func(): return game.economy.stats_view(0).generated.food>10000,600)
	check("automatic delivery returns to same reserved farm",resumed and game.economy.farm_view(farm.id).get("worker_id",-1)==worker.id and worker.resource_target==farm.id)
	game._submit("stop",{"ids":[worker.id]},0); tick()
	var generated=game.economy.stats_view(0).generated.food
	for i in 20: tick()
	check("ordinary Stop releases farm and generates no idle food",game.economy.farm_view(farm.id).get("worker_id",-1)==-1 and game.economy.stats_view(0).generated.food==generated)
	var wood=game._nearest_resource(worker.pos,"wood",0)
	game._submit("order",{"ids":[worker.id],"target":wood.id,"position":wood.pos},0); tick()
	var wood_load=wait_until(func(): return game._cargo_type(worker)=="wood" and game._cargo_amount(worker)>0,1200)
	check("worker obtains real finite wood cargo after farm Stop",wood_load)
	if wood_load:
		game._submit("order",{"ids":[worker.id],"target":farm.id,"position":farm.pos},0); tick()
		check("incompatible wood first routes to ordinary delivery",worker.state=="deliver" and game.economy.farm_view(farm.id).get("worker_id",-1)==-1)
		var resumed_food=wait_until(func(): return game.economy.stats_view(0).generated.food>generated,1200)
		check("postdelivery reassignment acquires farm and resumes food",resumed_food and worker.resource_target==farm.id and game.economy.farm_view(farm.id).get("worker_id",-1)==worker.id)
	check("farm routed lifecycle conserves all four resources",game.economy.audit().ok)
func test_large_attack_routes():
	await reset()
	# Explicit controlled targets in existing open land. No manufactured damage.
	var house=game._spawn("house",1,Vector3(17,0,6))
	var ram=game._spawn("siege",0,Vector3(12.5,0,6.5))
	game._navigation_rebuild(); game._update_vision(false)
	var start=ram.pos; var hp=house.hp
	observations.siege_initial=observe(ram,house)
	check("siege attack target is authority visible before command",game._visible_to(house,0))
	check("large siege fixture begins outside attack range",game._attack_distance(ram.pos,house)>Rules.RANGE.siege)
	game._submit("order",{"ids":[ram.id],"target":house.id,"position":house.pos},0); tick()
	var hit=wait_until(func(): return house.hp<hp,600)
	observations.siege_final=observe(ram,house)
	check("siege moves through ordinary routing and hits building",hit and ram.pos!=start and game._attack_distance(ram.pos,house)<=Rules.RANGE.siege)
	check("siege attack approach keeps swept disk outside structure",game._static_unit_step_is_free(ram,ram.pos))
	var barracks=game._spawn("barracks",1,Vector3(17.5,0,13.5))
	var cavalry=game._spawn("cavalry",0,Vector3(12.5,0,13.5))
	game._navigation_rebuild(); game._update_vision(false); hp=barracks.hp; start=cavalry.pos
	observations.cavalry_initial=observe(cavalry,barracks)
	game._submit("order",{"ids":[cavalry.id],"target":barracks.id,"position":barracks.pos},0); tick()
	hit=wait_until(func(): return barracks.hp<hp,500)
	observations.cavalry_final=observe(cavalry,barracks)
	check("cavalry ordinary route can attack a three-cell building",hit and cavalry.pos!=start)
	check("cavalry final approach preserves swept clearance",game._static_unit_step_is_free(cavalry,cavalry.pos))
func test_age_commands():
	await reset()
	var keep=game._first(0,"town_center"); var worker=game._first(0,"villager")
	var bank=game.economy.bank_milli(0)
	game._submit("research",{"building":keep.id},0); tick()
	check("ordinary research command pays exact four-resource ledger",keep.queue.size()==1 and game.economy.bank_milli(0).food==bank.food-350000 and game.economy.bank_milli(0).wood==bank.wood-150000 and game.economy.bank_milli(0).iron==bank.iron-50000)
	# All 1800 production steps use actual _tick; no shortened remaining_ticks.
	var almost=wait_until(func(): return not keep.queue.is_empty() and keep.queue[0].remaining_ticks==1,1798)
	check("research reaches final tick naturally",almost)
	var point=game._snap_build_position("stable",worker.pos+Vector3(5,0,0))
	game._submit("build",{"kind":"stable","position":point,"builder":worker.id},0); tick()
	check("command on completion tick cannot bypass age gate",game._count(0,"stable")==0 and game.age_completed_tick[0]==game.tick_count and not game._age2(0))
	tick(); point=plot("stable",worker)
	check("following tick ordinary stable placement becomes available",point!=Vector3.INF and game._age2(0))
	if point!=Vector3.INF:
		bank=game.economy.bank_milli(0); game._submit("build",{"kind":"stable","position":point,"builder":worker.id},0); tick()
		check("next-tick stable command creates paid construction",game._count(0,"stable")==1 and game.economy.bank_milli(0).wood==bank.wood-160000)
	check("research and stable command lifecycle conserves",game.economy.audit().ok)
func test_ai_payments():
	await reset()
	var before=game.economy.bank_milli(1); game._publish_faction_views(); game._ai_update()
	check("AI scheduling itself does not create or debit stock",game.economy.bank_milli(1)==before)
	var commands=game.commands.duplicate(true)
	var costs={"food":0,"wood":0,"stone":0,"iron":0}; var paid=0
	for command in commands:
		if command.type not in ["train","build","research"]: continue
		var kind="age2" if command.type=="research" else command.kind
		paid+=1
		for resource in Rules.COSTS[kind]: costs[resource]+=Rules.COSTS[kind][resource]*1000
	check("AI opening actually schedules a paid progression action",paid>0)
	tick(); var after=game.economy.bank_milli(1)
	var exact=true
	for resource in costs:
		if after[resource]!=before[resource]-costs[resource]: exact=false
	check("queued AI progression executes ordinary exact payment",exact)
	check("AI paid command conserves all four resource accounts",game.economy.audit().ok)

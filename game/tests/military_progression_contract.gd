extends SceneTree
## AUTHORED, NOT RUN locally. Controlled actual production APIs, not natural play.
## Funded resets, position fixtures and one low-HP terminal fixture are explicit.
const Rules=preload("res://scripts/rules.gd")
const Ledger=preload("res://scripts/economy_ledger.gd")
var game
var results=[]
var started_ms=0
var timed_out=false
func deadline() -> bool:
	if Time.get_ticks_msec()-started_ms<100000: return true
	if not timed_out: push_error("Military fixture exceeded 100 seconds")
	timed_out=true; quit(2); return false
func _initialize(): call_deferred("run")
func check(label: String,value: bool):
	results.append({"name":label,"passed":value})
	if not value: push_error(label)
func reset(stock: Dictionary={"food":2000,"wood":3000,"stone":1000,"iron":1000}):
	game._test_reset([stock,stock]); game.set_process(false); game.test_mode=true; game.ai_enabled=false
	await process_frame
func production_ticks(count: int):
	for i in count:
		if not deadline(): return
		game.tick_count+=1
		for ent in game.entities:
			if ent.alive and ent.category=="building": game._update_production(ent,Rules.TICK,false)
		game._process_ready_production()
func plot(kind: String,worker: Dictionary) -> Vector3:
	for z in range(-9,10):
		for x in range(-9,10):
			var point=game._snap_build_position(kind,game.MapRoutes.home(worker.team)+Vector3(x,0,z))
			if game._placement_reason(kind,point,worker.team,worker.id).is_empty(): return point
	return Vector3.INF
func at_work(worker: Dictionary,target: Dictionary) -> bool:
	var point=game._free_adjacent(target,worker.pos,false,worker.team,worker)
	if point==Vector3.INF: return false
	worker.pos=point; worker.path=PackedVector3Array(); game._update_vision(false)
	return game._at_work_approach(worker,target,true)
func run():
	started_ms=Time.get_ticks_msec()
	root.size=Vector2i(390,844)
	game=load("res://main.tscn").instantiate(); root.add_child(game); game.set_process(false); game.test_mode=true
	check("nine building and six unit profiles",Rules.FOOTPRINT.size()==9 and Rules.UNIT_KINDS.size()==6)
	await test_research()
	if deadline(): await test_farm()
	if deadline(): await test_minerals()
	if deadline(): await test_military()
	if deadline(): await test_ui_and_ai()
	if timed_out: return
	var failed=0
	for result in results:
		if not result.passed: failed+=1
	var report={"scope":"controlled integration fixture, not natural gameplay or art acceptance","results":results,"total":results.size(),"failed":failed,"build":Rules.BUILD_ID,"engine":Engine.get_version_info(),"elapsed_ms":Time.get_ticks_msec()-started_ms}
	var file=FileAccess.open("user://military_progression_contract.json",FileAccess.WRITE)
	if file==null: quit(2); return
	file.store_string(JSON.stringify(report,"\t")); file.close()
	print("MILITARY_PROGRESSION ",JSON.stringify(report)); quit(0 if failed==0 else 1)
func test_research():
	await reset({"food":350,"wood":150,"stone":100,"iron":49})
	var keep=game._first(0,"town_center"); var bank=game.economy.bank_milli(0)
	check("missing iron rejects research atomically",not game._enqueue_research(keep.id,0) and game.economy.bank_milli(0)==bank and keep.queue.is_empty())
	await reset(); keep=game._first(0,"town_center"); bank=game.economy.bank_milli(0)
	check("Age I stable placement is locked",game._placement_reason("stable",Vector3.ZERO,0,game._first(0,"villager").id)=="需要城防時代")
	check("enqueue research succeeds",game._enqueue_research(keep.id,0))
	check("research reserves no population",game._population(0)==6 and keep.queue.size()==1)
	check("research payment exact",game.economy.bank_milli(0).food==bank.food-350000 and game.economy.bank_milli(0).wood==bank.wood-150000 and game.economy.bank_milli(0).iron==bank.iron-50000)
	check("duplicate faction research rejected",not game._enqueue_research(keep.id,0) and keep.queue.size()==1)
	check("unstarted research cancellation refunds all",game._cancel_train(keep.id,0) and game.economy.bank_milli(0)==bank)
	game._enqueue_research(keep.id,0); production_ticks(1)
	check("started research cancellation succeeds",game._cancel_train(keep.id,0))
	var after=game.economy.bank_milli(0)
	check("started refund floors each original resource",after.food==bank.food-88000 and after.wood==bank.wood-38000 and after.iron==bank.iron-13000)
	check("double cancellation cannot mint refund",not game._cancel_train(keep.id,0) and game.economy.bank_milli(0)==after)
	await reset(); keep=game._first(0,"town_center")
	game._enqueue_train(keep.id,"villager",0); game._enqueue_research(keep.id,0); game._enqueue_train(keep.id,"scout",0)
	check("training and research share FIFO and only train reserves",keep.queue.size()==3 and game._population(0)==8)
	production_ticks(299); check("research cannot run ahead of villager",keep.queue.size()==3 and keep.queue[1].remaining_ticks==1800)
	production_ticks(1); check("villager commits at 300",game._count(0,"villager")==6 and keep.queue[0].kind=="age2")
	production_ticks(1799); check("age not early",not game._age2(0) and keep.queue[0].remaining_ticks==1)
	production_ticks(1); check("completion tick still locks commands",game.age_completed_tick[0]==2100 and not game._age2(0) and not game._kind_unlocked("cavalry",0))
	production_ticks(1); check("following tick unlocks military",game._age2(0) and game._kind_unlocked("stable",0) and game._kind_unlocked("siege",0))
	production_ticks(399); check("scout after research finishes at 2500",game._count(0,"scout")==2 and keep.queue.is_empty())
	check("completed age cannot be researched twice",not game._enqueue_research(keep.id,0))
	await reset(); keep=game._first(0,"town_center"); game._enqueue_research(keep.id,0)
	for i in 7: game._spawn("spearman",0,Vector3(-10-i,0,30))
	production_ticks(20); check("overpopulation does not pause research",game._population(0)>game._capacity(0) and keep.queue[0].remaining_ticks==1780)
	var remaining=keep.queue[0].remaining_ticks; game._update_production(keep,Rules.TICK,false)
	check("same-tick repeat cannot advance FIFO twice",keep.queue[0].remaining_ticks==remaining)
	bank=game.economy.bank_milli(0); game._kill(keep)
	check("producer death loses research without refund",keep.queue.is_empty() and game.economy.bank_milli(0)==bank and not game._research_pending(0))
	check("research transactions conserve",game.economy.audit().ok)
func test_farm():
	await reset(); var worker=game._first(0,"villager"); var point=plot("farm",worker)
	check("normal visible farm site exists",point!=Vector3.INF)
	if point==Vector3.INF: return
	var bank=game.economy.bank_milli(0); var farm=game._place_building("farm",point,worker.id,0)
	check("paid farm construction debits wood sixty",not farm.is_empty() and game.economy.bank_milli(0).wood==bank.wood-60000)
	if farm.is_empty(): return
	check("unbuilt farm cannot assign",not game.economy.assign_farm("unbuilt",worker.id,farm.id).ok)
	check("construction approach exists",at_work(worker,farm))
	for i in 300: game.tick_count+=1; game._update_unit(worker,Rules.TICK)
	check("farm completes after 300 real work ticks",farm.built and farm.build_ticks==300 and game.economy.farm_view(farm.id).alive)
	game._order(worker,"gather",farm.id); check("farm command reserves one worker",game.economy.farm_view(farm.id).worker_id==worker.id)
	var other={}
	for ent in game.entities:
		if ent.kind=="villager" and ent.team==0 and ent.id!=worker.id: other=ent; break
	var old_state=other.state; game._order(other,"gather",farm.id)
	check("second farmer rejected without changing prior order",other.state==old_state and game.economy.farm_view(farm.id).worker_id==worker.id)
	check("farmer legal perimeter work position",at_work(worker,farm)); bank=game.economy.bank_milli(0)
	for i in 100: game.tick_count+=1; game._update_work(worker)
	check("farm 100 ticks makes 3000 cargo not bank",game._cargo_amount(worker)==3000 and game.economy.bank_milli(0)==bank)
	game._update_work(worker); check("farm same tick no duplicate",game._cargo_amount(worker)==3000)
	game._set_stance(worker,"STOP"); check("stop releases farm and preserves cargo",game.economy.farm_view(farm.id).worker_id==-1 and game._cargo_amount(worker)==3000)
	var keep=game._first(0,"town_center"); game._order(worker,"deliver",keep.id); check("dropoff approach exists",at_work(worker,keep))
	check("farm food uses ordinary actual dropoff",game._deposit_cargo(worker,keep).applied and game.economy.bank_milli(0).food==bank.food+3000)
	game._order(worker,"gather",farm.id); at_work(worker,farm); game.tick_count+=1; game._update_work(worker)
	game._kill(farm); check("farm destruction preserves carried food",game._cargo_amount(worker)==30 and not game.economy.farm_view(farm.id).alive)
	game._kill(worker); check("farmer death records destroyed cargo",game.economy.stats_view(0).destroyed_cargo.food==30 and game.economy.audit().ok)
func test_minerals():
	await reset(); var iron=game._nearest_resource(game.MapRoutes.home(0),"iron",0)
	check("opening iron is known and Age I mineable",not iron.is_empty() and not game._age2(0))
	var counts={"stone":0,"iron":0}
	for ent in game.entities:
		if counts.has(ent.kind): counts[ent.kind]+=1
	check("mirrored finite mineral count",counts.stone==12 and counts.iron==12)
	var worker=game._first(0,"villager"); game._order(worker,"gather",iron.id)
	check("mineral work uses same route authority",worker.state=="gather" and worker.gather_type=="iron" and not game._work_candidates(worker).is_empty())
	check("mineral approach reachable fixture",at_work(worker,iron))
	var bank=game.economy.bank_milli(0)
	for i in 100: game.tick_count+=1; game._update_work(worker)
	check("iron 100 ticks produces 3000 cargo only",game._cargo_amount(worker)==3000 and game.economy.node_view(iron.id).remaining_milli==397000 and game.economy.bank_milli(0)==bank)
	var keep=game._first(0,"town_center"); game._order(worker,"deliver",keep.id); at_work(worker,keep)
	check("keep accepts iron",game._deposit_cargo(worker,keep).applied and game.economy.bank_milli(0).iron==bank.iron+3000)
	var ledger=Ledger.new(Ledger.FOUR_RESOURCE_TYPES); ledger.initialize([{"food":0,"wood":0,"stone":0,"iron":0}]); ledger.register_worker(1,0); ledger.register_node(9,"stone",31)
	check("mineral finite remainder preserved",ledger.gather_tick(1,9,1).amount_milli==30 and ledger.gather_tick(1,9,2).amount_milli==1 and ledger.node_view(9).remaining_milli==0)
	check("depleted mineral cannot generate more",not ledger.gather_tick(1,9,3).ok and ledger.audit().ok)
func test_military():
	await reset(); var stable=game._spawn("stable",0,Vector3(-13,0,25))
	var bank=game.economy.bank_milli(0)
	check("unit age gate also checked at enqueue",not game._enqueue_train(stable.id,"cavalry",0) and game.economy.bank_milli(0)==bank)
	game.age_completed_tick[0]=0; game.tick_count=1; game._navigation_rebuild(); game._update_vision(false)
	check("stable trains cavalry at approved cost",game._enqueue_train(stable.id,"cavalry",0) and game.economy.bank_milli(0).food==bank.food-90000 and game.economy.bank_milli(0).iron==bank.iron-35000)
	production_ticks(600); check("cavalry actually spawns",game._count(0,"cavalry")==1)
	var workshop=game._spawn("workshop",0,Vector3(-13,0,31)); game._navigation_rebuild(); game._update_vision(false)
	game._enqueue_train(workshop.id,"siege",0); production_ticks(900)
	check("workshop actually spawns larger siege",game._count(0,"siege")==1 and game._first(0,"siege").radius==0.65)
	var ram=game._first(0,"siege"); check("siege spawn swept footprint clear",game._static_unit_step_is_free(ram,ram.pos))
	var cavalry=game._first(0,"cavalry"); cavalry.pos=Vector3.ZERO
	var archer=game._spawn("archer",1,Vector3(1,0,0)); var spear=game._spawn("spearman",1,Vector3(0,0,1)); game._update_vision(false)
	var release=game._release_attack(cavalry,archer); check("cavalry counters archer",release.applied and release.event.damage==15)
	release=game._release_attack(spear,cavalry); check("spearman counters cavalry after armor",release.applied and release.event.damage==16)
	var house=game._spawn("house",1,Vector3(5,0,0)); ram.pos=Vector3(3,0,0); game._update_vision(false)
	release=game._release_attack(ram,house); check("siege deals building bonus",release.applied and release.event.damage==30)
	var tower=game._spawn("tower",0,Vector3(-3,0,0)); game._navigation_rebuild(); game._update_vision(false)
	var next=game.attack_ledger.next_attack_id(); game._update_tower(tower)
	check("tower prioritizes visible unit before building",game.attack_ledger.next_attack_id()==next+1 and game.attack_ledger.event(next).target_id in [archer.id,spear.id])
	tower.cooldown_ticks=0; archer.pos=Vector3(-2,0,1); spear.pos=Vector3(-2,0,-1); game._update_vision(false); next=game.attack_ledger.next_attack_id(); game._update_tower(tower)
	check("tower equal-distance ties use lower entity ID",game.attack_ledger.event(next).target_id==archer.id)
	tower.cooldown_ticks=0; game.visible_cells[0].fill(0); next=game.attack_ledger.next_attack_id(); game._update_tower(tower)
	check("tower cannot target hidden enemies",game.attack_ledger.next_attack_id()==next)
	var worker=game._first(0,"villager"); game._spawn("tower",0,Vector3(-8,0,0),false)
	check("tower cap counts unfinished sites",game._placement_reason("tower",Vector3.ZERO,0,worker.id)=="每方最多兩座守望塔")
	await reset(); var enemy_keep=game._first(1,"town_center"); ram=game._spawn("siege",0,enemy_keep.pos+Vector3(-2.7,0,0)); enemy_keep.hp=28
	game._order(ram,"attack",enemy_keep.id); game._update_vision(false); game._tick(Rules.TICK)
	check("siege hit uses ordinary victory settlement",game.game_over and game.victory and not enemy_keep.alive)
func test_ui_and_ai():
	await reset(); var keep=game._first(0,"town_center"); game._select([keep.id]); game._publish_faction_views(); game._update_hud()
	var text=""
	for child in game.actions.get_children():
		if child is Button: text+=child.text
	check("town center UI exposes scout and age research",text.contains("斥候") and text.contains("城防時代"))
	game._select([game._first(0,"villager").id]); game._update_hud(); text=""
	for child in game.actions.get_children():
		if child is Button: text+=child.text
	check("builder mobile strip exposes all new structures",text.contains("農田") and text.contains("馬廄") and text.contains("守望塔") and text.contains("工坊"))
	check("HUD shows all four bank resources",game.top_resources.text.contains("石") and game.top_resources.text.contains("鐵"))
	game._publish_faction_views(); var enemy=game._first(1,"town_center"); var bank=game.economy.bank_milli(1)
	game._ai_update(); check("AI decisions do not directly mint stock",game.economy.bank_milli(1)==bank)
	var ordinary_commands=not game.commands.is_empty()
	for command in game.commands:
		ordinary_commands=ordinary_commands and command.team==1 and command.type in ["order","build","train","research"]
	check("AI uses ordinary queued commands",ordinary_commands)
	var before=game.economy.bank_milli(1); game._enqueue_research(enemy.id,1)
	check("AI research same price",game.economy.bank_milli(1).iron==before.iron-50000)
	check("all integration economics conserve",game.economy.audit().ok)

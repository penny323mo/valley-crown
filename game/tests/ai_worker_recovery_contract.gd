extends SceneTree
# ENGINE_UNRUN. Controlled attrition and funded reset, ordinary AI submission,
# paid training, 300 production ticks, then at most 1600 actual simulation ticks.
# This is not a natural match, victory proof, rendered or physical-phone test.
const Rules=preload("res://scripts/rules.gd")
var game
var checks=[]
func check(label,ok):
	checks.append({"name":label,"passed":bool(ok)})
	if not ok: push_error(label)
func _initialize(): call_deferred("run")
func execute_pending():
	var batch=game.commands.duplicate(true); game.commands.clear()
	batch.sort_custom(func(a,b): return a.sequence<b.sequence)
	for command in batch: game._execute(command)
func rows():
	return [{"id":1,"kind":"town_center","category":"building","team":1,"owned":true,"alive":true,"built":true,"queue":[],"remembered":false}]
func run():
	game=load("res://main.tscn").instantiate(); root.add_child(game)
	game.set_process(false); game.test_mode=true; game.ai_enabled=false
	# Exact policy boundaries use explicit synthetic records and AI budget.
	for workers in [0,1,2]:
		game.ai_budget={"food":50000,"wood":60000,"stone":0,"iron":0}
		check("affordable worker floor "+str(workers),game._ai_progression_goal(rows(),workers,10,9)=="villager")
	game.ai_budget={"food":49000,"wood":60000,"stone":0,"iron":0}
	check("unaffordable worker keeps farm recovery route",game._ai_progression_goal(rows(),1,10,1)=="farm")
	game.ai_budget={"food":150000,"wood":200000,"stone":0,"iron":0}
	check("full population keeps housing goal",game._ai_progression_goal(rows(),2,10,10)=="house")
	check("three committed workers retain farm progression",game._ai_progression_goal(rows(),3,10,3)=="farm")
	# Real game/ledger APIs below; only setup removes the opening AI villagers.
	game._test_reset([{"food":150,"wood":200,"stone":100,"iron":0},{"food":150,"wood":200,"stone":100,"iron":0}])
	game.set_process(false); game.test_mode=true; game.ai_enabled=false
	await process_frame
	var keep=game._first(1,"town_center")
	var food=game._nearest_resource(keep.pos,"food",1)
	check("controlled setup retains a known usable food source",not food.is_empty())
	if food.is_empty(): game.queue_free(); quit(2); return
	# Controlled removal, not earned depletion: retire observed berry records
	# while opening workers still provide their real visibility. Keep one source
	# for the later ordinary gather/deposit loop; never edit FactionView memory.
	for ent in game.entities:
		if ent.alive and ent.kind=="berry" and ent.id!=food.id and game._visible_to(ent,1): game._kill(ent)
	game._update_vision(false); game._publish_faction_views()
	for ent in game.entities:
		if ent.alive and ent.team==1 and ent.kind=="villager": game._kill(ent)
	game._update_vision(false); game._publish_faction_views()
	var known_food=0
	for record in game.faction_views[1].records().values():
		if record.category=="resource" and record.kind=="berry": known_food+=1
	check("real caller establishes old farm-priority deadlock",known_food>=1 and known_food<=3 and game._count(1,"farm")==0 and game._capacity(1)-game._population(1)>2)
	var before=game.economy.bank_milli(1).duplicate()
	check("attrition setup has no villagers or queued replacement",game._count(1,"villager")==0 and keep.queue.is_empty())
	check("ordinary recovery predicate recognizes viable producer",game._recovery_view(1).recovery_possible)
	game._ai_update()
	var train=[]
	for command in game.commands:
		if command.type=="train": train.append(command)
	check("AI queues one ordinary paid villager request",train.size()==1 and train[0].kind=="villager" and train[0].building==keep.id and train[0].team==1)
	execute_pending()
	check("training costs exact fifty food",game.economy.bank_milli(1).food==before.food-50000 and keep.queue.size()==1 and keep.queue[0].kind=="villager" and keep.queue[0].remaining_ticks==300)
	# Advance the actual production subsystem only. No instant/free spawn.
	for i in 299:
		game.tick_count+=1; game._update_production(keep,Rules.TICK,false); game._process_ready_production()
	check("replacement cannot appear before normal training time",game._count(1,"villager")==0 and keep.queue[0].remaining_ticks==1)
	game.tick_count+=1; game._update_production(keep,Rules.TICK,false); game._process_ready_production()
	check("ordinary receipt commit creates one replacement",game._count(1,"villager")==1 and keep.queue.is_empty() and game.trained_total[1]==1)
	var worker=game._first(1,"villager")
	game._update_vision(false); game._publish_faction_views(); execute_pending()
	check("new worker receives ordinary food order",not worker.is_empty() and worker.state=="gather" and worker.gather_type=="food")
	var deposited=game.delivered_total[1]
	for i in 1600:
		if game.delivered_total[1]>deposited or game.game_over: break
		game._tick(Rules.TICK)
	check("replacement resumes actual gather and deposit loop",game.delivered_total[1]>deposited)
	check("economy remains conserved",game.economy.audit().ok)
	var failed=checks.filter(func(item): return not item.passed).size()
	print(JSON.stringify({"suite":"ai_worker_recovery_contract","build":Rules.BUILD_ID,"checks":checks,"failed":failed,"scope":"Controlled attrition, paid production and bounded recovery ticks; not natural match or rendered proof","source_sha256":FileAccess.get_sha256("res://scripts/game.gd")}))
	game.queue_free(); quit(1 if failed else 0)

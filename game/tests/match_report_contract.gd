extends SceneTree
# ENGINE_UNRUN. Controlled paid production/construction/combat then surrender.
# No accelerated live match, natural victory, routed touch or rendered claim.
const Rules=preload("res://scripts/rules.gd")
const Routes=preload("res://scripts/map_routes.gd")
var game
var checks=[]
func check(label,ok):
	checks.append({"name":label,"passed":bool(ok)})
	if not ok: push_error(label)
func _initialize(): call_deferred("run")
func run():
	game=load("res://main.tscn").instantiate(); root.add_child(game)
	game.set_process(false); game.test_mode=true; game.ai_enabled=false
	game._test_reset(); game.set_process(false)
	await process_frame
	var keep=game._first(0,"town_center"); var worker=game._first(0,"villager")
	check("setup units and buildings excluded",game.match_report.trained.is_empty() and game.match_report.completed.is_empty())
	game._enqueue_train(keep.id,"villager",0)
	for i in 300:
		game.tick_count+=1; game._update_production(keep,Rules.TICK,false); game._process_ready_production()
	check("paid completed birth counted once",game.match_report.trained.get("villager",0)==1)
	game._enqueue_train(keep.id,"villager",0); game._cancel_train(keep.id,0)
	check("cancelled training not counted",game.match_report.trained.get("villager",0)==1)
	var location=Vector3(-7.5,0,15.5)+Routes.home_offset(0)
	var house=game._place_building("house",location,worker.id,0)
	check("normal paid placement admitted",not house.is_empty())
	if house.is_empty(): game.queue_free(); quit(2); return
	# Controlled placement of the worker at the real legal work approach.
	worker.pos=game._free_adjacent(house,worker.pos,false,0,worker)
	for i in 400:
		game.tick_count+=1; game._update_unit(worker,Rules.TICK)
	check("normal construction commit counted",house.built and game.match_report.completed.get("house",0)==1)
	game._execute({"type":"demolish","team":0,"building":house.id,"command_id":"report-demolish"})
	check("self demolition is not combat loss",not house.alive and game.match_report.building_losses.is_empty())
	var raider=game._first(1,"scout")
	worker.hp=1; game._set_stance(worker,"STOP")
	raider.pos=worker.pos+Vector3(1,0,0); raider.cooldown_ticks=0
	game._update_vision(false); game._order(raider,"attack",worker.id)
	game._tick(Rules.TICK)
	check("settled lethal combat counted",not worker.alive and game.match_report.unit_losses.get("villager",0)==1)
	game._submit("surrender",{}); game._tick(Rules.TICK)
	var report=game.last_match_report.duplicate(true)
	check("ordinary surrender freezes established defeat",game.game_over and report.outcome=="defeat" and report.reason=="surrender")
	check("final report retains actual commits",report.trained.get("villager",0)==1 and report.completed.get("house",0)==1 and report.unit_losses.get("villager",0)==1)
	check("ledger is detached and correctly copied",report.economy==game.economy.stats_view(0) and report.bank==game.economy.bank_milli(0))
	var tick=game.tick_count
	game._check_end(); game._tick(Rules.TICK)
	check("ended match does not advance or refreeze",game.tick_count==tick and game.last_match_report==report)
	for page in ["overview","economy","units","buildings"]:
		game._show_match_report_page(page)
		check("report page "+page,game.end_report_page==page and not game.end_report_label.text.is_empty())
	game._test_reset()
	check("reset clears current report without changing detached prior result",game.last_match_report.is_empty() and game.match_report.trained.is_empty() and report.trained.get("villager",0)==1)
	check("ledger conservation after reset",game.economy.audit().ok)
	var failed=checks.filter(func(item): return not item.passed).size()
	print(JSON.stringify({"suite":"match_report_contract","build":Rules.BUILD_ID,"checks":checks,"failed":failed,"status":"ENGINE_UNRUN","scope":"Controlled actual authority commits and direct callbacks, not natural full match or routed input"}))
	game.queue_free(); quit(1 if failed else 0)

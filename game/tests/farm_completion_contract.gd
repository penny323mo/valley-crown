extends SceneTree
# ENGINE_UNRUN. Controlled farm/site and explicit position setup, not a match.
# Actual component ticks and ledger, but no earned travel or raw touch claim.
const Rules=preload("res://scripts/rules.gd")
var game
var checks=[]
func check(label,ok):
	checks.append({"name":label,"passed":bool(ok)})
	if not ok: push_error(label)
func _initialize(): call_deferred("run")
func step(worker):
	game.tick_count+=1; game._update_unit(worker,Rules.TICK)
func run():
	game=load("res://main.tscn").instantiate(); root.add_child(game)
	game.set_process(false); game.test_mode=true; game.ai_enabled=false
	game._test_reset(); game.set_process(false)
	await process_frame
	var worker=game._first(0,"villager")
	var farm=game._spawn("farm",0,Vector3(32.5,0,32.5),false)
	var payment=game._pay(Rules.COSTS.farm,0)
	check("controlled site uses actual paid construction receipt",payment.applied)
	if not payment.applied: game.queue_free(); quit(2); return
	farm.cost_receipt_id=payment.receipt_id
	game.economy.mark_started(payment.receipt_id,0)
	game._navigation_rebuild(); game._order(worker,"build",farm.id)
	var approach=game._free_adjacent(farm,worker.pos,false,0,worker)
	check("controlled construction approach exists",approach!=Vector3.INF)
	if approach==Vector3.INF: game.queue_free(); quit(2); return
	worker.pos=approach; worker.node.position=approach
	game._update_vision(false)
	for i in 299: step(worker)
	check("no farm or harvest before full build time",not farm.built and game.economy.farm_view(farm.id).is_empty())
	step(worker)
	check("farm builder continues without another player order",farm.built and worker.state=="gather" and worker.target==farm.id and worker.farm_id==farm.id)
	check("completion tick creates no food",game.economy.farm_view(farm.id).get("generated_milli",-1)==0)
	check("completed receipt fulfilled",game.economy.receipt_view(payment.receipt_id).state=="fulfilled")
	check("farm approach passes ordinary local work geometry",game._at_work_approach(worker,farm,true))
	if not game._at_work_approach(worker,farm,true): game.queue_free(); quit(2); return
	var bank_before=game.economy.bank_milli(0).food
	for i in 334: step(worker)
	check("farm fills cargo through original 0.6 food per second ledger",game.economy.worker_view(worker.id).cargo_milli==10000 and game.economy.farm_view(farm.id).generated_milli==10000)
	check("cargo is not banked remotely",game.economy.bank_milli(0).food==bank_before)
	step(worker)
	check("full cargo takes ordinary deposit route",worker.state=="deliver")
	var drop=game._get_entity(worker.target)
	if drop.is_empty(): game.queue_free(); quit(2); return
	var drop_approach=game._free_adjacent(drop,worker.pos,false,0,worker)
	check("controlled dropoff approach exists",drop_approach!=Vector3.INF)
	if drop_approach==Vector3.INF: game.queue_free(); quit(2); return
	worker.pos=drop_approach; worker.node.position=drop_approach
	game._update_vision(false); step(worker)
	check("deposit returns original farm work",game.economy.bank_milli(0).food==bank_before+10000 and worker.state=="gather" and worker.target==farm.id and worker.farm_id==farm.id)
	game._set_stance(worker,"STOP")
	check("ordinary Stop releases field",worker.state=="idle" and game.economy.farm_view(farm.id).worker_id==-1)
	check("ledger conservation",game.economy.audit().ok)
	var failed=checks.filter(func(item): return not item.passed).size()
	print(JSON.stringify({"suite":"farm_completion_contract","build":Rules.BUILD_ID,"checks":checks,"failed":failed,"scope":"Controlled paid site, position setup and component work ticks, no natural match or movement"}))
	game.queue_free(); quit(1 if failed else 0)

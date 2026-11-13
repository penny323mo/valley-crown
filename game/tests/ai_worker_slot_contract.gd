extends SceneTree
# ENGINE_UNRUN. Synthetic military population, structures, stocks and attrition.
# No claim of earned troops, natural battle, full match, rendering or phone use.
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
func run():
	game=load("res://main.tscn").instantiate(); root.add_child(game)
	game.set_process(false); game.test_mode=true; game.ai_enabled=false
	game._test_reset([{"food":150,"wood":200,"stone":100,"iron":0},{"food":75,"wood":45,"stone":0,"iron":0}]); game.set_process(false)
	await process_frame
	var keep=game._first(1,"town_center")
	game._spawn("house",1,Vector3(34,0,-34))
	var producer=game._spawn("range",1,Vector3(30.5,0,-30.5))
	for ent in game.entities:
		if ent.alive and ent.team==1 and ent.kind=="villager": game._kill(ent)
	for i in 13: game._spawn("scout",1,Vector3(10+i,0,-12))
	game.ai_opening_assigned=true
	check("controlled setup has fourteen living military and fifteen capacity",game._population(1,false)==14 and game._capacity(1)==15 and game._count(1,"villager")==0)
	check("ordinary paid military reservation fills last population slot",game._enqueue_train(producer.id,"archer",1) and game._population(1)==15 and game.economy.bank_milli(1).food==50000)
	game._update_vision(false); game._publish_faction_views()
	var before=game.economy.bank_milli(1).duplicate(); game._ai_update()
	var cancellations=game.commands.filter(func(c): return c.type=="cancel_queue_item")
	check("one exact cancellation with refund, no immediate bank mutation",cancellations.size()==1 and cancellations[0].building==producer.id and cancellations[0].expected_refund.food==25000 and game.economy.bank_milli(1)==before)
	if cancellations.size()!=1: game.queue_free(); quit(2); return
	var cancel=cancellations[0].duplicate(true); execute_pending()
	check("cancelled reservation returns paid resources and slot",producer.queue.is_empty() and game._population(1)==14 and game.economy.bank_milli(1).food==75000)
	game._execute(cancel)
	check("duplicate cannot return another refund",game.economy.bank_milli(1).food==75000)
	game._publish_faction_views(); game._ai_update(); execute_pending()
	check("next actual policy queues paid replacement villager",keep.queue.size()==1 and keep.queue[0].kind=="villager" and game.economy.bank_milli(1).food==25000 and game._population(1)==15)
	if keep.queue.is_empty(): game.queue_free(); quit(2); return
	for i in 299:
		game.tick_count+=1; game._update_production(keep,Rules.TICK,false); game._process_ready_production()
	check("no worker appears before three hundred production ticks",game._count(1,"villager")==0 and keep.queue[0].remaining_ticks==1)
	game.tick_count+=1; game._update_production(keep,Rules.TICK,false); game._process_ready_production()
	check("ordinary birth preserves population and restores worker",game._count(1,"villager")==1 and game._population(1)==15 and keep.queue.is_empty())
	game._update_vision(false); game._publish_faction_views(); execute_pending()
	var worker=game._first(1,"villager")
	check("new villager receives ordinary food work",not worker.is_empty() and worker.state=="gather" and worker.gather_type=="food")
	check("actual ledger conserved",game.economy.audit().ok)
	var failed=checks.filter(func(item): return not item.passed).size()
	print(JSON.stringify({"suite":"ai_worker_slot_contract","build":Rules.BUILD_ID,"checks":checks,"failed":failed,"scope":"Controlled population/refund/birth only; no natural match"}))
	game.queue_free(); quit(1 if failed else 0)

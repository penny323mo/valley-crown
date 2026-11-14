extends SceneTree
# Controlled native engine fixture. Funded reset and controlled worker attrition, not a natural match.
# Actual research payment, 75%-floor refund, AI commands, paid replacement and
# 300 production ticks. No instant/free spawn or direct bank/receipt mutation.
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
	game._test_reset([{"food":150,"wood":200,"stone":100,"iron":0},{"food":500,"wood":200,"stone":100,"iron":150}])
	game.set_process(false); game.test_mode=true; game.ai_enabled=false
	await process_frame
	var keep=game._first(1,"town_center")
	check("ordinary age payment accepted",game._enqueue_research(keep.id,1))
	for i in 1800:
		game.tick_count+=1; game._update_production(keep,Rules.TICK,false); game._process_ready_production()
	game.tick_count+=1
	check("ordinary military research accepted",game._enqueue_military_research(keep.id,"forged_blades",1))
	check("all food committed to sole research",game.economy.bank_milli(1).food==0 and keep.queue.size()==1 and keep.queue[0].kind=="forged_blades")
	game.tick_count+=1; game._update_production(keep,Rules.TICK,false)
	var receipt=keep.queue[0].receipt_id
	check("started research retains original remaining time",keep.queue[0].started and keep.queue[0].remaining_ticks==899)
	check("started refund obeys floored whole-unit rule",game.economy.quote_refund(receipt,1).food==112000)
	# Controlled attrition via ordinary cleanup. No FactionView or ledger edits.
	for ent in game.entities:
		if ent.alive and ent.team==1 and ent.kind=="villager": game._kill(ent)
	game._update_vision(false); game._publish_faction_views()
	check("zero-worker setup still has a recoverable research receipt",game._count(1,"villager")==0 and game._recovery_view(1).recovery_possible)
	var bank=game.economy.bank_milli(1).duplicate()
	game._ai_update()
	var cancellations=[]
	var premature_training=[]
	for command in game.commands:
		if command.type=="cancel_queue_item": cancellations.append(command)
		if command.type=="train": premature_training.append(command)
	check("AI requests exactly one ordinary research cancellation",cancellations.size()==1 and cancellations[0].building==keep.id and cancellations[0].team==1)
	check("no pre-credit or same-turn training",game.economy.bank_milli(1)==bank and premature_training.is_empty() and keep.queue.size()==1)
	if cancellations.is_empty(): game.queue_free(); quit(2); return
	var cancel=cancellations[0].duplicate(true); execute_pending()
	check("ordinary cancellation refunds and removes research",keep.queue.is_empty() and game.economy.bank_milli(1).food==112000 and not game.military_tech_completed[1].has("forged_blades"))
	var refunded=game.economy.bank_milli(1).duplicate()
	game._execute(cancel)
	check("duplicate cancellation cannot duplicate refund",game.economy.bank_milli(1)==refunded and keep.queue.is_empty())
	game._publish_faction_views(); game._ai_update()
	var train=[]
	for command in game.commands:
		if command.type=="train": train.append(command)
	check("next observed bank funds ordinary villager request",train.size()==1 and train[0].kind=="villager" and train[0].building==keep.id)
	execute_pending()
	check("replacement consumes exact fifty food",game.economy.bank_milli(1).food==62000 and keep.queue.size()==1 and keep.queue[0].kind=="villager" and keep.queue[0].remaining_ticks==300)
	for i in 299:
		game.tick_count+=1; game._update_production(keep,Rules.TICK,false); game._process_ready_production()
	check("replacement does not appear early",game._count(1,"villager")==0 and keep.queue[0].remaining_ticks==1)
	game.tick_count+=1; game._update_production(keep,Rules.TICK,false); game._process_ready_production()
	check("normal receipt commit restores one worker",game._count(1,"villager")==1 and game.trained_total[1]==1 and keep.queue.is_empty())
	game._update_vision(false); game._publish_faction_views(); execute_pending()
	var worker=game._first(1,"villager")
	check("new worker receives normal food task",not worker.is_empty() and worker.state=="gather" and worker.gather_type=="food")
	check("ledger conserves actual resources",game.economy.audit().ok)
	var failed=checks.filter(func(item): return not item.passed).size()
	print(JSON.stringify({"suite":"military_tech_worker_recovery_contract","build":Rules.BUILD_ID,"checks":checks,"failed":failed,"scope":"Controlled paid refund/replacement; no full-match or rendering proof","source_sha256":FileAccess.get_sha256("res://scripts/game.gd")}))
	game.queue_free(); quit(1 if failed else 0)

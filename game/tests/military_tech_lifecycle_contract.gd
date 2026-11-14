extends SceneTree
# Funded synthetic lifecycle fixture. Ordinary payments and countdowns.
const Rules=preload("res://scripts/rules.gd")
var game
var checks=[]
func check(label,ok):
	checks.append({"name":label,"passed":bool(ok)})
	if not ok: push_error(label)
func _initialize(): call_deferred("run")
func advance(n):
	for i in n:
		game.tick_count+=1
		for ent in game.entities:
			if ent.alive and ent.category=="building": game._update_production(ent,Rules.TICK,false)
		game._process_ready_production()
func run():
	game=load("res://main.tscn").instantiate(); root.add_child(game); game.set_process(false); game.test_mode=true; game.ai_enabled=false
	var bank={"food":2000,"wood":1000,"stone":100,"iron":300}
	game._test_reset([bank,bank]); game.set_process(false)
	await process_frame
	var keep=game._first(0,"town_center")
	game._enqueue_research(keep.id,0); advance(1800); game.tick_count+=1
	game._spawn("house",0,keep.pos+Vector3(7,0,7)) # Synthetic housing makes all five paid queue slots available.
	for i in 5: game._enqueue_train(keep.id,"villager",0)
	var before=game.economy.bank_milli(0).duplicate()
	check("full queue refuses technology without charge",not game._enqueue_military_research(keep.id,"forged_blades",0) and before==game.economy.bank_milli(0))
	while not keep.queue.is_empty():
		var item=keep.queue[0]
		game._cancel_queue_item(keep.id,item.queue_id,game.economy.quote_refund(item.receipt_id,0),0)
	game._enqueue_military_research(keep.id,"forged_blades",0)
	var item=keep.queue[0]; var stale=game.economy.quote_refund(item.receipt_id,0)
	advance(1)
	check("started research rejects stale refund",not game._cancel_queue_item(keep.id,item.queue_id,stale,0))
	var refund=game.economy.quote_refund(item.receipt_id,0)
	check("started tech uses existing 75 percent whole-unit refund",refund.food==112000 and refund.iron==75000)
	check("started cancellation removes unlock",game._cancel_queue_item(keep.id,item.queue_id,refund,0) and game._military_attack_bonus("spearman",0)==0)
	game._enqueue_military_research(keep.id,"forged_blades",0)
	var receipt=keep.queue[0].receipt_id
	advance(899); game._kill(keep); advance(2)
	check("destroyed keep never completes technology",not game.military_tech_completed[0].has("forged_blades"))
	check("destroyed research receipt not reusable",game.economy.receipt_view(receipt).state=="destroyed")
	check("dead keep cannot accept research",not game._enqueue_military_research(keep.id,"tempered_arrows",0))
	check("lifecycle economy conserved",game.economy.audit().ok)
	var failed=checks.filter(func(c):return not c.passed).size()
	print(JSON.stringify({"suite":"military_tech_lifecycle_contract","checks":checks,"failed":failed,"scope":"funded lifecycle fixture; no rendering acceptance"}))
	game.queue_free(); quit(1 if failed else 0)

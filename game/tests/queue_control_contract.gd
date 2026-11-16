extends SceneTree
# ENGINE_UNRUN. Actual paid queue/ordinary ticks with explicit fixture starting stocks.
# No natural gathering, full match, routed GUI input or rendering is claimed.
const Rules=preload("res://scripts/rules.gd")
var game
var checks=[]
func check(label,ok):
	checks.append({"name":label,"passed":bool(ok)})
	if not ok: push_error(label)
func _initialize():call_deferred("run")
func run():
	game=load("res://main.tscn").instantiate();root.add_child(game)
	game.set_process(false);game.test_mode=true;game.ai_enabled=false
	var stock={"food":1000,"wood":1000,"stone":1000,"iron":1000}
	game._test_reset([stock,stock.duplicate(true)]);game.set_process(false)
	await process_frame
	var keep=game._first(0,"town_center")
	game._enqueue_train(keep.id,"villager",0);game._enqueue_train(keep.id,"scout",0);game._enqueue_train(keep.id,"villager",0);game._enqueue_research(keep.id,0)
	check("four items actually paid and queued",keep.queue.size()==4 and game.economy.bank_milli(0).food==480000)
	if keep.queue.size()!=4:game.queue_free();quit(1);return
	game._tick(Rules.TICK)
	var head=keep.queue[0].duplicate(true);var middle=keep.queue[1].duplicate(true);var third=keep.queue[2].duplicate(true);var research=keep.queue[3].duplicate(true)
	var before=game.economy.bank_milli(0)
	game._select([keep.id]);game._update_hud()
	# Real helper performs synchronous Cancel/HUD node rebuild before queueing.
	game._queue_cancel_request(keep.id,middle.queue_id)
	check("real queue action queues exact middle after HUD rebuild",game.commands.size()==1 and game.commands[0].queue_id==middle.queue_id)
	game._tick(Rules.TICK)
	check("exact middle removed and unstarted refund applied",keep.queue.size()==3 and keep.queue[0].queue_id==head.queue_id and keep.queue[1].queue_id==third.queue_id and game.economy.bank_milli(0).food==before.food+70000)
	check("head production continues without reset",keep.queue[0].remaining_ticks==head.remaining_ticks-1)
	before=game.economy.bank_milli(0)
	game._submit("cancel_queue_item",{"building":keep.id,"queue_id":middle.queue_id,"expected_refund":{"food":70000,"wood":0,"stone":0,"iron":0}})
	game._tick(Rules.TICK)
	check("removed ID cannot refund twice or remove successor",keep.queue.size()==3 and game.economy.bank_milli(0)==before)
	game._submit("cancel_queue_item",{"building":keep.id,"queue_id":head.queue_id,"expected_refund":game.economy.quote_refund(head.receipt_id,0)})
	game._tick(Rules.TICK)
	check("started head uses whole-unit refund",game.economy.bank_milli(0).food==before.food+37000 and keep.queue[0].queue_id==third.queue_id)
	var research_quote=game.economy.quote_refund(research.receipt_id,0)
	game._submit("cancel_queue_item",{"building":keep.id,"queue_id":third.queue_id,"expected_refund":game.economy.quote_refund(third.receipt_id,0)})
	game._tick(Rules.TICK)
	check("research begins after earlier orders removed",keep.queue.size()==1 and keep.queue[0].started)
	before=game.economy.bank_milli(0)
	game._submit("cancel_queue_item",{"building":keep.id,"queue_id":research.queue_id,"expected_refund":research_quote})
	game._tick(Rules.TICK)
	check("stale full research refund rejected without mutation",keep.queue.size()==1 and game.economy.bank_milli(0)==before and not game._age2(0))
	game._submit("cancel_queue_item",{"building":keep.id,"queue_id":research.queue_id,"expected_refund":game.economy.quote_refund(research.receipt_id,0)})
	game._tick(Rules.TICK)
	check("fresh research refund clears pending unlock",keep.queue.is_empty() and not game._research_pending(0) and game.economy.bank_milli(0).food==before.food+262000)
	# Same-kind items: one real paid birth, then a new ID at unchanged queue size.
	game._enqueue_train(keep.id,"villager",0);game._enqueue_train(keep.id,"villager",0)
	game._select([keep.id]);game._update_hud()
	var completed_id=keep.queue[0].queue_id
	var retained_id=keep.queue[1].queue_id
	for index in 300:game._tick(Rules.TICK)
	game._enqueue_train(keep.id,"villager",0)
	# Direct fixture enqueue bypasses the tick publication boundary. Refresh
	# the owned view before asserting what the HUD sees; assertions unchanged.
	game._publish_faction_views();game._update_hud()
	var current_ids=[]
	for action in game.queue_actions:current_ids.append(action.queue_id)
	check("same-kind queue replacement rebinds exact identities",keep.queue.size()==2 and current_ids==[retained_id,keep.queue[1].queue_id] and completed_id not in current_ids)
	var pending=game.commands.size();game._queue_cancel_request(keep.id,completed_id)
	check("completed action cannot cancel new same-kind item",game.commands.size()==pending and keep.queue.size()==2)
	check("real queue ledger remains conserved",game.economy.audit().ok)
	var failed=checks.filter(func(item):return not item.passed).size()
	print(JSON.stringify({"suite":"queue_control_contract","build":Rules.BUILD_ID,"checks":checks,"failed":failed,"status":"ENGINE_UNRUN","scope":"Actual paid queue and normal ticks from controlled initial stocks; not natural income, routed touch or rendered acceptance"}))
	game.queue_free();quit(1 if failed else 0)

extends SceneTree
# ENGINE_UNRUN. Synthetic completed producer, ordinary initial bank, real
# payment/countdown/receipt components. No earned building or natural match.
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
	game._test_reset(); game.set_process(false)
	await process_frame
	var keep=game._first(0,"town_center")
	var building=game._spawn("barracks",0,keep.pos+Vector3(6,0,6))
	game._navigation_rebuild(); game._update_vision(false); game._publish_faction_views()
	var initial=game.economy.bank_milli(0).duplicate()
	check("repeat is off by default",building.get("repeat_kind","")=="")
	check("ordinary opt-in accepted",game._set_repeat_training(building.id,"spearman",0))
	check("worker producer excluded",not game._set_repeat_training(keep.id,"villager",0))
	game._update_repeat_training()
	check("proposal is not payment",game.economy.bank_milli(0)==initial and game.commands.size()==1)
	execute_pending()
	check("one normal paid item",building.queue.size()==1 and game.economy.bank_milli(0).food==initial.food-50000)
	if building.queue.size()!=1: game.queue_free(); quit(2); return
	var first_receipt=building.queue[0].receipt_id
	var before_trained=game.trained_total[0]
	for i in 720:
		game.tick_count+=1; execute_pending()
		game._update_production(building,Rules.TICK,false); game._process_ready_production()
		game._update_repeat_training()
		if i==358: check("no early first birth",game.trained_total[0]==before_trained)
	check("two paid births over two countdowns",game.trained_total[0]==before_trained+2)
	check("normal repeated total cost",game.economy.bank_milli(0).food==initial.food-100000 and game.economy.bank_milli(0).wood==initial.wood-40000)
	check("first receipt fulfilled",game.economy.receipt_view(first_receipt).state=="fulfilled")
	check("next item proposed not yet prepaid",building.queue.is_empty() and game.commands.size()==1)
	var before_disable=game.economy.bank_milli(0).duplicate()
	check("disable accepted",game._set_repeat_training(building.id,"",0))
	execute_pending()
	check("stale automatic intent cannot charge",building.queue.is_empty() and game.economy.bank_milli(0)==before_disable)
	game._set_repeat_training(building.id,"spearman",0); game._update_repeat_training(); execute_pending()
	check("can re-enable through normal queue",building.queue.size()==1)
	if building.queue.is_empty(): game.queue_free(); quit(2); return
	var item=building.queue[0]
	check("exact cancellation succeeds",game._cancel_queue_item(building.id,item.queue_id,game.economy.quote_refund(item.receipt_id,0),0))
	game._update_repeat_training()
	check("cancellation stops repeat without rebuy",building.get("repeat_kind","")=="" and game.commands.is_empty())
	check("ledger conservation",game.economy.audit().ok)
	var failed=checks.filter(func(item): return not item.passed).size()
	print(JSON.stringify({"suite":"continuous_training_contract","build":Rules.BUILD_ID,"checks":checks,"failed":failed,"scope":"Synthetic producer, ordinary paid production components. No natural whole-tick match or physical travel"}))
	game.queue_free(); quit(1 if failed else 0)

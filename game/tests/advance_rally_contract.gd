extends SceneTree
# ENGINE_UNRUN. Controlled producer site and paid training component ticks.
# No earned building, routed touch, physical march or natural combat claim.
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
	var point=game._nearest_free(keep.pos+Vector3(5,0,0),3,0)
	check("controlled rally point available",point!=Vector3.INF)
	if point==Vector3.INF: game.queue_free(); quit(2); return
	check("ordinary setter accepts explicit military advance rally",game._set_ground_rally(building.id,point,0,false,-1,"advance"))
	check("town center cannot inherit military-only rally",not game._set_ground_rally(keep.id,point,0,false,-1,"advance"))
	var before=game.economy.bank_milli(0).duplicate()
	check("ordinary paid spearman queue",game._enqueue_train(building.id,"spearman",0))
	if building.queue.is_empty(): game.queue_free(); quit(2); return
	var receipt=building.queue[0].receipt_id
	check("normal cost paid",game.economy.bank_milli(0).food==before.food-50000 and game.economy.bank_milli(0).wood==before.wood-20000)
	var original_ids=[]
	for ent in game.entities: original_ids.append(ent.id)
	for i in 359:
		game.tick_count+=1; game._update_production(building,Rules.TICK,false); game._process_ready_production()
	check("no early birth or advance command",game.commands.is_empty() and not building.queue.is_empty() and building.queue[0].remaining_ticks==1)
	game.tick_count+=1; game._update_production(building,Rules.TICK,false); game._process_ready_production()
	var newborn={}
	for ent in game.entities:
		if ent.id not in original_ids and ent.kind=="spearman" and ent.team==0: newborn=ent
	check("birth queues exactly one advance action",not newborn.is_empty() and game.commands.size()==1 and game.commands[0].type=="advance")
	if newborn.is_empty(): game.queue_free(); quit(2); return
	check("paid receipt fulfilled before rally",game.economy.receipt_view(receipt).state=="fulfilled")
	var birth_position=newborn.pos
	execute_pending()
	check("ordinary authority applies advance without teleporting",newborn.mode=="ADVANCE" and newborn.state=="move" and newborn.pos==birth_position)
	# A separate controlled replay of the helper checks order priority, not a
	# duplicate production event or a second actual birth.
	game._apply_newborn_rally(newborn,building)
	game._submit("stop",{"ids":[newborn.id]})
	execute_pending()
	check("later explicit player Stop wins",newborn.mode=="STOP" and newborn.state=="idle")
	check("clear removes stored advance mode",game._set_ground_rally(building.id,Vector3.INF,0,true) and not building.has("rally_mode"))
	check("ledger conservation",game.economy.audit().ok)
	var failed=checks.filter(func(item): return not item.passed).size()
	print(JSON.stringify({"suite":"advance_rally_contract","build":Rules.BUILD_ID,"checks":checks,"failed":failed,"scope":"Controlled producer, paid training and queued authority only, no path travel or natural battle"}))
	game.queue_free(); quit(1 if failed else 0)

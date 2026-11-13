extends SceneTree
# ENGINE_UNRUN. Controlled funded reset; actual paid training and newborn orders.
# This is not a natural match, routed phone input or rendered acceptance.
const Rules=preload("res://scripts/rules.gd")
var game
var checks=[]
func check(label,ok):
	checks.append({"name":label,"passed":bool(ok)})
	if not ok: push_error(label)
func _initialize(): call_deferred("run")
func consume():
	var batch=game.commands.duplicate(true); game.commands.clear()
	batch.sort_custom(func(a,b): return a.sequence<b.sequence)
	for command in batch: game._execute(command)
func run():
	game=load("res://main.tscn").instantiate(); root.add_child(game)
	game.set_process(false); game.test_mode=true; game.ai_enabled=false
	game._test_reset()
	game.set_process(false); game.test_mode=true; game.ai_enabled=false
	await process_frame
	var keep=game._first(0,"town_center")
	var resource=game._nearest_resource(keep.pos,"food",0)
	check("setup has visible natural food",not resource.is_empty() and game._visible_to(resource,0))
	if resource.is_empty(): game.queue_free(); quit(2); return
	game._submit("rally",{"building":keep.id,"position":Vector3(999,0,999),"target":resource.id})
	consume()
	check("resource rally stores authoritative observed point",keep.get("rally_target",-1)==resource.id and keep.rally_point==resource.pos)
	game._publish_faction_views()
	check("own projection carries resource plan",game.faction_views[0].get_record(keep.id).get("rally_target",-1)==resource.id)
	var workers=game._count(0,"villager"); var bank=game.economy.bank_milli(0).food
	game._submit("train",{"building":keep.id,"kind":"villager"}); consume()
	check("rallied worker still costs fifty food",game.economy.bank_milli(0).food==bank-50000 and keep.queue[0].remaining_ticks==300)
	for i in 299:
		game.tick_count+=1; game._update_production(keep,Rules.TICK,false); game._process_ready_production()
	check("no early rallied birth",game._count(0,"villager")==workers and keep.queue[0].remaining_ticks==1)
	game.tick_count+=1; game._update_production(keep,Rules.TICK,false); game._process_ready_production()
	var newborn=game.entities.back()
	check("normal production creates exactly one villager",game._count(0,"villager")==workers+1 and newborn.kind=="villager" and newborn.team==0 and keep.queue.is_empty())
	var orders=[]
	for command in game.commands:
		if command.type=="order" and command.ids==[newborn.id]: orders.append(command)
	check("only newborn receives ordinary resource command",orders.size()==1 and orders[0].target==resource.id and orders[0].position==resource.pos)
	check("birth does not directly start harvesting",newborn.state=="idle" and game.economy.worker_view(newborn.id).cargo_milli==0)
	consume()
	check("ordinary execution accepts newborn gather",newborn.state=="gather" and newborn.target==resource.id and newborn.gather_type=="food")
	var before=game.delivered_total[0]
	for i in 1600:
		if game.delivered_total[0]>before or game.game_over: break
		game._tick(Rules.TICK)
	check("rallied worker reaches real gather/deposit",game.delivered_total[0]>before)
	check("paid training and work conserve ledger",game.economy.audit().ok)
	# A current order may outlive its target. Keep the existing atomic rejection.
	game._set_stance(newborn,"STOP"); game._update_vision(false); game._publish_faction_views()
	game._apply_newborn_rally(newborn,keep)
	var pending=game.commands.duplicate(true); game.commands.clear()
	check("current resource can queue one fresh order",pending.size()==1 and pending[0].target==resource.id)
	# Controlled removal for stale-target coverage, not earned depletion.
	game._kill(resource)
	var prior=newborn.duplicate(true)
	for command in pending: game._execute(command)
	check("target death before execution leaves prior unit intent",newborn.state==prior.state and newborn.target==prior.target and newborn.work_epoch==prior.work_epoch)
	# Ordinary observation retires the depleted target; fallback uses only point.
	game._update_vision(false); game._publish_faction_views(); game.commands.clear()
	game._apply_newborn_rally(newborn,keep)
	check("retired resource gives bounded ground fallback",newborn.state=="move" and game.commands.is_empty() and newborn.target==-1)
	game._set_ground_rally(keep.id,Vector3.INF,0,true)
	check("clear removes both plan fields",not keep.has("rally_target") and not keep.has("rally_point"))
	var failed=checks.filter(func(item): return not item.passed).size()
	print(JSON.stringify({"suite":"resource_rally_contract","build":Rules.BUILD_ID,"checks":checks,"failed":failed,"scope":"Controlled paid newborn/gather/depletion; ENGINE_UNRUN","source_sha256":FileAccess.get_sha256("res://scripts/game.gd")}))
	game.queue_free(); quit(1 if failed else 0)

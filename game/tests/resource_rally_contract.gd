extends SceneTree
# Controlled funded reset; actual paid training and newborn orders.
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
	# Observed depletion with a same-type cluster continues ordinary work.
	game._update_vision(false); game._publish_faction_views(); game.commands.clear()
	var bank_before=game.economy.bank_milli(0).duplicate()
	var cargo_before=game.economy.worker_view(newborn.id).cargo_milli
	game._apply_newborn_rally(newborn,keep)
	check("observed depletion queues exactly one replacement gather",game.commands.size()==1 and newborn.state=="idle")
	if game.commands.size()==1:
		var command=game.commands[0]
		var replacement=game.faction_views[0].get_record(command.target)
		check("replacement is current visible live natural food within original cluster",not replacement.is_empty() and replacement.get("alive",false) and not replacement.get("remembered",true) and replacement.category=="resource" and game._resource_type(replacement)=="food" and replacement.pos.distance_to(keep.rally_point)<=8.0)
		check("replacement order only addresses newborn and exact observed position",command.type=="order" and command.ids==[newborn.id] and command.position==replacement.pos)
		consume()
		check("replacement uses authoritative normal gather execution",newborn.state=="gather" and newborn.target==replacement.id and newborn.gather_type=="food")
	else:
		check("replacement is current visible live natural food within original cluster",false)
		check("replacement order only addresses newborn and exact observed position",false)
		check("replacement uses authoritative normal gather execution",false)
	check("replacement neither pays again nor grants harvested cargo",game.economy.bank_milli(0)==bank_before and game.economy.worker_view(newborn.id).cargo_milli==cargo_before)
	# Actual newborn-handler fallback, not merely the replacement helper.
	game._set_stance(newborn,"STOP");game.commands.clear()
	var origin_cell=game._cell_index(keep.rally_point)
	var original_visibility=game.visible_cells[0][origin_cell]
	game.visible_cells[0][origin_cell]=0
	game._apply_newborn_rally(newborn,keep)
	check("hidden original resource site retains bounded ground fallback",newborn.state=="move" and game.commands.is_empty() and newborn.target==-1)
	game.visible_cells[0][origin_cell]=original_visibility
	game._set_stance(newborn,"STOP");game.commands.clear()
	var stored_type=keep.rally_resource_type
	keep.erase("rally_resource_type")
	game._apply_newborn_rally(newborn,keep)
	check("legacy rally without type retains bounded ground fallback",newborn.state=="move" and game.commands.is_empty() and newborn.target==-1)
	keep.rally_resource_type=stored_type
	# Keep the original fallback assertion, now with its explicit condition:
	# there is no same-type resource left for the local continuation policy.
	for candidate in game.entities:
		if candidate.alive and candidate.category=="resource" and game._resource_type(candidate)==stored_type:game._kill(candidate)
	game._update_vision(false);game._publish_faction_views()
	game._set_stance(newborn,"STOP");game.commands.clear()
	check("no live local replacement remains",game._resource_rally_replacement(keep,0).is_empty())
	game._apply_newborn_rally(newborn,keep)
	check("retired resource gives bounded ground fallback",newborn.state=="move" and game.commands.is_empty() and newborn.target==-1)
	check("all fallback paths conserve the economy",game.economy.audit().ok)
	game._set_ground_rally(keep.id,Vector3.INF,0,true)
	check("clear removes both plan fields",not keep.has("rally_target") and not keep.has("rally_point") and not keep.has("rally_resource_type"))
	var failed=checks.filter(func(item): return not item.passed).size()
	print(JSON.stringify({"suite":"resource_rally_contract","build":Rules.BUILD_ID,"checks":checks,"failed":failed,"scope":"Controlled paid newborn/gather/depletion, local continuation and hidden/legacy/no-replacement fallback; not rendered acceptance","source_sha256":FileAccess.get_sha256("res://scripts/game.gd")}))
	game.queue_free(); quit(1 if failed else 0)

extends SceneTree
# ENGINE_UNRUN. Controlled keep damage/initial stocks, ordinary policy/orders/work.
# Not earned resources, attack settlement, a natural match or rendered acceptance.
const Rules=preload("res://scripts/rules.gd")
var game
var checks=[]
func check(label,ok):
	checks.append({"name":label,"passed":bool(ok)})
	if not ok: push_error(label)
func _initialize(): call_deferred("run")
func run():
	game=load("res://main.tscn").instantiate(); root.add_child(game)
	game.set_process(false); game.test_mode=true; game.ai_enabled=false
	game._test_reset([{"food":150,"wood":200,"stone":100,"iron":0},{"food":150,"wood":10,"stone":100,"iron":0}]); game.set_process(false)
	await process_frame
	var castle=game._first(1,"town_center"); var workers=[]
	for ent in game.entities:
		if ent.alive and ent.team==1 and ent.kind=="villager": workers.append(ent)
	workers.sort_custom(func(a,b): return a.id<b.id)
	var repairer=workers[2]
	# Establish real gather intent through the existing worker assignment path.
	game._update_vision(false); game._publish_faction_views()
	game._assign_worker(workers[0],"food"); game._assign_worker(workers[1],"food")
	game._tick(Rules.TICK)
	game.ai_opening_assigned=true
	var start_point=game._free_adjacent(castle,castle.pos+Vector3(3,0,0),false,1,repairer)
	check("controlled repair starting point exists",start_point!=Vector3.INF)
	if start_point==Vector3.INF:
		game.queue_free(); quit(1); return
	repairer.pos=start_point
	game._set_stance(repairer,"STOP")
	castle.hp=castle.max_hp-10; castle.last_damage_tick=game.tick_count-100
	game._update_vision(false); game._publish_faction_views()
	var before=game.economy.bank_milli(1).wood
	var repair_spent_before=game.economy.stats_view(1).repaired.wood
	game._ai_update()
	check("AI submits a real keep order without immediate debit or HP grant",game.commands.any(func(c): return c.type=="order" and c.get("target",-1)==castle.id) and game.economy.bank_milli(1).wood==before and castle.hp==castle.max_hp-10)
	game._tick(Rules.TICK)
	var chosen={}
	for worker in workers:
		if worker.state=="repair" and worker.target==castle.id: chosen=worker; break
	check("ordinary target order resolves to repair",not chosen.is_empty())
	if not chosen.is_empty():
		for i in 240:
			if chosen.state=="repair" and chosen.work_ticks==19:
				game._publish_faction_views(); game._ai_update()
				check("policy does not steal the nearly-paid repair interval",game.ai_claimed_workers.get(chosen.id,"")=="repair" and chosen.work_ticks==19)
			game._tick(Rules.TICK)
			if castle.hp==castle.max_hp: break
	check("two ordinary paid work commits restore ten HP",castle.hp==castle.max_hp and game.economy.stats_view(1).repaired.wood==repair_spent_before+2000)
	game._publish_faction_views(); game._ai_update()
	check("completed repair releases worker to ordinary economy",chosen.is_empty() or chosen.state!="repair")
	check("ledger conserved",game.economy.audit().ok)
	var failed=checks.filter(func(item): return not item.passed).size()
	print(JSON.stringify({"suite":"ai_keep_recovery_contract","build":Rules.BUILD_ID,"checks":checks,"failed":failed,"scope":"Controlled ordinary policy/order/repair, no natural economic or battle progression"}))
	game.queue_free(); quit(1 if failed else 0)

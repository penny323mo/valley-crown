extends SceneTree
# Controlled worker/attacker/refuge placement; actual damage, movement and queues.
const Rules=preload("res://scripts/rules.gd")
var game
var checks=[]
func check(label,ok):
	checks.append({"name":label,"passed":bool(ok)})
	if not ok: push_error(label)
func _initialize(): call_deferred("run")
func run():
	game=load("res://main.tscn").instantiate();root.add_child(game);game.set_process(false);game.test_mode=true;game.ai_enabled=false
	game._test_reset();game.set_process(false)
	await process_frame
	var keep=game._spawn("town_center",0,Vector3(-10,0,-10))
	var worker=game._spawn("villager",0,Vector3(0,0,-10))
	var resource=game._spawn("berry",-1,Vector3(0,0,-11))
	game._navigation_rebuild();game._update_vision(false)
	game._order(worker,"gather",resource.id)
	for i in 60: game._tick(Rules.TICK)
	var cargo=game._cargo_amount(worker)
	check("worker earns actual cargo before raid",cargo>0)
	var enemy=game._spawn("spearman",1,worker.pos+Vector3(0.8,0,0))
	game._update_vision(false)
	game._publish_faction_views();game._update_worker_safety()
	check("proximity alone cannot commandeer worker",not game.worker_evacuations.has(worker.id) and worker.state=="gather")
	var hit=game._release_attack(enemy,worker)
	check("real enemy attack released",hit.applied)
	var bank=game.economy.bank_milli(0).duplicate()
	var node_before=game.economy.node_view(resource.id).remaining_milli
	game._tick(Rules.TICK)
	check("settled hit causes normal retreat move",worker.hp<worker.max_hp and game.worker_evacuations.has(worker.id) and worker.state=="move")
	check("evacuation preserves earned cargo and normal hit-tick harvest",game._cargo_amount(worker)==cargo+node_before-game.economy.node_view(resource.id).remaining_milli)
	var retreat_cargo=game._cargo_amount(worker)
	check("retreat has no free resource or heal",game.economy.bank_milli(0)==bank and worker.hp==worker.max_hp-hit.event.damage)
	var destination=worker.dest;var epoch=worker.work_epoch
	game._update_worker_safety();game._update_worker_safety()
	check("same hit does not reissue or reset work",worker.dest==destination and worker.work_epoch==epoch)
	# Actual bounded navigation, not a teleport to the refuge.
	for i in 400:
		game._tick(Rules.TICK)
		if worker.state=="idle":break
	print("WALK_DIAG ",JSON.stringify({"alive":worker.alive,"hp":worker.hp,"pos":str(worker.pos),"dest":str(destination),"state":worker.state,"status":worker.path_status,"reason":worker.path_reason,"epoch":worker.work_epoch,"saved":game.worker_evacuations.get(worker.id,{})}))
	check("walking to refuge preserves all typed cargo",game._cargo_amount(worker)==retreat_cargo and game._cargo_type(worker)=="food")
	check("worker reaches refuge by physical movement",worker.pos.distance_to(destination)<0.5 and worker.state=="idle")
	check("visible danger at original job prevents return",game.worker_evacuations.has(worker.id))
	check("fog wait is explained in selection status",game._worker_safety_label(game.faction_views[0].get_record(worker.id))=="等待原工作區重新可見")
	game._kill(enemy);game._spawn("scout",0,resource.pos+Vector3(0,0,3));game._update_vision(false);game._publish_faction_views();game._update_worker_safety()
	for i in 20: game._tick(Rules.TICK)
	check("safe wait is not immediate return",worker.state=="idle" and game.worker_evacuations.has(worker.id))
	var new_threat=game._spawn("spearman",1,resource.pos+Vector3(0,0,5))
	game._update_vision(false);game._publish_faction_views();game._update_worker_safety()
	check("renewed observed danger resets safe timer",game.worker_evacuations[worker.id].safe_since_tick==-1)
	game._kill(new_threat);game._update_vision(false);game._publish_faction_views();game._update_worker_safety()
	for i in 99: game._tick(Rules.TICK)
	check("must wait full continuous five seconds",worker.state=="idle" and game.worker_evacuations.has(worker.id))
	game._tick(Rules.TICK)
	check("safe worker resumes original berry job",worker.state=="gather" and worker.resource_target==resource.id and not game.worker_evacuations.has(worker.id))
	# Explicit destination consumes old automation state and cannot be resumed later.
	game.worker_evacuations[worker.id]={"epoch":worker.work_epoch,"resource":resource.id,"origin":resource.pos}
	game._submit("order",{"ids":[worker.id],"position":Vector3(-15,0,-15),"target":-1})
	game._tick(Rules.TICK)
	check("accepted manual move wins permanently",not game.worker_evacuations.has(worker.id) and worker.state=="move" and game.worker_manual_until[worker.id]>game.tick_count)
	# Terminal budgets are not reset by automatic evacuation.
	game.worker_manual_until.clear();game.worker_safety_hits.clear()
	game._order(worker,"gather",resource.id)
	worker.last_damage_tick=game.tick_count;worker.path_status="NO_PATH";worker.path_failures=3;worker.path_next_attempt_tick=game.tick_count+99
	game._publish_faction_views();game._update_worker_safety()
	check("terminal route is left terminal",worker.path_status=="NO_PATH" and worker.path_failures==3 and worker.path_next_attempt_tick==game.tick_count+99 and not game.worker_evacuations.has(worker.id))
	# Policy is entirely observation-limited. A remembered enemy is not live danger.
	var hidden={1:{"id":1,"team":1,"kind":"spearman","category":"unit","alive":true,"remembered":true,"pos":worker.pos}}
	check("remembered enemy never supplies threat",game.WorkerSafety.threats(hidden,0,worker.pos).is_empty())
	check("empty view cannot reveal enemies",game.WorkerSafety.threats({},0,worker.pos).is_empty())
	game.worker_evacuations[worker.id]={"epoch":worker.work_epoch,"resource":resource.id,"origin":resource.pos}
	game._toggle_worker_safety()
	check("user can disable automation and old resumption",not game.worker_safety_enabled and game.worker_evacuations.is_empty())
	check("ledger remains conserved",game.economy.audit().ok)
	game._test_reset();game.set_process(false)
	check("new match clears safety jobs and fences",game.worker_evacuations.is_empty() and game.worker_manual_until.is_empty() and game.worker_safety_hits.is_empty())
	var failed=checks.filter(func(c):return not c.passed).size()
	print(JSON.stringify({"suite":"worker_safety_cargo_contract","checks":checks,"failed":failed,"scope":"Controlled placements, actual damage and bounded walking; not natural full match or rendered/mobile acceptance"}))
	game.queue_free();quit(1 if failed else 0)

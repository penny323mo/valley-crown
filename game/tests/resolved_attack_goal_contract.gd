extends SceneTree
## Controlled request-identity regression, not natural match evidence.
const Rules=preload("res://scripts/rules.gd")
var game
var checks=[]
func check(name,ok):
	checks.append({"name":name,"passed":bool(ok)})
	if not ok:push_error(name)
func _initialize():call_deferred("run")
func run():
	game=load("res://main.tscn").instantiate();root.add_child(game)
	game.set_process(false);game.test_mode=true;game._test_reset();game.set_process(false);game.ai_enabled=false
	await process_frame
	var unit=game._first(0,"scout")
	# Isolated cached-path identity: raw occupied target is diagonal from snapped endpoint.
	unit.pos=Vector3(8.5,0,8.5);game._path_state(unit)
	unit.state="attack";unit.mode="ATTACK";unit.path_status="FOUND"
	unit.dest=Vector3(1.5,0,-0.5);unit.path_request_goal=Vector3(.5,0,.5)
	unit.path=PackedVector3Array([Vector3(8.5,0,7.5)]);unit.path_version=game.work_memory[0].revision
	unit.path_pending=false;var retries=unit.path_retry_ticks.duplicate();var searches=unit.path_searches
	game._move(unit,Vector3(.5,0,.5),0.0)
	check("unchanged raw target retains cached snapped route",not unit.path_pending and unit.path_status=="FOUND")
	check("retaining route spends no searches or resets retries",unit.path_searches==searches and unit.path_retry_ticks==retries)
	game._queue_traffic_route(unit)
	check("local combat traffic preserves raw target identity",unit.path_request_goal==Vector3(.5,0,.5) and unit.path_pending and unit.traffic_route)
	check("traffic still consumes its bounded replan allowance",unit.traffic_replans==1)
	game._path_cancel_pending(unit);unit.path_status="FOUND";unit.path=PackedVector3Array([Vector3(8.5,0,7.5)])
	game._move(unit,Vector3(-3.5,0,-3.5),0.0)
	check("genuinely changed target queues ordinary new request",unit.path_pending and unit.path_request_goal==Vector3(-3.5,0,-3.5))
	game._path_cancel_pending(unit);unit.path_status="LIMIT_REACHED";unit.path_reason="retry_rate_limit"
	game._move(unit,Vector3(.5,0,.5),0.0)
	check("terminal retry limit remains terminal",not unit.path_pending and unit.path_status=="LIMIT_REACHED" and unit.path_reason=="retry_rate_limit")
	unit.path_status="FOUND";unit.path=PackedVector3Array([Vector3(8.5,0,7.5)]);unit.path_version=-1
	game._move(unit,unit.path_request_goal,0.0)
	check("navigation revision still invalidates old route",unit.path_pending)
	var failed=checks.filter(func(c):return not c.passed).size()
	print(JSON.stringify({"suite":"resolved_attack_goal_contract","checks":checks,"failed":failed,"scope":"controlled cached-route identity, not organic battle"}))
	game.queue_free();quit(1 if failed else 0)

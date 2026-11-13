extends SceneTree
## ENGINE_UNRUN. Synthetic actors/topology/visibility/resolver, actual combat,
## request scheduler and bounded pathfinder. Not natural battle or device proof.
const Game=preload("res://scripts/game.gd")
const Rules=preload("res://scripts/rules.gd")
class Fixture:
	extends Game
	var observed=true
	var resolved=Vector3(4.5,0,-3.5)
	var fixture_grid=AStarGrid2D.new()
	var resolver_calls=0
	func _visible_to(_target,_team): return observed
	func _nearest_free(_p,_rings=8,_team=-1,_mover={},_reserved={},_ignore=[]):
		resolver_calls+=1
		return resolved
	func _route_grid(_ent: Dictionary) -> AStarGrid2D: return fixture_grid
	func _known_opposing_flow_costs(_ent,_goal): return {}
	func _note_unit_action(_ent: Dictionary,_action: String,_target: Vector3=Vector3.INF) -> void: pass
var checks=[]
func check(label,ok):
	checks.append({"name":label,"passed":bool(ok)})
	if not ok: push_error(label)
func setup(team=0):
	var game=Fixture.new()
	game.tick_count=100; game.test_mode=true; game.ai_enabled=false
	game.fixture_grid.region=Rect2i(36,36,9,9); game.fixture_grid.update()
	for y in range(36,45): game.fixture_grid.set_point_solid(Vector2i(40,y))
	var attacker={"id":0,"team":team,"category":"unit","kind":"siege","alive":true,
		"pos":Vector3(-3.5,0,-3.5),"anchor":Vector3(-3.5,0,-3.5),"dest":Vector3(4.5,0,-3.5),"radius":0.7,
		"state":"attack","mode":"ATTACK","target":1,"auto_target":false,
		"last_known":Vector3(4.5,0,-3.5),"path":PackedVector3Array(),"path_version":0,
		"cooldown_ticks":20,"stuck":0,"work_ticks":0,"last_repair_tick":-1}
	var target={"id":1,"team":1-team,"category":"unit","kind":"scout","alive":true,
		"pos":Vector3(4.5,0,-3.5),"radius":0.35}
	game.entities=[attacker,target]; game._path_state(attacker)
	return game
func history(ent):
	return {"ticks":ent.path_retry_ticks.duplicate(),"has_attempt":ent.path_has_attempt,
		"searches":ent.path_searches,"initial":ent.path_initial_searches,"retries":ent.path_retry_searches,
		"failures":ent.path_failures,"gate":ent.path_next_attempt_tick}
func failed(team=0):
	var game=setup(team); var ent=game.entities[0]
	game._plan_path(ent,game.entities[1].pos); game._process_path_requests()
	check("synthetic old goal has real static frontier failure",ent.path_status=="NO_PATH" and ent.path_reason=="frontier_exhausted" and ent.path_resolved_goal==game.resolved and not ent.path_pending)
	game.entities[1].pos=Vector3(-1.5,0,-3.5); game.resolved=game.entities[1].pos
	return game
func _initialize():
	for team in 2:
		for automatic in [false,true]:
			var game=failed(team); var ent=game.entities[0]; var budget=history(ent); var epoch=ent.work_epoch
			ent.mode="DEFEND" if automatic else "ATTACK"; ent.auto_target=automatic
			game._update_unit(ent,Rules.TICK)
			check("visible moved target retires only old route",ent.path_status=="IDLE" and ent.work_epoch==epoch+1 and ent.target==1 and ent.mode==("DEFEND" if automatic else "ATTACK") and ent.auto_target==automatic and ent.path_resolved_goal==Vector3.INF and history(ent)==budget)
			game._move_unit_phase(ent,Rules.TICK)
			check("ordinary motion queues new request",ent.path_pending and game.path_requests==[0])
			game.tick_count+=1; game._process_path_requests()
			check("actual bounded search reaches new side",ent.path_status=="FOUND" and ent.path_searches==2 and ent.path_initial_searches==1 and ent.path_retry_searches==1 and ent.path_retry_ticks==[101] and ent.path_resolved_goal==game.resolved)
			game.free()
	for variant in ["same_cell","alias","hidden","dead","revision","epoch","target","pending","traffic","path","limit","reason","missing_goal","stop","leash"]:
		var game=failed(); var ent=game.entities[0]; var target=game.entities[1]
		match variant:
			"same_cell": target.pos=Vector3(4.6,0,-3.5)
			"alias": game.resolved=ent.path_resolved_goal
			"hidden": game.observed=false
			"dead": target.alive=false
			"revision": ent.path_revision-=1
			"epoch": ent.path_request_epoch-=1
			"target": ent.path_request_target=7
			"pending": ent.path_pending=true
			"traffic": ent.traffic_route=true
			"path": ent.path.append(Vector3.ZERO)
			"limit": ent.path_status="LIMIT_REACHED"
			"reason": ent.path_reason="expansion_budget_exhausted"
			"missing_goal": ent.erase("path_resolved_goal")
			"stop": ent.mode="STOP"; ent.auto_target=true
			"leash": ent.mode="DEFEND"; ent.auto_target=true; ent.anchor=Vector3(-9.5,0,-3.5)
		var before=ent.duplicate(true); var queued=game.path_requests.duplicate()
		check("reject leaves actor unchanged "+variant,not game._recover_observed_attack_goal(ent,target) and ent==before and game.path_requests==queued)
		game.free()
	var gated=failed(); var ent=gated.entities[0]
	ent.path_retry_ticks=[90,95,99]; ent.path_next_attempt_tick=105
	var budget=history(ent)
	gated._update_unit(ent,Rules.TICK)
	check("recovery retains saturated future gate",ent.path_status=="IDLE" and history(ent)==budget)
	gated._move_unit_phase(ent,Rules.TICK)
	check("gated queue uses newly observed goal",ent.path_request_goal==gated.entities[1].pos and ent.path_pending)
	gated.tick_count=101; gated._process_path_requests()
	check("gate defers without a search",ent.path_pending and gated.last_path_queries==0 and history(ent)==budget)
	gated.tick_count=105; gated._process_path_requests()
	check("original retry cap remains terminal",ent.path_status=="LIMIT_REACHED" and not ent.path_pending and gated.last_path_queries==0 and history(ent)==budget)
	gated.free()
	var failures=checks.filter(func(row):return not row.passed)
	print("MOVING_ATTACK_RECOVERY "+JSON.stringify({"build":Rules.BUILD_ID,"checks":checks,"failure_count":failures.size(),"scope":"synthetic topology, resolver, observation; actual callbacks; ENGINE_UNRUN at preparation"}))
	quit(0 if failures.is_empty() else 1)

extends SceneTree
## ENGINE_UNRUN. Synthetic actors, threat records, static topology and resolver;
## actual AI submission, command acceptance, order and bounded-search callbacks.
const Game=preload("res://scripts/game.gd")
const Rules=preload("res://scripts/rules.gd")
class Fixture:
	extends Game
	var visible_new=true
	var resolved=Vector3(4.5,0,-3.5)
	var fixture_grid=AStarGrid2D.new()
	var resolver_calls=0
	func _visible_to(target,_team): return visible_new if target.id==2 else false
	func _nearest_free(_p,_rings=8,_team=-1,_mover={},_reserved={},_ignore=[]):
		resolver_calls+=1
		return resolved
	func _route_grid(_ent: Dictionary) -> AStarGrid2D: return fixture_grid
	func _known_opposing_flow_costs(_ent,_goal): return {}
	func _note_unit_action(_ent: Dictionary,_action: String,_point: Vector3=Vector3.INF) -> void: pass
var checks=[]
func check(label,ok):
	checks.append({"name":label,"passed":bool(ok)})
	if not ok: push_error(label)
func setup(team=1):
	var game=Fixture.new(); game.tick_count=100; game.test_mode=true; game.ai_enabled=false
	game.fixture_grid.region=Rect2i(36,36,9,9); game.fixture_grid.update()
	for y in range(36,45): game.fixture_grid.set_point_solid(Vector2i(40,y))
	var ent={"id":0,"team":team,"category":"unit","kind":"siege","alive":true,"owned":true,
		"pos":Vector3(-3.5,0,-3.5),"anchor":Vector3(-3.5,0,-3.5),"dest":Vector3(4.5,0,-3.5),"radius":0.65,
		"state":"attack","mode":"ATTACK","target":1,"auto_target":false,"last_known":Vector3(4.5,0,-3.5),
		"path":PackedVector3Array(),"path_version":0,"cooldown_ticks":20,"stuck":0,"work_ticks":0,"last_repair_tick":-1}
	var old={"id":1,"team":1-team,"category":"unit","kind":"scout","alive":true,"pos":Vector3(4.5,0,-3.5),"radius":0.35}
	var target={"id":2,"team":1-team,"category":"unit","kind":"scout","alive":true,"owned":false,"remembered":false,"pos":Vector3(-1.5,0,-3.5),"radius":0.35}
	game.entities=[ent,old,target]; game._path_state(ent)
	game._plan_path(ent,old.pos); game._process_path_requests()
	check("old attack produces real static NO_PATH",ent.path_status=="NO_PATH" and ent.path_reason=="frontier_exhausted" and ent.path_resolved_goal==game.resolved)
	game.resolved=target.pos
	return game
func history(ent):
	return {"ticks":ent.path_retry_ticks.duplicate(),"has_attempt":ent.path_has_attempt,"searches":ent.path_searches,
		"initial":ent.path_initial_searches,"retries":ent.path_retry_searches,"failures":ent.path_failures,"gate":ent.path_next_attempt_tick}
func order(game):
	var target=game.entities[2]
	game._execute({"type":"order","team":game.entities[0].team,"ids":[0],"target":target.id,"position":target.pos})
func _initialize():
	var game=setup(); var ent=game.entities[0]; var budget=history(ent); var epoch=ent.work_epoch
	var home={"id":3,"team":1,"category":"building","kind":"town_center","owned":true,"pos":Vector3(-3.5,0,-6.5)}
	game._ai_army([ent.duplicate(true),game.entities[2].duplicate(true),home],home)
	check("actual AI policy submits visible new home threat",game.commands.size()==1 and game.commands[0].target==2 and game.ai_status.army=="home_defense")
	var queued=game.commands[0].duplicate(true); game.commands.clear(); game._execute(queued)
	check("accepted AI handoff retires only old failure once",ent.state=="attack" and ent.target==2 and ent.path_status=="IDLE" and ent.work_epoch==epoch+1 and history(ent)==budget)
	var after=ent.duplicate(true); game._execute(queued)
	check("same command ID is still idempotent",ent==after)
	game._move_unit_phase(ent,Rules.TICK); game.tick_count+=1; game._process_path_requests()
	check("new home threat pursuit uses actual bounded search",ent.path_status=="FOUND" and ent.path_searches==2 and ent.path_retry_searches==1 and ent.path_initial_searches==1)
	game.free()
	var close=setup(); ent=close.entities[0]; close.entities[2].pos=Vector3(-2.5,0,-3.5)
	close.resolved=Vector3.INF; var calls=close.resolver_calls; budget=history(ent); order(close)
	check("in-range handoff performs no movement resolution",ent.path_status=="IDLE" and close.resolver_calls==calls and history(ent)==budget)
	close.entities[2].pos=Vector3(-0.5,0,-3.5); close.resolved=close.entities[2].pos
	close._update_unit(ent,Rules.TICK); close._move_unit_phase(ent,Rules.TICK)
	check("later retreat of in-range target can queue ordinary pursuit",ent.path_pending and close.path_requests==[0] and ent.path_request_target==2 and history(ent)==budget)
	close.free()
	for variant in ["alias","limit","epoch","revision","traffic","pending","reason","same_target"]:
		var rejected=setup(); ent=rejected.entities[0]
		match variant:
			"alias": rejected.resolved=ent.path_resolved_goal
			"limit": ent.path_status="LIMIT_REACHED"
			"epoch": ent.path_request_epoch-=1
			"revision": ent.path_revision-=1
			"traffic": ent.traffic_route=true
			"pending": ent.path_pending=true
			"reason": ent.path_reason="retry_rate_limit"
			"same_target": ent.target=2; ent.path_request_target=2
		var status=ent.path_status; budget=history(ent); epoch=ent.work_epoch
		order(rejected)
		check("refusal does not discard otherwise valid order "+variant,ent.state=="attack" and ent.target==2 and ent.path_status==status and ent.work_epoch==epoch+1 and history(ent)==budget)
		rejected.free()
	for invalid in ["hidden","dead"]:
		var rejected=setup(); ent=rejected.entities[0]
		if invalid=="hidden": rejected.visible_new=false
		else: rejected.entities[2].alive=false
		var before=ent.duplicate(true); order(rejected)
		check("invalid new target is atomic "+invalid,ent==before)
		rejected.free()
	var gate=setup(); ent=gate.entities[0]
	ent.path_retry_ticks=[90,95,99]; ent.path_next_attempt_tick=105; budget=history(ent)
	order(gate); gate._move_unit_phase(ent,Rules.TICK); gate.tick_count=101; gate._process_path_requests()
	check("future search gate preserved",ent.path_pending and gate.last_path_queries==0 and history(ent)==budget)
	gate.tick_count=105; gate._process_path_requests()
	check("same saturated retry cap still terminates",ent.path_status=="LIMIT_REACHED" and not ent.path_pending and gate.last_path_queries==0 and history(ent)==budget)
	gate.free()
	var player=setup(0); ent=player.entities[0]; ent.path_retry_ticks=[90,95,99]; ent.path_failures=3; order(player)
	check("player command keeps prior reset semantics",ent.path_status=="IDLE" and ent.target==2 and not ent.path_has_attempt and ent.path_retry_ticks.is_empty() and ent.path_failures==0 and ent.path_next_attempt_tick==player.tick_count)
	player.free()
	var failures=checks.filter(func(row):return not row.passed)
	print("AI_ATTACK_HANDOFF "+JSON.stringify({"build":Rules.BUILD_ID,"checks":checks,"failure_count":failures.size(),"scope":"synthetic setup; actual callbacks; ENGINE_UNRUN at preparation"}))
	quit(0 if failures.is_empty() else 1)

extends SceneTree
# ENGINE_UNRUN. Synthetic indexed actors, grid and destination resolver.
# Actual AI submission, command acceptance, route state and bounded searches.
const Game=preload("res://scripts/game.gd")
const Rules=preload("res://scripts/rules.gd")
class Fixture:
	extends Game
	var resolved=Vector3(4.5,0,-3.5)
	var fixture_grid=AStarGrid2D.new()
	var resolver_calls=0
	var visibility_calls=0
	func _visible_to(_target,_team):
		visibility_calls+=1
		return false
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
	var ent={"id":0,"team":team,"category":"unit","kind":"spearman","alive":true,"owned":true,"remembered":false,
		"pos":Vector3(-3.5,0,-3.5),"anchor":Vector3(-3.5,0,-3.5),"dest":Vector3(4.5,0,-3.5),"radius":0.35,
		"state":"attack","mode":"ATTACK","target":1,"auto_target":false,"last_known":Vector3(4.5,0,-3.5),
		"path":PackedVector3Array(),"path_version":0,"cooldown_ticks":20,"stuck":0,"work_ticks":0,"last_repair_tick":-1}
	var old={"id":1,"team":1-team,"category":"unit","kind":"scout","alive":true,"owned":false,"remembered":true,"pos":Vector3(4.5,0,-3.5),"radius":0.35}
	var home={"id":2,"team":team,"category":"building","kind":"town_center","alive":true,"owned":true,"remembered":false,"pos":Vector3(-3.5,0,3.5)}
	game.entities=[ent,old,home]; game._path_state(ent)
	game._plan_path(ent,old.pos); game._process_path_requests()
	check("actual old attack frontier fails",ent.path_status=="NO_PATH" and ent.path_reason=="frontier_exhausted" and ent.path_resolved_goal==game.resolved)
	game.resolved=Vector3(-3.5,0,1.5)
	game.ai_raid_members=[0]; game.ai_raid_departure_count=5; game.ai_raid_retreating=true
	game.ai_raid_keep={"category":"building","kind":"town_center","pos":Vector3(30,0,0)}
	return game
func history(ent):
	return [ent.cooldown_ticks,ent.path_has_attempt,ent.path_searches,ent.path_initial_searches,ent.path_retry_searches,ent.path_retry_ticks.duplicate(),ent.path_failures,ent.path_next_attempt_tick]
func home_order(game):
	game._execute({"type":"order","team":game.entities[0].team,"ids":[0],"target":-1,"position":game.entities[2].pos})
func _initialize():
	var game=setup(); var ent=game.entities[0]; var before=history(ent); var epoch=ent.work_epoch
	game._ai_army(game.entities.duplicate(true),game.entities[2])
	check("retreat policy submits normal home MOVE",game.commands.size()==1 and game.commands[0].target==-1 and game.commands[0].ids==[0] and game.ai_status.army=="retreat")
	var command=game.commands[0].duplicate(true); game.commands.clear(); var calls=game.resolver_calls
	game._execute(command)
	check("accepted home MOVE retires only old static failure",ent.state=="move" and ent.mode=="MOVE" and ent.path_status=="IDLE" and ent.dest==game.resolved and ent.work_epoch==epoch+1 and history(ent)==before)
	check("destination resolved once without old enemy visibility",game.resolver_calls==calls+1 and game.visibility_calls==0)
	var accepted=ent.duplicate(true); game._execute(command)
	check("duplicate command remains idempotent",ent==accepted)
	game._move_unit_phase(ent,Rules.TICK); game.tick_count+=1; game._process_path_requests()
	check("homeward request reaches ordinary bounded search",ent.path_status=="FOUND" and ent.path_searches==2 and ent.path_retry_searches==1 and ent.path_initial_searches==1 and not ent.path.is_empty())
	game.free()
	for variant in ["alias","invalid","limit","epoch","revision","traffic","pending","reason","old_move","automatic"]:
		var refused=setup(); ent=refused.entities[0]
		match variant:
			"alias": refused.resolved=ent.path_resolved_goal
			"invalid": refused.resolved=Vector3.INF
			"limit": ent.path_status="LIMIT_REACHED"
			"epoch": ent.path_request_epoch-=1
			"revision": ent.path_revision-=1
			"traffic": ent.traffic_route=true
			"pending": ent.path_pending=true
			"reason": ent.path_reason="retry_rate_limit"
			"old_move": ent.state="move"; ent.mode="MOVE"; ent.target=-1; ent.path_request_state="move"; ent.path_request_target=-1
			"automatic": ent.auto_target=true; ent.mode="DEFEND"
		var status=ent.path_status; before=history(ent); home_order(refused)
		check("terminal history retained "+variant,ent.path_status==status and history(ent)==before)
		refused.free()
	for old_alive in [true,false]:
		var hidden=setup(); hidden.entities[1].alive=old_alive; hidden.entities[1].pos=Vector3(100,0,100)
		home_order(hidden)
		check("unobserved old target cannot affect recall "+str(old_alive),hidden.entities[0].path_status=="IDLE" and hidden.visibility_calls==0)
		hidden.free()
	var gate=setup(); ent=gate.entities[0]; ent.path_retry_ticks=[90,95,99]; ent.path_next_attempt_tick=105; before=history(ent)
	home_order(gate); gate._move_unit_phase(ent,Rules.TICK); gate.tick_count=101; gate._process_path_requests()
	check("future gate retained",ent.path_pending and gate.last_path_queries==0 and history(ent)==before)
	gate.tick_count=105; gate._process_path_requests()
	check("saturated retry cap still stops recall",ent.path_status=="LIMIT_REACHED" and not ent.path_pending and gate.last_path_queries==0 and history(ent)==before)
	gate.free()
	var player=setup(0); ent=player.entities[0]; ent.path_retry_ticks=[90,95,99]; ent.path_failures=3; home_order(player)
	check("player reset semantics unchanged",ent.path_status=="IDLE" and not ent.path_has_attempt and ent.path_retry_ticks.is_empty() and ent.path_failures==0)
	player.free()
	var failed=checks.filter(func(row):return not row.passed).size()
	print(JSON.stringify({"suite":"ai_retreat_route_contract","build":Rules.BUILD_ID,"checks":checks,"failed":failed,"scope":"Synthetic actors/resolver/grid; actual callbacks, ENGINE_UNRUN"}))
	quit(1 if failed else 0)

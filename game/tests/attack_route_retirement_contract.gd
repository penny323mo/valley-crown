extends SceneTree
## ENGINE_UNRUN. Synthetic actors/visibility/pending traffic and retry history.
## Actual unit update, ledger, scheduler and pursuit callbacks, not natural
## combat, reached-by-movement proof, rendering or device acceptance.
const Game=preload("res://scripts/game.gd")
const Rules=preload("res://scripts/rules.gd")
var checks=[]
func check(label,ok):
	checks.append({"name":label,"passed":bool(ok)})
	if not ok: push_error(label)
func setup(team,traffic=true,pending=true,waypoint=true):
	var game=Game.new(); game.tick_count=100; game.test_mode=true; game.ai_enabled=false
	for faction in 2:
		game.visible_cells[faction].resize(Rules.MAP_SIZE*Rules.MAP_SIZE)
		game.visible_cells[faction].fill(1)
	var attacker={"id":0,"team":team,"category":"unit","kind":"spearman","alive":true,
		"pos":Vector3(0.5,0,0.5),"anchor":Vector3(0.5,0,0.5),"dest":Vector3(4.5,0,0.5),
		"radius":0.35,"state":"attack","mode":"ATTACK","target":1,"auto_target":false,
		"last_known":Vector3(4.5,0,0.5),"path":PackedVector3Array(),"path_version":0,
		"cooldown_ticks":0,"stuck":0,"work_ticks":0,"last_repair_tick":-1}
	var enemy={"id":1,"team":1-team,"category":"unit","kind":"spearman","alive":true,
		"pos":Vector3(1.5,0,0.5),"radius":0.35,"hp":60,"max_hp":60}
	game.entities=[attacker,enemy]; game._path_state(attacker)
	attacker.path_status="QUEUED" if pending else "FOUND"; attacker.path_reason="waiting_for_search" if pending else ""
	attacker.path_pending=pending; attacker.traffic_route=traffic
	attacker.path=PackedVector3Array([Vector3(2.5,0,0.5)]) if waypoint else PackedVector3Array()
	attacker.path_has_attempt=true; attacker.path_retry_ticks=[90,95,99]
	attacker.path_searches=7; attacker.path_initial_searches=1; attacker.path_retry_searches=6; attacker.path_failures=2
	attacker.path_next_attempt_tick=101; attacker.work_epoch=5; attacker.path_request_epoch=5
	attacker.path_request_state="attack"; attacker.path_request_target=1; attacker.path_request_goal=attacker.dest
	game.path_requests=[0] if pending else []
	return game
func budget(ent):
	return {"retry_ticks":ent.path_retry_ticks.duplicate(),"searches":ent.path_searches,"initial":ent.path_initial_searches,
		"retries":ent.path_retry_searches,"failures":ent.path_failures,"has_attempt":ent.path_has_attempt,"next_gate":ent.path_next_attempt_tick}
func _initialize():
	for team in 2:
		for traffic in [false,true]:
			var game=setup(team,traffic); var attacker=game.entities[0]; var before=budget(attacker)
			game._update_unit(attacker,Rules.TICK)
			check("in-range removes stale normal/traffic request "+str(team)+"/"+str(traffic),not attacker.path_pending and game.path_requests.is_empty() and not attacker.traffic_route and attacker.path.is_empty() and attacker.work_epoch==6)
			check("attack identity and budgets remain",attacker.state=="attack" and attacker.mode=="ATTACK" and attacker.target==1 and not attacker.auto_target and budget(attacker)==before)
			var hit=game.attack_ledger.event(1)
			check("ordinary release remains exact",not hit.is_empty() and hit.attacker_id==0 and hit.target_id==1 and hit.damage==5 and attacker.cooldown_ticks==Rules.ATTACK_TICKS.spearman)
			game.tick_count=101; game._process_path_requests()
			check("obsolete request spends no next-tick search and cannot stop attack",game.last_path_queries==0 and attacker.state=="attack" and attacker.target==1 and not attacker.path_pending and budget(attacker)==before)
			var epoch=attacker.work_epoch
			game._update_unit(attacker,Rules.TICK)
			check("steady in-range tick has no cancellation churn or duplicate attack",attacker.work_epoch==epoch and game.attack_ledger.next_attack_id()==2 and budget(attacker)==before)
			# Visible target departs. Ordinary next pursuit can queue; unchanged
			# saturated retry gate still owns whether any search may execute.
			game.entities[1].pos=Vector3(3.5,0,0.5); game._update_unit(attacker,Rules.TICK)
			game._move_unit_phase(attacker,Rules.TICK)
			check("departed target uses ordinary queued pursuit",attacker.path_pending and game.path_requests==[0] and attacker.state=="attack" and attacker.target==1 and budget(attacker)==before)
			game.free()
		for shape in [[false,false,false],[false,false,true],[true,false,false]]:
			var game=setup(team,shape[0],shape[1],shape[2]); var attacker=game.entities[0]; var before=budget(attacker)
			var expected_epoch=5 if not shape[0] and not shape[2] else 6
			game._update_unit(attacker,Rules.TICK)
			check("only actual stale movement is retired "+str(shape),attacker.work_epoch==expected_epoch and not attacker.path_pending and attacker.path.is_empty() and not attacker.traffic_route and budget(attacker)==before)
			game.free()
		var outside=setup(team); var attacker=outside.entities[0]; outside.entities[1].pos=Vector3(3.5,0,0.5)
		outside._update_unit(attacker,Rules.TICK)
		check("out-of-range pursuit not canceled",attacker.work_epoch==5 and attacker.path_pending and outside.path_requests==[0] and outside.attack_ledger.next_attack_id()==1)
		outside.free()
		var hidden=setup(team); attacker=hidden.entities[0]
		hidden.visible_cells[team][hidden._cell_index(hidden.entities[1].pos)]=0
		var original=attacker.duplicate(true); hidden._update_unit(attacker,Rules.TICK)
		check("hidden nearby target cannot retire movement or release attack",attacker==original and hidden.path_requests==[0] and hidden.attack_ledger.next_attack_id()==1)
		hidden.entities[1].alive=false; hidden.entities[1].death_observed_by=[false,false]
		hidden._update_unit(attacker,Rules.TICK)
		check("unseen death unchanged",attacker==original and hidden.path_requests==[0] and hidden.attack_ledger.next_attack_id()==1)
		hidden.free()
	var failures=checks.filter(func(row):return not row.passed)
	print("ATTACK_ROUTE_RETIREMENT "+JSON.stringify({"build":Rules.BUILD_ID,"scope":"synthetic actors; actual callbacks; ENGINE_UNRUN at preparation","checks":checks,"failure_count":failures.size()}))
	quit(0 if failures.is_empty() else 1)

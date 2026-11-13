extends SceneTree
## ENGINE_UNRUN. Synthetic actors, visibility, completed failure and retries;
## actual finish/order/planning callbacks. Not natural A*, combat or device proof.
const Game=preload("res://scripts/game.gd")
const Rules=preload("res://scripts/rules.gd")
var checks=[]
func check(label,ok):
	checks.append({"name":label,"passed":bool(ok)})
	if not ok: push_error(label)
func actor(id,team,position):
	return {"id":id,"team":team,"category":"unit","kind":"spearman","alive":true,
		"pos":position,"anchor":position,"dest":position,"radius":0.35,
		"state":"attack","mode":"DEFEND","target":1,"auto_target":true,
		"last_known":position+Vector3(2,0,0),"path":PackedVector3Array(),
		"path_version":0,"cooldown_ticks":20,"stuck":0,"work_ticks":0,"last_repair_tick":-1}
func setup(team,status,retries,next_gate=100):
	var game=Game.new()
	game.tick_count=100; game.test_mode=true; game.ai_enabled=false
	for faction in 2:
		game.visible_cells[faction].resize(Rules.MAP_SIZE*Rules.MAP_SIZE)
		game.visible_cells[faction].fill(1)
	var defender=actor(0,team,Vector3(0.5,0,0.5))
	var old_enemy=actor(1,1-team,Vector3(4.5,0,0.5))
	var new_enemy=actor(2,1-team,Vector3(2.5,0,0.5))
	old_enemy.mode="STOP"; old_enemy.state="idle"; old_enemy.target=-1
	new_enemy.mode="STOP"; new_enemy.state="idle"; new_enemy.target=-1
	game.entities=[defender,old_enemy,new_enemy]
	game._path_state(defender)
	defender.path_status=status; defender.path_reason="frontier_exhausted" if status=="NO_PATH" else "retry_rate_limit"
	defender.path_has_attempt=true; defender.path_retry_ticks=retries.duplicate()
	defender.path_searches=7; defender.path_initial_searches=1; defender.path_retry_searches=6
	defender.path_failures=4; defender.path_next_attempt_tick=next_gate
	defender.work_epoch=5; defender.path_request_epoch=5
	defender.path_request_state="attack"; defender.path_request_target=1
	return game
func history(ent):
	return {"retry_ticks":ent.path_retry_ticks.duplicate(),"searches":ent.path_searches,
		"initial":ent.path_initial_searches,"retries":ent.path_retry_searches,
		"failures":ent.path_failures,"has_attempt":ent.path_has_attempt}
func _initialize():
	for team in 2:
		for status in ["NO_PATH","LIMIT_REACHED"]:
			var game=setup(team,status,[90],103)
			var defender=game.entities[0]; var budget=history(defender)
			# Old observed target now outside leash, static navigation unchanged.
			game._update_unit(defender,Rules.TICK)
			check("near anchor retires completed "+str(team)+"/"+status,defender.state=="idle" and defender.mode=="DEFEND" and defender.target==-1 and not defender.auto_target and defender.path_status=="IDLE" and defender.work_epoch==6)
			check("finish preserves prior search budget",history(defender)==budget and defender.path_next_attempt_tick==103)
			var next=game._stance_target(defender)
			check("new observed reachable-side enemy selected",not next.is_empty() and next.id==2)
			game._update_unit(defender,Rules.TICK)
			check("ordinary acquisition preserves DEFEND",defender.state=="attack" and defender.target==2 and defender.auto_target and defender.mode=="DEFEND")
			game._move_unit_phase(defender,Rules.TICK)
			check("new goal queues without budget reset",defender.path_pending and game.path_requests==[0] and history(defender)==budget and defender.path_next_attempt_tick==103)
			game._process_path_requests()
			check("future gate blocks immediate search",game.last_path_queries==0 and game.path_requests==[0] and history(defender)==budget)
			game.free()
		var saturated=setup(team,"LIMIT_REACHED",[90,95,99],101)
		var defender=saturated.entities[0]; var budget=history(defender)
		saturated._update_unit(defender,Rules.TICK)
		check("saturated retry window retained",defender.path_next_attempt_tick==110 and history(defender)==budget)
		saturated._update_unit(defender,Rules.TICK); saturated._move_unit_phase(defender,Rules.TICK)
		saturated._process_path_requests()
		check("no saturated-budget search",saturated.last_path_queries==0 and defender.path_pending and history(defender)==budget)
		saturated.free()
		var hidden=setup(team,"NO_PATH",[],100)
		defender=hidden.entities[0]
		hidden._update_unit(defender,Rules.TICK)
		hidden.visible_cells[team][hidden._cell_index(hidden.entities[2].pos)]=0
		hidden._update_unit(defender,Rules.TICK)
		check("hidden replacement cannot be acquired",defender.state=="idle" and defender.mode=="DEFEND" and not defender.path_pending and hidden.path_requests.is_empty())
		hidden.free()
		var returning=setup(team,"NO_PATH",[90,95,99],120)
		defender=returning.entities[0]; defender.pos+=Vector3(0,0,1); budget=history(defender)
		returning._finish_attack(defender)
		check("far return retains stricter gate",defender.state=="return" and defender.dest==defender.anchor and defender.path_next_attempt_tick==120 and history(defender)==budget)
		returning.free()
		var pending=setup(team,"NO_PATH",[90],100)
		defender=pending.entities[0]; defender.path_pending=true; pending.path_requests=[0]
		defender.path=PackedVector3Array([Vector3(1.5,0,0.5)])
		pending._finish_attack(defender)
		check("old queued route retired",not defender.path_pending and pending.path_requests.is_empty() and defender.path.is_empty() and defender.path_version==-1 and defender.work_epoch==6)
		pending.free()
		# Unseen death must behave like an unseen living enemy, not retire.
		var unseen=setup(team,"NO_PATH",[90],100)
		defender=unseen.entities[0]
		unseen.visible_cells[team][unseen._cell_index(unseen.entities[1].pos)]=0
		var before=defender.duplicate(true); before.cooldown_ticks-=1
		unseen._update_unit(defender,Rules.TICK)
		check("unseen living target retains pursuit",defender==before)
		unseen.entities[1].alive=false; unseen.entities[1].death_observed_by=[false,false]
		before=defender.duplicate(true); before.cooldown_ticks-=1
		unseen._update_unit(defender,Rules.TICK)
		check("unseen death does not finish pursuit",defender==before)
		unseen.free()
	for automatic in [false,true]:
		var stopped=setup(0,"NO_PATH",[90],105)
		var defender=stopped.entities[0]; defender.auto_target=automatic; defender.mode="STOP" if automatic else "ATTACK"
		var budget=history(defender)
		stopped._finish_attack(defender)
		check("explicit/STOP finish unchanged",defender.mode=="STOP" and defender.state=="idle" and defender.path_status=="NO_PATH" and history(defender)==budget and defender.path_next_attempt_tick==105)
		stopped.free()
	var failures=checks.filter(func(row):return not row.passed)
	print("DEFEND_RETARGET_CONTRACT "+JSON.stringify({"build":Rules.BUILD_ID,"scope":"synthetic state; actual callbacks; ENGINE_UNRUN at preparation","checks":checks,"failure_count":failures.size()}))
	quit(0 if failures.is_empty() else 1)

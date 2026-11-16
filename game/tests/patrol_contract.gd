extends SceneTree
# ENGINE_UNRUN. Controlled paid-free fixture entities, ordinary commands/ticks.
# Not a natural match, touch dispatch, scene rendering or safety admission.
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
	game._test_reset(); game.set_process(false)
	await process_frame
	var scout=game._first(0,"scout"); var worker=game._first(0,"villager")
	var foe=game._first(1,"villager")
	var origin=scout.pos; var goal=origin+Vector3(6,0,0)
	var worker_state=worker.state; var worker_dest=worker.dest
	game._submit("patrol",{"ids":[worker.id,scout.id,scout.id],"position":goal})
	game._tick(Rules.TICK)
	check("ordinary mixed command starts military patrol only",scout.mode=="PATROL" and worker.state==worker_state and worker.dest==worker_dest)
	var points=scout.get("patrol_points",[]).duplicate()
	var previous=scout.get("patrol_index",-1); var turns=0
	for i in 900:
		if scout.mode!="PATROL" or game.game_over: break
		game._tick(Rules.TICK)
		if scout.get("patrol_index",-1)!=previous:
			turns+=1; previous=scout.get("patrol_index",-1)
		if turns>=3: break
	check("ordinary bounded paths complete three patrol legs",turns>=3 and scout.mode=="PATROL")
	check("fixed original endpoints survive repeated travel",scout.get("patrol_points",[])==points)
	check("automatic legs do not grant new initial searches",scout.path_initial_searches==1 and scout.path_retry_searches>=2)
	# Introduce an explicitly controlled one-HP foe, not earned combat progression.
	foe.pos=scout.pos+Vector3(1,0,0); foe.hp=1; game._set_stance(foe,"STOP")
	scout.cooldown_ticks=0
	game._update_vision(false); game._publish_faction_views()
	var held=scout.pos; var prior_leg=scout.get("patrol_index",-1)
	game._tick(Rules.TICK)
	check("in-range real attack settles without patrol movement",not foe.alive and scout.pos==held and scout.mode=="PATROL" and scout.advance_engaged)
	check("encounter does not replace endpoint or leg",scout.get("patrol_points",[])==points and scout.get("patrol_index",-1)==prior_leg)
	for i in 200:
		game._tick(Rules.TICK)
		if scout.pos.distance_to(held)>0.5: break
	check("patrol resumes after actual target death",scout.mode=="PATROL" and scout.pos.distance_to(held)>0.5)
	game._select([scout.id]); game._start_patrol_command()
	check("explicit military action enters patrol targeting",game.touch_command and game.unit_command_kind=="patrol")
	game._cancel_mode()
	check("cancel targeting does not cancel the applied patrol",not game.touch_command and game.unit_command_kind=="order" and scout.mode=="PATROL")
	game._submit("stop",{"ids":[scout.id]}); game._tick(Rules.TICK)
	check("Stop retires applied patrol route",scout.mode=="STOP" and not scout.has("patrol_points") and not scout.has("patrol_index"))
	check("economy conserved after controlled movement and combat",game.economy.audit().ok)
	var failed=checks.filter(func(item): return not item.passed).size()
	print(JSON.stringify({"suite":"patrol_contract","build":Rules.BUILD_ID,"checks":checks,"failed":failed,"scope":"Controlled ordinary command/movement/damage, not natural progression or routed touch"}))
	game.queue_free(); quit(1 if failed else 0)

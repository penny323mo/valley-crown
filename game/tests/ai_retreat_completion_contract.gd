extends SceneTree
# ENGINE_UNRUN. Synthetic owned/threat records and positions; actual AI
# submission, STOP command acceptance, stance/cancellation and movement-phase
# dispatch. _move only records intent, not a real route or motion simulation.
const Rules=preload("res://scripts/rules.gd")
class Fixture:
	extends "res://scripts/game.gd"
	var motion_intents=[]
	func _visible_to(_target,_team): return true
	func _move(ent,destination,_dt):
		motion_intents.append({"id":ent.id,"destination":destination}); return false
var checks=[]
func check(label,ok):
	checks.append({"name":label,"passed":bool(ok)})
	if not ok: push_error(label)
func setup(state="attack",mode="ATTACK",dest=Vector3(12,0,0),pos=Vector3(4.5,0,0)):
	var game=Fixture.new(); game.tick_count=100; game.test_mode=true; game.ai_enabled=false
	var actor={"id":0,"kind":"spearman","category":"unit","team":1,"owned":true,"alive":true,"remembered":false,
		"pos":pos,"anchor":pos,"dest":dest,"radius":0.35,"state":state,"mode":mode,"target":1,
		"auto_target":mode in ["STOP","DEFEND"],"last_known":Vector3(9.5,0,0),
		"path":PackedVector3Array([Vector3(5.5,0,0)]),"path_version":0,"cooldown_ticks":17}
	var enemy={"id":1,"kind":"scout","category":"unit","team":0,"owned":false,"alive":true,"remembered":false,"pos":Vector3(9.5,0,0),"radius":0.35}
	var home={"id":2,"kind":"town_center","category":"building","team":1,"owned":true,"alive":true,"remembered":false,"pos":Vector3.ZERO}
	game.entities=[actor,enemy,home]; game._path_state(actor)
	actor.path_has_attempt=true; actor.path_searches=4; actor.path_retry_searches=3; actor.path_retry_ticks=[90,95,99]
	actor.path_next_attempt_tick=105; actor.path_failures=2
	game.ai_raid_members=[0]; game.ai_raid_departure_count=5; game.ai_raid_keep={"category":"building","kind":"town_center","pos":Vector3(30,0,0)}
	game.ai_raid_retreating=true
	return game
func history(actor):
	return [actor.cooldown_ticks,actor.path_has_attempt,actor.path_searches,actor.path_retry_searches,actor.path_retry_ticks.duplicate(),actor.path_next_attempt_tick,actor.path_failures]
func policy(game):
	# Value-only synthetic own record intentionally omits auto_target. The
	# product must use projected mode/dest, not add private world lookups.
	var actor=game.entities[0].duplicate(true); actor.erase("auto_target")
	game._ai_army([actor,game.entities[1].duplicate(true),game.entities[2].duplicate(true)],game.entities[2])
func _initialize():
	for state in ["attack","move"]:
		var game=setup(state,"ATTACK" if state=="attack" else "MOVE")
		var actor=game.entities[0]; var before=history(actor); var epoch=actor.work_epoch
		game._move_unit_phase(actor,Rules.TICK)
		check("old outbound intent reaches movement dispatcher "+state,game.motion_intents.size()==1)
		game.motion_intents.clear(); policy(game)
		check("completed retreat submits ordinary AI Stop "+state,game.commands.size()==1 and game.commands[0].type=="stop" and game.commands[0].team==1 and game.commands[0].ids==[0])
		check("policy does not mutate authoritative actor "+state,actor.state==state and actor.path.size()==1 and history(actor)==before and actor.work_epoch==epoch)
		check("all-home membership retires "+state,game.ai_raid_members.is_empty() and not game.ai_raid_retreating)
		var command=game.commands[0].duplicate(true); game.commands.clear(); game._execute(command)
		check("accepted Stop retires outbound task "+state,actor.state=="idle" and actor.mode=="STOP" and actor.target==-1 and actor.path.is_empty() and actor.work_epoch==epoch+1)
		check("Stop preserves cooldown and retry budgets "+state,history(actor)==before)
		game._move_unit_phase(actor,Rules.TICK)
		check("next movement cannot resume old pursuit "+state,game.motion_intents.is_empty())
		var after=actor.duplicate(true); game._execute(command)
		check("same Stop command remains idempotent "+state,actor==after)
		game.free()
	for pair in [["attack","STOP"],["attack","DEFEND"],["idle","STOP"],["return","DEFEND"]]:
		var game=setup(pair[0],pair[1]); policy(game)
		check("bounded automatic or idle behavior preserved "+str(pair),game.commands.is_empty())
		game.free()
	var homebound=setup("move","MOVE",Vector3(2.5,0,0)); policy(homebound)
	check("existing home-bound movement preserved",homebound.commands.is_empty()); homebound.free()
	var far=setup("attack","ATTACK",Vector3(12,0,0),Vector3(7,0,0)); policy(far)
	check("distant survivor retains ordinary return move",far.commands.size()==1 and far.commands[0].type=="order" and far.commands[0].target==-1 and far.commands[0].position==Vector3.ZERO and far.ai_raid_members==[0] and far.ai_raid_retreating)
	far.free()
	var danger=setup(); danger.entities[1].pos=Vector3(7,0,0); policy(danger)
	check("active home threat still takes priority",danger.ai_status.army=="home_defense" and danger.ai_raid_members==[0] and danger.commands.is_empty())
	danger.free()
	var failed=checks.filter(func(item): return not item.passed).size()
	print(JSON.stringify({"suite":"ai_retreat_completion_contract","build":Rules.BUILD_ID,"checks":checks,"failed":failed,"scope":"Synthetic records; actual command/stance/movement dispatch, not natural battle or motion","source_sha256":FileAccess.get_sha256("res://scripts/game.gd")}))
	quit(1 if failed else 0)

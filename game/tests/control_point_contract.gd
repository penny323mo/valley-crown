extends SceneTree
const Point=preload("res://scripts/control_point.gd")
const Rules=preload("res://scripts/rules.gd")
var checks=[]
var game
func check(label,ok):
	checks.append({"name":label,"passed":bool(ok)})
	if not ok:push_error(label)
func _initialize():call_deferred("run")
func unit(id,team,kind="spearman",pos=Vector3.ZERO):
	return {"id":id,"team":team,"kind":kind,"pos":pos,"category":"unit","alive":true}
func run():
	var point=Point.new()
	var a=unit(1,0);var b=unit(2,0);var c=unit(3,1)
	check("one soldier cannot score",not point.advance([a],1) and point.owner==-1)
	check("villagers cannot capture",not point.advance([a,unit(4,0,"villager")],2))
	check("two troops gain one tick",point.advance([a,b],3) and point.scores==[1,0] and point.owner==0)
	check("same tick cannot score twice",not point.advance([a,b],3) and point.scores==[1,0])
	check("one defender contests larger army",not point.advance([a,b,c],4) and point.contested and point.owner==-1)
	check("contested score is frozen",point.scores==[1,0])
	check("absence does not erase earned score",not point.advance([],5) and point.scores==[1,0])
	check("duplicate record cannot supply two troops",not point.advance([a,a],6))
	var dead=b.duplicate();dead.alive=false
	check("dead troops excluded",not point.advance([a,dead],7))
	check("outside circle excluded",not point.advance([a,unit(6,0,"archer",Vector3(5.01,0,0))],8))
	check("boundary is inside",point.advance([a,unit(6,0,"archer",Vector3(5,0,0))],9))
	point.reset()
	for i in 3599:point.advance([a,b],i+1)
	check("no early victory",point.winner()==-1 and point.scores[0]==3599)
	point.advance([a,b],3600)
	check("exact 180 second objective victory",point.winner()==0)
	point.advance([a,b],3601);check("score caps at target",point.scores[0]==3600)
	point.reset();check("reset clears all scores",point.scores==[0,0] and point.owner==-1 and point.winner()==-1)
	game=load("res://main.tscn").instantiate();root.add_child(game);game.set_process(false);game.test_mode=true;game.ai_enabled=false
	game._test_reset();game.set_process(false)
	await process_frame
	check("legacy default preserved",game.victory_mode=="conquest" and not game.control_point_marker.visible)
	game._spawn("spearman",0,Vector3(1,0,0));game._spawn("archer",0,Vector3(-1,0,0))
	game._update_vision(false);game._tick(Rules.TICK)
	check("legacy mode never scores",game.control_point.scores==[0,0])
	game.victory_mode="control";game._tick(Rules.TICK);game._update_hud()
	check("real simulation admits objective tick",game.control_point.scores==[1,0])
	check("objective score HUD and marker",game.control_point_marker.visible and "180" in game.objective_button.text)
	check("objective construction exclusion",not game._placement_reason("house",Vector3.ZERO,0,game._first(0,"villager").id).is_empty())
	# Tick-to-terminal integration uses actual goal component calls, not a score write.
	for i in 3599:
		game.tick_count+=1;game.control_point.advance(game.entities,game.tick_count)
	game._check_end()
	check("objective yields official victory and report",game.game_over and game.outcome=="victory" and game.end_reason=="control_point" and game.last_match_report.control_ticks[0]==3600)
	check("result screen explains objective", "180" in game.end_body.text)
	check("war report identifies mode and score", "中央據點爭奪" in game.end_report_label.text and "180" in game.end_report_label.text)
	game._test_reset();game.set_process(false)
	check("new match clears objective progress",game.control_point.scores==[0,0])
	# AI must act without learning an unseen keep or enemy target.
	game.victory_mode="control"
	var s1=game._spawn("spearman",1,Vector3(10,0,10));var s2=game._spawn("archer",1,Vector3(12,0,10))
	game._update_vision(false);game._publish_faction_views()
	var records=game.faction_views[1].records().values();var army=[]
	for record in records:
		if record.get("owned",false) and record.kind in ["spearman","archer"]:army.append(record)
	game.commands.clear();var before=game.economy.bank_milli(1).duplicate()
	game._ai_control_point_orders(army,records)
	check("AI sends ordinary ground advance orders",game.commands.size()==2 and game.commands[0].type=="advance" and not game.commands[0].has("target"))
	check("AI objective orders have no economic privilege",game.economy.bank_milli(1)==before)
	var batch=game.commands.duplicate();game.commands.clear()
	for command in batch:game._execute(command)
	check("ordinary execution assigns bounded advance",s1.state=="move" and s1.mode=="ADVANCE" and s2.state=="move")
	game._publish_faction_views();records=game.faction_views[1].records().values();army=[game.faction_views[1].get_record(s1.id),game.faction_views[1].get_record(s2.id)]
	game._ai_control_point_orders(army,records)
	check("unchanged objective move is not reissued",game.commands.is_empty())
	for i in 360: game._tick(Rules.TICK)
	check("AI troops physically reach capture circle",s1.pos.distance_to(Vector3.ZERO)<=5.0 and s2.pos.distance_to(Vector3.ZERO)<=5.0)
	check("real marched troops earn objective ticks",game.control_point.scores[1]>0)
	# Controlled observed-policy records: never a hidden authority lookup.
	var own={"id":s1.id,"team":1,"owned":true,"alive":true,"category":"unit","kind":"spearman","pos":Vector3.ZERO,"state":"attack","target":777,"path_status":"FOUND"}
	game.ai_control_targets={s1.id:777};game.commands.clear()
	game._ai_control_point_orders([own],[])
	check("departed objective target is retired even by sole survivor",game.commands.size()==1 and game.commands[0].type=="stop" and game.commands[0].ids==[s1.id])
	check("retired target ownership cleared",game.ai_control_targets.is_empty())
	own.path_status="NO_PATH";game.ai_control_targets={s1.id:777};game.commands.clear()
	game._ai_control_point_orders([own],[])
	check("terminal route still retires stale attack",game.commands.size()==1 and game.commands[0].type=="stop")
	s1.path_failures=3;s1.path_retry_ticks=[game.tick_count];s1.path_next_attempt_tick=game.tick_count+20
	game._execute(game.commands[0]);game.commands.clear()
	check("retirement preserves retry budget",s1.path_failures==3 and s1.path_retry_ticks==[game.tick_count] and s1.path_next_attempt_tick==game.tick_count+20)
	check("economy conserves",game.economy.audit().ok)
	var failed=checks.filter(func(c):return not c.passed).size()
	print(JSON.stringify({"suite":"control_point_contract","checks":checks,"failed":failed,"scope":"synthetic placements, real objective countdown and official end/command integration; not natural match or rendering acceptance"}))
	game.queue_free();quit(1 if failed else 0)

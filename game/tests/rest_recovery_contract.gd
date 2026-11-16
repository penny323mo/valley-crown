extends SceneTree
const Rest=preload("res://scripts/rest_recovery.gd")
const Rules=preload("res://scripts/rules.gd")
var checks=[]
var game
func check(label,ok):
	checks.append({"name":label,"passed":bool(ok)})
	if not ok:push_error(label)
func _initialize():call_deferred("run")
func step(n):
	for i in n:
		game.tick_count+=1;game._update_rest_recovery()
func run():
	game=load("res://main.tscn").instantiate();root.add_child(game);game.set_process(false);game.test_mode=true;game.ai_enabled=false
	game._test_reset();game.set_process(false)
	await process_frame
	var keep=game._first(0,"town_center")
	var soldier=game._spawn("spearman",0,keep.pos+Vector3(5,0,0));soldier.hp=30
	var bank=game.economy.bank_milli(0).duplicate();var commands=game.commands.duplicate(true)
	step(199);check("no healing before ten seconds",soldier.hp==30 and soldier.rest_ticks==199)
	step(1);check("safe wait completes without instant healing",soldier.hp==30 and soldier.rest_ticks==200)
	step(39);check("no healing before first two second interval",soldier.hp==30)
	step(1);check("first heal at twelve seconds",soldier.hp==31)
	game._update_rest_recovery();check("duplicate tick cannot heal twice",soldier.hp==31 and soldier.rest_ticks==240)
	step(40);check("continued rest heals one per two seconds",soldier.hp==32)
	check("resources and commands unchanged",bank==game.economy.bank_milli(0) and commands==game.commands)
	soldier.hp=soldier.max_hp-1;step(40);step(80);check("max health clamped and full rest cleared",soldier.hp==soldier.max_hp and soldier.rest_ticks==0)
	soldier.hp=30;game.paused=true;step(240);check("pause cannot heal",soldier.hp==30 and soldier.rest_ticks==0)
	game.paused=false;step(1);check("time gap does not bank rest",soldier.rest_ticks==1)
	soldier.state="move";step(1);check("movement cancels rest",soldier.rest_ticks==0)
	soldier.state="idle";soldier.path_pending=true;step(1);check("pending route blocks rest",soldier.rest_ticks==0)
	soldier.path_pending=false;soldier.path=PackedVector3Array([soldier.pos+Vector3.RIGHT]);step(1);check("queued path blocks rest",soldier.rest_ticks==0)
	soldier.path=PackedVector3Array();step(100);soldier.last_damage_tick=game.tick_count+1;step(1);check("new damage resets safe time",soldier.rest_ticks==0)
	step(100);keep.last_damage_tick=game.tick_count+1;step(1);check("keep damage resets safe time",soldier.rest_ticks==0)
	step(100);soldier.last_attack_tick=game.tick_count+1;step(1);check("successful attack resets safe time",soldier.rest_ticks==0)
	step(240);check("post combat full delay then heal",soldier.hp==31)
	soldier.pos=keep.pos+Vector3(7.01,0,0);step(1);check("outside keep radius resets",soldier.rest_ticks==0)
	soldier.pos=keep.pos+Vector3(7,0,0);step(1);check("radius boundary admitted",soldier.rest_ticks==1)
	keep.built=false;step(1);check("unfinished keep cannot heal",soldier.rest_ticks==0);keep.built=true
	keep.alive=false;step(1);check("destroyed keep cannot heal",soldier.rest_ticks==0);keep.alive=true
	var enemy=game._spawn("archer",1,keep.pos+Vector3(6,0,0));game._update_vision(false)
	step(1);check("visible enemy blocks rest",soldier.rest_ticks==0)
	enemy.alive=false;step(1);check("dead threat ignored",soldier.rest_ticks==1)
	var remembered={"alive":true,"remembered":true,"team":1,"category":"unit","pos":soldier.pos}
	check("remembered threats ignored",Rest.blocked(soldier,keep,[remembered],game.tick_count).is_empty())
	remembered.remembered=false;remembered.category="building";remembered.kind="tower";remembered.built=true
	check("visible completed enemy towers block",Rest.blocked(soldier,keep,[remembered],game.tick_count)=="threat")
	remembered.kind="house"
	check("noncombat buildings do not block",Rest.blocked(soldier,keep,[remembered],game.tick_count).is_empty())
	remembered.kind="tower";remembered.built=false
	check("unfinished towers do not block",Rest.blocked(soldier,keep,[remembered],game.tick_count).is_empty())
	check("enemy recovery labels not disclosed",Rest.label({"kind":"spearman","hp":10,"max_hp":60,"owned":false,"rest_ticks":240}).is_empty())
	var worker=game._first(0,"villager");worker.hp=10
	check("villagers cannot recover",Rest.blocked(worker,keep,[],game.tick_count)=="ineligible")
	var siege=game._spawn("siege",0,keep.pos+Vector3(-5,0,0));siege.hp=10
	check("siege cannot recover",Rest.blocked(siege,keep,[],game.tick_count)=="ineligible")
	soldier.alive=false;step(240);check("dead soldiers never revived",not soldier.alive and soldier.hp==31);soldier.alive=true
	var other_keep=game._first(1,"town_center");var other=game._spawn("cavalry",1,other_keep.pos+Vector3(-5,0,0));other.hp=50
	step(240);check("opponent same recovery rule",other.hp==51)
	check("enemy keep never heals own soldier",Rest.base_for(soldier,[other_keep]).is_empty())
	soldier.path_failures=3;soldier.path_next_attempt_tick=123456;soldier.path_retry_ticks=[1,2,3]
	step(40);check("rest leaves route failure limits alone",soldier.path_failures==3 and soldier.path_next_attempt_tick==123456 and soldier.path_retry_ticks==[1,2,3])
	game._publish_faction_views();game.selected=[soldier.id];game._update_hud()
	check("own HUD explains recovery", "休整" in game.selection_detail.text)
	check("owned view exposes current rest",game.faction_views[0].get_record(soldier.id).rest_ticks==soldier.rest_ticks)
	soldier.hp=30;game._set_stance(soldier,"STOP");step(239)
	game._execute({"type":"stop","team":0,"ids":[soldier.id]});step(1)
	check("new stop cancels existing rest",soldier.hp==30 and soldier.rest_ticks==1)
	step(238);game._execute({"type":"defend","team":0,"ids":[soldier.id]});step(1)
	check("new defend cancels existing rest",soldier.hp==30 and soldier.rest_ticks==1)
	other.hp=50;step(239);var prior_hp=other.hp
	game._execute({"type":"stop","team":1,"ids":[other.id]});step(1)
	check("AI stop also cancels rest",other.hp==prior_hp and other.rest_ticks==1)
	# Real engine simulation, rather than only calling the new component.
	game._test_reset();game.set_process(false);keep=game._first(0,"town_center")
	soldier=game._spawn("archer",0,keep.pos+Vector3(5,0,0));soldier.hp=20
	for i in 240:game._tick(Rules.TICK)
	check("native full tick heals stationary archer",soldier.hp==21 and not game.game_over)
	check("same tick owned HP published",game.faction_views[0].get_record(soldier.id).hp==21)
	game._execute({"type":"order","team":0,"ids":[soldier.id],"position":keep.pos+Vector3(10,0,0)})
	game._tick(Rules.TICK);check("explicit move remains active and ends recovery",soldier.state=="move" and soldier.rest_ticks==0)
	game._test_reset();game.set_process(false)
	check("new match has no prior recovery timers",game.entities.all(func(e):return e.get("rest_ticks",0)==0))
	keep=game._first(0,"town_center")
	soldier=game._spawn("scout",0,keep.pos+Vector3(10,0,0));soldier.hp=20
	var origin=soldier.pos
	game._execute({"type":"order","team":0,"ids":[soldier.id],"position":keep.pos+Vector3(5,0,0)})
	for i in 600:
		game._tick(Rules.TICK)
		if soldier.hp>20:break
	check("normal ground command walks home before recovering",soldier.hp==21 and soldier.pos.distance_to(origin)>1 and soldier.pos.distance_to(keep.pos)<=Rest.RADIUS)
	var attacker=game._spawn("spearman",1,soldier.pos+Vector3(0.8,0,0))
	soldier.hp=1;game._update_vision(false)
	var released=game._release_attack(attacker,soldier)
	check("successful attack stamps combat time",released.applied and attacker.last_attack_tick==game.tick_count)
	game._tick(Rules.TICK)
	check("lethal settled hit cannot be healed alive",not soldier.alive and soldier.hp<=0)
	check("economy conserves",game.economy.audit().ok)
	var failed=checks.filter(func(c):return not c.passed).size()
	print(JSON.stringify({"suite":"rest_recovery_contract","checks":checks,"failed":failed,"scope":"controlled fixtures and actual native ticks; not natural full-match balance or rendered/phone acceptance"}))
	game.queue_free();quit(1 if failed else 0)

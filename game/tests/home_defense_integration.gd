extends SceneTree
const Rules=preload("res://scripts/rules.gd")
var game
var checks=[]
func check(label,ok):
	checks.append({"name":label,"passed":bool(ok)})
	if not ok: push_error(label)
func _initialize(): call_deferred("run")
func run():
	game=load("res://main.tscn").instantiate();root.add_child(game)
	game.set_process(false);game.test_mode=true;game.ai_enabled=false
	game._test_reset();game.set_process(false)
	await process_frame
	var home=game._first(1,"town_center")
	for ent in game.entities:
		if ent.alive and ent.team==0 and ent.category=="unit":
			ent.pos=Vector3(-28,0,-28);game._set_stance(ent,"STOP")
	var base=home.pos+Vector3(4,0,0)
	var own_spear=game._spawn("spearman",1,base)
	var own_horse=game._spawn("cavalry",1,base+Vector3(0,0,0.1))
	var own_archer=game._spawn("archer",1,base+Vector3(0,0,-0.1))
	var enemy_horse=game._spawn("cavalry",0,base+Vector3(1,0,0))
	var enemy_archer=game._spawn("archer",0,base+Vector3(1,0,0.1))
	var enemy_spear=game._spawn("spearman",0,base+Vector3(1,0,-0.1))
	var decoy=game._spawn("villager",0,base+Vector3(0.5,0,0))
	for ent in [enemy_horse,enemy_archer,enemy_spear,decoy]:
		game._set_stance(ent,"STOP");ent.cooldown_ticks=999
	game._update_vision()
	var records=game._ai_records()
	check("all controlled raid threats actually visible",[enemy_horse,enemy_archer,enemy_spear,decoy].all(func(ent):return not game.faction_views[1].get_record(ent.id).is_empty()))
	game.ai_raid_members=[own_spear.id];game.ai_raid_departure_count=1
	# Explicit prior-raid fixture includes the remembered objective metadata.
	var player_home=game._first(0,"town_center")
	game.ai_raid_keep={"id":player_home.id,"kind":"town_center","category":"building","pos":player_home.pos,"remembered":true}
	game._ai_army(records,game.faction_views[1].get_record(home.id))
	for pair in [[own_spear,enemy_horse],[own_horse,enemy_archer],[own_archer,enemy_spear]]:
		check(pair[0].kind+" queues distinct counter",game.commands.any(func(c):return c.type=="order" and c.get("target",-1)==pair[1].id and pair[0].id in c.get("ids",[])))
	check("closer worker decoy not priority",game.commands.all(func(c):return c.get("target",-1)!=decoy.id))
	check("defense interrupts raid through existing retreat flag",game.ai_raid_retreating and game.ai_status.army=="home_defense")
	enemy_horse.hp=1
	game._tick(Rules.TICK)
	check("ordinary ledger settles actual counter attack",not enemy_horse.alive and game.attack_ledger.next_attack_id()>1)
	check("economy conserved after defense combat",game.economy.audit().ok)
	# New observed threats get retargeted through real command handlers.
	game.commands.clear();game._update_vision()
	game._ai_army(game._ai_records(),game.faction_views[1].get_record(home.id))
	check("dead target not reused",game.commands.all(func(c):return c.get("target",-1)!=enemy_horse.id))
	game._tick(Rules.TICK)
	# Move surviving invaders out of every home zone as explicit fixture setup.
	for ent in [enemy_archer,enemy_spear,decoy]: ent.pos=Vector3(-26,0,-26)
	game._update_vision();game.commands.clear()
	var remembered_target=own_horse.target
	game._ai_army(game._ai_records(),game.faction_views[1].get_record(home.id))
	check("retired threat causes ordinary Stop not hidden pursuit",game.commands.any(func(c):return c.type=="stop" and own_horse.id in c.ids))
	check("retired defense tracking cleared",game.ai_home_defense_targets.is_empty())
	game._tick(Rules.TICK)
	check("Stop applied to actual military state",own_horse.target==-1 and own_horse.mode=="STOP")
	game.commands.clear();game._update_vision()
	game._ai_army(game._ai_records(),game.faction_views[1].get_record(home.id))
	check("next turn resumes existing retreat or muster",game.ai_status.army!="home_defense" and game.ai_status.army!="home_defense_released")
	check("old defense cannot issue repeated stops",not game.commands.any(func(c):return c.type=="stop" and own_horse.id in c.ids))
	check("economy remains conserved",game.economy.audit().ok)
	var failed=checks.filter(func(c):return not c.passed).size()
	print(JSON.stringify({"suite":"home_defense_integration","checks":checks,"failed":failed,"scope":"Controlled spawned mixed raid; actual game AI orders, combat ledger and stop; not natural match or visual acceptance"}))
	game.queue_free();quit(1 if failed else 0)

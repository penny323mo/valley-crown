extends SceneTree
const Codec=preload("res://scripts/checkpoint_codec.gd")
const Restore=preload("res://scripts/checkpoint_restore.gd")
var checks=[]
var game
func check(label,ok):
	checks.append({"name":label,"passed":bool(ok)})
	if not ok:push_error(label)
func _initialize():call_deferred("run")
func run():
	game=load("res://main.tscn").instantiate();root.add_child(game)
	game.set_process(false);game.test_mode=true;game.ai_enabled=false
	game._test_reset();game.set_process(false)
	await process_frame
	var home=game._first(1,"town_center")
	var local=game._spawn("spearman",1,Vector3.ZERO)
	var raider=game._spawn("cavalry",1,Vector3(-20,0,-20))
	var intruder=game._spawn("scout",0,Vector3(1,0,0))
	game._spawn("storehouse",1,Vector3.ZERO)
	game._update_vision()
	var records=game._ai_records().duplicate(true)
	var castle={}
	var enemy_keep={}
	for r in records:
		if r.id==home.id:castle=r
		if r.team==0 and r.kind=="town_center":enemy_keep=r
	# Provide a legitimate remembered enemy keep to the controlled observation
	# fixture, so an existing raid can continue without revealing hidden units.
	if enemy_keep.is_empty():
		var player=game._first(0,"town_center")
		enemy_keep={"id":player.id,"team":0,"owned":false,"alive":true,"kind":"town_center","category":"building","pos":player.pos,"remembered":true}
		records.append(enemy_keep)
	game.ai_raid_members=[raider.id,local.id];game.ai_raid_departure_count=3
	game.ai_raid_keep=enemy_keep.duplicate(true)
	game.commands.clear();game._ai_army(records,castle)
	check("actual army only assigns local interceptor",game.ai_home_defense_targets.size()==1 and game.ai_home_defense_targets.has(local.id))
	check("raid remains active and not retreating",game.ai_raid_members==[raider.id] and not game.ai_raid_retreating)
	check("raid still receives offensive command",game.commands.any(func(c):return c.type=="order" and raider.id in c.get("ids",[]) and c.get("target",-1)!=intruder.id))
	check("detached defender adjusts departure baseline",game.ai_raid_departure_count==2)
	var captured=Codec.capture_result(game)
	check("fresh defense and raid checkpoint validates",captured.ok)
	if captured.ok:
		var restored=load("res://main.tscn").instantiate();root.add_child(restored)
		restored.set_process(false);restored.test_mode=true
		await process_frame
		var applied=Restore.apply(restored,captured.data)
		check("fresh checkpoint restores existing AI fields",applied)
		if applied:
			restored.paused=false;game.commands.clear();restored.commands.clear()
			game._ai_army(records,castle);restored._ai_army(records,castle)
			check("same tick restored defense commands identical",game.commands==restored.commands)
			check("same tick restored tracking and raid identical",game.ai_home_defense_targets==restored.ai_home_defense_targets and game.ai_raid_members==restored.ai_raid_members and game.ai_raid_departure_count==restored.ai_raid_departure_count and game.ai_raid_retreating==restored.ai_raid_retreating)
		restored.queue_free()
	# Applied defensive observation on repeat: no repeated target order.
	for r in records:
		if r.id==local.id:r.state="attack";r.mode="ATTACK";r.target=intruder.id
	game.commands.clear();game._ai_army(records,castle)
	check("repeat does not requeue same defensive target",not game.commands.any(func(c):return c.type=="order" and local.id in c.get("ids",[])))
	for r in records:
		if r.id==intruder.id:r.remembered=true
	game.commands.clear();game._ai_army(records,castle)
	check("fog produces ordinary interceptor stop",game.commands.any(func(c):return c.type=="stop" and local.id in c.get("ids",[])))
	check("release cannot overwrite Stop this turn",not game.commands.any(func(c):return c.type=="order" and local.id in c.get("ids",[])))
	check("fog clears defense tracking",game.ai_home_defense_targets.is_empty())
	check("fog does not retire offensive cohort",game.ai_raid_members==[raider.id] and not game.ai_raid_retreating)
	game.commands.clear();game._ai_army(records,castle)
	check("retired tracking cannot repeatedly stop",not game.commands.any(func(c):return c.type=="stop" and local.id in c.get("ids",[])))
	check("economy remains conserved",game.economy.audit().ok)
	var failed=checks.filter(func(c):return not c.passed).size()
	print(JSON.stringify({"suite":"home_defense_allocation_integration","checks":checks,"failed":failed,"scope":"Controlled native game army routing with sanitized observation fixtures; no natural-match or phone claim"}))
	game.queue_free();quit(1 if failed else 0)

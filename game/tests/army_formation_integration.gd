extends SceneTree
const Rules=preload("res://scripts/rules.gd")
var game
var checks=[]
func check(name,ok):
	checks.append({"name":name,"passed":bool(ok)})
	if not ok: push_error(name)
func _initialize(): call_deferred("run")
func run():
	game=load("res://main.tscn").instantiate(); root.add_child(game)
	game.set_process(false);game.test_mode=true;game.ai_enabled=false
	game._test_reset();game.set_process(false)
	await process_frame
	var scout=game._first(0,"scout");var worker=game._first(0,"villager")
	var ids=[scout.id]
	for kind in ["spearman","spearman","archer","archer","siege"]:
		var e=game._spawn(kind,0,scout.pos+Vector3(ids.size(),0,0)); ids.append(e.id)
	game._update_vision(false);game._publish_faction_views()
	var destination=scout.pos+Vector3(0,0,6)
	var worker_before=worker.duplicate(true)
	game._execute({"type":"advance","team":0,"ids":ids+[worker.id,ids[0]],"position":destination,"formation":"line"})
	var slots={};var engaged=0
	for id in ids:
		var e=game._get_entity(id);slots[game._cell(e.dest)]=true
		if e.mode=="ADVANCE": engaged+=1
	check("all six military use advance",engaged==6)
	check("destinations unique after resolver",slots.size()==6)
	check("worker unchanged",worker.dest==worker_before.dest and worker.state==worker_before.state)
	var prior=scout.dest
	game._execute({"type":"advance","team":0,"ids":ids,"position":destination,"formation":"invalid"})
	check("invalid formation atomic",scout.dest==prior)
	game._select(ids);game._start_formation_command("spread")
	check("formation targeting shown",game.touch_command and game.advance_formation=="spread")
	game._cancel_mode()
	check("cancel clears formation",not game.touch_command and game.advance_formation=="")
	game._start_advance_command()
	check("ordinary advance no stale formation",game.advance_formation=="")
	game._cancel_mode()
	game._execute({"type":"stop","team":0,"ids":ids})
	check("stop retires formation movement",ids.all(func(id):return game._get_entity(id).mode=="STOP"))
	var enemy=game._first(1,"villager");var old=enemy.dest
	game._execute({"type":"advance","team":0,"ids":[enemy.id],"position":destination,"formation":"line"})
	check("cannot control enemy",enemy.dest==old)
	game._execute({"type":"advance","team":0,"ids":ids,"position":Vector3.INF,"formation":"line"})
	check("invalid destination no movement",scout.mode=="STOP")
	# Ordinary contextual ground order still uses the old order handler.
	game._execute({"type":"order","team":0,"ids":[scout.id],"position":destination,"target":-1})
	check("ordinary move remains move",scout.mode=="MOVE")
	game._select(ids);game._start_formation_command("line")
	game.commands.clear()
	var point=game.camera.unproject_position(destination)
	game._send_world_order(point,true)
	check("targeting queues formation metadata",game.commands.size()==1 and game.commands[0].type=="advance" and game.commands[0].get("formation","")=="line")
	check("targeting retires mode after submit",game.advance_formation=="" and not game.touch_command)
	game.commands.clear();game.paused=true
	game._start_formation_command("spread")
	check("paused cannot arm formation",not game.touch_command)
	game.paused=false
	var failed=checks.filter(func(c):return not c.passed).size()
	print(JSON.stringify({"suite":"army_formation_integration","checks":checks,"failed":failed,"scope":"Controlled actual game handlers; not natural battle or rendered acceptance"}))
	game.queue_free();quit(1 if failed else 0)

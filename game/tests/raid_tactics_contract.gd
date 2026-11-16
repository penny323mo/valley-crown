extends SceneTree
# ENGINE_UNRUN. Controlled army/defender setup, not paid progression or a natural match.
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
	var target=game._first(0,"town_center");var home=game._first(1,"town_center")
	# Isolate this setup: opening player units otherwise remain in escort range.
	# Relocation is deliberate fixture setup, not natural movement or victory evidence.
	var relocated=0
	for unit in game.entities:
		if unit.alive and unit.team==0 and unit.category=="unit":
			unit.pos=Vector3(-30+2*relocated,0,-30);game._set_stance(unit,"STOP");relocated+=1
	var position=target.pos+Vector3(5,0,0)
	var archer=game._spawn("archer",1,position)
	var siege=game._spawn("siege",1,position+Vector3(0,0,2))
	var defender=game._spawn("spearman",0,position+Vector3(2.5,0,0));defender.hp=1
	game._update_vision();game.ai_raid_members=[archer.id,siege.id];game.ai_raid_departure_count=2
	game.ai_raid_keep=game.faction_views[1].get_record(target.id).duplicate(true)
	check("controlled raid can actually observe keep",not game.ai_raid_keep.is_empty())
	if game.ai_raid_keep.is_empty(): game.queue_free();quit(1);return
	game._ai_army(game._ai_records(),game.faction_views[1].get_record(home.id))
	check("escort queues defender attack",game.commands.any(func(c):return c.type=="order" and c.get("target",-1)==defender.id and archer.id in c.get("ids",[])))
	check("siege queues original strategic keep",game.commands.any(func(c):return c.type=="order" and c.get("target",-1)==target.id and siege.id in c.get("ids",[])))
	game._tick(Rules.TICK)
	check("normal attack settlement removes controlled defender",not defender.alive and game.attack_ledger.next_attack_id()>1)
	game._ai_army(game._ai_records(),game.faction_views[1].get_record(home.id))
	check("escort resumes keep objective after encounter",game.commands.any(func(c):return c.type=="order" and c.get("target",-1)==target.id and archer.id in c.get("ids",[])))
	check("paid-economy ledger remains conserved",game.economy.audit().ok)
	var failed=checks.filter(func(item):return not item.passed).size()
	print(JSON.stringify({"suite":"raid_tactics_contract","build":Rules.BUILD_ID,"checks":checks,"failed":failed,"status":"ENGINE_UNRUN","scope":"Controlled spawned raid and ordinary queued orders/settlement; not paid training, natural match or rendered evidence"}))
	game.queue_free();quit(1 if failed else 0)

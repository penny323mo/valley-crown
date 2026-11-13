extends SceneTree
# ENGINE_UNRUN. Controlled encounter through ordinary orders and fixed ticks.
# This is not a natural match, routed touch or rendered acceptance.
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
	var origin=scout.pos; var goal=origin+Vector3(5,0,0)
	var worker_destination=worker.dest
	# Explicit controlled enemy placement and low HP, not earned progression.
	foe.pos=origin+Vector3(1,0,0); foe.hp=1; game._set_stance(foe,"STOP")
	game._update_vision(false); game._publish_faction_views()
	game._submit("advance",{"ids":[worker.id,scout.id,scout.id],"position":goal})
	game._tick(Rules.TICK)
	check("mixed advance leaves worker order and applies to scout",worker.dest==worker_destination and worker.mode!="ADVANCE" and scout.mode=="ADVANCE")
	check("in-range encounter holds original point",scout.pos==origin and scout.advance_engaged)
	check("ordinary attack settlement kills controlled foe",not foe.alive and game.attack_ledger.next_attack_id()>1)
	var accepted_goal=scout.dest
	for i in 240:
		if scout.state=="idle" or game.game_over: break
		game._tick(Rules.TICK)
	check("cleared encounter continues to destination",scout.pos.distance_to(accepted_goal)<0.01 and scout.mode=="STOP")
	check("economy ledger remains conserved after encounter",game.economy.audit().ok)
	game._select([scout.id]); game._start_advance_command()
	check("military action enters explicit advance targeting",game.touch_command and game.unit_command_kind=="advance")
	game._cancel_mode()
	check("cancel retires stale targeting",not game.touch_command and game.unit_command_kind=="order")
	game._submit("advance",{"ids":[scout.id],"position":origin})
	game._tick(Rules.TICK)
	game._submit("stop",{"ids":[scout.id]}); game._tick(Rules.TICK)
	check("explicit Stop replaces advance",scout.mode=="STOP" and not scout.advance_engaged)
	var failed=checks.filter(func(item): return not item.passed).size()
	print(JSON.stringify({"suite":"advance_contract","build":Rules.BUILD_ID,"checks":checks,"failed":failed,"status":"ENGINE_UNRUN","scope":"Controlled normal command, attack settlement and movement; not natural match or routed input"}))
	game.queue_free(); quit(1 if failed else 0)

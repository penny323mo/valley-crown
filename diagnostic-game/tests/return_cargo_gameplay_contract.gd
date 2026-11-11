extends SceneTree
## PENDING guarded native execution. Controlled test, not original failed replay,
## physical-phone touch, visual acceptance, or proof all congestion is recoverable.
var game
var failures=0
func _initialize(): call_deferred("run")
func check(label,ok):
	print("RETURN_CARGO_GAMEPLAY ",label,": ",ok)
	if not ok: failures+=1
func run():
	game=load("res://main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game._test_reset()
	var worker=game._first(0,"villager")
	var keep=game._first(0,"town_center")
	var berry=game._nearest_resource(worker.pos,"food",0)
	game._submit("order",{"ids":[worker.id],"target":berry.id,"position":berry.pos})
	var gathered=false
	for i in 1800:
		game._tick(game.Rules.TICK)
		if game._cargo_amount(worker)>0: gathered=true; break
	check("ordinary gather produces partial cargo",gathered)
	if not gathered: game.free(); quit(1); return
	game._submit("stop",{"ids":[worker.id]})
	game._tick(game.Rules.TICK)
	# Controlled damaged-keep fixture proves delivery precedence over repair.
	keep.hp=533
	game._publish_faction_views()
	var cargo=game._cargo_amount(worker)
	var gather_target=worker.resource_target
	var bank=game.economy.bank_milli(0).duplicate()
	var delivered=game.delivered_total[0]
	check("ledger conservation before action",game.economy.audit().ok)
	game._select([worker.id])
	game._return_selected_cargo(); game._return_selected_cargo()
	check("one ordinary targeted order",game.commands.size()==1 and game.commands[0].target==keep.id)
	check("damaged keep intent is deliver",game._target_order_intent(worker,keep,0)=="deliver")
	game._tick(game.Rules.TICK)
	check("gather target preserved",worker.resource_target==gather_target)
	var credited=false
	for i in 1800:
		if game.delivered_total[0]>delivered: credited=true; break
		game._tick(game.Rules.TICK)
	check("normal ticks deposit cargo",credited)
	check("cargo zero immediately after deposit",game._cargo_amount(worker)==0)
	check("exact cargo credit once",game.economy.bank_milli(0).food==bank.food+cargo and game.delivered_total[0]==delivered+cargo/1000.0)
	check("ledger conservation after delivery",game.economy.audit().ok)
	check("no repair wood spent",game.economy.bank_milli(0).wood==bank.wood and keep.hp==533)
	check("normal resume retains resource target",worker.state=="gather" and worker.resource_target==gather_target)
	game._submit("stop",{"ids":[worker.id]}); game._tick(game.Rules.TICK)
	var settled=game.economy.bank_milli(0).food
	for i in 10: game._tick(game.Rules.TICK)
	check("ledger conservation after repeated taps and STOP",game.economy.audit().ok)
	check("no duplicate credit after STOP",game.economy.bank_milli(0).food==settled)
	# Final authority rejects vanished targets and workers rather than grounding
	# a targeted order. Restore fixture fields immediately after each assertion.
	var prior_state=worker.state; var prior_dest=worker.dest
	keep.alive=false
	game._execute({"team":0,"type":"order","ids":[worker.id],"target":keep.id,"position":keep.pos})
	check("invalid target does not become move",worker.state==prior_state and worker.dest==prior_dest)
	keep.alive=true; worker.alive=false
	game._execute({"team":0,"type":"order","ids":[worker.id],"target":keep.id,"position":keep.pos})
	check("dead worker unchanged",worker.state==prior_state and worker.dest==prior_dest)
	worker.alive=true
	game.free()
	quit(1 if failures else 0)

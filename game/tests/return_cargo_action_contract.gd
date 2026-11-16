extends SceneTree
## Prepared native contract, not executed during source-only preparation.
const Plan = preload("res://scripts/return_cargo_action.gd")
const Game = preload("res://scripts/game.gd")
var checks=0
var failures=0
func check(label: String, ok: bool):
	checks+=1
	if not ok: failures+=1; push_error(label)
func worker(id=1, cargo=1, pos=Vector3.ZERO) -> Dictionary:
	return {"id":id,"owned":true,"alive":true,"remembered":false,"team":0,"category":"unit","kind":"villager","cargo_milli":cargo,"pos":pos,"state":"idle","path_status":"NO_PATH","built":true}
func drop(id=10, pos=Vector3(2,0,0)) -> Dictionary:
	return {"id":id,"owned":true,"alive":true,"remembered":false,"team":0,"category":"building","kind":"storehouse","built":true,"pos":pos}
func _initialize():
	var records={1:worker(),10:drop(),11:drop(11,Vector3(-2,0,0))}
	var snapshot=records.duplicate(true)
	var plan=Plan.orders(records,[1,1],[])
	check("partial cargo, one order, tie by smaller ID",plan.size()==1 and plan[0]=={"ids":[1],"target":10,"position":Vector3(2,0,0)})
	check("inputs immutable",records==snapshot)
	var shuffled={11:records[11],10:records[10],1:records[1]}
	check("record insertion order irrelevant",Plan.orders(shuffled,[1],[])==plan)
	records[2]=worker(2,10000,Vector3(-3,0,0))
	plan=Plan.orders(records,[2,1],[])
	check("multiple workers choose their own nearest target in ID order",plan.size()==2 and plan[0].ids==[1] and plan[1].ids==[2] and plan[1].target==11)
	for changes in [{"owned":false},{"alive":false},{"remembered":true},{"team":1},{"kind":"spearman"},{"category":"building"},{"cargo_milli":0}]:
		var bad=worker(); bad.merge(changes,true)
		check("exclude worker "+str(changes),Plan.orders({1:bad,10:drop()},[1],[]).is_empty())
	for changes in [{"owned":false},{"alive":false},{"remembered":true},{"team":1},{"kind":"house"},{"category":"unit"},{"built":false}]:
		var bad=drop(); bad.merge(changes,true)
		check("exclude dropoff "+str(changes),Plan.orders({1:worker(),10:bad},[1],[]).is_empty())
	check("no target never produces ground move",Plan.orders({1:worker()},[1],[]).is_empty())
	check("missing selection ignored",Plan.orders(records,[999],[]).is_empty())
	for state in ["FOUND","QUEUED","WAIT_SLOT","IDLE"]:
		var active=worker(); active.state="deliver"; active.path_status=state
		check("healthy delivery untouched "+state,Plan.orders({1:active,10:drop()},[1],[]).is_empty())
	var terminal=worker(); terminal.state="deliver"
	check("terminal delivery retry available",Plan.orders({1:terminal,10:drop()},[1],[]).size()==1)
	terminal.path_status="LIMIT_REACHED"; terminal.mode="STOP"
	check("terminal limit and STOP can be explicitly recovered",Plan.orders({1:terminal,10:drop()},[1],[]).size()==1)
	for kind in ["order","stop","defend","build"]:
		var pending={"team":0,"type":kind,"ids":[1],"builder":1}
		check("queued own intent protected "+kind,Plan.orders(records,[1],[pending]).is_empty())
		pending.team=1
		check("enemy queue does not affect eligibility "+kind,Plan.orders(records,[1],[pending]).size()==1)
	var mixed={1:worker(),2:worker(2,0),3:worker(3),4:worker(4),10:drop()}
	mixed[3].kind="spearman"; mixed[4].owned=false; mixed[4].team=1
	check("mixed selection",Plan.orders(mixed,[1,2,3,4],[]).size()==1)
	_test_ui()
	print("RETURN_CARGO_CONTRACT %d/%d; helper/UI contract, not live gameplay acceptance" % [checks-failures,checks])
	quit(1 if failures else 0)
func _test_ui():
	# Off-tree Game exercises real control and submission functions without world
	# creation. Full native gameplay/camera/touch acceptance is a separate gate.
	var game=Game.new()
	game.actions=HBoxContainer.new()
	game.selected=[1]
	game.faction_views[0].current={1:worker(),10:drop()}
	game._rebuild_actions([worker()])
	game._refresh_return_cargo_button()
	var button=game.return_cargo_button
	var button_id=button.get_instance_id()
	check("house remains first action",game.actions.get_child(0).text.begins_with(Game.Rules.NAMES.house))
	check("loaded button enabled",button.visible and not button.disabled)
	game.faction_views[0].current[1].cargo_milli=0
	game._refresh_return_cargo_button()
	check("same node updates empty cargo",button.disabled and button.get_instance_id()==button_id)
	game._return_selected_cargo()
	check("empty cargo emits no repair or move",game.commands.is_empty())
	game.faction_views[0].current[1].cargo_milli=1
	game.faction_views[0].current.erase(10)
	game._refresh_return_cargo_button()
	check("dropoff invalidation disables",button.disabled)
	game._return_selected_cargo()
	check("missing dropoff emits nothing",game.commands.is_empty())
	game.faction_views[0].current[10]=drop()
	game.paused=true; game._refresh_return_cargo_button(); game._return_selected_cargo()
	check("paused disabled and guarded",button.disabled and game.commands.is_empty())
	game.paused=false; game.game_over=true; game._refresh_return_cargo_button(); game._return_selected_cargo()
	check("game over disabled and guarded",button.disabled and game.commands.is_empty())
	game.game_over=false
	game.selected=[]; game._return_selected_cargo(); game._refresh_return_cargo_button()
	check("selection revalidated",not button.visible and game.commands.is_empty())
	game.selected=[1]; game.faction_views[0].current[1].alive=false
	game._return_selected_cargo(); game._refresh_return_cargo_button()
	check("death revalidated",not button.visible and game.commands.is_empty())
	game.faction_views[0].current[1].alive=true
	game.touch_command=true; game._return_selected_cargo(); game._return_selected_cargo()
	check("ordinary order preserves entity target",game.commands.size()==1 and game.commands[0].type=="order" and game.commands[0].target==10 and game.commands[0].ids==[1])
	check("duplicate taps disabled, target mode exits",button.disabled and not game.touch_command)
	game._submit("stop",{"ids":[1]})
	game._return_selected_cargo()
	check("later STOP remains last",game.commands.size()==2 and game.commands[-1].type=="stop")
	game.commands.clear()
	game._submit("order",{"ids":[1],"target":-1,"position":Vector3.ONE})
	game._return_selected_cargo()
	check("pending manual order not overwritten",game.commands.size()==1 and game.commands[0].target==-1)
	game.commands.clear()
	for mode in ["build","box","rally"]:
		game.build_mode="house" if mode=="build" else ""
		game.box_select_mode=mode=="box"
		game.rally_building=10 if mode=="rally" else -1
		game._return_selected_cargo()
		check("mode guard "+mode,game.commands.is_empty())
	game.actions.free(); game.free()

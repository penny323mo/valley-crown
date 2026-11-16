extends SceneTree
# ENGINE_UNRUN. Controlled selector/UI-component calls, not raw touch routing.
# No earned economy, natural battle, screenshot or phone acceptance.
const Rules=preload("res://scripts/rules.gd")
const Idle=preload("res://scripts/idle_worker_selection.gd")
var game
var checks=[]
func check(label,ok):
	checks.append({"name":label,"passed":bool(ok)})
	if not ok: push_error(label)
func _initialize(): call_deferred("run")
func open_shortcuts():
	game.compact_menu.show(); game.compact_menu_dismiss.show(); game._refresh_idle_worker_button()
func run():
	game=load("res://main.tscn").instantiate(); root.add_child(game)
	game.set_process(false); game.test_mode=true; game.ai_enabled=false; game._test_reset(); game.set_process(false)
	await process_frame
	game._update_vision(false); game._publish_faction_views(); open_shortcuts()
	var ids=Idle.eligible(game.faction_views[0].records(),game.commands)
	check("opening has five eligible owned villagers",ids.size()==5)
	if ids.size()<2: game.queue_free(); quit(2); return
	var orders=game.commands.size()
	game._focus_idle_worker()
	check("first stable worker selected without any order",game.selected==[ids[0]] and game.commands.size()==orders and game.idle_worker_cursor==ids[0])
	check("camera focuses actual owned position",game.camera_focus==game.faction_views[0].get_record(ids[0]).pos)
	game.paused=true; open_shortcuts(); game._focus_idle_worker()
	check("paused navigation selects next worker, not work",game.selected==[ids[1]] and game.paused and game.commands.size()==orders)
	game.paused=false; open_shortcuts()
	var target=game.idle_worker_button.get_meta("idle_target",-1)
	var previous=game.selected.duplicate(); var cursor=game.idle_worker_cursor
	game._submit("order",{"ids":[target],"target":-1,"position":Vector3(-20,0,20)})
	game._focus_idle_worker()
	check("new queued order invalidates old displayed target before selection",game.selected==previous and game.idle_worker_cursor==cursor and game.commands.size()==orders+1)
	check("pending worker excluded individually",target not in game.idle_worker_button.get_meta("idle_ids",[]) and game.idle_worker_button.get_meta("idle_ids",[]).size()==4)
	var dead=game.idle_worker_button.get_meta("idle_target",-1)
	game._kill(game._get_entity(dead)); game._publish_faction_views(); game._focus_idle_worker()
	check("death cannot redirect a stale activation",game.selected==previous and game.idle_worker_cursor==cursor)
	game._focus_idle_worker()
	check("fresh activation can select a surviving idle worker",game.selected.size()==1 and game.selected[0]!=dead and game.selected[0]!=target and game.commands.size()==orders+1)
	game._test_reset(); game.set_process(false)
	check("new match resets cursor and queued intent",game.idle_worker_cursor==-1 and game.commands.is_empty())
	var failed=checks.filter(func(item): return not item.passed).size()
	print(JSON.stringify({"suite":"idle_worker_cycle_contract","build":Rules.BUILD_ID,"checks":checks,"failed":failed,"scope":"Controlled source/UI navigation only, no routed-input or camera pixel proof"}))
	game.queue_free(); quit(1 if failed else 0)

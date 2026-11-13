extends SceneTree
# ENGINE_UNRUN. Native menu/report lifecycle preparation; no routed-input claim.
var shell
var checks=[]
func check(label,ok):
	checks.append({"name":label,"passed":bool(ok)})
	if not ok: push_error(label)
func _initialize(): call_deferred("run")
func run():
	shell=load("res://main_menu.tscn").instantiate(); root.add_child(shell)
	shell._replace_match()
	var game=shell.match_node
	game.set_process(false); game.test_mode=true; game.ai_enabled=false
	game._test_reset(); game.set_process(false)
	game._submit("surrender",{}); game._tick(game.Rules.TICK)
	var report=game.last_match_report.duplicate(true); var tick=game.tick_count
	shell._open_menu()
	check("completed match offers report action",shell.buttons.has_node("MatchReportButton"))
	shell._review_finished_match()
	await process_frame
	await process_frame
	check("review reuses exact match",shell.match_node==game and game.game_over and game.tick_count==tick and game.last_match_report==report)
	check("review shows report not menu",not shell.menu_layer.visible and game.ui.visible and game.end_panel.visible)
	check("review does not unpause ended game",game.paused and not shell.transition_busy)
	shell._open_menu(); shell._review_finished_match()
	await process_frame
	check("repeated review keeps frozen report",game.last_match_report==report and game.tick_count==tick)
	var failed=checks.filter(func(item): return not item.passed).size()
	print(JSON.stringify({"suite":"match_report_menu_contract","checks":checks,"failed":failed,"status":"ENGINE_UNRUN"}))
	shell.queue_free(); quit(1 if failed else 0)

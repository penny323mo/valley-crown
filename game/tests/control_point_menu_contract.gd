extends SceneTree
var checks=[]
func check(label,ok):
	checks.append({"name":label,"passed":bool(ok)})
	if not ok:push_error(label)
func _initialize():call_deferred("run")
func run():
	var shell=load("res://main_menu.tscn").instantiate();root.add_child(shell)
	await process_frame
	shell._show_page("setup")
	shell.buttons.get_node("CycleModeButton").pressed.emit()
	shell.buttons.get_node("CycleModeButton").pressed.emit()
	check("fourth option selects control mode",shell.selected_victory_mode=="control" and shell.selected_mode=="standard")
	check("setup explains goal and public information", "180" in shell.description.text and "分數公開" in shell.description.text and shell.mode_title.text=="中央據點爭奪")
	for size in [Vector2i(390,844),Vector2i(320,568),Vector2i(568,320),Vector2i(1280,800)]:
		root.size=size;shell._layout();await process_frame;await process_frame
		var viewport=Rect2(Vector2.ZERO,Vector2(size));var card=shell.card.get_global_rect()
		for button in shell.buttons.get_children():
			check("setup action fits %s %s" % [size,button.name],viewport.encloses(button.get_global_rect()) and card.encloses(button.get_global_rect()))
	root.size=Vector2i(390,844);shell._layout();await process_frame
	shell.buttons.get_node("LaunchMatchButton").pressed.emit();await process_frame;await process_frame
	var game=shell.match_node;game.set_process(false);game.ai_enabled=false
	check("actual menu launches objective match",game.victory_mode=="control" and game.control_point_marker.visible)
	for size in [Vector2i(390,844),Vector2i(320,568),Vector2i(568,320),Vector2i(1280,800)]:
		root.size=size;game._update_hud();game._layout_ui();await process_frame;await process_frame;game._layout_ui()
		var rect=game.objective_button.get_global_rect()
		check("objective HUD fits %s"%[size],game.objective_button.visible and Rect2(Vector2.ZERO,Vector2(size)).encloses(rect) and rect.size.y>=44)
		check("objective HUD does not overlap lower panel %s"%[size],rect.end.y<game.hud_bottom.position.y)
	game.camera_focus=Vector3(10,0,10);game.objective_button.pressed.emit()
	check("score button focuses known central landmark only",game.camera_focus==Vector3.ZERO and game.commands.is_empty())
	shell._restart_match();await process_frame;await process_frame
	game=shell.match_node;game.set_process(false)
	check("restart preserves mode but resets score",game.victory_mode=="control" and game.control_point.scores==[0,0])
	shell._show_page("setup");shell._cycle_victory_mode()
	check("mode cycle returns to ordinary practice",shell.selected_victory_mode=="conquest" and shell.selected_mode=="practice")
	var failed=checks.filter(func(c):return not c.passed).size()
	print(JSON.stringify({"suite":"control_point_menu_contract","checks":checks,"failed":failed,"scope":"native controls, viewport geometry and real menu transitions; no rendered or physical-device acceptance"}))
	shell.queue_free();quit(1 if failed else 0)

extends SceneTree
## Engine integration fixture. NOT executed by the source-only checks.
var failures = []
var checks = []
func check(value, message):
	checks.append({"name": message, "passed": bool(value)})
	if not value: failures.append(message)
func check_visible_controls(shell, phase: String):
	var viewport: Rect2 = shell.get_viewport().get_visible_rect()
	var card_rect: Rect2 = shell.card.get_global_rect()
	var previous_bottom = -1.0
	for button in shell.buttons.get_children():
		var rect: Rect2 = button.get_global_rect()
		check(button.is_visible_in_tree(), phase + ": " + button.name + " visible")
		check(rect.size.x >= 44.0 and rect.size.y >= 54.0, phase + ": " + button.name + " hit target")
		check(viewport.encloses(rect) and card_rect.encloses(rect), phase + ": " + button.name + " inside viewport and panel")
		if not viewport.encloses(rect) or not card_rect.encloses(rect):
			push_error("MENU_LAYOUT " + JSON.stringify({"phase": phase, "button": str(rect), "card": str(card_rect), "card_minimum": str(shell.card.get_combined_minimum_size()), "scroll": str(shell.scroll.get_global_rect()), "actions": str(shell.buttons.get_global_rect()), "footer": str(shell.footer.get_global_rect())}))
		check(rect.position.y >= previous_bottom, phase + ": " + button.name + " nonoverlapping")
		previous_bottom = rect.end.y
	check(shell.scroll.get_global_rect().end.y <= shell.buttons.get_global_rect().position.y, phase + ": prose cannot push or overlap actions")
	if shell.footer.visible:
		check(viewport.encloses(shell.footer.get_global_rect()), phase + ": footer visible")

func check_layout_matrix(shell, phase: String):
	var previous = root.size
	for size in [Vector2i(320,568), Vector2i(390,844), Vector2i(844,390), Vector2i(1440,900)]:
		root.size = size
		shell._layout()
		await process_frame
		await process_frame
		check_visible_controls(shell, phase + " %dx%d" % [size.x, size.y])
	root.size = previous
	shell._layout()
	await process_frame
	await process_frame

func _initialize():
	call_deferred("run")
func run():
	var shell = load("res://main_menu.tscn").instantiate()
	root.add_child(shell)
	await process_frame
	check(not is_instance_valid(shell.match_node), "landing must not instantiate a battlefield")
	check(shell.buttons.has_node("StartMatchButton"), "ordinary start action exists")
	await check_layout_matrix(shell, "fresh home")
	shell.buttons.get_node("HelpButton").pressed.emit()
	check(shell.page == "help" and not is_instance_valid(shell.match_node), "help never starts simulation")
	await check_layout_matrix(shell, "help")
	shell.buttons.get_node("BackButton").pressed.emit()
	# Synthetic event-handler checks, not physical-device acceptance.
	var start = shell.buttons.get_node("StartMatchButton")
	var press = InputEventScreenTouch.new()
	press.index = 0; press.position = Vector2(20,20); press.pressed = true
	var release = InputEventScreenTouch.new()
	release.index = 0; release.position = Vector2(20,20)
	shell._input(press); shell._button_touch(start,press)
	shell._layout()
	shell._input(release); shell._button_touch(start,release)
	check(not shell.transition_busy, "resize quarantines held start")
	shell._input(press); shell._button_touch(start,press)
	var drag = InputEventScreenDrag.new()
	drag.index = 0; drag.position = Vector2(80,20)
	shell._button_touch(start,drag)
	shell._input(release); shell._button_touch(start,release)
	check(not shell.transition_busy, "drag-return cannot start")
	shell._input(press); shell._button_touch(start,press)
	var second = InputEventScreenTouch.new()
	second.index = 1; second.position = Vector2(25,25); second.pressed = true
	shell._input(second); shell._button_touch(start,second)
	shell._input(release); shell._button_touch(start,release)
	second.pressed = false
	shell._input(second); shell._button_touch(start,second)
	check(not shell.transition_busy, "multi-touch cannot start")
	shell._input(press); shell._button_touch(start,press)
	shell._show_page("help"); shell._show_page("home")
	start = shell.buttons.get_node("StartMatchButton")
	shell._input(release); shell._button_touch(start,release)
	check(not shell.transition_busy, "page replacement cannot inherit held start")
	shell._input(press); shell._button_touch(start,press)
	release.position = Vector2(70,20)
	shell._input(release); shell._button_touch(start,release)
	check(not shell.transition_busy, "distant release without drag sample cannot start")
	# Exercise the same deliberate public button as a player, never a QA bypass.
	shell.buttons.get_node("StartMatchButton").pressed.emit()
	await process_frame
	await process_frame
	var game = shell.match_node
	check(is_instance_valid(game) and not shell.menu_layer.visible, "start enters match")
	game._request_main_menu()
	check(game.paused and not game.ui.visible and shell.menu_layer.visible, "return pauses and hides HUD")
	await check_layout_matrix(shell, "paused home")
	var ticks = game.tick_count
	var tutorial_step = game.demo_tutorial.step()
	await process_frame
	await process_frame
	check(game.tick_count == ticks, "menu does not advance simulation")
	shell.buttons.get_node("NewMatchButton").pressed.emit()
	check(shell.page == "confirm", "new match requires discard choice")
	await check_layout_matrix(shell, "new match confirmation")
	shell.buttons.get_node("CancelNewMatchButton").pressed.emit()
	check(shell.match_node == game and game.demo_tutorial.step() == tutorial_step, "cancel preserves match and tutorial")
	shell.buttons.get_node("ResumeMatchButton").pressed.emit()
	await process_frame
	check(shell.match_node == game and game.ui.visible and not game.paused, "resume keeps same scene")
	game._request_main_menu()
	game.game_over = true
	shell._show_page("home")
	check(not shell.buttons.has_node("ResumeMatchButton"), "terminal match cannot resume")
	shell.buttons.get_node("NewMatchButton").pressed.emit()
	await process_frame
	await process_frame
	check(shell.match_node != game and not shell.match_node.game_over, "new match replaces terminal game")
	shell.queue_free()
	await process_frame
	for failure in failures: push_error(failure)
	var report = {
		"suite": "main_menu_flow_contract",
		"build": preload("res://scripts/rules.gd").BUILD_ID,
		"scope": "Controlled button-signal and synthetic event-handler integration; not browser input dispatch, rendering, or physical-device acceptance. Terminal navigation uses an explicitly synthetic game_over assignment, not a played victory.",
		"checks": checks,
		"failure_count": failures.size(),
		"source_sha256": {
			"scripts/game.gd": FileAccess.get_sha256("res://scripts/game.gd"),
			"scripts/main_menu.gd": FileAccess.get_sha256("res://scripts/main_menu.gd")
		}
	}
	print(JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)

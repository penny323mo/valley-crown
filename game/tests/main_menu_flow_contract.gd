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
		if viewport.size.y >= viewport.size.x or viewport.size.y >= 500.0:
			check(shell.identity.is_visible_in_tree(), phase + ": home identity must be visible on portrait and desktop")
			check(shell.wordmark.is_visible_in_tree(), phase + ": game title must be visible on portrait and desktop")
		check(viewport.encloses(shell.footer.get_global_rect()), phase + ": footer visible")
		check(not shell.identity.visible or viewport.encloses(shell.identity.get_global_rect()), phase + ": visible identity inside viewport")
		var identity_clear = not shell.identity.visible or (not shell.identity.get_global_rect().intersects(shell.scroll.get_global_rect()) and not shell.identity.get_global_rect().intersects(shell.buttons.get_global_rect()))
		if not identity_clear:
			push_error("MENU_IDENTITY_LAYOUT " + JSON.stringify({"phase": phase, "identity": str(shell.identity.get_global_rect()), "identity_minimum": str(shell.identity.get_combined_minimum_size()), "wordmark": str(shell.wordmark.get_global_rect()), "wordmark_minimum": str(shell.wordmark.get_combined_minimum_size()), "font_size": shell.wordmark.get_theme_font_size("font_size"), "card": str(card_rect), "scroll": str(shell.scroll.get_global_rect()), "actions": str(shell.buttons.get_global_rect())}))
		check(identity_clear, phase + ": identity cannot overlap prose or actions")

func check_layout_matrix(shell, phase: String):
	var previous = root.size
	for size in [Vector2i(1280,800), Vector2i(390,844), Vector2i(320,568), Vector2i(390,844), Vector2i(844,390), Vector2i(1440,900), Vector2i(568,320)]:
		root.size = size
		shell._layout()
		await process_frame
		await process_frame
		check_visible_controls(shell, phase + " %dx%d" % [size.x, size.y])
	root.size = previous
	shell._layout()
	await process_frame
	await process_frame

func help_touch(shell, position: Vector2, pressed: bool, index: int = 0, canceled: bool = false):
	var event = InputEventScreenTouch.new()
	event.position = position; event.pressed = pressed; event.index = index; event.canceled = canceled
	shell._input(event)

func help_drag(shell, position: Vector2):
	var event = InputEventScreenDrag.new()
	event.position = position; event.index = 0
	shell._input(event)

func check_help_touch(shell):
	# Direct synthetic handler probes only. Real browser swipes and pixels
	# independently establish that the final Help paragraph can be reached.
	var previous = root.size
	root.size = Vector2i(320,568)
	shell._layout()
	await process_frame
	await process_frame
	var prose: Rect2 = shell.scroll.get_global_rect()
	var start = Vector2(prose.get_center().x, prose.end.y - 12.0)
	var bar = shell.scroll.get_v_scroll_bar()
	check(bar.max_value > bar.page, "help touch: short viewport genuinely overflows")
	shell.scroll.scroll_vertical = 0
	help_touch(shell, start, true)
	help_drag(shell, start - Vector2(0,4))
	check(shell.scroll.scroll_vertical == 0, "help touch: small movement stays within deadzone")
	help_drag(shell, start - Vector2(0,100))
	check(shell.scroll.scroll_vertical > 0, "help touch: single prose drag moves content")
	help_drag(shell, start - Vector2(0,10000))
	check(absf(shell.scroll.scroll_vertical - (bar.max_value - bar.page)) <= 1.0, "help touch: drag clamps at final content")
	await process_frame
	await process_frame
	check(shell.scroll.get_global_rect().encloses(shell.help_tail.get_global_rect()), "help touch: final paragraph fits within reading viewport")
	help_touch(shell, start, false)
	check(shell.prose_touch == -1 and shell.active_touches.is_empty(), "help touch: release clears capture")
	help_touch(shell, start, true)
	help_drag(shell, start + Vector2(0,10000))
	check(shell.scroll.scroll_vertical == 0, "help touch: reverse drag clamps at top")
	help_touch(shell, start, false, 0, true)
	help_drag(shell, start - Vector2(0,100))
	check(shell.scroll.scroll_vertical == 0 and shell.prose_touch == -1, "help touch: canceled stream cannot continue")
	help_touch(shell, start, true)
	shell._layout()
	help_drag(shell, start - Vector2(0,100))
	check(shell.scroll.scroll_vertical == 0 and shell.prose_touch == -1, "help touch: resize quarantines held drag")
	help_touch(shell, start, false)
	help_touch(shell, start, true)
	help_touch(shell, start + Vector2(10,0), true, 1)
	help_drag(shell, start - Vector2(0,100))
	check(shell.scroll.scroll_vertical == 0 and shell.prose_touch == -1, "help touch: multitouch cancels drag")
	help_touch(shell, start, false, 1)
	help_drag(shell, start - Vector2(0,100))
	check(shell.scroll.scroll_vertical == 0, "help touch: remaining finger cannot inherit canceled drag")
	help_touch(shell, start, false)
	var back = shell.buttons.get_node("BackButton").get_global_rect().get_center()
	help_touch(shell, start, true)
	help_drag(shell, back)
	help_touch(shell, back, false)
	check(shell.page == "help" and not shell.transition_busy, "help touch: prose drag onto Back cannot activate it")
	help_touch(shell, back, true)
	help_drag(shell, start - Vector2(0,100))
	check(shell.prose_touch == -1 and shell.scroll.scroll_vertical == 0, "help touch: button-origin drag cannot capture prose")
	help_touch(shell, back, false)
	help_touch(shell, Vector2(1,1), true)
	help_drag(shell, start - Vector2(0,100))
	check(shell.prose_touch == -1 and shell.scroll.scroll_vertical == 0, "help touch: outside-origin drag cannot capture prose")
	help_touch(shell, Vector2(1,1), false)
	help_touch(shell, start, true)
	shell._show_page("home"); shell._show_page("help")
	help_drag(shell, start - Vector2(0,100))
	check(shell.prose_touch == -1 and shell.scroll.scroll_vertical == 0, "help touch: page replacement cancels drag")
	help_touch(shell, start, false)
	help_touch(shell, start, true)
	shell._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	help_drag(shell, start - Vector2(0,100))
	check(shell.prose_touch == -1 and shell.scroll.scroll_vertical == 0, "help touch: focus loss cancels drag")
	help_touch(shell, start, false)
	check(shell.page == "help" and not shell.transition_busy and not is_instance_valid(shell.match_node), "help touch: scrolling never starts or leaves a match")
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
	await check_help_touch(shell)
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
	check(shell.page=="setup" and not is_instance_valid(shell.match_node), "start opens setup without world")
	await check_layout_matrix(shell, "skirmish setup")
	var saved_size=root.size
	root.size=Vector2i(568,320);shell._layout()
	await process_frame
	await process_frame
	var setup_start=shell.scroll.get_global_rect().get_center()
	help_touch(shell,setup_start,true)
	help_drag(shell,setup_start-Vector2(0,200))
	check(shell.scroll.scroll_vertical>0 and shell.page=="setup", "setup prose scrolls on short touch viewport")
	help_touch(shell,setup_start-Vector2(0,200),false)
	root.size=saved_size;shell._layout()
	await process_frame
	shell._choose_mode("pressure")
	check(shell.selected_mode=="pressure" and shell.description.text.contains("60"), "setup pressure describes actual policy")
	shell.buttons.get_node("LaunchMatchButton").pressed.emit()
	await process_frame
	await process_frame
	var game = shell.match_node
	check(is_instance_valid(game) and not shell.menu_layer.visible, "start enters match")
	check(game.skirmish_mode=="pressure", "policy installed before match ready")
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
	check(shell.page=="setup", "terminal new opens setup")
	shell._choose_mode("practice")
	shell.buttons.get_node("LaunchMatchButton").pressed.emit()
	await process_frame
	await process_frame
	check(shell.match_node != game and not shell.match_node.game_over, "new match replaces terminal game")
	check(shell.match_node.skirmish_mode=="practice", "new match uses new policy")
	shell._open_menu(); shell._show_page("setup"); shell._choose_mode("standard")
	shell.buttons.get_node("BackButton").pressed.emit()
	check(shell.match_node.skirmish_mode=="practice", "cancel setup never mutates current match")
	shell._restart_match()
	await process_frame
	await process_frame
	check(shell.match_node.skirmish_mode=="practice", "restart retains active policy not canceled selection")
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

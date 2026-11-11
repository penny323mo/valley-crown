extends Node
## Product entry point. The battlefield does not exist until Start is chosen.
## main.tscn remains the explicit battle fixture for simulation tests.
const MATCH_SCENE = preload("res://main.tscn")
var match_node
var menu_layer: CanvasLayer
var menu_root: Control
var card: PanelContainer
var heading: Label
var description: Label
var buttons: VBoxContainer
var page = "home"
var transition_busy = false
var touch_presses = {}
var active_touches = {}
var touch_blocked = false
var web_cancel_callback
var qa_callback
var qa_mode = false

func _ready():
	if OS.has_feature("web"):
		get_window().content_scale_factor = maxf(1.0, DisplayServer.screen_get_scale())
	menu_layer = CanvasLayer.new()
	menu_layer.layer = 100
	add_child(menu_layer)
	menu_root = Control.new()
	menu_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu_layer.add_child(menu_root)
	var theme = Theme.new()
	theme.default_font = load("res://assets/fonts/ui_tc.otf")
	theme.default_font_size = 17
	menu_root.theme = theme
	var background = ColorRect.new()
	background.color = Color("18231f")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu_root.add_child(background)
	card = PanelContainer.new()
	menu_root.add_child(card)
	var style = StyleBoxFlat.new()
	style.bg_color = Color("25352d")
	style.border_color = Color("ad9c70")
	style.set_border_width_all(1)
	style.set_corner_radius_all(12)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 18
	style.content_margin_bottom = 18
	card.add_theme_stylebox_override("panel", style)
	var scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	card.add_child(scroll)
	var box = VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 14)
	scroll.add_child(box)
	heading = Label.new()
	heading.add_theme_font_size_override("font_size", 26)
	heading.add_theme_color_override("font_color", Color("e1d3a8"))
	heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(heading)
	description = Label.new()
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(description)
	buttons = VBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	box.add_child(buttons)
	get_viewport().size_changed.connect(_layout)
	_layout()
	_show_page("home")
	if OS.has_feature("web"):
		web_cancel_callback = JavaScriptBridge.create_callback(func(_args): _cancel_menu_touches())
		qa_mode = JavaScriptBridge.eval("new URLSearchParams(location.search).has('qa')")
		if qa_mode:
			qa_callback = JavaScriptBridge.create_callback(_web_menu_snapshot)
			JavaScriptBridge.get_interface("window").valleyMenuSnapshot = qa_callback
		JavaScriptBridge.get_interface("window").valleyMenuTouchCancel = web_cancel_callback
		JavaScriptBridge.eval("window.valleyMenuCancelHandler=function(){if(window.valleyMenuTouchCancel){window.valleyMenuTouchCancel();}};window.addEventListener('touchcancel',window.valleyMenuCancelHandler,true);")

func _layout():
	_cancel_menu_touches()
	if not is_instance_valid(card): return
	var available = get_viewport().get_visible_rect().size
	var width = minf(520.0, maxf(1.0, available.x - 24.0))
	var height = minf(680.0, maxf(1.0, available.y - 24.0))
	card.position = Vector2((available.x - width) / 2.0, (available.y - height) / 2.0)
	card.size = Vector2(width, height)

func _add_button(label: String, id: String, action: Callable):
	var button = Button.new()
	button.name = id
	button.text = label
	button.custom_minimum_size.y = 48
	button.add_theme_font_size_override("font_size", 18)
	button.pressed.connect(action)
	# Mouse emulation is intentionally disabled by the project. Own touch
	# releases explicitly and never turn a canceled/dragged press into a click.
	button.gui_input.connect(func(event): _button_touch(button, event))
	buttons.add_child(button)

func _button_touch(button: Button, event: InputEvent):
	if event is InputEventScreenTouch:
		if event.pressed and not event.canceled and not touch_blocked and active_touches.size() == 1:
			touch_presses[event.index] = {"button": button, "origin": event.position}
		elif touch_presses.has(event.index):
			var press = touch_presses[event.index]
			touch_presses.erase(event.index)
			if not event.canceled and not touch_blocked and event.position.distance_to(press.origin) <= 12.0 and press.button == button and Rect2(Vector2.ZERO, button.size).has_point(event.position):
				button.pressed.emit()
		button.accept_event()
	elif event is InputEventScreenDrag and touch_presses.has(event.index):
		if event.position.distance_to(touch_presses[event.index].origin) > 12.0:
			touch_presses.erase(event.index)

func _show_page(next_page: String):
	page = next_page
	_cancel_menu_touches()
	for child in buttons.get_children():
		buttons.remove_child(child)
		child.queue_free()
	if page == "help":
		heading.text = "教學"
		description.text = "採集資源，建造民居與兵營，訓練士兵，探索霧谷。\n\n觸控：點選己方單位，再點空地移動、敵人攻擊。村民點樹木或漿果採集。單指平移；雙指縮放。\n\n建造：選村民→民居或兵營→選位置→確認；等待施工完成。負重送回主堡後入庫。\n\nMouse：左擊選取、右擊指令。WASD／方向鍵平移；滾輪縮放。P 暫停。\n\n開始戰役後，教學：採集、建造與出兵。"
		_add_button("返回", "BackButton", func(): _show_page("home"))
	elif page == "confirm":
		heading.text = "開始新戰役？"
		description.text = "目前戰役與教學會重新開始。關閉遊戲不會保留戰役。"
		_add_button("開始新戰役", "ConfirmNewMatchButton", _start_match)
		_add_button("保留目前戰役", "CancelNewMatchButton", func(): _show_page("home"))
	else:
		heading.text = "霧谷王旗"
		description.text = "採集、建造、出兵。\n建立聚落，探索霧谷。\n\n準備好再開始戰役。"
		if is_instance_valid(match_node):
			if not match_node.game_over:
				description.text = "目前戰役已暫停。\n按繼續返回戰場。\n\n關閉遊戲不會保留戰役。"
				_add_button("繼續戰役", "ResumeMatchButton", _resume_match)
			else:
				description.text = "戰役已結束。\n再開一局，建立新的聚落。"
			_add_button("新戰役", "NewMatchButton", func(): _show_page("confirm") if not match_node.game_over else _start_match())
		else:
			_add_button("開始戰役", "StartMatchButton", _start_match)
		_add_button("教學", "HelpButton", func(): _show_page("help"))
	call_deferred("_focus_first_button")

func _focus_first_button():
	if menu_layer.visible and buttons.get_child_count() > 0:
		buttons.get_child(0).grab_focus()

func _start_match():
	if transition_busy: return
	transition_busy = true
	# Finish the button's input dispatch before creating a live battlefield.
	call_deferred("_replace_match")

func _replace_match():
	if is_instance_valid(match_node):
		remove_child(match_node)
		match_node.queue_free()
	match_node = MATCH_SCENE.instantiate()
	match_node.main_menu_requested.connect(_open_menu)
	match_node.restart_requested.connect(_start_match)
	add_child(match_node)
	_release_menu_focus()
	menu_layer.hide()
	touch_presses.clear()
	transition_busy = false

func _open_menu():
	if not is_instance_valid(match_node) or transition_busy: return
	match_node.compact_menu.hide()
	match_node.compact_menu_dismiss.hide()
	match_node.compact_menu_button.text = "選單"
	match_node._cancel_mode()
	match_node._cancel_pointer_streams()
	match_node._quarantine_camera_keys()
	match_node.paused = true
	match_node.tick_accumulator = 0.0
	match_node._sync_audio()
	match_node.process_mode = Node.PROCESS_MODE_DISABLED
	match_node.hide()
	match_node.ui.hide()
	menu_layer.show()
	_show_page("home")

func _resume_match():
	if transition_busy or not is_instance_valid(match_node) or match_node.game_over: return
	transition_busy = true
	call_deferred("_finish_resume")

func _finish_resume():
	match_node.process_mode = Node.PROCESS_MODE_INHERIT
	match_node.show()
	match_node.ui.show()
	# Retain the game's focus/background resume guard and clear its tick debt.
	match_node._toggle_pause()
	_release_menu_focus()
	menu_layer.hide()
	touch_presses.clear()
	transition_busy = false

func _unhandled_key_input(event):
	if menu_layer.visible and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if page != "home": _show_page("home")
		get_viewport().set_input_as_handled()

func _notification(what):
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		active_touches.clear()
		_cancel_menu_touches()

func _release_menu_focus():
	var focused = get_viewport().gui_get_focus_owner()
	if is_instance_valid(focused) and menu_root.is_ancestor_of(focused): focused.release_focus()

func _exit_tree():
	if OS.has_feature("web"):
		JavaScriptBridge.eval("if(window.valleyMenuCancelHandler){window.removeEventListener('touchcancel',window.valleyMenuCancelHandler,true);delete window.valleyMenuCancelHandler;}delete window.valleyMenuTouchCancel;delete window.valleyMenuSnapshot;")
	web_cancel_callback = null
	qa_callback = null

# Read-only, opt-in geometry projection. Browser QA must click real controls.
func _web_menu_snapshot(_args):
	if not qa_mode: return
	var visible_buttons = []
	if menu_layer.visible:
		for button in buttons.get_children():
			var rect = button.get_global_rect().intersection(get_viewport().get_visible_rect())
			var parent = button.get_parent()
			while parent is Control:
				if parent.clip_contents: rect = rect.intersection(parent.get_global_rect())
				parent = parent.get_parent()
			visible_buttons.append({"id": button.name, "text": button.text, "rect": [rect.position.x, rect.position.y, rect.size.x, rect.size.y]})
	var snapshot = {"visible": menu_layer.visible, "page": page, "match_exists": is_instance_valid(match_node), "buttons": visible_buttons}
	JavaScriptBridge.eval("window.valleyMenuState=" + JSON.stringify(snapshot) + ";")

func _cancel_menu_touches():
	touch_presses.clear()
	touch_blocked = not active_touches.is_empty()

func _input(event):
	if not menu_layer or not menu_layer.visible: return
	if event is InputEventScreenTouch:
		if event.pressed:
			touch_presses.erase(event.index)
			active_touches[event.index] = true
			if active_touches.size() > 1: _cancel_menu_touches()
		else:
			active_touches.erase(event.index)
			if event.canceled: touch_presses.erase(event.index)
			if active_touches.is_empty(): touch_blocked = false

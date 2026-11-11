extends Node
## Product entry point. The battlefield does not exist until Start is chosen.
## main.tscn remains the explicit battle fixture for simulation tests.
const MATCH_SCENE = preload("res://main.tscn")
var match_node
var menu_layer: CanvasLayer
var menu_root: Control
var card: Panel
var heading: Label
var description: Label
var help_tail: Label
var buttons: VBoxContainer
var crest: TextureRect
var identity: VBoxContainer
var wordmark: Label
var latin_name: Label
var footer: Label
var scroll: ScrollContainer
var card_style: StyleBoxFlat
var backdrop_material: ShaderMaterial
var page = "home"
var transition_busy = false
var touch_presses = {}
var active_touches = {}
var touch_blocked = false
var prose_touch = -1
var prose_origin = Vector2.ZERO
var prose_scroll_origin = 0.0
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
	# One static original illustration. No world, camera, particles, or simulation.
	var background = TextureRect.new()
	background.texture = load("res://assets/mature/menu/valley_keep.png")
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_SCALE
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop_material = ShaderMaterial.new()
	backdrop_material.shader = load("res://assets/mature/menu/menu_backdrop.gdshader")
	background.material = backdrop_material
	menu_root.add_child(background)
	identity = VBoxContainer.new()
	identity.mouse_filter = Control.MOUSE_FILTER_IGNORE
	identity.add_theme_constant_override("separation", 6)
	menu_root.add_child(identity)
	crest = TextureRect.new()
	crest.texture = load("res://assets/mature/menu/valley_crown_mark.svg")
	crest.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	crest.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	crest.custom_minimum_size.y = 44
	crest.mouse_filter = Control.MOUSE_FILTER_IGNORE
	identity.add_child(crest)
	wordmark = Label.new()
	wordmark.text = "霧谷王旗"
	wordmark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	wordmark.add_theme_font_override("font", load("res://assets/fonts/menu_title_tc.otf"))
	wordmark.add_theme_color_override("font_color", Color("eee5d2"))
	wordmark.add_theme_color_override("font_shadow_color", Color(0.02, 0.025, 0.03, 0.7))
	wordmark.add_theme_constant_override("shadow_offset_y", 2)
	wordmark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	identity.add_child(wordmark)
	latin_name = Label.new()
	latin_name.text = "V A L L E Y   &   C R O W N"
	latin_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	latin_name.add_theme_font_override("font", load("res://assets/fonts/title.ttf"))
	latin_name.add_theme_font_size_override("font_size", 13)
	latin_name.add_theme_color_override("font_color", Color("c7ae7b"))
	latin_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	identity.add_child(latin_name)
	card = Panel.new()
	menu_root.add_child(card)
	card_style = StyleBoxFlat.new()
	card_style.set_corner_radius_all(2)
	card.add_theme_stylebox_override("panel", card_style)
	# The fixed panel does not inherit wrapped prose minimum sizes. Keep every
	# action in a separately bounded area, including the first layout frame.
	scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	card.add_child(scroll)
	var box = VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 16)
	scroll.add_child(box)
	heading = Label.new()
	heading.add_theme_font_size_override("font_size", 28)
	heading.add_theme_color_override("font_color", Color("eee5d2"))
	heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(heading)
	description = Label.new()
	description.add_theme_color_override("font_color", Color("ded9ce"))
	description.add_theme_constant_override("line_spacing", 5)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(description)
	help_tail = Label.new()
	help_tail.text = "開始戰役後，教學：採集、建造與出兵。"
	help_tail.add_theme_color_override("font_color", Color("ded9ce"))
	help_tail.add_theme_constant_override("line_spacing", 5)
	help_tail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(help_tail)
	buttons = VBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	card.add_child(buttons)
	footer = Label.new()
	footer.text = "關閉遊戲不會保留戰役。"
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer.add_theme_font_size_override("font_size", 13)
	footer.add_theme_color_override("font_color", Color("b8b8ae"))
	card.add_child(footer)
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
	var wide = available.x >= 640.0 and available.x > available.y * 1.15
	var short_landscape = available.x > available.y and available.y < 500.0
	var margin = 28.0 if available.x >= 360.0 else 20.0
	var width = minf(390.0 if wide else 440.0, maxf(1.0, available.x - margin * 2.0))
	var x = maxf(32.0, available.x * 0.075) if wide else (available.x - width) * 0.5
	var home = page == "home"
	identity.visible = home
	crest.visible = not wide and not short_landscape
	latin_name.visible = not wide and not short_landscape
	heading.visible = not home
	help_tail.visible = page == "help"
	footer.visible = home
	description.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if home else HORIZONTAL_ALIGNMENT_LEFT
	backdrop_material.set_shader_parameter("landscape", wide)
	backdrop_material.set_shader_parameter("view_size", available)
	backdrop_material.set_shader_parameter("inner_page", not home)
	# Update the font minimum before resetting the container size. Otherwise
	# a previous larger font can leave empty identity bounds over the prose.
	wordmark.add_theme_font_size_override("font_size", 32 if short_landscape else (40 if wide else (46 if width >= 330.0 else 38)))
	identity.position = Vector2(x, 18.0 if short_landscape else clampf(available.y * 0.065, 24.0, 60.0))
	identity.size = Vector2(width, 0)
	var height: float
	if home:
		card_style.bg_color = Color(0, 0, 0, 0)
		card_style.set_border_width_all(0)
		card_style.set_content_margin_all(0)
		scroll.custom_minimum_size.y = 56
		height = 54.0 * buttons.get_child_count() + 10.0 * max(0, buttons.get_child_count() - 1) + 104.0
	else:
		card_style.bg_color = Color(0.055, 0.075, 0.083, 0.96)
		card_style.border_color = Color("76674d")
		card_style.set_border_width_all(1)
		card_style.set_content_margin_all(20)
		scroll.custom_minimum_size.y = 0
		height = minf(640.0, maxf(1.0, available.y - 48.0))
		width = minf(560.0, maxf(1.0, available.x - margin * 2.0))
		x = (available.x - width) * 0.5
	var y = available.y - height - 28.0 if home else (available.y - height) * 0.5
	card.position = Vector2(x, maxf(16.0, y))
	card.size = Vector2(width, height)
	# A paused match needs three full-size actions. In a 320px-tall viewport
	# its pause message takes priority over a repeated decorative wordmark.
	identity.visible = home and (not short_landscape or identity.get_global_rect().end.y + 12.0 <= card.position.y)
	# Layout authority belongs to the viewport, not deferred content minima.
	var inset = 0.0 if home else 20.0
	var content_width = maxf(1.0, width - inset * 2.0)
	var actions_height = 54.0 * buttons.get_child_count() + 10.0 * max(0, buttons.get_child_count() - 1)
	var actions_y = height - inset - actions_height - (34.0 if home else 0.0)
	buttons.position = Vector2(inset, actions_y)
	buttons.size = Vector2(content_width, actions_height)
	scroll.position = Vector2(inset, inset)
	scroll.size = Vector2(content_width, maxf(1.0, actions_y - inset - 14.0))
	footer.position = Vector2(inset, height - 20.0)
	footer.size = Vector2(content_width, 20.0)

func _button_style(fill: Color, border: Color) -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(2)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	return style

func _add_button(label: String, id: String, action: Callable):
	var button = Button.new()
	button.name = id
	button.text = label
	button.custom_minimum_size.y = 54
	button.add_theme_font_size_override("font_size", 18)
	var primary = buttons.get_child_count() == 0 and id != "BackButton" and id != "HelpButton"
	if primary:
		button.add_theme_stylebox_override("normal", _button_style(Color("c4aa78"), Color("ddc593")))
		button.add_theme_stylebox_override("hover", _button_style(Color("d7bd8b"), Color("f0ddae")))
		button.add_theme_stylebox_override("pressed", _button_style(Color("aa8d59"), Color("dec18a")))
		for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			button.add_theme_color_override(state, Color("141c20"))
	else:
		button.add_theme_stylebox_override("normal", _button_style(Color("151e22"), Color("756b57")))
		button.add_theme_stylebox_override("hover", _button_style(Color("263136"), Color("c4aa78")))
		button.add_theme_stylebox_override("pressed", _button_style(Color("0d1519"), Color("c4aa78")))
		for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			button.add_theme_color_override(state, Color("eae3d5"))
	var focus = StyleBoxFlat.new()
	focus.bg_color = Color(0, 0, 0, 0)
	focus.border_color = Color("f4e6bf")
	focus.set_border_width_all(2)
	focus.set_expand_margin_all(3)
	focus.set_corner_radius_all(2)
	button.add_theme_stylebox_override("focus", focus)
	button.pressed.connect(action)
	# Keep tested cancellation, drag, resize and multi-touch handling unchanged.
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
	scroll.scroll_vertical = 0
	for child in buttons.get_children():
		buttons.remove_child(child)
		child.queue_free()
	if page == "help":
		heading.text = "教學"
		description.text = "採集資源，建造民居與兵營，訓練士兵，探索霧谷。\n\n觸控：點選己方單位，再點空地移動、敵人攻擊。村民點樹木或漿果採集。單指平移；雙指縮放。\n\n建造：選村民→民居或兵營→選位置→確認；等待施工完成。負重送回主堡後入庫。\n\nMouse：左擊選取、右擊指令。WASD／方向鍵平移；滾輪縮放。P 暫停。"
		_add_button("返回", "BackButton", func(): _show_page("home"))
	elif page == "confirm":
		heading.text = "開始新戰役？"
		description.text = "目前戰役與教學會重新開始。關閉遊戲不會保留戰役。"
		_add_button("開始新戰役", "ConfirmNewMatchButton", _start_match)
		_add_button("保留目前戰役", "CancelNewMatchButton", func(): _show_page("home"))
	else:
		heading.text = "霧谷王旗"
		description.text = "建立聚落，探索霧谷。"
		if is_instance_valid(match_node):
			if not match_node.game_over:
				description.text = "目前戰役已暫停。\n按繼續返回戰場。"
				_add_button("繼續戰役", "ResumeMatchButton", _resume_match)
			else:
				description.text = "戰役已結束。\n再開一局，建立新的聚落。"
			_add_button("新戰役", "NewMatchButton", func(): _show_page("confirm") if not match_node.game_over else _start_match())
		else:
			_add_button("開始戰役", "StartMatchButton", _start_match)
		_add_button("教學", "HelpButton", func(): _show_page("help"))
	_layout()
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
	prose_touch = -1
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
	if menu_layer.visible and page == "help":
		var bar = scroll.get_v_scroll_bar()
		var tail = help_tail.get_global_rect()
		var clipped = tail.intersection(scroll.get_global_rect()).intersection(get_viewport().get_visible_rect())
		snapshot["help_scroll"] = {"value": bar.value, "maximum": bar.max_value, "page": bar.page, "final_rect": [tail.position.x, tail.position.y, tail.size.x, tail.size.y], "final_visible_rect": [clipped.position.x, clipped.position.y, clipped.size.x, clipped.size.y], "final_text": help_tail.text}
	JavaScriptBridge.eval("window.valleyMenuState=" + JSON.stringify(snapshot) + ";")

func _cancel_menu_touches():
	touch_presses.clear()
	prose_touch = -1
	touch_blocked = not active_touches.is_empty()

func _help_touch(event: InputEvent) -> bool:
	# Native ScrollContainer dragging uses mouse events. Keep the game's
	# mouse-from-touch emulation disabled and own only this reading area.
	if page != "help": return false
	if event is InputEventScreenTouch:
		if event.pressed:
			if event.canceled or touch_blocked or active_touches.size() != 1: return false
			var prose_rect = scroll.get_global_rect()
			var bar = scroll.get_v_scroll_bar()
			if not prose_rect.has_point(event.position) or (bar.visible and bar.get_global_rect().has_point(event.position)): return false
			prose_touch = event.index
			prose_origin = event.position
			prose_scroll_origin = scroll.scroll_vertical
			return true
		elif event.index == prose_touch:
			prose_touch = -1
			return true
	elif event is InputEventScreenDrag and event.index == prose_touch:
		if touch_blocked or active_touches.size() != 1:
			prose_touch = -1
			return false
		var distance = prose_origin.y - event.position.y
		if absf(distance) >= 8.0:
			var bar = scroll.get_v_scroll_bar()
			scroll.scroll_vertical = roundi(clampf(prose_scroll_origin + distance, bar.min_value, maxf(bar.min_value, bar.max_value - bar.page)))
		return true
	return false

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
	if _help_touch(event): get_viewport().set_input_as_handled()

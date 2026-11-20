extends Node
## Product entry point. The battlefield does not exist until Start is chosen.
## main.tscn remains the explicit battle fixture for simulation tests.
const ExpeditionCheckpointStore=preload("res://scripts/expedition_checkpoint_store.gd")
const CheckpointStore=preload("res://scripts/checkpoint_store.gd")
const CheckpointBackups=preload("res://scripts/checkpoint_backups.gd")
const CheckpointRestore=preload("res://scripts/checkpoint_restore.gd")
const BattlefieldLayout=preload("res://scripts/battlefield_layout.gd")
var selected_layout="valley"
var battlefield_preview
const BattleSelection=preload("res://scripts/battle_selection.gd")
var battle_group=0
const CampaignProgress=preload("res://scripts/campaign_progress.gd")
var campaign_progress_path=CampaignProgress.PATH
var campaign_storage={}
var campaign_expected={}
var campaign_unlocked=0
var selected_campaign=-1
var restart_campaign_on_launch=false
var replay_campaign_on_launch=false
var live_campaign_replay=false
var campaign_notice=""
const Rules=preload("res://scripts/rules.gd")
var checkpoint_path=CheckpointStore.PATH
var expedition_checkpoint_path=ExpeditionCheckpointStore.PATH
var checkpoint_status=""
const AutoCheckpoint=preload("res://scripts/auto_checkpoint.gd")
var auto_checkpoint_path=AutoCheckpoint.PATH
var auto_checkpoint_enabled=false
var auto_checkpoint_status=""
var auto_checkpoint_last_attempt=""
var auto_checkpoint_pending=""
var auto_checkpoint_writes=0
var backup_name=""
var backup_expedition=false
var backup_info={}
var backup_index=0
const MATCH_SCENE = preload("res://main.tscn")
const ModelCatalogue=preload("res://scripts/model_catalogue.gd")
var manual_preview
const FieldManual=preload("res://scripts/field_manual.gd")
const BattleHistory=preload("res://scripts/battle_history.gd")
var history_path=BattleHistory.PATH
var history_index=0
var history_page=0
var manual_section=0
var manual_index=0
var manual_back_page="help"
const SkirmishPolicy=preload("res://scripts/skirmish_policy.gd")
var selected_mode="standard"
const AIDifficulty=preload("res://scripts/ai_difficulty.gd")
var selected_difficulty="standard"
var selected_victory_mode="conquest"
var match_node
var menu_layer: CanvasLayer
var menu_root: Control
var card: Panel
var heading: Label
var description: Label
var help_tail: Label
var buttons: GridContainer
var crest: TextureRect
var identity: VBoxContainer
var wordmark: Label
var latin_name: Label
var footer: Label
var scroll: ScrollContainer
var prose_stack: VBoxContainer
var short_setup_map: Label
var short_setup_goal: Label
var setup_split_active=false
var setup_original_description=""
var card_style: StyleBoxFlat
var backdrop_material: ShaderMaterial
var eyebrow: Label
var section_rule: Panel
var mode_title: Label
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
	campaign_storage=CampaignProgress.read(campaign_progress_path)
	if campaign_storage.ok:campaign_unlocked=campaign_storage.completed
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
	identity.add_theme_constant_override("separation", 10)
	menu_root.add_child(identity)
	crest = TextureRect.new()
	crest.texture = load("res://assets/mature/menu/valley_crown_mark.svg")
	crest.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	crest.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	crest.custom_minimum_size.y = 44
	crest.mouse_filter = Control.MOUSE_FILTER_IGNORE
	identity.add_child(crest)
	crest.visible = false
	wordmark = Label.new()
	wordmark.text = "霧谷王旗"
	wordmark.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	wordmark.add_theme_font_override("font", load("res://assets/fonts/menu_title_tc.otf"))
	wordmark.add_theme_color_override("font_color", Color("eee5d2"))
	wordmark.add_theme_color_override("font_shadow_color", Color(0.02, 0.025, 0.03, 0.7))
	wordmark.add_theme_constant_override("shadow_offset_y", 2)
	wordmark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	identity.add_child(wordmark)
	latin_name = Label.new()
	latin_name.text = "V A L L E Y   /   C R O W N"
	latin_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	latin_name.add_theme_font_override("font", load("res://assets/fonts/title.ttf"))
	latin_name.add_theme_font_size_override("font_size", 13)
	latin_name.add_theme_color_override("font_color", Color("c7ae7b"))
	latin_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	identity.add_child(latin_name)
	card = Panel.new()
	menu_root.add_child(card)
	card_style = StyleBoxFlat.new()
	card_style.set_corner_radius_all(0)
	card.add_theme_stylebox_override("panel", card_style)
	# The fixed panel does not inherit wrapped prose minimum sizes. Keep every
	# action in a separately bounded area, including the first layout frame.
	scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	card.add_child(scroll)
	var box = VBoxContainer.new()
	prose_stack=box
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 14)
	eyebrow = Label.new()
	eyebrow.add_theme_font_size_override("font_size", 12)
	eyebrow.add_theme_color_override("font_color", Color("c7ae7b"))
	box.add_child(eyebrow)
	scroll.add_child(box)
	heading = Label.new()
	heading.add_theme_font_size_override("font_size", 28)
	heading.add_theme_color_override("font_color", Color("eee5d2"))
	heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(heading)
	section_rule = Panel.new()
	section_rule.custom_minimum_size.y = 2
	section_rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rule = StyleBoxFlat.new()
	rule.bg_color = Color("b89a65")
	section_rule.add_theme_stylebox_override("panel", rule)
	box.add_child(section_rule)
	mode_title = Label.new()
	mode_title.add_theme_font_size_override("font_size", 24)
	mode_title.add_theme_color_override("font_color", Color("f2e9d7"))
	mode_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(mode_title)
	short_setup_map=Label.new()
	short_setup_map.add_theme_font_size_override("font_size",15)
	short_setup_map.add_theme_color_override("font_color",Color("c7ae7b"))
	short_setup_map.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	short_setup_map.hide()
	box.add_child(short_setup_map)
	short_setup_goal=Label.new()
	short_setup_goal.add_theme_font_size_override("font_size",16)
	short_setup_goal.add_theme_color_override("font_color",Color("f2e9d7"))
	short_setup_goal.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	short_setup_goal.hide()
	box.add_child(short_setup_goal)
	manual_preview=ModelCatalogue.new()
	box.add_child(manual_preview)
	manual_preview.hide()
	battlefield_preview=preload("res://scripts/battlefield_preview.gd").new()
	box.add_child(battlefield_preview);battlefield_preview.hide()
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
	buttons = GridContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	card.add_child(buttons)
	footer = Label.new()
	footer.text = "關閉前請確認存檔成功。"
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
	var wide = available.x >= 900.0 and available.x > available.y * 1.15
	var short_landscape = available.x > available.y and available.y < 500.0
	var split=page=="setup" and short_landscape and available.x>=568 and available.y>=320 and buttons.get_child_count()<=5
	var changed_split=setup_split_active!=split
	setup_split_active=split
	short_setup_map.visible=split
	short_setup_goal.visible=split
	if page=="setup":
		var duplicate_line=short_setup_map.text+"\n"
		description.text=setup_original_description.replace(duplicate_line,"") if split else setup_original_description
	battlefield_preview.set_compact_setup(split)
	prose_stack.add_theme_constant_override("separation",8 if split else 14)
	mode_title.add_theme_font_size_override("font_size",21 if split else 24)
	var margin = 24.0 if available.x >= 360.0 else 16.0
	var home = page == "home"
	var home_auto=home and (not auto_checkpoint_status.is_empty() or FileAccess.file_exists(auto_checkpoint_path))
	var width = minf(410.0 if wide else 440.0, available.x - margin * 2.0)
	var x = available.x * 0.08 if wide else (available.x - width) * 0.5
	crest.visible = false
	latin_name.visible = not short_landscape
	heading.visible = not home
	mode_title.visible = page == "setup"
	mode_title.text = "資源爭奪戰" if selected_victory_mode=="supply" else ("中央據點爭奪" if selected_victory_mode=="control" else SkirmishPolicy.title(selected_mode))
	eyebrow.text = "THE BORDERLANDS  /  01" if home else ("SKIRMISH  /  01" if page == "setup" else "FIELD MANUAL" if page in ["help","manual","history"] else "NEW CAMPAIGN")
	section_rule.visible = true
	help_tail.visible = page == "help"
	footer.visible = home
	description.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	backdrop_material.set_shader_parameter("landscape", wide)
	backdrop_material.set_shader_parameter("view_size", available)
	backdrop_material.set_shader_parameter("inner_page", not home)
	wordmark.add_theme_font_size_override("font_size", 34 if short_landscape else (60 if wide else 44))
	# Measure the current labels, not the VBox's previous-frame rectangle.
	# On desktop -> portrait resize that rectangle still held the 60px title
	# and the old visibility guard incorrectly hid the entire identity.
	var identity_height = wordmark.get_combined_minimum_size().y
	if latin_name.visible:
		identity_height += latin_name.get_combined_minimum_size().y + 10.0
	identity.size = Vector2(width, identity_height)
	buttons.columns=3 if page=="manual" else (2 if short_landscape and buttons.get_child_count()>3 and (home or page in ["checkpoint","checkpoint_backup_slot","battle_groups","battle_options","campaign","setup","help"]) else 1)
	if split:buttons.columns=1
	var button_height=54.0
	if is_instance_valid(manual_preview):manual_preview.custom_minimum_size.y=160.0 if short_landscape else 230.0
	var button_gap=(4 if available.y<358 else 6) if split else 10
	buttons.add_theme_constant_override("v_separation",button_gap)
	buttons.add_theme_constant_override("h_separation",6)
	for button in buttons.get_children():
		button.custom_minimum_size.y=button_height
		if page!="manual":
			button.add_theme_font_size_override("font_size",16 if split else 18)
			button.size_flags_horizontal=Control.SIZE_EXPAND_FILL if split else Control.SIZE_FILL
	var action_rows=ceili(float(buttons.get_child_count())/buttons.columns)
	var actions_height = button_height * action_rows + button_gap * max(0, action_rows - 1)
	var height: float
	var y: float
	if home:
		height = actions_height + ((100.0 if home_auto else 48.0) if short_landscape and buttons.get_child_count()>3 else (104.0 if short_landscape else (100.0 if buttons.get_child_count()>4 else 144.0)))
		y = minf(available.y - height - 28.0, available.y * 0.49) if not short_landscape else available.y - height - 16.0
		y = maxf(16.0, y)
		identity.position = Vector2(x, maxf(14.0, y - identity_height - 24.0))
		card_style.bg_color = Color(0, 0, 0, 0)
		card_style.set_border_width_all(0)
		card_style.set_content_margin_all(0)
		scroll.custom_minimum_size.y = 0
	else:
		width = minf(760.0,available.x-32.0) if split else minf(520.0, available.x - margin * 2.0)
		x = (available.x - width) * 0.5 if split else (available.x * 0.08 if wide else (available.x - width) * 0.5)
		height = minf(650.0, available.y - (16.0 if split and available.y<358 else 32.0))
		y = (available.y - height) * 0.5
		card_style.bg_color = Color(0.045, 0.06, 0.064, 0.94)
		card_style.border_color = Color("5f5745")
		card_style.set_border_width_all(1)
		card_style.border_width_top = 3
		card_style.set_content_margin_all(22)
		scroll.custom_minimum_size.y = 0
	card.position = Vector2(x, y)
	card.size = Vector2(width, height)
	identity.visible = home and identity.position.y + identity_height + 16.0 <= card.position.y
	var inset = 0.0 if home else (16.0 if split else 22.0)
	var content_width = maxf(1.0, width - inset * 2.0)
	var actions_y = height - inset - actions_height - (34.0 if home else 0.0)
	buttons.position = Vector2(inset, actions_y)
	buttons.size = Vector2(content_width, actions_height)
	scroll.position = Vector2(inset, inset)
	scroll.size = Vector2(content_width, maxf(1.0, actions_y - inset - 14.0))
	if split:
		var rail_width=198.0
		for button in buttons.get_children():rail_width=maxf(rail_width,button.get_combined_minimum_size().x)
		rail_width=minf(maxf(rail_width,content_width*0.35),content_width-190.0)
		var gap=16.0
		var prose_width=content_width-rail_width-gap
		var rail_inset=8.0 if available.y<358 else inset
		scroll.position=Vector2(inset,rail_inset)
		scroll.size=Vector2(prose_width,height-2.0*rail_inset)
		buttons.position=Vector2(inset+prose_width+gap,rail_inset)
		buttons.size=Vector2(rail_width,actions_height)
		heading.add_theme_font_size_override("font_size",22)
		if changed_split:scroll.scroll_vertical=0
	elif page=="manual" and short_landscape:
		heading.add_theme_font_size_override("font_size",22)
		manual_preview.custom_minimum_size.y=maxf(100.0,minf(160.0,scroll.size.y-64.0))
	else:heading.add_theme_font_size_override("font_size",28)
	footer.position = Vector2(inset, height - 20.0)
	footer.size = Vector2(content_width, 20.0)

func _button_style(fill: Color, border: Color) -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(0)
	style.content_margin_left = 20
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
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	var primary = id in ["StartMatchButton", "LaunchMatchButton", "ResumeMatchButton", "ConfirmNewMatchButton", "MatchReportButton"]
	if primary:
		var primary_style = _button_style(Color("263b3b"), Color("b89a65"))
		primary_style.border_width_left = 4
		button.add_theme_stylebox_override("normal", primary_style)
		button.add_theme_stylebox_override("hover", _button_style(Color("385251"), Color("e0c28b")))
		button.add_theme_stylebox_override("pressed", _button_style(Color("192a2c"), Color("dec18a")))
		for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			button.add_theme_color_override(state, Color("f2e9d7"))
	else:
		button.add_theme_stylebox_override("normal", _button_style(Color(0.06, 0.08, 0.085, 0.66), Color("58574c")))
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
	if page=="manual":
		button.add_theme_font_size_override("font_size",14)
		button.alignment=HORIZONTAL_ALIGNMENT_CENTER
		button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		for state in ["normal","hover","pressed"]:
			var style=button.get_theme_stylebox(state).duplicate()
			style.content_margin_left=8;style.content_margin_right=8
			button.add_theme_stylebox_override(state,style)
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
	if next_page in ["home","battle_groups","campaign"]:
		selected_campaign=-1;restart_campaign_on_launch=false;replay_campaign_on_launch=false
	if next_page=="manual" and page!="manual":manual_back_page="home" if page=="home" else "help"
	if is_instance_valid(manual_preview):manual_preview.clear_model();manual_preview.hide()
	if is_instance_valid(battlefield_preview):battlefield_preview.hide()
	page = next_page
	_cancel_menu_touches()
	scroll.scroll_vertical = 0
	for child in buttons.get_children():
		buttons.remove_child(child)
		child.queue_free()
	if page == "help":
		heading.text = "教學"
		description.text = "採集資源，建造民居與兵營，訓練士兵，探索霧谷。\n\n觸控：點選己方單位，再點空地移動、敵人攻擊。村民點樹木或漿果採集。單指拖曳框選；雙指移鏡／縮放。\n\n建造：選村民→民居或兵營→選位置→確認；等待施工完成。負重送回主堡後入庫。\n\nMouse：左擊選取，再點空地移動或敵軍攻擊；右擊亦可指令。WASD／方向鍵平移；滾輪縮放。P 暫停。"
		_add_button("設定引導練習", "GuidedPracticeButton", func(): _show_page("tutorial_confirm") if is_instance_valid(match_node) and not match_node.game_over else _choose_battle("practice"))
		description.text+="\n\n引導練習：正常採集、付費建造與訓練；電腦不主動遠征，靠近仍會交戰。"
		if is_instance_valid(match_node) and not match_node.game_over and match_node.skirmish_mode not in ["battle","fortress","survival","expedition","escort","breach","depot"]:
			_add_button("恢復本局引導", "ResumeTutorialButton", func(): match_node._resume_tutorial();_show_page("help"))
			description.text+="\n本局引導："+("已收起" if match_node.demo_tutorial.skipped else "顯示中")+"；恢復保留已完成步驟，不重開戰役。"
		_add_button("戰場手冊", "FieldManualButton", func(): _show_page("manual"))
		_add_button("本機戰績", "BattleHistoryButton", func(): _show_page("history"))
		_add_button("返回", "BackButton", func(): _show_page("home"))
	elif page == "history":
		var stored=BattleHistory.read_history(history_path)
		heading.text="本機戰績"
		description.text="保留最近十場已完成戰役；只存於此裝置／瀏覽器。無痕模式或清除網站資料可能移除紀錄，不會跨裝置同步。未完成戰役不能讀檔續玩。\n\n"
		if not stored.ok:description.text+=stored.get("reason","無法讀取戰績")
		elif stored.entries.is_empty():description.text+="尚無已完成戰役。戰役結束後會自動記錄。"
		else:
			history_index=posmod(history_index,stored.entries.size())
			var entry=stored.entries[history_index]
			var titles=["總覽","經濟","軍隊","建設"]
			var outcome_title={"victory":"勝利","defeat":"失敗","draw":"和局"}[entry.outcome]
			heading.text="%s · %d/%d" % [outcome_title,history_index+1,stored.entries.size()]
			description.text+=entry.saved_at+" · "+entry.build+"\n\n"+entry.pages[BattleHistory.PAGES[history_page]]
			_add_button("分頁："+titles[history_page]+" >", "HistoryPageButton", func(): history_page=(history_page+1)%4;_show_page("history"))
			_add_button("較早戰役 >", "HistoryNextButton", func(): history_index=(history_index+1)%stored.entries.size();history_page=0;_show_page("history"))
		_add_button("返回教學", "HistoryBackButton", func(): _show_page("help"))
	elif page == "manual":
		var item=FieldManual.entry(manual_section,manual_index)
		heading.text="%s · %s  %d/%d" % [FieldManual.SECTIONS[manual_section],item.title,item.index+1,item.count]
		description.text=item.body
		if manual_section in [0,1]:
			manual_preview.show()
			manual_preview.show_model(item.kind)
		_add_button(FieldManual.SECTIONS[manual_section]+" >", "ManualSectionButton", func(): manual_section=(manual_section+1)%3;manual_index=0;_show_page("manual"))
		_add_button("下一項 >", "ManualNextButton", func(): manual_index=(manual_index+1)%FieldManual.entries(manual_section).size();_show_page("manual"))
		_add_button("返回", "ManualBackButton", func(): _show_page(manual_back_page))
	elif page == "campaign":
		heading.text=BattleSelection.CAMPAIGN_TITLE
		description.text="三場連戰 · 已完成 %d / 3\n各場重新開局，資源與軍隊不帶到下一場。\n%s\n\n" % [campaign_unlocked,_campaign_storage_label()]
		if not campaign_notice.is_empty():description.text=campaign_notice+"\n\n"+description.text
		for i in BattleSelection.CAMPAIGN.size():
			var chapter=BattleSelection.option(BattleSelection.CAMPAIGN[i])
			var status="已完成" if i<campaign_unlocked else ("可出征" if i==campaign_unlocked else "先完成上一場")
			description.text+="第 %d 場 · %s · %s\n%s\n\n" % [i+1,chapter.title,status,BattleSelection.CAMPAIGN_BLURBS[i]]
		if campaign_unlocked<BattleSelection.CAMPAIGN.size():_add_button("查看第 %d 場" % (campaign_unlocked+1),"CampaignChapterButton",func():_choose_campaign(campaign_unlocked))
		if campaign_unlocked>0:
			_add_button("重玩第一場（保留進度）","ReplayCampaignButton",func():_choose_campaign(0,false,true))
			if campaign_storage.ok:_add_button("清除進度並重開","RestartCampaignButton",func():_choose_campaign(0,true))
		_add_button("返回主選單","CampaignBackButton",func():_show_page("battle_groups"))
	elif page == "battle_groups":
		heading.text="選擇戰役"
		description.text="先選對戰方式，再查看開局、敵軍與取勝條件。只有出征才會開始新戰役。"
		for index in BattleSelection.GROUPS.size():
			_add_button(BattleSelection.GROUPS[index],"BattleGroup"+str(index),func(): battle_group=index;_show_page("battle_options"))
		if not is_instance_valid(match_node) or match_node.game_over:
			_add_button(BattleSelection.CAMPAIGN_TITLE,"CampaignMenuButton",func():_show_page("campaign"))
		_add_button("返回主選單","BattleGroupsBackButton",func(): _show_page("home"))
	elif page == "battle_options":
		heading.text=BattleSelection.GROUPS[battle_group]
		description.text="選擇後先查看戰役設定，不會立即開始。"
		for item in BattleSelection.OPTIONS:
			if item.group==battle_group:_add_button(item.title,"ChooseBattle_"+item.id,func(): _choose_battle(item.id))
		_add_button("返回分類","BattleOptionsBackButton",func(): _show_page("battle_groups"))
	elif page == "setup":
		heading.text = "戰役設定"
		selected_difficulty=AIDifficulty.valid_for(selected_mode,selected_victory_mode,selected_difficulty)
		selected_layout=BattlefieldLayout.valid(selected_layout) if BattlefieldLayout.supported(selected_mode,selected_victory_mode) else "valley"
		if BattlefieldLayout.supported(selected_mode,selected_victory_mode):
			battlefield_preview.configure(selected_layout);battlefield_preview.show()
		short_setup_map.text="戰場："+BattlefieldLayout.title(selected_layout)
		short_setup_goal.text="勝利："+BattleSelection.briefing_sections(selected_mode,selected_victory_mode,selected_difficulty).win
		description.text="戰場："+BattlefieldLayout.title(selected_layout)+"\n"+BattlefieldLayout.details(selected_layout)+"\n\n"+BattleSelection.briefing(selected_mode,selected_victory_mode,selected_difficulty)
		if AIDifficulty.supported(selected_mode,selected_victory_mode):
			description.text+="\n\n電腦難度："+AIDifficulty.title(selected_difficulty)
			_add_button("電腦難度："+AIDifficulty.title(selected_difficulty),"ChooseDifficultyButton",func():_show_page("difficulty"))
		if BattlefieldLayout.supported(selected_mode,selected_victory_mode):_add_button("選擇戰場", "ChooseLayoutButton", func(): _show_page("battlefield"))
		if selected_campaign>=0:
			heading.text="霧谷戰役 · 第 %d / 3 場" % (selected_campaign+1)
			description.text=BattleSelection.CAMPAIGN_BLURBS[selected_campaign]+"\n"+_campaign_briefing_line()+"\n\n"+description.text
			if restart_campaign_on_launch:
				heading.text="清除戰役進度？"
				short_setup_goal.text="清除已完成場次，並重新開始第一場"
			elif replay_campaign_on_launch:heading.text="重玩第一場 · 保留進度"
		else:_add_button("選擇其他戰役", "ChooseBattleButton", func(): _show_page("battle_groups"))
		_add_button("清除進度並出征" if restart_campaign_on_launch else "出征", "LaunchMatchButton", _start_match)
		_add_button("返回", "BackButton", func(): _show_page("campaign" if selected_campaign>=0 else "home"))
		setup_original_description=description.text
	elif page == "difficulty":
		heading.text="電腦難度"
		description.text="只適用於標準戰役。\n\n"+AIDifficulty.title("easy")+"\n"+AIDifficulty.details("easy")+"\n\n標準\n"+AIDifficulty.details("standard")
		_add_button("較低襲擊壓力","DifficultyEasyButton",func():selected_difficulty="easy";_show_page("setup"))
		_add_button("標準","DifficultyStandardButton",func():selected_difficulty="standard";_show_page("setup"))
		_add_button("返回","DifficultyBackButton",func():_show_page("setup"))
	elif page == "battlefield":
		heading.text="選擇戰場"
		description.text="經典谷地：保留原有開局與資源布局。\n\n雙翼林地：中場林帶與兩翼資源路線；樹木仍可正常砍伐，空地仍可自由建造。\n\n前線鐵谷：中央短路可爭前線鐵礦，兩翼可繞行並採糧石；基地附近礦區及資源總量不變。\n\n雙渡河谷：在木橋或淺灘過河，借兩翼前置資源開闢攻勢。河水不通行。\n\n不贈送資源或軍隊；普通對戰 AI、視野與付費規則不變。"
		_add_button("經典谷地", "LayoutValleyButton", func(): selected_layout="valley";_show_page("setup"))
		_add_button("雙翼林地", "LayoutWoodlandButton", func(): selected_layout="woodland";_show_page("setup"))
		_add_button("前線鐵谷", "LayoutIronCrossroadsButton", func(): selected_layout="iron_crossroads";_show_page("setup"))
		_add_button("雙渡河谷", "LayoutRiverCrossingsButton", func(): selected_layout=BattlefieldLayout.River.ID;_show_page("setup"))
		_add_button("返回", "LayoutBackButton", func(): _show_page("setup"))
	elif page == "checkpoint":
		heading.text="本機戰役存檔"
		description.text=checkpoint_status+"\n\n普通戰役與遠征各保留一個本機存檔，再次儲存只取代同類存檔。不相容的舊存檔會先保留本機備存，備存失敗就不會覆寫。備存不等於跨版本可讀，仍只支援相同遊戲版本。讀取後保持暫停，不計離線時間。瀏覽器清除資料或私密模式可能令存檔消失；不會跨裝置同步。"
		if is_instance_valid(match_node) and match_node.skirmish_mode in ["escort","breach","depot"]:
			description.text=SkirmishPolicy.title(match_node.skirmish_mode)+"暫不支援存檔；普通戰役與遠征存檔不變。\n\n"+description.text
		if is_instance_valid(match_node) and match_node.skirmish_mode=="expedition":
			description.text="遠征使用分開存檔，普通戰役存檔不變。\n\n"+description.text
		# The generic checkpoint view also accepts lightweight noncampaign matches.
		var chapter=match_node.get("campaign_chapter") if is_instance_valid(match_node) else null
		if chapter is int and chapter>=0:
			description.text="霧谷戰役只保留本次遊戲進度，不寫入存檔。\n\n"+description.text
		elif is_instance_valid(match_node) and not match_node.game_over and match_node.skirmish_mode not in ["escort","breach","depot"]:
			_add_button("儲存目前戰役", "SaveCheckpointButton", _save_checkpoint)
		if FileAccess.file_exists(checkpoint_path):
			_add_button("讀取存檔（取代目前戰役）", "LoadCheckpointButton", _load_checkpoint)
		if FileAccess.file_exists(expedition_checkpoint_path):
			_add_button("讀取遠征存檔（取代目前戰役）", "LoadExpeditionCheckpointButton", func(): _load_checkpoint(true))
		_add_button("自動備存設定", "AutoCheckpointSettingsButton", func():_show_page("auto_checkpoint"))
		_add_button("本機備存", "CheckpointBackupsButton", func(): _show_page("checkpoint_backups"))
		_add_button("返回", "CheckpointBackButton", func(): _show_page("home"))
	elif page == "auto_checkpoint":
		heading.text="自動備存"
		description.text="\n\n自動備存："+("本次開啟" if auto_checkpoint_enabled else "關閉")+"。只於正常暫停時保存普通戰役至獨立槽，不覆蓋手動存檔；重新開啟遊戲後預設關閉。強制關閉前未必能保存，只支援相同版本。\n"+auto_checkpoint_status
		if FileAccess.file_exists(auto_checkpoint_path):description.text+="\n"+_auto_slot_summary()
		_add_button("關閉自動備存" if auto_checkpoint_enabled else "本次開啟自動備存", "ToggleAutoCheckpointButton", _toggle_auto_checkpoint)
		if FileAccess.file_exists(auto_checkpoint_path):
			_add_button("讀取自動備存（取代本局）", "LoadAutoCheckpointButton", _load_auto_checkpoint)
		_add_button("返回存檔", "AutoCheckpointBackButton", func():_show_page("checkpoint"))
	elif page == "checkpoint_backups":
		heading.text="本機備存"
		description.text=checkpoint_status+"\n\n保留已儲存進度，不是目前未儲存戰役。相同版本同類備存可讀，讀取不覆寫存檔；舊版不會轉換。"
		_add_button("普通戰役備存","OrdinaryBackupsButton",func(): backup_expedition=false;backup_index=0;_show_page("checkpoint_backup_slot"))
		_add_button("遠征備存","ExpeditionBackupsButton",func(): backup_expedition=true;backup_index=0;_show_page("checkpoint_backup_slot"))
		_add_button("返回存檔","BackupsBackButton",func(): _show_page("checkpoint"))
	elif page == "checkpoint_backup_slot":
		heading.text="遠征備存" if backup_expedition else "普通戰役備存"
		var slot=expedition_checkpoint_path if backup_expedition else checkpoint_path
		var listing=CheckpointBackups.list_slot(slot,Rules.BUILD_ID,backup_expedition)
		description.text=checkpoint_status+"\n固定排序，最多顯示 24 個；其他備存不會移除。只在查看選中備存時讀取內容。"
		if not listing.ok:description.text+="\n無法列出："+listing.reason
		if FileAccess.file_exists(slot):_add_button("保留目前存檔","KeepBackupButton",func(): _keep_checkpoint_backup(backup_expedition))
		if not listing.entries.is_empty():
			backup_index=clampi(backup_index,0,listing.entries.size()-1)
			var entry=listing.entries[backup_index]
			description.text+="\n%d / %d · " % [backup_index+1,listing.entries.size()]+entry.name.substr(entry.name.find(".preserved-")+11,8)
			_add_button("查看版本","InspectBackupButton",func(): _inspect_checkpoint_backup(backup_expedition,entry.name))
			if backup_index>0:_add_button("上一個","PreviousBackupButton",func(): backup_index-=1;_show_page("checkpoint_backup_slot"))
			if backup_index+1<listing.entries.size():_add_button("下一個","NextBackupButton",func(): backup_index+=1;_show_page("checkpoint_backup_slot"))
		else:description.text+="\n尚未保留備存。"
		_add_button("返回備存","BackupSlotBackButton",func(): _show_page("checkpoint_backups"))

	elif page == "checkpoint_backup_detail":
		heading.text="備存版本"
		var compatible=backup_info.get("ok",false)
		var version=Rules.BUILD_ID if compatible else backup_info.get("source_build","未知")
		description.text=("遠征" if backup_expedition else "普通戰役")+"\n備存："+backup_name.substr(backup_name.find(".preserved-")+11,8)+"\n版本："+str(version)+"\n"+("此版本可讀。讀取後暫停，不覆寫目前存檔。" if compatible else "此版不可讀。此版本尚未確認；原檔保留，不會轉換。")
		if compatible:_add_button("讀取備存（取代目前戰役）","LoadBackupButton",func(): _load_checkpoint_backup(backup_expedition,backup_name))
		_add_button("返回備存","BackupDetailBackButton",func(): _show_page("checkpoint_backup_slot"))

	elif page in ["confirm","tutorial_confirm"]:
		heading.text = "開始新戰役？"
		description.text = "目前未儲存的戰役與教學會重新開始。本機存檔不會被新戰役覆蓋。"
		_add_button("設定新戰役", "ConfirmNewMatchButton", func(): _choose_battle("practice") if page=="tutorial_confirm" else _show_page("battle_groups"))
		_add_button("保留目前戰役", "CancelNewMatchButton", func(): _show_page("home"))
	else:
		heading.text = "霧谷王旗"
		description.text = "建立聚落，探索霧谷。"
		if is_instance_valid(match_node):
			if not match_node.game_over:
				description.text = "目前戰役已暫停。\n按繼續返回戰場。"
				_add_button("繼續戰役", "ResumeMatchButton", _resume_match)
			else:
				description.text = "戰役已結束。\n查看總結，或再開一局。"
				_add_button("戰役總結", "MatchReportButton", _review_finished_match)
			if AIDifficulty.supported(match_node.skirmish_mode,match_node.victory_mode):
				description.text+="\n本局電腦："+AIDifficulty.title(match_node.ai_difficulty)
			_add_button("新戰役", "NewMatchButton", func(): _show_page("confirm") if not match_node.game_over else _show_page("battle_groups"))
		else:
			_add_button("開始戰役", "StartMatchButton", func(): _show_page("battle_groups"))
			_add_button("前線遠征任務", "ExpeditionHomeButton", func(): selected_mode="expedition";selected_victory_mode="conquest";_show_page("setup"))
		if not is_instance_valid(match_node) and FileAccess.file_exists(auto_checkpoint_path):
			_add_button("繼續上次（自動備存）", "ContinueAutoCheckpointButton", _load_auto_checkpoint)
			description.text+="\n"+_auto_slot_summary()
		if not auto_checkpoint_status.is_empty():description.text+="\n"+auto_checkpoint_status
		_add_button("兵種與建築圖鑑", "CatalogueMenuButton", func(): manual_section=0;manual_index=0;_show_page("manual"))
		_add_button("本機存檔", "CheckpointMenuButton", func(): _show_page("checkpoint"))
		_add_button("教學", "HelpButton", func(): _show_page("help"))
	_layout()
	call_deferred("_focus_first_button")

func _focus_first_button():
	if menu_layer.visible and buttons.get_child_count() > 0:
		buttons.get_child(0).grab_focus()

func _choose_mode(mode: String):
	selected_mode=SkirmishPolicy.valid(mode)
	_show_page("setup")

func _restart_match():
	if is_instance_valid(match_node):
		selected_campaign=match_node.campaign_chapter
		replay_campaign_on_launch=live_campaign_replay
		selected_mode=match_node.skirmish_mode
		selected_victory_mode=match_node.victory_mode
		selected_layout=match_node.layout_id
		selected_difficulty=match_node.ai_difficulty
	_start_match()

func _start_match():
	if transition_busy: return
	transition_busy = true
	# Finish the button's input dispatch before creating a live battlefield.
	call_deferred("_replace_match")

func _replace_match():
	if restart_campaign_on_launch and selected_campaign==0:
		if not _write_campaign_progress(campaign_storage,0,true):
			var conflict=campaign_storage.get("reason","")=="CONFLICT"
			campaign_storage=CampaignProgress.read(campaign_progress_path)
			if campaign_storage.ok:campaign_unlocked=campaign_storage.completed
			campaign_notice="進度已喺另一頁更新；未有清除。請重新選擇。" if conflict and campaign_storage.ok else "未能清除進度，沒有開始新戰場。"
			transition_busy=false
			_show_page("campaign")
			return
		campaign_unlocked=0
	live_campaign_replay=replay_campaign_on_launch
	if is_instance_valid(match_node):
		remove_child(match_node)
		match_node.queue_free()
	match_node = MATCH_SCENE.instantiate()
	match_node.campaign_chapter=selected_campaign
	campaign_expected=campaign_storage.duplicate(true) if selected_campaign>=0 else {}
	selected_campaign=-1;restart_campaign_on_launch=false;replay_campaign_on_launch=false
	match_node.ai_difficulty=AIDifficulty.valid_for(selected_mode,selected_victory_mode,selected_difficulty)
	match_node.skirmish_mode=selected_mode
	match_node.layout_id=selected_layout if BattlefieldLayout.supported(selected_mode,selected_victory_mode) else "valley"
	match_node.victory_mode=selected_victory_mode
	match_node.main_menu_requested.connect(_open_menu)
	match_node.restart_requested.connect(_restart_match)
	match_node.setup_requested.connect(_reconfigure_finished_match)
	match_node.campaign_next_requested.connect(_campaign_next)
	match_node.match_finished.connect(_observe_campaign_result.bind(match_node))
	_connect_auto_checkpoint(match_node)
	add_child(match_node)
	_configure_new_match_camera(match_node)
	_release_menu_focus()
	manual_preview.clear_model()
	menu_layer.hide()
	touch_presses.clear()
	transition_busy = false

func _configure_new_match_camera(game):
	# New matches in short viewports only; portrait keeps its wider field.
	# _ready has synchronized the web viewport already.
	# Never run from layout/resize, resume, or checkpoint restoration.
	var size=game.get_viewport().get_visible_rect().size
	if size.is_finite() and size.x>0 and size.y>0 and size.y<560 and is_equal_approx(game.camera_zoom,30.0):
		game.camera_zoom=22.0
		game._camera_update()

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
	_schedule_auto_checkpoint(match_node)
	match_node._sync_audio()
	match_node.process_mode = Node.PROCESS_MODE_DISABLED
	match_node.hide()
	match_node.ui.hide()
	menu_layer.show()
	_show_page("home")

func _review_finished_match():
	if transition_busy or not is_instance_valid(match_node) or not match_node.game_over: return
	transition_busy = true
	call_deferred("_finish_report_review")

func _finish_report_review():
	if not is_instance_valid(match_node) or not match_node.game_over:
		transition_busy = false
		return
	match_node._cancel_pointer_streams()
	match_node.process_mode = Node.PROCESS_MODE_INHERIT
	match_node.show(); match_node.ui.show()
	match_node._set_aftermath_view(false)
	match_node._layout_ui()
	_release_menu_focus()
	manual_preview.clear_model()
	menu_layer.hide()
	touch_presses.clear()
	transition_busy = false
	# Do not toggle pause, replace the match or reset its frozen report.

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
	manual_preview.clear_model()
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
	if menu_layer.visible and page=="campaign":
		snapshot.campaign_storage_available=campaign_storage.get("ok",false)
		snapshot.campaign_completed=campaign_unlocked
	if menu_layer.visible and page == "help":
		var bar = scroll.get_v_scroll_bar()
		var tail = help_tail.get_global_rect()
		var clipped = tail.intersection(scroll.get_global_rect()).intersection(get_viewport().get_visible_rect())
		snapshot["help_scroll"] = {"value": bar.value, "maximum": bar.max_value, "page": bar.page, "final_rect": [tail.position.x, tail.position.y, tail.size.x, tail.size.y], "final_visible_rect": [clipped.position.x, clipped.position.y, clipped.size.x, clipped.size.y], "final_text": help_tail.text}
	JavaScriptBridge.eval("window.valleyMenuState=" + JSON.stringify(snapshot) + ";")

func _cancel_menu_touches():
	if is_instance_valid(manual_preview):manual_preview.cancel_input()
	touch_presses.clear()
	prose_touch = -1
	touch_blocked = not active_touches.is_empty()

func _help_touch(event: InputEvent) -> bool:
	# Native ScrollContainer dragging uses mouse events. Keep the game's
	# mouse-from-touch emulation disabled and own only this reading area.
	if page not in ["help","setup","manual","campaign"]: return false
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
	if touch_blocked and is_instance_valid(manual_preview):manual_preview.cancel_input();manual_preview.blocked=true
	if page=="manual" and manual_preview.visible:
		var captured=manual_preview.handle_touch(event,scroll.get_global_rect())
		if not manual_preview.scroll_request.is_empty():
			prose_touch=manual_preview.scroll_request.index
			prose_origin=manual_preview.scroll_request.origin
			prose_scroll_origin=scroll.scroll_vertical
			manual_preview.scroll_request.clear()
		elif captured:
			prose_touch=-1;get_viewport().set_input_as_handled();return
	if _help_touch(event): get_viewport().set_input_as_handled()

func _save_checkpoint():
	if not is_instance_valid(match_node) or transition_busy:return
	var result=ExpeditionCheckpointStore.save_slot(match_node,expedition_checkpoint_path) if match_node.skirmish_mode=="expedition" else CheckpointStore.save_slot(match_node,checkpoint_path)
	checkpoint_status=("已寫入遠征存檔：%d 秒。" if match_node.skirmish_mode=="expedition" else "已寫入本機存檔：%d 秒。") % int(result.tick/20) if result.ok else "未能儲存，原存檔不變："+str(result.get("reason","UNKNOWN"))
	if result.ok and result.get("preserved",false):checkpoint_status+=" 舊版本或無效存檔已保留本機備存，不能在此版讀取；未作跨版本轉換。"
	_show_page("checkpoint")

func _load_checkpoint(expedition=false):
	if transition_busy:return
	transition_busy=true
	call_deferred("_restore_checkpoint",expedition)

func _restore_checkpoint(expedition=false,backup_name="",automatic=false):
	var result={}
	if automatic:
		result=AutoCheckpoint.read_slot(Rules.BUILD_ID,auto_checkpoint_path)
	elif not backup_name.is_empty():
		result=CheckpointBackups.read(expedition_checkpoint_path if expedition else checkpoint_path,backup_name,Rules.BUILD_ID,expedition)
	else:
		result=ExpeditionCheckpointStore.read_slot(Rules.BUILD_ID,expedition_checkpoint_path) if expedition else CheckpointStore.read_slot(Rules.BUILD_ID,checkpoint_path)
	if not result.ok:
		checkpoint_status=("存檔版本 %s 與目前 %s 不同，原檔未改動；不會自行轉換。" % [result.get("source_build","未知"),Rules.BUILD_ID]) if result.get("reason")=="BUILD_MISMATCH" else "無法讀取存檔，未改動目前戰役："+str(result.get("reason","UNKNOWN"))
		transition_busy=false;_show_page("checkpoint");return
	# Build a disposable replacement before touching the player's current game.
	var candidate=MATCH_SCENE.instantiate()
	candidate.ai_difficulty=result.data.game.ai_difficulty
	candidate.skirmish_mode=result.data.game.skirmish_mode
	candidate.layout_id=result.data.game.layout_id
	candidate.victory_mode=result.data.game.victory_mode
	add_child(candidate);candidate.set_process(false);candidate.hide();candidate.ui.hide()
	if not CheckpointRestore.apply(candidate,result.data):
		candidate.queue_free();checkpoint_status="存檔無效，未改動目前戰役。"
		transition_busy=false;_show_page("checkpoint");return
	if is_instance_valid(match_node):remove_child(match_node);match_node.queue_free()
	match_node=candidate
	selected_mode=candidate.skirmish_mode;selected_victory_mode=candidate.victory_mode;selected_layout=candidate.layout_id;selected_difficulty=candidate.ai_difficulty
	candidate.main_menu_requested.connect(_open_menu);candidate.restart_requested.connect(_restart_match);candidate.setup_requested.connect(_reconfigure_finished_match)
	_connect_auto_checkpoint(candidate)
	candidate.process_mode=Node.PROCESS_MODE_DISABLED
	candidate.set_process(true)
	checkpoint_status="已讀取存檔，戰役保持暫停。按繼續返回。"
	transition_busy=false;_show_page("home")

func _keep_checkpoint_backup(expedition:bool):
	if transition_busy:return
	var result=CheckpointBackups.keep(expedition_checkpoint_path if expedition else checkpoint_path,Rules.BUILD_ID,expedition)
	checkpoint_status="已保留本機備存，原存檔不變。" if result.ok else "未能保留備存，原存檔不變："+str(result.get("reason","UNKNOWN"))
	_show_page("checkpoint_backup_slot")
func _load_checkpoint_backup(expedition:bool,name:String):
	if transition_busy:return
	transition_busy=true
	call_deferred("_restore_checkpoint",expedition,name)

func _inspect_checkpoint_backup(expedition:bool,name:String):
	if transition_busy:return
	backup_name=name;backup_expedition=expedition
	var result=CheckpointBackups.read(expedition_checkpoint_path if expedition else checkpoint_path,name,Rules.BUILD_ID,expedition)
	# Never cache decoded snapshot data; loading re-reads and validates the bytes.
	backup_info={"ok":result.ok,"reason":result.get("reason",""),"source_build":result.get("source_build","未知")}
	_show_page("checkpoint_backup_detail")

func _choose_campaign(index:int,restart=false,replay=false):
	if transition_busy or index<0 or index>=BattleSelection.CAMPAIGN.size():return
	if index!=(0 if restart or replay else campaign_unlocked) or ((restart or replay) and campaign_unlocked<=0):return
	if is_instance_valid(match_node) and not match_node.game_over:return
	var row=BattleSelection.option(BattleSelection.CAMPAIGN[index])
	campaign_notice=""
	selected_campaign=index;restart_campaign_on_launch=restart;replay_campaign_on_launch=replay;selected_mode=row.mode;selected_victory_mode=row.victory
	selected_layout="valley";selected_difficulty="standard"
	_show_page("setup")

func _observe_campaign_result(game):
	if game!=match_node or not game.game_over:return
	if live_campaign_replay:
		game.end_setup_button.text="戰役流程"
		game.end_body.text+="\n重玩不會更改已完成場次。"
		return
	var index=game.campaign_chapter
	if index<0 or index>=BattleSelection.CAMPAIGN.size() or index!=campaign_unlocked:return
	if not BattleSelection.campaign_completed(index,game.skirmish_mode,game.outcome,game.end_reason) or game.layout_id!="valley" or game.victory_mode!="conquest":return
	campaign_unlocked+=1
	if not _write_campaign_progress(campaign_expected,campaign_unlocked):
		game.end_body.text+="\n"+_campaign_storage_label()

func _campaign_briefing_line() -> String:
	if restart_campaign_on_launch:return "出征會清除這個瀏覽器或裝置已完成的場次，從第一場重新開始。"
	if replay_campaign_on_launch:return "只重玩第一場，不改動已完成紀錄。不會保留未完成的戰場。"
	return "完成後保留場次進度；不會保留未完成的戰場。" if campaign_storage.get("ok",false) else "目前未能保留場次進度；不會保留未完成的戰場。"

func _campaign_storage_label() -> String:
	if campaign_storage.get("ok",false):return "已完成場次保留在此瀏覽器或裝置；未完成戰場不會恢復。"
	return "未能保留進度，只限本次遊戲；重開網頁前請留意。"

func _write_campaign_progress(expected:Dictionary,completed:int,reset=false)->bool:
	if reset and expected.get("ok",false) and expected.get("completed",-1)==0:return true
	campaign_storage=CampaignProgress.save(expected,completed,reset,campaign_progress_path)
	return campaign_storage.ok

func _campaign_next():
	if not is_instance_valid(match_node) or not match_node.game_over or match_node.campaign_chapter<0 or transition_busy:return
	var chapter=match_node.campaign_chapter
	var proceed=not live_campaign_replay and BattleSelection.campaign_completed(chapter,match_node.skirmish_mode,match_node.outcome,match_node.end_reason) and campaign_unlocked==chapter+1 and campaign_unlocked<BattleSelection.CAMPAIGN.size()
	_open_menu()
	if proceed:_choose_campaign(campaign_unlocked)
	else:_show_page("campaign")

func _choose_battle(id:String):
	selected_campaign=-1;restart_campaign_on_launch=false;replay_campaign_on_launch=false
	var option=BattleSelection.option(id)
	if option.is_empty():return
	selected_mode=option.mode;selected_victory_mode=option.victory
	_show_page("setup")
func _reconfigure_finished_match():
	if not is_instance_valid(match_node) or not match_node.game_over or transition_busy:return
	selected_mode=match_node.skirmish_mode;selected_victory_mode=match_node.victory_mode;selected_layout=match_node.layout_id;selected_difficulty=match_node.ai_difficulty
	_open_menu();_show_page("battle_groups")

func _connect_auto_checkpoint(game):
	game.paused_checkpoint_requested.connect(func():_schedule_auto_checkpoint(game))

func _toggle_auto_checkpoint():
	auto_checkpoint_enabled=not auto_checkpoint_enabled
	auto_checkpoint_last_attempt=""
	if auto_checkpoint_enabled and is_instance_valid(match_node):_schedule_auto_checkpoint(match_node)
	_show_page("auto_checkpoint")

func _schedule_auto_checkpoint(game):
	if not auto_checkpoint_enabled or transition_busy or game!=match_node or not AutoCheckpoint.supported(game) or not game.paused:return
	var key=str(game.get_instance_id())+":"+str(game.tick_count)
	if key==auto_checkpoint_last_attempt or key==auto_checkpoint_pending:return
	auto_checkpoint_pending=key
	call_deferred("_write_auto_checkpoint",game.get_instance_id(),key)

func _write_auto_checkpoint(instance_id,key):
	if auto_checkpoint_pending==key:auto_checkpoint_pending=""
	if not auto_checkpoint_enabled or transition_busy or not is_instance_valid(match_node) or match_node.get_instance_id()!=instance_id or not match_node.paused or not AutoCheckpoint.supported(match_node):return
	var current=str(instance_id)+":"+str(match_node.tick_count)
	if current!=key or key==auto_checkpoint_last_attempt:return
	auto_checkpoint_last_attempt=key
	var result={"ok":false,"reason":"SLOT_CONFLICT"} if ProjectSettings.globalize_path(auto_checkpoint_path) in [ProjectSettings.globalize_path(checkpoint_path),ProjectSettings.globalize_path(expedition_checkpoint_path)] else AutoCheckpoint.save_slot(match_node,auto_checkpoint_path)
	auto_checkpoint_status="上次自動備存成功：遊戲 %d 秒。" % int(result.tick/20) if result.ok else "自動備存失敗，舊備存未替換："+str(result.get("reason","UNKNOWN"))
	if result.ok:auto_checkpoint_writes+=1
	if menu_layer.visible and page in ["home","checkpoint","auto_checkpoint"]:_show_page(page)

func _load_auto_checkpoint():
	if transition_busy:return
	transition_busy=true
	call_deferred("_restore_checkpoint",false,"",true)

func _auto_slot_summary():
	var result=AutoCheckpoint.read_slot(Rules.BUILD_ID,auto_checkpoint_path)
	return "可繼續：遊戲 %d 秒。讀取後保持暫停。" % int(result.data.game.tick_count/20) if result.ok else "現有自動備存暫不可讀："+str(result.get("reason","UNKNOWN"))

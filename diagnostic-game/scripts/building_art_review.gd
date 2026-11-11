extends Control
## DIAGNOSTIC COMPONENT ART REVIEW ONLY. No Game enters the tree; no match runs.
const Assets = preload("res://scripts/advanced_building_visuals.gd")
const Construction = preload("res://scripts/construction_visual.gd")
const Damage = preload("res://scripts/building_damage_presenter.gd")
const Game = preload("res://scripts/game.gd")
const Rules = preload("res://scripts/rules.gd")
const STAGES = ["stable", "workshop", "tower", "farm", "portrait-stable-blue", "portrait-tower-red"]
const STATES = ["blue-completed", "red-completed", "construction-10pct", "construction-75pct", "blue-hp20pct", "red-gray-memory"]
var helper = Game.new() # Detached: only existing material and gray-proxy helpers.
var presenters: Array = []
var cells: Array = []
var grid: GridContainer
var title: Label
var stage := ""
var phase := "starting"
var generation := 0
var draws := 0
var sink
var select_callback

func _ready():
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var background := ColorRect.new()
	background.color = Game.DARK
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.add_theme_constant_override("separation", 8)
	add_child(column)
	title = Label.new()
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Game.CREAM)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.custom_minimum_size.y = 64
	column.add_child(title)
	grid = GridContainer.new()
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	column.add_child(grid)
	RenderingServer.frame_post_draw.connect(_after_draw)
	get_viewport().size_changed.connect(_resized)
	if OS.has_feature("web"):
		JavaScriptBridge.eval("""(()=>{let payload='{}',select;const freeze=x=>{if(x&&typeof x==='object'){Object.values(x).forEach(freeze);Object.freeze(x)}return x};const stages=['stable','workshop','tower','farm','portrait-stable-blue','portrait-tower-red'];Object.defineProperty(window,'valleyBuildingArt',{value:Object.freeze({read:()=>freeze(JSON.parse(payload)),select:s=>{if(!stages.includes(s))throw Error('Unknown fixed fixture stage');select(s)}}),writable:false,configurable:false});window.__buildingArtSink={publish:s=>{payload=s},bind:f=>{if(select)throw Error('Already bound');select=f}}})()""")
		sink = JavaScriptBridge.get_interface("__buildingArtSink")
		JavaScriptBridge.eval("delete window.__buildingArtSink")
		select_callback = JavaScriptBridge.create_callback(_select_js)
		sink.bind(select_callback)
	_set_stage("stable")

func _exit_tree():
	for presenter in presenters: presenter.clear()
	helper.free()

func _select_js(arguments):
	if arguments.size() == 1 and str(arguments[0]) in STAGES:
		_set_stage.call_deferred(str(arguments[0]))

func _resized():
	draws = 0
	phase = "drawing"
	_publish()

func _set_stage(requested: String):
	if requested not in STAGES: return
	for presenter in presenters: presenter.clear()
	presenters.clear()
	for child in grid.get_children():
		grid.remove_child(child)
		child.queue_free()
	cells.clear()
	stage = requested
	generation += 1
	draws = 0
	phase = "drawing"
	var portrait := stage.begins_with("portrait-")
	grid.columns = 1 if portrait else 3
	var kind := stage.split("-")[1] if portrait else stage
	title.text = "DIAGNOSTIC · ART REVIEW\n" + kind.to_upper() + " · COMPONENT ONLY\nNOT GAMEPLAY / NOT PERFORMANCE"
	if portrait:
		_add_cell(kind, "blue-completed" if stage.ends_with("blue") else "red-completed")
	else:
		for state in STATES: _add_cell(kind, state)
	_publish()

func _add_cell(kind: String, state: String):
	var cell := VBoxContainer.new()
	cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cell.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid.add_child(cell)
	var caption := Label.new()
	caption.text = state
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.add_theme_color_override("font_color", Game.CREAM)
	caption.add_theme_font_size_override("font_size", 16)
	cell.add_child(caption)
	var container := SubViewportContainer.new()
	container.stretch = true
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cell.add_child(container)
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	container.add_child(viewport)
	var root := Node3D.new()
	viewport.add_child(root)
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color("727967")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("b6bec5")
	settings.ambient_light_energy = 0.36
	settings.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	environment.environment = settings
	root.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -32, 0)
	sun.light_color = Color("ffedce")
	sun.light_energy = 0.95
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 80
	root.add_child(sun)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(12, 12)
	floor_mesh.mesh = plane
	floor_mesh.material_override = helper._material(Color("727967"))
	root.add_child(floor_mesh)
	var body := Node3D.new()
	root.add_child(body)
	var team: Color = Game.RED if state.begins_with("red") else Game.BLUE
	var asset: Node3D = Assets.instantiate_asset(kind, team)
	body.add_child(asset)
	var built := not state.begins_with("construction")
	var progress := 0.10 if state == "construction-10pct" else (0.75 if not built else 1.0)
	Construction.apply(body, kind, built, progress)
	var remembered := state == "red-gray-memory"
	if remembered: helper._gray_proxy(body, true)
	var damaged := state == "blue-hp20pct"
	var presenter = Damage.new()
	presenters.append(presenter)
	var record := {"category":"building", "kind":kind, "remembered":remembered, "alive":true, "built":built, "hp":20 if damaged else 100, "max_hp":100, "pos":Vector3.ZERO}
	presenter.update({1:record}, root)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	camera.size = 6.2 if stage.begins_with("portrait-") else (8.0 if kind == "tower" else 6.8)
	root.add_child(camera)
	var focus := Vector3(0, float(Assets.HEIGHTS[kind]) * 0.42, 0)
	camera.position = focus + Vector3(6, 5.6, 8)
	camera.look_at(focus)
	camera.current = true
	cells.append({"kind":kind, "state":state, "asset":asset, "body":body, "viewport":viewport, "presenter":presenter, "built":built, "progress":progress, "remembered":remembered, "team":team.to_html(false), "damage_tier":Damage.tier(record)})

func _after_draw():
	if phase != "drawing": return
	draws += 1
	if draws >= 3:
		phase = "ready"
		_publish()

func _publish():
	if sink == null: return
	var rows: Array = []
	for cell in cells:
		rows.append({"kind":cell.kind, "state":cell.state, "asset_kind":cell.asset.get_meta("asset_kind", ""), "asset_visible":cell.asset.visible, "construction_stage":cell.body.get_meta("construction_stage", -1), "built":cell.built, "progress":cell.progress, "remembered":cell.remembered, "team":cell.team, "damage_tier":cell.damage_tier, "damage_nodes":cell.presenter.nodes.size(), "viewport":[cell.viewport.size.x,cell.viewport.size.y]})
	var size := get_viewport().get_visible_rect().size
	sink.publish(JSON.stringify({"schema":"vc-building-art-report-v1", "diagnostic_only":true, "normal_gameplay":false, "performance_claim":false, "build":Rules.BUILD_ID, "stage":stage, "generation":generation, "phase":phase, "draws_since_stage_or_resize":draws, "viewport":[size.x,size.y], "game_source_sha256":FileAccess.get_sha256("res://scripts/game.gd"), "overlay_sha256":FileAccess.get_sha256("res://scripts/building_art_review.gd"), "cells":rows}))

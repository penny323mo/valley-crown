extends Node3D
## Original RTS vertical slice. All game state is deterministic and available to smoke tests.
const WorkerIdleStatus = preload("res://scripts/worker_idle_status.gd")
const MAP_LIMIT = Rules.MAP_WORLD_LIMIT
const BLUE = Color("435d6c")
const RED = Color("813d32")
const GOLD = Color("d9cba2")
const CREAM = Color("e4dfcb")
const DARK = Color("20261f")
const Rules = preload("res://scripts/rules.gd")
const EndRules = preload("res://scripts/end_rules.gd")
const Economy = preload("res://scripts/economy_ledger.gd")
const AttackLedger = preload("res://scripts/attack_ledger.gd")
const INITIAL_STOCKS = [{"food":150,"wood":200},{"food":150,"wood":200}]
const BoundedPath = preload("res://scripts/bounded_grid_pathfinder.gd")
const WorkPath = preload("res://scripts/bounded_work_routes.gd")
const FactionView = preload("res://scripts/faction_view.gd")
const ReturnCargoAction = preload("res://scripts/return_cargo_action.gd")
const WorkMemory = preload("res://scripts/faction_work_memory.gd")
const MapRoutes = preload("res://scripts/map_routes.gd")
const MatureVisuals = preload("res://assets/mature/visual_library.gd")
const BuildingDamagePresenter = preload("res://scripts/building_damage_presenter.gd")
const ConstructionVisual = preload("res://scripts/construction_visual.gd")
const MatureWorld = preload("res://scripts/mature_world_visuals.gd")
const CharacterPresenter = preload("res://scripts/observed_character_presenter.gd")
const COSTS = Rules.COSTS
const MAX_HP = Rules.HP
# Embedded Windows do not send their _input stream to the parent viewport.
# Track their pointers before GUI dispatch, retaining native mouse/key behavior.
class ModalInputBridge:
	extends Node
	var game: Node
	func _input(event):
		game._track_pointer_input(event,get_viewport())
	func _exit_tree():
		if is_instance_valid(game) and game.is_inside_tree(): game._cancel_pointer_streams()
const ATTACK_EFFECT_SECONDS = 0.12
const MAX_ATTACK_EFFECTS = 2 * Rules.POP_LIMIT # At most one cue per unit inside the 0.12s lifetime.
var attack_effects: Array = [] # Detached, witnessed release cues; never authoritative projectiles.
# S09 isolated candidate: observers receive only verified own commit facts.
var demo_tutorial = preload("res://scripts/demo_tutorial.gd").new()
var tutorial_panel: PanelContainer
var tutorial_label: Label
var tutorial_skip: Button

var entities: Array = []
var selected: Array = []
var next_id = 0
var economy = Economy.new()
var economy_sequence = 0
# Compatibility projections only. Every authoritative economic read uses economy.
var stocks:
	get:
		var display=[]
		for team in 2:
			var bank=economy.bank_milli(team)
			display.append({"food":bank.get("food",0)/1000.0,"wood":bank.get("wood",0)/1000.0})
		return display
var camera: Camera3D
var camera_focus=MapRoutes.PLAYER_HOME # Frame the opening keep and workers on portrait phones.
const CAMERA_KEYS=[KEY_A,KEY_D,KEY_W,KEY_S,KEY_LEFT,KEY_RIGHT,KEY_UP,KEY_DOWN]
# A UI-owned press cannot become a world press through focus transfer/dismissal.
var ui_camera_keys={}
var camera_zoom=30.0
var game_time=0.0
var ai_clock=0.0
var raid_clock=0.0
var ai_raids=0
var paused=false
var game_over=false
var victory=false
var build_mode=""
var ghost: Node3D
var placement_ok=false
var build_preview_held=false # Presentation/input intent only; no payment until explicit Confirm.
var pointer_world=Vector3.ZERO
var pointer_screen=Vector2.ZERO
var hover_id=-1
var drag_start=Vector2.ZERO
var dragging=false
var drag_active=false
var touch_command=false
var rally_building=-1
# UX01 selection intent only; no simulation command or world-state mutation.
var box_select_mode=false
var touch_box_index=-1
var touch_box_origin=Vector2.ZERO
var touch_box_active=false
# Preserve raw crossing samples only while this mode owns pointer intent.
var box_input_accumulation_owned=false
var box_previous_input_accumulation=true
# A canceled UI click owns its OS-marked double-click/tap continuation only.
var box_cancel_press={}
var box_cancel_repeat={}
# A reused touch index is a new press, even before deferred cleanup runs.
var touch_press_serial=0
var touch_press_epochs={}
var ui: Control
var top_resources: Label
var time_label: Label
var toast_label: Label
var toast_time=0.0
var toast_build_guidance=false
var selection_title: Label
var selection_detail: Label
var help_label: Label
var mission_label: Label
var queue_label: Label
var actions: HBoxContainer
var minimap: Control
var drag_rect: ReferenceRect
var end_panel: PanelContainer
var end_title: Label
var end_body: Label
var pause_button: Button
var touch_button: Button
var frame_counter=0
var mats={}
var models={}
var rng=RandomNumberGenerator.new()
var title_font: Font
var body_font: Font
var order_marker: Node3D
var marker_time=0.0
var test_mode=false

var tick_count=0
var tick_accumulator=0.0
var commands: Array=[]
var command_sequence=0
var processed_command_ids={}
var navigation=AStarGrid2D.new()
var ground_trails=MapRoutes.corridor_mask() # Visual only, never a construction restriction.
var navigation_version=0
var faction_views=[FactionView.new(),FactionView.new()]
var building_damage_presenter=BuildingDamagePresenter.new()
var presentation_nodes={}
var character_presenter=CharacterPresenter.new()
# Observation-only cues, intentionally outside entity/ledger authority.
var unit_action_cues=[{},{}]
var pending_visual_deaths: Array = []
var resource_pick_face_cache={} # Immutable public mesh triangles, never world/entity state.
var work_memory=[WorkMemory.new(),WorkMemory.new()]
var visible_cells=[PackedByteArray(),PackedByteArray()]
var explored_cells=[PackedByteArray(),PackedByteArray()]
var fog: MultiMeshInstance3D
var fog_render_state=PackedByteArray()
var touch_points={}
var all_touch_ids=[]
var action_touch_scroll={} # Single-finger ownership for action-strip/menu scrolling.
var canceled_touch_ids={}
var pressed_mouse_buttons={}
var canceled_mouse_buttons={}
var gui_touch_press={} # GUI-only ownership; world touch_points remain separate.
var touch_gesture=false
var touch_origin=Vector2.ZERO
var touch_previous_center=Vector2.ZERO
var touch_previous_distance=0.0
var middle_drag=false
var hud_bottom: PanelContainer
var hud_top: PanelContainer
var action_scroll: ScrollContainer
var action_key=""
var return_cargo_button: Button
var build_confirm: Button
var compact_ui=false
var short_ui=false
var compact_top_stack: VBoxContainer
var compact_top_line: HBoxContainer
var compact_brand: Label
var compact_bottom_stack: VBoxContainer
var compact_narrow_info: VBoxContainer
var compact_unit_tools: HBoxContainer
var compact_cancel_button: Button
var compact_menu: PanelContainer
var compact_menu_dismiss: Control
var compact_menu_button: Button
var compact_map_choice=-1
var selection_row: HBoxContainer
var outcome=""
var pending_damage={}
var attack_ledger=AttackLedger.new()
var delivered_total:
	get:
		var display=[]
		for team in 2:
			var stats=economy.stats_view(team)
			var delivered=stats.get("delivered",{"food":0,"wood":0})
			display.append((delivered.food+delivered.wood)/1000.0)
		return display
var completed_builds=[0,0]
var trained_total=[0,0]
var qa_callback
var web_touch_cancel_callback
var qa_mode=false
var ai_enabled=true
var groups={}
var footprints={}
var sounds_enabled=false
var audio_cues
var audio_button
var last_path_queries=0
var last_path_expansions=0
var path_requests=[]
var path_budget_tick=-1
var path_expansion_budget=4096
var spawn_availability_polls=0
var spawn_candidate_checks=0
var ready_cursor=-1
var next_queue_id=0
var spawn_commit_order=[]
var background_paused=false
var application_focused=true
var application_suspended=false
var discard_return_delta=false
var world_decor=[]
var recovery_ticks=[0,0]
var no_progress_ticks=0
var progress_serial=0
var inactivity_paused=false
var future_recovery_events=[]
var end_reason=""
# Private accepted terminal intent, settled only at the normal post-combat stage.
# Both factions surrendering in one batch retains the existing synthetic draw.
var _surrender_intent={}
# Local motion is serialized by entity ID, rotating its first claimant every
# twenty fixed ticks. This is independent of command sequence and combat order.
# MOV01's accepted search ceiling remains3 retries per rolling20ticks at
# the shared scheduler below. The12-replan and240-tick local safeguards are
# chosen implementation limits, not new specification constants. Parking
# yields share that finite240-tick bound and never push stopped units.
const TRAFFIC_ROTATION_TICKS=20
const TRAFFIC_REPLAN_TICKS=20
const TRAFFIC_MAX_REPLANS=12
const TRAFFIC_STALL_TICKS=240
var traffic_priority_order=[]
var traffic_tick_segments={}


func _ready():
	_sync_web_display_scale()
	audio_cues=preload("res://scripts/audio_cues.gd").new(); add_child(audio_cues)
	_reset_economy(INITIAL_STOCKS)
	rng.seed=824613
	test_mode="--smoke-test" in OS.get_cmdline_user_args()
	title_font=load("res://assets/fonts/title.ttf")
	body_font=load("res://assets/fonts/ui_tc.otf")
	# Baked original native scenes share textures; legacy GLBs are not loaded.
	models["berry"]=load("res://assets/mature/models/berry.scn")
	_create_world()
	_seed_match()
	_navigation_rebuild()
	_create_fog()
	_update_vision()
	_create_ui()
	_create_tutorial_ui()
	audio_cues.observe(faction_views[0].records(),tick_count,Time.get_ticks_msec())
	_select([_first(0,"town_center").id])
	_message("選取村民，再向漿果或樹木落指令。建立聚落，探索霧谷。",9)
	_install_web_bridge()
	if test_mode: call_deferred("_run_smoke_test")

func _material(color: Color, roughness=1.0):
	var key=color.to_html()+str(roughness)
	if mats.has(key): return mats[key]
	var m=StandardMaterial3D.new()
	m.albedo_color=color
	m.roughness=roughness
	mats[key]=m
	return m

func _mesh(parent: Node3D, mesh: Mesh, position: Vector3, color: Color):
	var mi=MeshInstance3D.new()
	mi.mesh=mesh
	mi.position=position
	mi.material_override=_material(color)
	parent.add_child(mi)
	return mi

func _box(parent, position, dimensions, color):
	var shape=BoxMesh.new(); shape.size=dimensions
	return _mesh(parent,shape,position,color)

func _cylinder(parent, position, radius, height, color, top=-1.0, sides=8):
	var shape=CylinderMesh.new()
	shape.bottom_radius=radius; shape.top_radius=radius if top<0 else top
	shape.height=height; shape.radial_segments=sides
	return _mesh(parent,shape,position,color)

func _create_world():
	var env=WorldEnvironment.new()
	var e=Environment.new()
	e.background_mode=Environment.BG_COLOR
	e.background_color=Color("727967")
	e.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color=Color("b6bec5")
	e.ambient_light_energy=0.36
	e.tonemap_mode=Environment.TONE_MAPPER_LINEAR
	env.environment=e; add_child(env)
	var sun=DirectionalLight3D.new()
	sun.rotation_degrees=Vector3(-48,-32,0)
	sun.light_color=Color("ffedce"); sun.light_energy=0.95
	sun.shadow_enabled=true
	sun.directional_shadow_max_distance=80
	add_child(sun)
	var ground=Node3D.new(); add_child(ground)
	# One continuous matte terrain surface, rather than a thick toy-board slab.
	# Retain the decorative sample count, not historical RNG-state equivalence.
	# Larger sampling bounds and changed home-distance skip branches can alter
	# subsequent RNG consumption; this prototype has its own source/seed identity.
	# These draws and decoration do not decide resource positions or amounts.
	for i in 120:
		var _x=rng.randf_range(-Rules.MAP_HALF,Rules.MAP_HALF); var _z=rng.randf_range(-Rules.MAP_HALF,Rules.MAP_HALF)
		var _radius=rng.randf_range(0.5,2.7)
		var _rotation=rng.randf()*TAU
	MatureWorld.create_ground(ground,ground_trails)
	# No decorative water on otherwise buildable land. Low grass is not an obstacle.
	for i in 150:
		var p=Vector3(rng.randf_range(-MAP_LIMIT,MAP_LIMIT),0.05,rng.randf_range(-MAP_LIMIT,MAP_LIMIT))
		if p.distance_to(MapRoutes.home(0))<6 or p.distance_to(MapRoutes.home(1))<6: continue
		if i%4==0:
			world_decor.append(_cylinder(ground,p,0.13,0.18,Color("71614b"),0.08,5))
		else:
			var grass=_box(ground,p,Vector3(0.06,0.2,0.35),Color("777c55"))
			grass.rotation.y=rng.randf()*TAU
			world_decor.append(grass)
	# Distant pines frame the playable map.
	for i in 46:
		var edge=-Rules.MAP_HALF if i%2==0 else Rules.MAP_HALF
		var p=Vector3(edge,0,rng.randf_range(-Rules.MAP_HALF,Rules.MAP_HALF)) if i%4<2 else Vector3(rng.randf_range(-Rules.MAP_HALF,Rules.MAP_HALF),0,edge)
		world_decor.append(_tree_visual(ground,p,"pine",rng.randf_range(0.8,1.25)))
	camera=Camera3D.new(); camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.size=camera_zoom; camera.far=120; camera.near=0.1
	add_child(camera); camera.current=true; _camera_update()
	order_marker=Node3D.new(); add_child(order_marker)
	var ring=TorusMesh.new(); ring.inner_radius=0.43; ring.outer_radius=0.52; ring.rings=24; ring.ring_segments=6
	_mesh(order_marker,ring,Vector3(0,0.1,0),GOLD)
	order_marker.visible=false

func _tree_visual(parent, p, kind, sc=1.0):
	var root=Node3D.new(); parent.add_child(root); root.position=p; root.scale=Vector3.ONE*sc
	if kind in ["pine","oak"]:
		# Variant derives from fixed position, never authoritative gameplay RNG.
		var anchor=parent.to_global(p)
		var variant=(int(round(anchor.x*100))*73856093) ^ (int(round(anchor.z*100))*19349663)
		root.add_child(MatureVisuals.instantiate_asset(kind,variant)); return root
	_cylinder(root,Vector3(0,0.9,0),0.16,1.8,Color("73563d"),0.12)
	if kind=="pine":
		for i in 3: _cylinder(root,Vector3(0,1.7+i*0.65,0),1.0-i*0.2,1.5,Color("3d6b52"),0,7)
	else:
		var sphere=SphereMesh.new(); sphere.radius=1.2; sphere.height=2.0; sphere.radial_segments=7; sphere.rings=4
		_mesh(root,sphere,Vector3(0,2.2,0),Color("71914e"))
	return root

func _seed_match():
	# Mirrored resource fairness. No free military buildings or gifted AI income.
	for team in 2:
		var sign_team=1.0 if team==0 else -1.0
		_spawn("town_center",team,MapRoutes.home(team))
		for i in 5: _spawn("villager",team,Vector3(-14.5+i*1.3,0,13.5)*sign_team+MapRoutes.home_offset(team))
		_spawn("scout",team,Vector3(-7,0,8)*sign_team+MapRoutes.home_offset(team))
		for c in [Vector3(-17,0,3),Vector3(-5,0,1)]:
			for i in 7:
				var p=c+Vector3((i%3)*1.5,0,floor(i/3.0)*1.5)
				_spawn("pine" if i%3 else "oak",-1,p*sign_team+MapRoutes.home_offset(team))
		for i in 6: _spawn("berry",-1,Vector3(-17+(i%2)*1.5,0,11+floor(i/2.0)*1.5)*sign_team+MapRoutes.home_offset(team))
	# Mirrored forward expansion groves: modest extra supply, not a 2.78x
	# multiplication of expensive tree nodes. Starting travel/economy is intact.
	for team in 2:
		var sign_team=1.0 if team==0 else -1.0
		for i in 6: _spawn("pine" if i%3 else "oak",-1,_point(_cell(Vector3(-13+(i%3)*1.5,0,8+floor(i/3.0)*1.5)))*sign_team)
		for i in 3: _spawn("berry",-1,_point(_cell(Vector3(-9+i*1.5,0,11)))*sign_team)
	# Three antipodal pairs centered inside cells, so the contested supply has
	# mirrored local footprints, not merely equal node counts. Full routes
	# still include the inherited home groves and need paired simulation QA.
	for p in [Vector3(-3.5,0,-1.5),Vector3(-0.5,0,-1.5),Vector3(2.5,0,-1.5)]:
		_spawn("berry",-1,p); _spawn("berry",-1,-p)

func _spawn(kind: String, team: int, p: Vector3, complete=true, resource_capacity_milli=-1):
	var category="unit" if kind in ["villager","scout","spearman","archer"] else ("resource" if kind in ["pine","oak","berry"] else "building")
	if category=="building": p=_snap_build_position(kind,p)
	var n=Node3D.new(); add_child(n); n.position=p
	var e={"path":PackedVector3Array(),"path_version":-1,"last_damage_tick":-1000,"mode":"DEFEND","anchor":p,"auto_target":false,"stuck":0.0,"last_known":p,"id":next_id,"kind":kind,"team":team,"pos":p,"node":n,"category":category,"alive":true,"hp":MAX_HP.get(kind,200) if complete else ceili(MAX_HP.get(kind,200)*0.1),"max_hp":MAX_HP.get(kind,200),"state":"idle","target":-1,"dest":p,"cooldown_ticks":0,"carry":0.0,"carry_type":"","resource_target":-1,"queue":[],"next_spawn_check_tick":0,"build_ticks":0,"construction_hcap":MAX_HP.get(kind,200) if complete else ceili(MAX_HP.get(kind,200)*0.1),"progress":1.0 if complete else 0.0,"built":complete,"ring":null,"body":null,"bar":null,"bar_fill":null,"anim":rng.randf()*TAU,"radius":Rules.UNIT_RADIUS}
	next_id+=1; entities.append(e)
	e.death_observed_by=[false,false]
	e.cost_receipt_id=""; e.work_ticks=0; e.last_repair_tick=-1
	e.gather_type=""
	e.dropoff_failures={}; e.dropoff_failure_revision=work_memory[team].revision if team>=0 else -1
	if kind=="villager":
		var registered=economy.register_worker(e.id,team)
		assert(registered.ok)
	elif category=="resource":
		var capacity=resource_capacity_milli if resource_capacity_milli>=0 else int(MAX_HP[kind])*Economy.SCALE
		var registered=economy.register_node(e.id,_resource_type(e),capacity)
		assert(registered.ok)
	_project_economy_entity(e)
	if category=="unit": progress_serial+=1
	var body=Node3D.new(); n.add_child(body); e.body=body
	if category=="unit":
		_unit_visual(body,kind,team)
	elif category=="resource":
		if kind in ["pine","oak"]:
			_tree_visual(body,Vector3.ZERO,kind,0.85+rng.randf()*0.2)
		elif models.has(kind): body.add_child(models[kind].instantiate())
		elif kind=="gold":
			for i in 3:
				var rock=_box(body,Vector3((i-1)*0.25,0.3+i*0.15,0),Vector3(0.7,0.6,0.65),Color("c4ab61")); rock.rotation=Vector3(0.2,i*0.8,0.2)
		else:
			_cylinder(body,Vector3(0,0.4,0),0.55,0.8,Color("57744d"),0.4,7)
			for i in 7: _box(body,Vector3(cos(i)*0.45,0.7,sin(i)*0.45),Vector3.ONE*0.14,Color("b95150"))
		e.radius=0.7 if kind in ["pine","oak"] else 0.55
	else:
		_building_visual(body,kind,team)
		e.radius=2.0 if kind=="town_center" else (1.5 if kind in ["barracks","range"] else 1.0)
		if not complete: ConstructionVisual.apply(body,kind,false,0.0)
	var ring_root=Node3D.new(); n.add_child(ring_root)
	var ring=TorusMesh.new(); ring.inner_radius=e.radius+0.16; ring.outer_radius=e.radius+0.23; ring.rings=32; ring.ring_segments=5
	_mesh(ring_root,ring,Vector3(0,0.09,0),GOLD if team!=1 else RED)
	ring_root.visible=false; e.ring=ring_root
	if category!="resource":
		var bar=Node3D.new(); n.add_child(bar); bar.position.y=1.95 if category=="unit" else 4.5
		_box(bar,Vector3.ZERO,Vector3(1.05,0.07,0.16),DARK)
		var fill=_box(bar,Vector3(0,0.05,0),Vector3(1.0,0.07,0.15),Color("83bb83") if team==0 else Color("d97c65"))
		# Horizontal unit bars retain the original projected box width, including depth.
		if category=="unit" and is_instance_valid(camera):
			bar.rotation.y=camera.rotation.y
			bar.scale.x=(1.05*absf(camera.global_basis.x.x)+0.16*absf(camera.global_basis.x.z))/1.05
		bar.visible=false; e.bar=bar; e.bar_fill=fill
	return e

func _health_bar_fill_scale(record, bar):
	var fraction=maxf(0.01,float(record.hp)/record.max_hp)
	if record.category!="unit" or not is_instance_valid(camera): return fraction
	# Preserve the old centered fill's whole projected width, even near empty.
	return (fraction*absf(camera.global_basis.x.x)+0.15*absf(camera.global_basis.x.z))/bar.scale.x

func _unit_visual(_parent, _kind, _team):
	# Rigs are instantiated only by the observation presenter, not on hidden
	# authority actors. Missing assets are an explicit incomplete-candidate error.
	pass

func _building_visual(parent,kind,team):
	if kind in MatureVisuals.BUILDING_KINDS:
		# Native candidate bounds already fit Rules footprints. No legacy mesh scaling.
		parent.add_child(MatureVisuals.instantiate_asset(kind,0,RED if team==1 else BLUE))
		return
	var col=BLUE if team==0 else RED
	if kind=="farm":
		_box(parent,Vector3(0,0.07,0),Vector3(2.5,0.12,2.5),Color("846944"))
		for x in 6:
			for z in 5:
				_box(parent,Vector3(-1+x*0.38,0.3,-0.9+z*0.4),Vector3(0.12,0.48,0.15),Color("d1bf73"))
		return
	var s=1.4 if kind=="town_center" else 1.0
	_box(parent,Vector3(0,1*s,0),Vector3(2.7*s,2*s,2.3*s),Color("e1d6ac"))
	_box(parent,Vector3(0,0.18,0),Vector3(3*s,0.36,2.6*s),Color("a5a18c"))
	for x in [-1,1]:
		for z in [-1,1]: _box(parent,Vector3(x*1.3*s,1*s,z*1.1*s),Vector3(0.16,2*s,0.16),Color("68533c"))
	_cylinder(parent,Vector3(0,2.7*s,0),2.15*s,1.5*s,col,0,4).rotation.y=PI/4
	_box(parent,Vector3(0,0.7,-1.17*s),Vector3(0.65,1.3,0.12),Color("63523a"))
	_cylinder(parent,Vector3(0,3.7*s,0),0.05,1.4,Color("76593b"),0.04,6)
	_box(parent,Vector3(0.36,4.2*s,0),Vector3(0.7,0.4,0.035),col)

func _recolor_team(node):
	MatureVisuals.apply_team_color(node,RED)

# --- Fixed-tick simulation and ordered commands ---
func _sync_audio():
	if is_instance_valid(audio_cues): audio_cues.configure(sounds_enabled,paused or game_over or not application_focused or application_suspended)

func _toggle_audio():
	sounds_enabled=not sounds_enabled
	audio_cues.activate(); _sync_audio()
	audio_button.text="音效：開" if sounds_enabled else "音效：關"
	if sounds_enabled: audio_cues.selection(faction_views[0].records(),selected,Time.get_ticks_msec())

func _process(delta):
	_sync_audio()
	frame_counter+=1
	if frame_counter%60==0: _sync_web_display_scale()
	var elapsed=maxf(0.0,delta) if is_finite(delta) else 0.0
	# Focus return may precede its first stale render delta. Consume it even
	# when still paused, so a later explicit resume keeps ordinary frame time.
	if discard_return_delta:
		elapsed=0.0; discard_return_delta=false
	if not paused and not game_over and not test_mode and application_focused and not application_suspended:
		tick_accumulator+=elapsed
		var steps=0
		while tick_accumulator+0.000000001>=Rules.TICK and steps<5 and not paused and not game_over:
			tick_accumulator=maxf(0.0,tick_accumulator-Rules.TICK)
			_tick(Rules.TICK); steps+=1
		if paused or game_over: tick_accumulator=0.0
	else: tick_accumulator=0.0
	var visual_delta=minf(elapsed,0.1)
	if not game_over and application_focused and not application_suspended: _camera_input(visual_delta)
	_camera_update()
	_update_visuals(visual_delta)
	if frame_counter%4==0: _update_hud(); _refresh_fog()
	if is_instance_valid(minimap): minimap.queue_redraw()
	if toast_time>0:
		toast_time-=visual_delta
		toast_label.visible=true
	else: toast_label.visible=false
	if marker_time>0:
		marker_time-=visual_delta; order_marker.visible=true
		order_marker.scale=Vector3.ONE*(1.0+marker_time*0.25)
	else:
		order_marker.visible=false
		# Reuse the existing order ring for the selected producer's owned plan.
		if selected.size()==1:
			var record=faction_views[0].get_record(selected[0])
			var point=record.get("rally_point",Vector3.INF)
			if record.get("owned",false) and point!=Vector3.INF:
				order_marker.position=point; order_marker.scale=Vector3.ONE; order_marker.visible=true
	if not build_mode.is_empty(): _update_ghost()

func _tick(dt):
	if paused or game_over: return
	var previous_progress=progress_serial
	tick_count+=1; game_time=tick_count*Rules.TICK; last_path_queries=0
	var batch=commands.duplicate(); commands.clear()
	batch.sort_custom(func(a,b): return a.get("sequence",0)<b.get("sequence",0))
	for command in batch: _execute(command)
	_process_path_requests()
	_begin_unit_motion()
	owned_motion_witness_tick=tick_count # Projection freshness only; movement authority is unchanged.
	for ent in traffic_priority_order: _move_unit_phase(ent,dt)
	_update_vision(false)
	pending_damage.clear()
	for ent in entities:
		if ent.alive and ent.category=="unit": _update_unit(ent,dt)
	for ent in entities:
		if ent.alive and ent.category=="building": _update_production(ent,dt,false)
	_process_ready_production()
	# Settle issued attack IDs once, after all work, then resolve deaths together.
	pending_damage=attack_ledger.settle()
	# Every attack on this tick observes the same live set. Resolve deaths together.
	for id in pending_damage:
		var target=_get_entity(id)
		if not target.is_empty() and target.alive:
			target.hp-=pending_damage[id]; target.last_damage_tick=tick_count
			if pending_damage[id]>0 and target.hp>0 and target.category=="unit": _note_unit_action(target,"hit")
			if pending_damage[id]>0: progress_serial+=1
	for ent in entities:
		if ent.alive and ((ent.category=="resource" and economy.node_view(ent.id).remaining_milli<=0) or (ent.category!="resource" and ent.hp<=0)): _kill(ent)
	_publish_faction_views()
	_sync_audio()
	audio_cues.observe(faction_views[0].records(),tick_count,Time.get_ticks_msec())
	for team in 2:
		recovery_ticks[team]=recovery_ticks[team]+1 if EndRules.irrecoverable(_recovery_view(team)) else 0
	no_progress_ticks=no_progress_ticks+1 if progress_serial==previous_progress else 0
	_check_end()
	_sync_audio()
	if not game_over and no_progress_ticks>=EndRules.NO_PROGRESS_TICKS:
		paused=true; inactivity_paused=true; tick_accumulator=0; _cancel_mode()
		_sync_audio()
		_message("180 秒內沒有採集、建造或交戰進展，已暫停。按繼續可重設計時。",INF)
	if ai_enabled and not game_over and not paused and tick_count%20==0: _ai_update()

func _submit(type: String, data: Dictionary={}, team=0):
	if paused or game_over:
		_reject_command(team,"目前已暫停，請按繼續。" if paused else "戰役已結束。")
		return
	command_sequence+=1
	var command=data.duplicate(true)
	command.type=type; command.team=team; command.sequence=command_sequence; command.enqueue_tick=tick_count
	command.command_id=data.get("command_id",str(command_sequence))
	commands.append(command)

func _reject_command(team,reason):
	if team==0: _message(reason,3)
	return false

func _execute(command):
	var team=command.team
	if team not in [0,1]: return
	if command.has("command_id"):
		var dedup_key=str(team)+":"+str(command.command_id)
		if processed_command_ids.has(dedup_key): return
		processed_command_ids[dedup_key]=true
	match command.type:
		"order":
			var target_id=command.get("target",-1)
			var target=_get_entity(target_id)
			# An entity-target command is not a ground MOVE. A target that became
			# invalid before execution must leave prior orders/paths unchanged.
			if target_id>=0 and (target.is_empty() or not _visible_to(target,team) or not target.alive):
				return _reject_command(team,"目標已失效或不在視野內，請重新落指令。")
			var index=0
			var order_ids=command.ids.duplicate()
			# Only ground group MOVE uses ID allocation. Build takeover intentionally
			# retains submitted member order (the final valid builder owns the site).
			var reserved_destinations={}
			if target.is_empty(): order_ids.sort()
			var applied_ids={}
			for id in order_ids:
				if target.is_empty() and applied_ids.has(id): continue
				applied_ids[id]=true
				var ent=_get_entity(id)
				if ent.is_empty() or not ent.alive or ent.team!=team or ent.category!="unit": continue
				# Resolve each unit independently: cargo delivery and construction win
				# over repair. Rejected repair must not clear pending paths/retries.
				var intent=_target_order_intent(ent,target,team)
				if intent=="repair" and not _repair_order_allowed(ent,target):
					_reject_command(team,"受傷後五秒內無法開始修理。")
					index+=1
					continue
				if team==0: _path_new_command(ent)
				if intent!="move": _order(ent,intent,target.id)
				elif not target.is_empty(): _order_move(ent,command.position)
				else:
					_order_move(ent,command.position,reserved_destinations,order_ids)
					reserved_destinations[_cell(ent.dest)]=true
				index+=1
			if index==0: return _reject_command(team,"請選取自己的存活單位。")
		"stop":
			var applied=false
			for id in command.ids:
				var ent=_get_entity(id)
				if not ent.is_empty() and ent.alive and ent.team==team and ent.category=="unit":
					if team==0: _path_new_command(ent)
					_set_stance(ent,"STOP")
					applied=true
			if not applied: return _reject_command(team,"請選取自己的存活單位。")
		"defend":
			var applied=false
			for id in command.ids:
				var ent=_get_entity(id)
				if not ent.is_empty() and ent.alive and ent.team==team and ent.category=="unit":
					if team==0: _path_new_command(ent)
					_set_stance(ent,"DEFEND")
					applied=true
			if not applied: return _reject_command(team,"請選取自己的存活單位。")
		"rally": _set_ground_rally(command.get("building",-1),command.get("position",Vector3.INF),team,command.get("clear",false))
		"train": _enqueue_train(command.building,command.kind,team)
		"cancel_train": _cancel_train(command.building,team)
		"build": _place_building(command.kind,command.position,command.builder,team)
		"cancel_build":
			var ent=_get_entity(command.building)
			if not ent.is_empty() and ent.alive and not ent.built and ent.team==team:
				_cancel_construction(ent)
			else: return _reject_command(team,"只能取消自己的未完成施工。")
		"demolish":
			var ent=_get_entity(command.get("building",-1))
			if not _can_demolish(ent,team):
				return _reject_command(team,"只能拆除自己的已完成建築，主堡不可拆除。")
			# BLD01: no refund. Reuse destruction's single cleanup transaction for
			# queues, population reservations, footprint and navigation revision.
			_kill(ent)
		"surrender":
			var castle=_first(team,"town_center")
			if not castle.is_empty(): _surrender_intent[team]=true
			else: return _reject_command(team,"目前沒有可投降的對局。")
		_: return _reject_command(team,"未知指令。")

func _get_entity(id):
	if id<0 or id>=entities.size(): return {}
	return entities[id]

func _can_demolish(ent,team):
	return not ent.is_empty() and ent.alive and ent.category=="building" and ent.built and ent.team==team and ent.kind!="town_center"

func _first(team,kind):
	for ent in entities:
		if ent.alive and ent.team==team and ent.kind==kind: return ent
	return {}

func _count(team,kind):
	var count=0
	for ent in entities:
		if ent.alive and ent.team==team and ent.kind==kind: count+=1
	return count

func _population(team, include_reserved=true):
	var result=0
	for ent in entities:
		if not ent.alive or ent.team!=team: continue
		if ent.category=="unit": result+=1
		elif include_reserved: result+=ent.queue.size()
	return result

func _capacity(team):
	var total=0
	for ent in entities:
		if ent.alive and ent.team==team and ent.built:
			if ent.kind=="town_center": total+=10
			elif ent.kind=="house": total+=5
	return mini(total,Rules.POP_LIMIT)

func _reset_economy(initial_stocks_units):
	economy=Economy.new(); economy_sequence=0
	var initialized=economy.initialize(initial_stocks_units)
	assert(initialized.ok)

func _cargo_amount(ent):
	return economy.worker_view(ent.id).get("cargo_milli",0)

func _cargo_type(ent):
	return economy.worker_view(ent.id).get("cargo_type","")

func _project_economy_entity(ent):
	# This is the sole writer of presentation cargo and resource HP caches.
	# Combat HP is independent; generic death cleanup never trusts resource HP.
	if ent.kind=="villager":
		var cargo=economy.worker_view(ent.id)
		ent.carry=cargo.cargo_milli/1000.0; ent.carry_type=cargo.cargo_type
	elif ent.category=="resource":
		ent.hp=economy.node_view(ent.id).remaining_milli/1000.0

func _can_pay(cost,team):
	return economy.can_pay(cost,team)

func _pay(cost,team,refund_policy=Economy.REFUND_UNSTARTED,purpose="purchase",transaction_id=""):
	if transaction_id.is_empty():
		economy_sequence+=1; transaction_id="payment:%d" % economy_sequence
	var payment=economy.pay(transaction_id,team,cost,refund_policy,purpose)
	if payment.applied and not cost.is_empty(): progress_serial+=1
	return payment

func _cancel_construction(ent):
	if ent.is_empty() or not ent.alive or ent.built: return false
	var receipt_id=ent.get("cost_receipt_id","")
	if not receipt_id.is_empty():
		var result=economy.cancel_cost("cancel:"+receipt_id,receipt_id,ent.team)
		if not result.applied: return false
	# Unpaid setup-only sites can be removed but never mint a nominal refund.
	_kill(ent)
	return true

# Producer-owned ground destination only. No entity target, harvest order,
# spawn override or route probe is stored. Validate faction-known cells only.
func _set_ground_rally(id,p,team,clear=false):
	var building=_get_entity(id)
	if building.is_empty() or not building.alive or building.team!=team or not building.built or not Rules.PRODUCES.has(building.kind):
		return _reject_command(team,"請選取自己的已完成生產建築。")
	if clear:
		building.erase("rally_point")
		if team==0: _message("已取消集合點；新單位在出口待命。")
		return true
	if not p is Vector3 or not p.is_finite(): return _reject_command(team,"請點可見空地。")
	# Reject outside points before _cell's clamping. Height carries no intent.
	if absf(p.x)>=Rules.MAP_HALF-Rules.MAP_BORDER or absf(p.z)>=Rules.MAP_HALF-Rules.MAP_BORDER:
		return _reject_command(team,"請在戰場設定集合點。")
	var cell=_cell(p)
	if visible_cells[team][_cell_index(p)]==0: return _reject_command(team,"請點可見空地。")
	_refresh_work_memory()
	if work_memory[team].grid.is_point_solid(cell): return _reject_command(team,"集合點需要空地。")
	building.rally_point=_point(cell)
	if team==0: _message("集合點已設定；新單位自動移動。",4)
	return true

func _enqueue_train(id,kind,team):
	var building=_get_entity(id)
	if building.is_empty() or not building.alive or building.team!=team or not building.built:
		return _reject_command(team,"請選取自己的已完成生產建築。")
	if Rules.PRODUCES.get(building.kind,"")!=kind: return _reject_command(team,"這座建築不能訓練該兵種。")
	if building.queue.size()>=5: return _reject_command(team,"生產隊列已滿。")
	if _population(team)>=_capacity(team):
		if team==0: _message("人口已滿，先建民居。每方最多 20 人。")
		return false
	var payment=_pay(COSTS[kind],team)
	if not payment.applied:
		if team==0: _message("資源不足，未有扣款。")
		return false
	building.queue.append({"receipt_id":payment.receipt_id,"queue_id":next_queue_id,"kind":kind,"remaining_ticks":Rules.TRAIN_TICKS[kind],"started":false,"next_retry_tick":0,"candidate_cursor":0})
	next_queue_id+=1
	return true

func _spawn_exit(building,order):
	# Maximum building is 4x4, so its one-cell outer perimeter has 20 cells.
	# Fixed (x,z) coordinate order; bounded occupancy checks only, never A*.
	# Placement preserves a locally open exit, not exclusive birth cells.
	var candidates=_perimeter_cells(building)
	for cell in candidates:
		spawn_candidate_checks+=1
		if cell.x<Rules.MAP_BORDER or cell.y<Rules.MAP_BORDER or cell.x>Rules.MAP_LAST_PLAYABLE or cell.y>Rules.MAP_LAST_PLAYABLE or navigation.is_point_solid(cell): continue
		var point=_point(cell); var blocked=false
		for unit in entities:
			if unit.alive and unit.category=="unit" and unit.pos.distance_to(point)<0.7: blocked=true; break
		if not blocked: return point
	return Vector3.INF

func _cancel_train(id,team):
	var building=_get_entity(id)
	if building.is_empty() or not building.alive or building.team!=team or building.queue.is_empty():
		return _reject_command(team,"沒有可取消的己方生產項目。")
	var order=building.queue.back()
	var receipt_id=order.get("receipt_id","")
	var refund=economy.cancel_cost("cancel:"+receipt_id,receipt_id,team)
	if not refund.applied: return false
	building.queue.pop_back()
	return true

func _update_production(ent,dt,commit_ready=true):
	if not ent.built or ent.queue.is_empty(): return
	var order=ent.queue[0]
	if order.remaining_ticks>0 and _population(ent.team)>_capacity(ent.team): return
	if not economy.mark_started(order.get("receipt_id",""),ent.team).ok: return
	order.started=true; order.remaining_ticks=maxi(0,order.remaining_ticks-1)
	if order.remaining_ticks<=0 and commit_ready: _try_ready_production(ent)

func _process_ready_production():
	var eligible=[]
	for ent in entities:
		if ent.alive and ent.built and not ent.queue.is_empty() and ent.queue[0].remaining_ticks<=0 and tick_count>=ent.queue[0].next_retry_tick: eligible.append(ent)
	if eligible.is_empty(): return
	eligible.sort_custom(func(a,b): return a.id<b.id)
	var start=0
	for i in eligible.size():
		if eligible[i].id>ready_cursor: start=i; break
	var batch=[]
	for i in mini(64,eligible.size()): batch.append(eligible[(start+i)%eligible.size()])
	ready_cursor=batch.back().id
	# Fair scheduling chooses items, but successful commits remain globally ordered.
	batch.sort_custom(func(a,b): return a.id<b.id or (a.id==b.id and a.queue[0].queue_id<b.queue[0].queue_id))
	for ent in batch: _try_ready_production(ent)

func _try_ready_production(ent):
	if not ent.alive or ent.queue.is_empty(): return
	var order=ent.queue[0]
	if order.remaining_ticks>0 or tick_count<order.next_retry_tick: return
	order.next_retry_tick=tick_count+20
	spawn_availability_polls+=1
	if _population(ent.team,false)>=_capacity(ent.team): return
	var spawn_point=_spawn_exit(ent,order)
	if spawn_point==Vector3.INF: return
	# This is the commit point. Prior commits are already in entities/population.
	if _population(ent.team,false)>=_capacity(ent.team) or navigation.is_point_solid(_cell(spawn_point)): return
	for unit in entities:
		if unit.alive and unit.category=="unit" and unit.pos.distance_to(spawn_point)<0.7: return
	var receipt_id=order.get("receipt_id","")
	var fulfilled=economy.fulfill_cost("fulfilled:"+receipt_id,receipt_id,ent.team)
	if not fulfilled.applied: return
	ent.queue.pop_front()
	spawn_commit_order.append({"building":ent.id,"queue":order.queue_id,"tick":tick_count})
	var unit=_spawn(order.kind,ent.team,spawn_point)
	# Birth/receipt commit above is unchanged. Only the newborn inherits the
	# current ground destination, once, through ordinary bounded MOVE routing.
	if ent.has("rally_point"): _order_move(unit,ent.rally_point)
	trained_total[ent.team]+=1
	if ent.team==0 and order.kind in ["spearman","archer"]: demo_tutorial.record("soldier")
	if ent.team==0: _message(Rules.NAMES[order.kind]+"已準備好。",2.5)
	if ent.team==1 and unit.kind=="villager" and not ent.has("rally_point"): _assign_worker(unit)

# --- Grid navigation, atomic occupancy and construction ---
func _cell(p): return Vector2i(clampi(floori(p.x+Rules.MAP_HALF),0,Rules.MAP_SIZE-1),clampi(floori(p.z+Rules.MAP_HALF),0,Rules.MAP_SIZE-1))
func _point(cell): return Vector3(cell.x-Rules.MAP_HALF+0.5,0,cell.y-Rules.MAP_HALF+0.5)
func _cell_index(p):
	var c=_cell(p)
	return c.y*Rules.MAP_SIZE+c.x

func _snap_build_position(kind,p):
	return Vector3(floorf(p.x),0,floorf(p.z)) if Rules.FOOTPRINT.get(kind,1)%2==0 else _point(_cell(p))

func _occupied_cells(ent):
	var cells=[]
	var c=Vector2i(floori(ent.pos.x+Rules.MAP_HALF),floori(ent.pos.z+Rules.MAP_HALF))
	var width=Rules.FOOTPRINT.get(ent.kind,1)
	var low=floori(width/2.0)
	var high=width-low-1
	for y in range(c.y-low,c.y+high+1):
		for x in range(c.x-low,c.x+high+1): cells.append(Vector2i(x,y))
	return cells

func _perimeter_cells(ent):
	var footprint=_occupied_cells(ent)
	var first=footprint[0]; var last=footprint.back()
	var result=[]
	for x in range(first.x-1,last.x+2):
		for z in range(first.y-1,last.y+2):
			if x==first.x-1 or x==last.x+1 or z==first.y-1 or z==last.y+1: result.append(Vector2i(x,z))
	return result

func _navigation_rebuild():
	navigation.clear()
	navigation.region=Rect2i(0,0,Rules.MAP_SIZE,Rules.MAP_SIZE)
	navigation.cell_size=Vector2.ONE
	navigation.diagonal_mode=AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	navigation.default_compute_heuristic=AStarGrid2D.HEURISTIC_OCTILE
	navigation.default_estimate_heuristic=AStarGrid2D.HEURISTIC_OCTILE
	navigation.update(); footprints.clear()
	for y in Rules.MAP_SIZE:
		for x in Rules.MAP_SIZE:
			if x<Rules.MAP_BORDER or y<Rules.MAP_BORDER or x>Rules.MAP_LAST_PLAYABLE or y>Rules.MAP_LAST_PLAYABLE: navigation.set_point_solid(Vector2i(x,y))
	for ent in entities:
		if ent.alive and ent.category!="unit":
			for c in _occupied_cells(ent):
				navigation.set_point_solid(c); footprints[c]=ent.id
	navigation_version+=1
	_refresh_work_memory()

func _nearest_free(p,max_ring=8,team=-1,mover={},reserved={},ignore_orders=[]):
	var grid=navigation if team<0 else work_memory[team].grid
	var c=_cell(p)
	for ring in range(max_ring+1):
		var best=Vector3.INF; var best_dist=INF
		for y in range(c.y-ring,c.y+ring+1):
			for x in range(c.x-ring,c.x+ring+1):
				var cell=Vector2i(x,y)
				if x<Rules.MAP_BORDER or y<Rules.MAP_BORDER or x>Rules.MAP_LAST_PLAYABLE or y>Rules.MAP_LAST_PLAYABLE or grid.is_point_solid(cell): continue
				var world=_point(cell); var dist=world.distance_squared_to(p)
				if not mover.is_empty() and not _known_destination_clear(mover,world,reserved,ignore_orders): continue
				if dist<best_dist: best=world; best_dist=dist
		if best!=Vector3.INF: return best
	return Vector3.INF

# Long-range destination/slot checks use current owned state and detached
# observed enemy records only. Hidden units and enemy orders are never queried.
func _known_destination_clear(ent,point,reserved={},ignore_orders=[]):
	if reserved.has(_cell(point)): return false
	for other in entities:
		if other.team!=ent.team or other.category!="unit" or not other.alive or other.id==ent.id: continue
		var clearance=ent.radius+other.radius
		if point.distance_squared_to(other.pos)<clearance*clearance: return false
		if other.id in ignore_orders: continue
		if other.state=="move" and other.get("path_status","") not in [BoundedPath.NO_PATH,BoundedPath.LIMIT_REACHED] and point.distance_squared_to(other.dest)<clearance*clearance: return false
		if other.state in ["gather","deliver"] and other.get("work_approach",Vector3.INF)!=Vector3.INF:
			if point.distance_squared_to(other.work_approach)<clearance*clearance: return false
	for other in faction_views[ent.team].records().values():
		if other.owned or other.remembered or other.category!="unit": continue
		var clearance=ent.radius+other.radius
		if point.distance_squared_to(other.pos)<clearance*clearance: return false
	return true

func _free_adjacent(target,from,avoid_units=false,team=-1,mover={}):
	var grid=navigation if team<0 else work_memory[team].grid
	var best=Vector3.INF; var best_dist=INF
	for cell in _perimeter_cells(target):
		if cell.x<Rules.MAP_BORDER or cell.y<Rules.MAP_BORDER or cell.x>Rules.MAP_LAST_PLAYABLE or cell.y>Rules.MAP_LAST_PLAYABLE or grid.is_point_solid(cell): continue
		var world=_point(cell); var dist=world.distance_squared_to(from)
		if not mover.is_empty() and not _known_destination_clear(mover,world): continue
		if avoid_units:
			var occupied=false
			for unit in entities:
				if unit.alive and unit.category=="unit" and unit.pos.distance_to(world)<0.7: occupied=true; break
			if occupied: continue
		if dist<best_dist: best=world; best_dist=dist
	return best

# --- Faction-known occupancy shared by point and work routing ---
func _is_work_path(ent):
	return ent.state in ["gather","deliver"] or ent.get("path_request_kind","")=="work"

func _work_snapshot(ent):
	return {"id":ent.id,"kind":ent.kind,"category":ent.category,"team":ent.team,"pos":ent.pos,
		"alive":ent.alive,"built":ent.built,"radius":ent.radius,"cells":_occupied_cells(ent)}

func _refresh_work_memory():
	if visible_cells[0].size()!=Rules.MAP_SIZE*Rules.MAP_SIZE: return
	for team in 2:
		var own={}; var owned_cells={}; var observed={}
		for ent in entities:
			if ent.category=="unit": continue
			if ent.team==team:
				if ent.alive:
					own[ent.id]=_work_snapshot(ent); own[ent.id].knowledge_source="owned_current"
					for cell in _occupied_cells(ent): owned_cells[cell]=true
				continue
			# Same center visibility as the existing entity presentation/commands.
			# A hidden center with one revealed footprint cell is NOT observable.
			if _visible_to(ent,team):
				observed[ent.id]=_work_snapshot(ent)
				observed[ent.id].knowledge_source="visible_static_entity_observation"
		var change=work_memory[team].observe(observed,own,owned_cells,tick_count)
		if change.records_changed or not change.cells.is_empty():
			for ent in entities:
				if ent.alive and ent.team==team and ent.category=="unit":
					if _is_work_path(ent): _work_navigation_changed(ent,change)
					else: _path_navigation_changed(ent,change.cells)

func _work_navigation_changed(ent,change):
	_path_state(ent)
	var memory=work_memory[ent.team]
	ent.dropoff_failures.clear(); ent.dropoff_failure_revision=memory.revision
	# A prior ordinary-route limit is not cleared by merely switching to work.
	if ent.work_route_revision<0: return
	if ent.path_status in [BoundedPath.NO_PATH,BoundedPath.LIMIT_REACHED,"NO_WORK"]:
		ent.path_status="IDLE"; ent.path_reason=""; ent.path_failures=0
	var affected=false; var previous=_cell(ent.pos)
	for point in ent.path:
		var cell=_cell(point)
		if change.cells.has(cell) or change.cells.has(previous): affected=true
		if cell.x!=previous.x and cell.y!=previous.y:
			if change.cells.has(Vector2i(previous.x,cell.y)) or change.cells.has(Vector2i(cell.x,previous.y)): affected=true
		previous=cell
	var known=_known_work_target(ent)
	if known.is_empty() or not known.alive: affected=true
	if affected:
		ent.path=PackedVector3Array(); ent.work_approach=Vector3.INF; ent.work_target_id=-1
		if not ent.path_pending: ent.path_status="IDLE"
	ent.work_route_revision=memory.revision

func _known_work_target(ent):
	var records=work_memory[ent.team].resources if ent.state=="gather" else work_memory[ent.team].structures
	return records.get(ent.target,{})

func _nearest_known_resource(p,kind,team):
	var best={}; var distance=INF
	for known in work_memory[team].resources.values():
		if not known.alive or (_resource_type(known)!=kind and known.kind!=kind): continue
		var d=known.pos.distance_squared_to(p)
		if d<distance or (d==distance and (best.is_empty() or known.id<best.id)):
			distance=d; best=known
	return best

func _work_candidates(ent):
	var records=work_memory[ent.team].resources if ent.state=="gather" else work_memory[ent.team].structures
	var ranked=[]
	for known in records.values():
		if not known.alive: continue
		if ent.state=="gather" and _resource_type(known)!=_gather_intent(ent): continue
		if ent.state=="deliver" and (not known.built or known.kind not in ["town_center","storehouse"]): continue
		ranked.append(known)
	var preferred=-1 if ent.work_any_target else ent.target
	ranked.sort_custom(func(a,b):
		if (a.id==preferred)!=(b.id==preferred): return a.id==preferred
		var da=a.pos.distance_squared_to(ent.pos); var db=b.pos.distance_squared_to(ent.pos)
		return a.id<b.id if da==db else da<db)
	var result=[]
	for i in ranked.size():
		var approaches=[]
		for cell in _perimeter_cells(ranked[i]):
			if _known_destination_clear(ent,_point(cell)): approaches.append(cell)
		if not approaches.is_empty(): result.append({"target_id":ranked[i].id,"rank":i,"approaches":approaches})
	return result

func _plan_work_path(ent):
	_path_state(ent)
	if ent.path_status in [BoundedPath.NO_PATH,BoundedPath.LIMIT_REACHED,"NO_WORK"] or ent.path_pending: return
	if ent.path_status=="WAIT_SLOT" and tick_count<ent.path_next_attempt_tick: return
	ent.path_request_kind="work"; ent.path_revision=work_memory[ent.team].revision; ent.path_pending=true; ent.path_status="QUEUED"; ent.path_reason="waiting_for_work_search"
	ent.path_request_state=ent.state; ent.path_request_target=ent.target; ent.path_request_epoch=ent.work_epoch
	ent.path=PackedVector3Array(); ent.path_expanded=0
	path_requests.append(ent.id)

func _at_work_approach(ent,target,adopt=false):
	_path_state(ent)
	if ent.work_target_id==target.id and ent.work_approach!=Vector3.INF:
		return ent.pos.distance_to(ent.work_approach)<0.1 and _cell(ent.work_approach) in _perimeter_cells(target) and not navigation.is_point_solid(_cell(ent.work_approach)) and _known_destination_clear(ent,ent.work_approach) and _unit_step_is_free(ent,ent.pos)
	# Already at a valid approach (e.g. a new command issued at the building)
	# needs only local geometric validation, never nearest-cell reselection.
	for cell in _perimeter_cells(target):
		var point=_point(cell)
		if ent.pos.distance_to(point)<0.1 and navigation.region.has_point(cell) and not navigation.is_point_solid(cell) and _known_destination_clear(ent,point) and _unit_step_is_free(ent,ent.pos):
			if adopt:
				ent.work_target_id=target.id; ent.work_approach=point; ent.work_route_revision=work_memory[ent.team].revision
			return true
	return false

func _move_work(ent,dt):
	_path_state(ent)
	var target=_known_work_target(ent)
	if target.is_empty() or not target.alive: return
	if _at_work_approach(ent,target,true): return
	if ent.path_status in [BoundedPath.NO_PATH,BoundedPath.LIMIT_REACHED,"NO_WORK"]: return
	if ent.work_approach==Vector3.INF or ent.path.is_empty(): _plan_work_path(ent); return
	var next=ent.path[0]
	if not _path_step_is_free(ent.pos,next):
		ent.path=PackedVector3Array(); ent.work_approach=Vector3.INF; ent.work_target_id=-1
		_refresh_work_memory(); _plan_work_path(ent); return
	if _anticipate_local_traffic(ent,next): return
	var vector=next-ent.pos
	if vector.length()<0.001: ent.path.remove_at(0); return
	var step=vector.normalized()*minf(Rules.SPEED[ent.kind]*dt,vector.length())
	var next_pos=ent.pos+step
	if not _path_step_is_free(ent.pos,next_pos):
		ent.path=PackedVector3Array(); ent.work_approach=Vector3.INF; ent.work_target_id=-1
		_refresh_work_memory(); _plan_work_path(ent); return
	_apply_unit_step(ent,next_pos,dt)
	if not ent.path.is_empty() and ent.path[0]==next and ent.pos.distance_to(next)<0.001:
		ent.path.remove_at(0); ent.traffic_progress_tick=tick_count

func _resume_gather(ent):
	var known=work_memory[ent.team].resources.get(ent.resource_target,{})
	var original=not known.is_empty() and known.alive and _resource_type(known)==_gather_intent(ent)
	if not original: known=_nearest_known_resource(ent.pos,_gather_intent(ent),ent.team)
	if known.is_empty(): _path_cancel_pending(ent); ent.state="idle"; ent.target=-1; return
	if ent.path_status==BoundedPath.NO_PATH: ent.path_status="IDLE"; ent.path_reason=""
	_order(ent,"gather",known.id); ent.work_any_target=not original

func _update_work(ent):
	if ent.kind!="villager": _set_stance(ent,"STOP"); return
	_path_state(ent)
	var known=_known_work_target(ent)
	if ent.state=="gather":
		if known.is_empty() or not known.alive:
			if _cargo_amount(ent)>0: _route_to_dropoff(ent)
			else: _resume_gather(ent)
			return
		if ent.gather_type.is_empty(): ent.gather_type=_resource_type(known)
		if _cargo_amount(ent)>=Economy.CARGO_CAP or (_cargo_amount(ent)>0 and _cargo_type(ent)!=_resource_type(known)):
			_route_to_dropoff(ent); return
	else:
		if known.is_empty() or not known.built or known.kind not in ["town_center","storehouse"]:
			_route_to_dropoff(ent); return
	if ent.path_status in [BoundedPath.NO_PATH,BoundedPath.LIMIT_REACHED,"NO_WORK"]:
		if ent.state=="deliver": _cargo_idle(ent)
		else: _path_cancel_pending(ent); ent.state="idle"
		return
	if not _at_work_approach(ent,known,true): return
	# Resource authority is consulted only for a currently observed local action.
	if ent.state=="gather" and visible_cells[ent.team][_cell_index(known.pos)]==0: return
	var target=_get_entity(known.id)
	if ent.state=="gather":
		if target.is_empty() or not target.alive: _refresh_work_memory(); return
		var gathered=economy.gather_tick(ent.id,target.id,tick_count)
		if gathered.applied:
			if ent.team==0: demo_tutorial.record("gather")
			_note_unit_action(ent,"gather_wood" if _resource_type(target)=="wood" else "gather_food",target.pos)
			ent.path=PackedVector3Array(); progress_serial+=1
			_project_economy_entity(ent); _project_economy_entity(target)
		if economy.node_view(target.id).remaining_milli<=0: _kill(target)
	else:
		if not _valid_dropoff(ent,target): _route_to_dropoff(ent); return
		if _cargo_amount(ent)>0 and not _deposit_cargo(ent,target).applied: return
		_resume_gather(ent)

func _path_state(ent):
	if ent.has("path_status"): return
	ent.path_status="IDLE"; ent.path_reason=""; ent.path_pending=false
	ent.path_request_goal=ent.pos; ent.path_revision=work_memory[ent.team].revision
	ent.path_has_attempt=false; ent.path_retry_ticks=[]; ent.path_failures=0
	ent.path_next_attempt_tick=0; ent.path_searches=0; ent.path_initial_searches=0; ent.path_retry_searches=0; ent.path_expanded=0
	ent.path_request_kind="point"; ent.work_epoch=0; ent.path_request_epoch=0
	ent.work_approach=Vector3.INF; ent.work_target_id=-1; ent.work_route_revision=-1; ent.work_any_target=false
	ent.traffic_goal=Vector3.INF; ent.traffic_best_distance=INF; ent.traffic_progress_tick=tick_count
	ent.traffic_replans=0; ent.traffic_last_replan=tick_count; ent.traffic_route=false; ent.work_slot_wait=-1; ent.traffic_path_length=0; ent.traffic_command_origin=ent.pos; ent.traffic_gate_since=-1

func _path_new_command(ent):
	_path_state(ent)
	path_requests.erase(ent.id)
	ent.path_pending=false; ent.path_status="IDLE"; ent.path_reason=""
	ent.path_has_attempt=false; ent.path_retry_ticks.clear(); ent.path_failures=0
	ent.path_next_attempt_tick=tick_count; ent.path_revision=work_memory[ent.team].revision
	ent.path=PackedVector3Array(); ent.path_version=-1; ent.path_expanded=0
	_reset_traffic(ent)

func _path_navigation_changed(ent,changed_cells):
	_path_state(ent)
	ent.path_revision=work_memory[ent.team].revision
	# Terminal routes may be tried again after the map changes. Keep the
	# rolling retry timestamps: unrelated rebuilds must not bypass the cap.
	if ent.path_status in [BoundedPath.NO_PATH,BoundedPath.LIMIT_REACHED] and not (ent.state=="idle" and ent.traffic_route):
		ent.path_status="IDLE"; ent.path_reason=""; ent.path_failures=0
		ent.path_version=-1
	if ent.path.is_empty(): return
	var previous=_cell(ent.pos)
	var affected=changed_cells.has(previous)
	for point in ent.path:
		var cell=_cell(point)
		if changed_cells.has(cell): affected=true
		if cell.x!=previous.x and cell.y!=previous.y:
			if changed_cells.has(Vector2i(previous.x,cell.y)) or changed_cells.has(Vector2i(cell.x,previous.y)): affected=true
		previous=cell
	if affected:
		ent.path=PackedVector3Array(); ent.path_version=-1; ent.path_status="IDLE"
	else: ent.path_version=work_memory[ent.team].revision

func _path_stop(ent,status,reason):
	ent.path_status=status; ent.path_reason=reason; ent.path_pending=false
	ent.path=PackedVector3Array(); ent.path_version=work_memory[ent.team].revision
	if _is_work_path(ent):
		ent.work_route_revision=work_memory[ent.team].revision
		ent.work_approach=Vector3.INF; ent.work_target_id=-1
	if ent.team==0: _message("路線受阻，請重新落指令。",2)

func _plan_path(ent,destination):
	_path_state(ent)
	if ent.path_status in [BoundedPath.NO_PATH,BoundedPath.LIMIT_REACHED]: return false
	ent.path_request_goal=destination
	ent.path_request_kind="point"
	if ent.path_pending: return false
	ent.path_pending=true; ent.path_status="QUEUED"; ent.path_reason="waiting_for_search"
	ent.path_request_state=ent.state; ent.path_request_target=ent.target; ent.path_request_epoch=ent.work_epoch
	ent.path=PackedVector3Array(); ent.path_expanded=0
	path_requests.append(ent.id)
	return false

func _known_opposing_flow_costs(ent,goal):
	# Owned MOVE plans are known command state. Prefer distinct lanes for
	# opposing owned streams, before contact compresses them into a deadlock.
	# This is a soft cost, never a blocker, and never reads enemy orders.
	var costs={}
	if ent.state!="move": return costs
	var direction=(goal-ent.pos).normalized()
	for other in entities:
		if other.team!=ent.team or not other.alive or other.category!="unit" or other.id==ent.id or other.state!="move" or other.path.is_empty(): continue
		if direction.dot((other.dest-other.pos).normalized())>-0.5: continue
		for point in other.path: costs[_cell(point)]=20
	return costs

func _process_path_requests():
	# All ordinary and work routes share this gate, even repeated same-tick drains.
	if path_budget_tick!=tick_count:
		path_budget_tick=tick_count; last_path_queries=0; last_path_expansions=0
	var batch=path_requests.duplicate(); path_requests.clear()
	var deferred=[]; var retries=[]
	for id in batch:
		var ent=_get_entity(id)
		if ent.is_empty() or not ent.alive or not ent.get("path_pending",false): continue
		if ent.state!=ent.path_request_state or ent.target!=ent.path_request_target or ent.work_epoch!=ent.path_request_epoch:
			_path_cancel_pending(ent); ent.path_reason="request_superseded"; continue
		var work=ent.path_request_kind=="work"
		if not work and ent.path_request_target>=0 and ent.path_request_state in ["build","repair","deliver"]:
			var target=_get_entity(ent.path_request_target)
			if target.is_empty() or not target.alive:
				_path_cancel_pending(ent); ent.path_reason="target_unavailable"; continue
		if last_path_queries>=4 or tick_count<ent.path_next_attempt_tick:
			deferred.append(id); continue
		while not ent.path_retry_ticks.is_empty() and tick_count-ent.path_retry_ticks[0]>=20:
			ent.path_retry_ticks.pop_front()
		if ent.path_has_attempt and ent.path_retry_ticks.size()>=3:
			if ent.traffic_route: _traffic_stop(ent,"retry_rate_limit")
			else: _path_stop(ent,BoundedPath.LIMIT_REACHED,"retry_rate_limit")
			continue
		var route_grid=work_memory[ent.team].grid
		var candidates=_work_candidates(ent) if work else []
		if work and candidates.is_empty():
			# A busy slot is not NO_PATH. Poll at most once per second, without
			# spending a search; after a finite wait retain cargo and stop safely.
			if ent.work_slot_wait<0: ent.work_slot_wait=tick_count
			if tick_count-ent.work_slot_wait>=TRAFFIC_STALL_TICKS:
				_traffic_stop(ent,"work_slots_busy")
			else:
				ent.path_pending=false; ent.path_status="WAIT_SLOT"; ent.path_reason="known_slots_reserved"
				ent.path_next_attempt_tick=tick_count+20
			continue
		var goal=Vector3.INF if work else _nearest_free(ent.path_request_goal,8,ent.team)
		if not work and goal==Vector3.INF:
			_path_stop(ent,BoundedPath.LIMIT_REACHED,"no_free_destination"); continue
		var start=_cell(ent.pos)
		if not route_grid.region.has_point(start) or route_grid.is_point_solid(start):
			_path_stop(ent,BoundedPath.LIMIT_REACHED,"source_blocked"); continue
		if ent.path_has_attempt:
			ent.path_retry_ticks.append(tick_count); ent.path_retry_searches+=1
		else: ent.path_initial_searches+=1
		ent.path_has_attempt=true; ent.path_searches+=1; last_path_queries+=1
		var reanchor=ent.traffic_route and ent.pos.distance_to(_point(start))>=0.001 and _unit_step_is_free(ent,_point(start))
		var traffic_edges=_local_traffic_edges(ent,start,_point(start) if reanchor else ent.pos) if ent.traffic_route else {}
		var result=WorkPath.search(route_grid,start,candidates,path_expansion_budget,traffic_edges) if work else BoundedPath.search(route_grid,start,_cell(goal),path_expansion_budget,traffic_edges,_known_opposing_flow_costs(ent,goal))
		if ent.traffic_route and result.status==BoundedPath.FOUND and result.path.size()>ent.traffic_path_length+12:
			# A local yield must not silently become a map-wide traffic detour.
			# This is a bounded congestion refusal, never a claim of NO_PATH.
			result.status=BoundedPath.LIMIT_REACHED; result.reason="local_traffic_detour_limit"
		ent.path_expanded=result.expanded; last_path_expansions+=result.expanded
		ent.path_pending=false; ent.path_revision=work_memory[ent.team].revision
		ent.path_status=result.status; ent.path_reason=result.reason
		if result.status==BoundedPath.FOUND:
			if work:
				goal=_point(result.goal); ent.target=result.target_id
				ent.work_target_id=result.target_id; ent.work_approach=goal; ent.work_route_revision=work_memory[ent.team].revision
				if ent.state=="gather": ent.resource_target=result.target_id
				if ent.state=="deliver" and result.frontier_exhausted:
					for candidate in candidates:
						if candidate.target_id==result.target_id: break
						ent.dropoff_failures[candidate.target_id]=true
			ent.path=PackedVector3Array()
			# The search start represents the mover's actual position, not a
			# compulsory return to its cell center (which a neighbor may occupy).
			# Reanchor only when that short physical segment is clear, and use
			# the same chosen origin in the local constrained search.
			if reanchor: ent.path.append(_point(start))
			for i in range(1,result.path.size()): ent.path.append(_point(result.path[i]))
			if ent.path.is_empty() and ent.pos.distance_to(goal)>=0.001: ent.path.append(goal)
			ent.path_version=work_memory[ent.team].revision; ent.dest=goal; ent.path_failures=0
		elif ent.traffic_route:
			# A temporary traffic frontier is not a static NO_PATH proof. Wait
			# through priority rotations, recomputing only at bounded intervals.
			if ent.traffic_replans>=TRAFFIC_MAX_REPLANS:
				_traffic_stop(ent,"local_traffic_blocked" if result.status==BoundedPath.NO_PATH else result.reason)
			else:
				ent.traffic_replans+=1; ent.traffic_last_replan=tick_count
				ent.path_status="QUEUED"; ent.path_reason="waiting_for_local_traffic"; ent.path_pending=true
				ent.path_next_attempt_tick=tick_count+TRAFFIC_REPLAN_TICKS; retries.append(id)
		elif result.status==BoundedPath.NO_PATH:
			_path_stop(ent,BoundedPath.NO_PATH,result.reason)
		elif result.status==WorkPath.INVALID_INPUT or result.reason in ["candidate_limit","approach_limit"]:
			_path_stop(ent,BoundedPath.LIMIT_REACHED,result.reason)
		else:
			ent.path_failures+=1
			if ent.path_failures>=4 or ent.path_retry_ticks.size()>=3:
				_path_stop(ent,BoundedPath.LIMIT_REACHED,result.reason)
			else:
				ent.path_status="QUEUED"; ent.path_pending=true
				ent.path_next_attempt_tick=tick_count+1; retries.append(id)
	path_requests=deferred+retries

func _begin_unit_motion():
	traffic_priority_order=[]; traffic_tick_segments.clear()
	var epoch=int(tick_count/TRAFFIC_ROTATION_TICKS)
	# Rotate each faction's owned ID sequence independently. An unseen death
	# or spawn in the other faction must not reshuffle our local claimants.
	for offset in 2:
		var team=(epoch+offset)%2; var members=[]
		for ent in entities:
			if ent.team==team and ent.alive and ent.category=="unit": members.append(ent)
		members.sort_custom(func(a,b): return a.id<b.id)
		if members.is_empty(): continue
		var first=epoch%members.size()
		traffic_priority_order.append_array(members.slice(first)+members.slice(0,first))

func _reset_traffic(ent):
	ent.traffic_goal=Vector3.INF; ent.traffic_best_distance=INF; ent.traffic_progress_tick=tick_count
	ent.traffic_replans=0; ent.traffic_last_replan=tick_count; ent.traffic_route=false; ent.work_slot_wait=-1; ent.traffic_path_length=0; ent.traffic_command_origin=ent.pos; ent.traffic_gate_since=-1

func _traffic_stop(ent,reason):
	_path_stop(ent,BoundedPath.LIMIT_REACHED,reason)
	path_requests.erase(ent.id)
	ent.work_approach=Vector3.INF; ent.work_target_id=-1; ent.work_route_revision=-1
	ent.state="idle"; ent.mode="STOP"; ent.target=-1

func _segment_distance_squared(point,from,to):
	var delta=to-from
	var t=0.0 if delta.length_squared()<0.0000001 else clampf((point-from).dot(delta)/delta.length_squared(),0,1)
	return point.distance_squared_to(from+delta*t)

func _box_distance_squared(point,cell):
	var lo=_point(cell)-Vector3(0.5,0,0.5)
	var nearest=Vector3(clampf(point.x,lo.x,lo.x+1),0,clampf(point.z,lo.z,lo.z+1))
	return point.distance_squared_to(nearest)

func _segment_box_distance_squared(from,to,cell):
	var lo=Vector2(cell.x-Rules.MAP_HALF,cell.y-Rules.MAP_HALF); var hi=lo+Vector2.ONE
	var a=Vector2(from.x,from.z); var delta=Vector2(to.x-from.x,to.z-from.z)
	var near=0.0; var far=1.0; var crosses=true
	for axis in 2:
		if absf(delta[axis])<0.0000001:
			if a[axis]<lo[axis] or a[axis]>hi[axis]: crosses=false; break
		else:
			var first=(lo[axis]-a[axis])/delta[axis]; var last=(hi[axis]-a[axis])/delta[axis]
			near=maxf(near,minf(first,last)); far=minf(far,maxf(first,last))
			if near>far: crosses=false; break
	if crosses: return 0.0
	var distance=minf(_box_distance_squared(from,cell),_box_distance_squared(to,cell))
	for corner in [lo,Vector2(hi.x,lo.y),hi,Vector2(lo.x,hi.y)]:
		distance=minf(distance,_segment_distance_squared(Vector3(corner.x,0,corner.y),from,to))
	return distance

func _static_unit_step_is_free(ent,to):
	# Only the short physical capsule touches authority. Planning still uses
	# faction-known static grids; hidden distant cells cannot affect this test.
	var radius_squared=ent.radius*ent.radius
	var low=Vector2i(floori(minf(ent.pos.x,to.x)+Rules.MAP_HALF-ent.radius),floori(minf(ent.pos.z,to.z)+Rules.MAP_HALF-ent.radius))
	var high=Vector2i(floori(maxf(ent.pos.x,to.x)+Rules.MAP_HALF+ent.radius),floori(maxf(ent.pos.z,to.z)+Rules.MAP_HALF+ent.radius))
	for y in range(low.y,high.y+1):
		for x in range(low.x,high.x+1):
			var cell=Vector2i(x,y)
			if navigation.region.has_point(cell) and not navigation.is_point_solid(cell): continue
			var distance=_segment_box_distance_squared(ent.pos,to,cell)
			if distance>=radius_squared-0.0000001: continue
			# A site may have appeared next to an off-center unit. Permit only
			# monotonic escape from pre-existing contact, never a deeper entry.
			var before=_box_distance_squared(ent.pos,cell); var after=_box_distance_squared(to,cell)
			if before<radius_squared and after>before+0.0000001 and distance>=before-0.0000001: continue
			return false
	return true

func _unit_step_is_free(ent,to):
	if not _static_unit_step_is_free(ent,to): return false
	# Authoritative collision is deliberately LOCAL to the swept segment. No
	# result is consulted by remote destination selection or faction A* grids.
	for other in entities:
		if not other.alive or other.category!="unit" or other.id==ent.id: continue
		var clearance=ent.radius+other.radius
		if _segment_distance_squared(other.pos,ent.pos,to)<clearance*clearance-0.000001: return false
		# Conservative same-tick swept reservation prevents crossing a segment
		# already committed by a higher priority mover, not just its endpoint.
		if traffic_tick_segments.has(other.id):
			var segment=traffic_tick_segments[other.id]
			if _segment_distance_squared(to,segment[0],segment[1])<clearance*clearance-0.000001: return false
	return true

func _local_traffic_edges(ent,start,origin):
	# Local, detached KNOWN circles constrain edges, not whole square cells.
	# In particular, a safe diagonal gap between units must not acquire the
	# static-obstacle corner prohibition. The authoritative static grid is
	# untouched; hidden enemy positions and orders never enter this query.
	var obstacles=[]
	for other in entities:
		if other.team==ent.team and other.alive and other.category=="unit" and other.id!=ent.id and other.pos.distance_squared_to(ent.pos)<=6.25:
			obstacles.append({"pos":other.pos,"radius":ent.radius+other.radius})
	for other in faction_views[ent.team].records().values():
		if not other.owned and not other.remembered and other.category=="unit" and other.pos.distance_squared_to(ent.pos)<=6.25:
			obstacles.append({"pos":other.pos,"radius":ent.radius+other.radius})
	var edges={}
	for y in range(maxi(Rules.MAP_BORDER,start.y-4),mini(Rules.MAP_LAST_PLAYABLE+1,start.y+5)):
		for x in range(maxi(Rules.MAP_BORDER,start.x-4),mini(Rules.MAP_LAST_PLAYABLE+1,start.x+5)):
			var cell=Vector2i(x,y); var from=origin if cell==start else _point(cell)
			for direction in BoundedPath.DIRECTIONS:
				var neighbor=cell+direction; var to=_point(neighbor)
				for obstacle in obstacles:
					if _segment_distance_squared(obstacle.pos,from,to)<obstacle.radius*obstacle.radius-0.000001:
						edges[Vector4i(x,y,neighbor.x,neighbor.y)]=true; break
	return edges

func _queue_traffic_route(ent):
	if ent.traffic_replans>=TRAFFIC_MAX_REPLANS:
		_traffic_stop(ent,"local_traffic_retry_limit"); return
	ent.traffic_replans+=1; ent.traffic_last_replan=tick_count; ent.traffic_route=true
	ent.traffic_path_length=ent.path.size(); ent.path=PackedVector3Array()
	if ent.state in ["gather","deliver"]:
		ent.work_approach=Vector3.INF; ent.work_target_id=-1; _plan_work_path(ent)
	else: _plan_path(ent,ent.dest)

func _anticipate_local_traffic(ent,waypoint):
	# Look only as far as the next adjacent grid waypoint, not a remote goal.
	# Early replanning leaves room to yield instead of first compressing the
	# two streams into a touching wall. It spends the same bounded query gate.
	if tick_count-ent.traffic_last_replan<TRAFFIC_REPLAN_TICKS: return false
	if ent.pos.distance_to(waypoint)<0.001 or _unit_step_is_free(ent,waypoint): return false
	_queue_traffic_route(ent); return true

func _apply_unit_step(ent,next_pos,dt):
	var goal=ent.work_approach if ent.state in ["gather","deliver"] else ent.dest
	if ent.traffic_goal!=goal:
		ent.traffic_goal=goal; ent.traffic_best_distance=ent.pos.distance_to(goal); ent.traffic_progress_tick=tick_count
	var distance=ent.pos.distance_to(goal)
	if distance<ent.traffic_best_distance-0.1:
		ent.traffic_best_distance=distance; ent.traffic_progress_tick=tick_count
	var wanted=next_pos-ent.pos
	var step=Vector3.ZERO
	if _unit_step_is_free(ent,next_pos): step=wanted
	else:
		# Fixed right-hand candidate order breaks head-on symmetry. Priority
		# rotates above; STOP units remain stationary and are never pushed.
		for angle in [PI/4,PI/2,3*PI/4,-PI/4,-PI/2,-3*PI/4,PI]:
			var candidate=wanted.rotated(Vector3.UP,angle)
			var point=ent.pos+candidate
			if _path_step_is_free(ent.pos,point) and _unit_step_is_free(ent,point):
				step=candidate; break
		var stalled=tick_count-ent.traffic_progress_tick
		if stalled>=TRAFFIC_STALL_TICKS:
			_traffic_stop(ent,"local_traffic_timeout"); return
		if stalled>=TRAFFIC_REPLAN_TICKS and tick_count-ent.traffic_last_replan>=TRAFFIC_REPLAN_TICKS:
			_queue_traffic_route(ent); return
	if step==Vector3.ZERO: ent.stuck+=1; return
	var before=ent.pos
	ent.pos+=step; ent.stuck=0
	traffic_tick_segments[ent.id]=[before,ent.pos]
	ent.body.rotation.y=lerp_angle(ent.body.rotation.y,atan2(step.x,step.z),0.35)

func _path_step_is_free(from,to):
	var a=_cell(from); var b=_cell(to)
	if navigation.is_point_solid(a) or navigation.is_point_solid(b): return false
	if absi(a.x-b.x)>1 or absi(a.y-b.y)>1: return false
	if a.x!=b.x and a.y!=b.y:
		if navigation.is_point_solid(Vector2i(a.x,b.y)) or navigation.is_point_solid(Vector2i(b.x,a.y)): return false
	return true

func _settling_unit_at(team,cell,exclude_id):
	var point=_point(cell)
	for other in entities:
		if other.team!=team or not other.alive or other.category!="unit" or other.id==exclude_id: continue
		if other.pos.distance_to(point)>0.5: continue
		if other.state=="idle" or (other.state=="move" and _cell(other.dest)==cell and other.pos.distance_to(other.dest)<0.5): return true
	for other in faction_views[team].records().values():
		if not other.owned and not other.remembered and other.category=="unit" and not other.visual_moving and other.pos.distance_to(point)<=0.5: return true
	return false

func _yield_before_closing_lane(ent):
	if ent.state!="move" or ent.path.size()!=1 or ent.pos.distance_to(ent.dest)>1.5: return false
	var heading=ent.dest-ent.traffic_command_origin
	var horizontal=absf(heading.x)>=absf(heading.z)
	var axis=Vector3.RIGHT if horizontal else Vector3.BACK
	var sign_dir=signf(heading.dot(axis))
	if sign_dir==0: return false
	var destination_cell=_cell(ent.dest);var cross_axis=Vector2i(0,1) if horizontal else Vector2i(1,0)
	var grid=work_memory[ent.team].grid
	# Only the last parking unit in an otherwise occupied wall-to-wall cross
	# section waits. Holding every member would merely move the obstruction.
	for side in [-1,1]:
		var wall=false
		for distance in range(1,9):
			var cell=destination_cell+cross_axis*side*distance
			if not grid.region.has_point(cell) or grid.is_point_solid(cell): wall=true;break
			if not _settling_unit_at(ent.team,cell,ent.id): return false
		if not wall: return false
	var crossing=false
	for other in entities:
		if other.team!=ent.team or not other.alive or other.category!="unit" or other.id==ent.id or other.state!="move" or other.path_status in [BoundedPath.NO_PATH,BoundedPath.LIMIT_REACHED]: continue
		var past=(other.dest-ent.dest).dot(axis)*sign_dir
		var behind=(other.pos-ent.dest).dot(axis)*sign_dir
		var lateral=absf(other.pos.z-ent.dest.z) if horizontal else absf(other.pos.x-ent.dest.x)
		if past>0.7 and behind<0.7 and lateral<8: crossing=true;break
	if not crossing: ent.traffic_gate_since=-1;return false
	if ent.traffic_gate_since<0: ent.traffic_gate_since=tick_count
	if tick_count-ent.traffic_gate_since>=TRAFFIC_STALL_TICKS:
		_traffic_stop(ent,"local_parking_yield_limit");return true
	ent.path_reason="yielding_before_parking";return true

func _move(ent,destination,dt):
	_path_state(ent)
	if ent.pos.distance_to(destination)<0.001:
		ent.path=PackedVector3Array(); ent.path_status=BoundedPath.FOUND; ent.path_reason="goal_reached"; return true
	if ent.path_status in [BoundedPath.NO_PATH,BoundedPath.LIMIT_REACHED]: return false
	if ent.path_version!=work_memory[ent.team].revision or ent.dest.distance_to(destination)>1.1 or ent.path.is_empty():
		_plan_path(ent,destination)
		return false
	var next=ent.path[0]
	# Recheck the full grid step and diagonal side cells before approaching
	# the next waypoint, even if a caller edited solids without a rebuild.
	if not _path_step_is_free(ent.pos,next):
		ent.path=PackedVector3Array(); ent.path_version=-1
		_plan_path(ent,destination); return false
	if _yield_before_closing_lane(ent): return false
	if _anticipate_local_traffic(ent,next): return false
	var vector=next-ent.pos
	if vector.length()<0.001:
		ent.path.remove_at(0)
		return ent.path.is_empty()
	var step=vector.normalized()*minf(Rules.SPEED[ent.kind]*dt,vector.length())
	var next_pos=ent.pos+step
	if not _path_step_is_free(ent.pos,next_pos):
		ent.path=PackedVector3Array(); ent.path_version=-1
		_plan_path(ent,destination); return false
	_apply_unit_step(ent,next_pos,dt)
	if not ent.path.is_empty() and ent.path[0]==next and ent.pos.distance_to(next)<0.001:
		ent.path.remove_at(0); ent.traffic_progress_tick=tick_count
		if ent.path.is_empty(): ent.path_reason="goal_reached"
		return ent.path.is_empty()
	return false

# Public geometry only: union of building-center bounds and the unit-radius
# ring. Never derive the envelope from live/hidden entities or their state.
func _placement_visibility_cells(footprint,catalog=Rules.FOOTPRINT,public_max_unit_radius=Rules.UNIT_RADIUS):
	var unit_pad=ceili(public_max_unit_radius)
	var max_low=unit_pad; var max_high=unit_pad
	for width in catalog.values():
		var low=floori(width/2.0)
		max_low=maxi(max_low,low); max_high=maxi(max_high,int(width)-low-1)
	var cells={}
	for cell in footprint:
		for y in range(cell.y-max_high,cell.y+max_low+1):
			for x in range(cell.x-max_high,cell.x+max_low+1): cells[Vector2i(x,y)]=true
	return cells.keys()

func _placement_reason(kind,p,team,builder_id):
	if not Rules.BUILD_TIME.has(kind): return "未知建築"
	var mock={"pos":p,"kind":kind,"category":"building"}
	var footprint=_occupied_cells(mock)
	for c in footprint:
		if c.x<Rules.MAP_BORDER+1 or c.y<Rules.MAP_BORDER+1 or c.x>Rules.MAP_LAST_PLAYABLE-1 or c.y>Rules.MAP_LAST_PLAYABLE-1: return "地圖邊界"
	for c in _placement_visibility_cells(footprint):
		# Out-of-map envelope cells are public boundary, not observable cells.
		# Bounds precede indexing even if the public size catalog grows.
		if c.x<0 or c.y<0 or c.x>=Rules.MAP_SIZE or c.y>=Rules.MAP_SIZE: continue
		if visible_cells[team][c.y*Rules.MAP_SIZE+c.x]==0: return "需要地點及周邊目前可見"
	var builder=_get_entity(builder_id)
	if builder.is_empty() or not builder.alive or builder.team!=team or builder.kind!="villager": return "請先選取村民"
	if not _can_pay(COSTS[kind],team): return "資源不足"
	for c in footprint:
		if navigation.is_point_solid(c): return "與建築或資源重疊"
		for unit in entities:
			# Physical disk penetration, with the static movement tolerance.
			# Tangency is legal; placement never pushes or permits escape contact.
			if unit.alive and unit.category=="unit" and _box_distance_squared(unit.pos,c)<unit.radius*unit.radius-0.0000001: return "地點有單位"

	return _placement_access_reason(mock,footprint,team)

# Geometric access, not a zoning rule. Only own/currently observed geometry
# contributes. At most 20 perimeter cells per producer; no A*, full-map scan,
# hidden-enemy producer lookup, or mutable preview reservation.
func _placement_access_reason(mock,footprint,team):
	var reserved={}
	for cell in footprint: reserved[cell]=true
	var known_grid=work_memory[team].grid
	var site_has_access=false
	for cell in _perimeter_cells(mock):
		if known_grid.region.has_point(cell) and not known_grid.is_point_solid(cell): site_has_access=true; break
	if not site_has_access: return "需要留有施工通道"
	for producer in entities:
		if producer.team!=team: continue
		if not producer.alive or producer.category!="building" or not Rules.PRODUCES.has(producer.kind): continue
		var touched=false; var had_exit=false; var retains_exit=false
		for cell in _perimeter_cells(producer):
			if not known_grid.region.has_point(cell) or known_grid.is_point_solid(cell): continue
			had_exit=true
			if reserved.has(cell): touched=true
			else: retains_exit=true
		if touched and had_exit and not retains_exit: return "不可阻住生產建築最後出口"
	return ""

func _place_building(kind,p,builder_id,team):
	p=_snap_build_position(kind,p)
	var reason=_placement_reason(kind,p,team,builder_id)
	if not reason.is_empty():
		if team==0: _message(reason+"，未有扣款。")
		return {}
	var payment=_pay(COSTS[kind],team,Economy.REFUND_STARTED)
	if not payment.applied: return {}
	# All ordinary failure checks precede this synchronous commit: no await,
	# signals, callbacks or later placement revalidation can split the debit/site.
	var building=_spawn(kind,team,p,false)
	building.cost_receipt_id=payment.receipt_id
	_navigation_rebuild()
	if team==0: _path_new_command(_get_entity(builder_id))
	_order(_get_entity(builder_id),"build",building.id)
	completed_builds[team]+=0
	return building

# --- Economy and unit state machines ---
func _path_cancel_pending(ent):
	_path_state(ent)
	path_requests.erase(ent.id); ent.path_pending=false
	ent.work_epoch+=1; ent.work_approach=Vector3.INF; ent.work_target_id=-1; ent.work_route_revision=-1
	_reset_traffic(ent)
	if ent.path_status=="QUEUED": ent.path_status="IDLE"

func _target_order_intent(ent,target,team):
	if target.is_empty(): return "move"
	if target.team==1-team: return "attack"
	if ent.kind!="villager": return "move"
	if target.category=="resource": return "gather"
	if target.team==team:
		if not target.built: return "build"
		if target.kind in ["town_center","storehouse"] and _cargo_amount(ent)>0: return "deliver"
		if target.category=="building" and target.hp<target.max_hp: return "repair"
	return "move"

func _repair_order_allowed(ent,target):
	return not target.is_empty() and target.alive and ent.kind=="villager" and target.team==ent.team and target.category=="building" and target.built and target.hp<target.max_hp and tick_count-target.last_damage_tick>=100

func _order(ent,state,target_id,automatic=false):
	# Internal callers obey the same preflight, before any unit mutation.
	if state=="repair" and not _repair_order_allowed(ent,_get_entity(target_id)): return false
	if state=="build":
		var site=_get_entity(target_id)
		if ent.is_empty() or not ent.alive or ent.kind!="villager" or site.is_empty() or not site.alive or site.category!="building" or site.built or site.team!=ent.team: return false
		# Ownership follows execution order, not entity ID. Commands execute by
		# sequence; group members execute in ids array order (last valid wins).
		# Repeated command IDs are rejected upstream; repeated members are safe.
		for other in entities:
			if other.id!=ent.id and other.alive and other.state=="build" and other.target==target_id:
				_path_new_command(other)
				_set_stance(other,"STOP")
				other.dest=other.pos; other.stuck=0; other.work_ticks=0; other.last_repair_tick=-1
	_path_cancel_pending(ent)
	ent.auto_target=automatic
	if not automatic: ent.mode="ATTACK" if state=="attack" else "WORK"
	ent.state=state; ent.target=target_id; ent.work_ticks=0; ent.last_repair_tick=-1; ent.path=PackedVector3Array(); ent.path_version=-1; ent.stuck=0
	ent.path_request_kind="work" if state in ["gather","deliver"] else "point"; ent.work_any_target=false
	if state in ["gather","deliver"]: ent.path_revision=work_memory[ent.team].revision
	var target=_get_entity(target_id)
	if state=="gather":
		_refresh_work_memory()
		var known=work_memory[ent.team].resources.get(target_id,{})
		ent.resource_target=target_id
		ent.gather_type=_resource_type(known) if not known.is_empty() else ""
		if not known.is_empty(): ent.last_known=known.pos
		if _cargo_amount(ent)>0 and not known.is_empty() and _cargo_type(ent)!=_resource_type(known): _route_to_dropoff(ent)
	elif not target.is_empty(): ent.last_known=target.pos

func _order_move(ent,p,reserved={},ignore_orders=[]):
	_path_cancel_pending(ent)
	ent.mode="MOVE"; ent.auto_target=false; ent.path_request_kind="point"
	ent.state="move"; ent.target=-1; ent.dest=_nearest_free(p,8,ent.team,ent,reserved,ignore_orders); ent.path=PackedVector3Array(); ent.path_version=-1; ent.stuck=0
	if ent.dest==Vector3.INF: ent.dest=ent.pos; _set_stance(ent,"STOP")

func _set_stance(ent,mode):
	_path_cancel_pending(ent)
	ent.path_request_kind="point"
	ent.mode=mode; ent.state="idle"; ent.anchor=ent.pos; ent.auto_target=false
	ent.target=-1; ent.path=PackedVector3Array(); ent.path_version=-1

func _finish_attack(ent):
	if ent.auto_target and ent.mode=="DEFEND":
		ent.target=-1; ent.auto_target=false
		if ent.pos.distance_to(ent.anchor)>0.2:
			# Return is a new goal, not a new player command. Retire the old
			# pursuit once without erasing its rolling search/failure budget.
			_path_cancel_pending(ent)
			ent.path_status="IDLE"; ent.path_reason=""
			var recent_retries=[]
			for retry_tick in ent.path_retry_ticks:
				if tick_count-retry_tick<20: recent_retries.append(retry_tick)
			if recent_retries.size()>=3:
				ent.path_next_attempt_tick=maxi(ent.path_next_attempt_tick,recent_retries[recent_retries.size()-3]+20)
			ent.state="return"; ent.path=PackedVector3Array(); ent.path_version=-1; ent.dest=ent.anchor
		else: ent.state="idle"
	else: _set_stance(ent,"STOP")

func _stance_target(ent):
	var best={}; var distance=INF
	for enemy in entities:
		if not enemy.alive or enemy.team!=1-ent.team or not _visible_to(enemy,ent.team): continue
		if ent.mode=="STOP" and _attack_distance(ent.pos,enemy)>Rules.RANGE[ent.kind]: continue
		if ent.mode=="DEFEND" and enemy.pos.distance_to(ent.anchor)>3.0: continue
		var d=ent.pos.distance_squared_to(enemy.pos)
		if d<distance or (is_equal_approx(d,distance) and (best.is_empty() or enemy.id<best.id)):
			distance=d; best=enemy
	return best

func _move_unit_phase(ent,dt):
	if ent.state=="move":
		if _move(ent,ent.dest,dt): _set_stance(ent,"STOP")
		return
	if ent.state=="return":
		if _move(ent,ent.anchor,dt): ent.state="idle"; ent.mode="DEFEND"
		return
	if ent.state in ["gather","deliver"]:
		_move_work(ent,dt); return
	var target=_get_entity(ent.target)
	if target.is_empty(): return
	if ent.state=="attack":
		var observed=_attack_target_observed(target,ent.team)
		if observed and not target.alive: _finish_attack(ent); return
		if ent.auto_target and ent.mode=="STOP": return
		if ent.auto_target and ent.mode=="DEFEND" and ent.last_known.distance_to(ent.anchor)>3.0:
			_finish_attack(ent); return
		var remembered={"category":target.category,"kind":target.kind,"pos":ent.last_known,"radius":target.radius}
		if observed and _attack_distance(ent.pos,remembered)<=Rules.RANGE[ent.kind]: return
		if not observed and _attack_distance(ent.pos,remembered)<0.6: return
		var goal=_free_adjacent(remembered,ent.pos,false,ent.team) if target.category!="unit" else ent.last_known
		if goal==Vector3.INF: return
		var before=ent.pos
		_move(ent,goal,dt)
		if ent.auto_target and ent.mode=="DEFEND" and ent.pos.distance_to(ent.anchor)>3.0:
			ent.pos=before; _finish_attack(ent)
	elif ent.state in ["build","repair"] and target.alive:
		if ent.state=="gather" and ent.pos.distance_to(target.pos)<1.65: return
		var adjacent=_free_adjacent(target,ent.pos,false,ent.team,ent)
		if adjacent!=Vector3.INF and ent.pos.distance_to(adjacent)>0.3: _move(ent,adjacent,dt)

func _resource_type(ent):
	if ent.kind=="berry": return "food"
	return "wood" if ent.kind in ["pine","oak"] else ""

func _gather_intent(ent):
	# The next requested resource is independent of the old carried load.
	if not ent.gather_type.is_empty(): return ent.gather_type
	return _cargo_type(ent) if not _cargo_type(ent).is_empty() else "food"

func _nearest_resource(p,kind,team=-1):
	if team>=0:
		var known=_nearest_known_resource(p,kind,team)
		if known.is_empty(): return {}
		# Preserve the local entity API only when it is currently observable.
		# Offscreen callers receive the frozen record, never hidden live state.
		return _get_entity(known.id) if visible_cells[team][_cell_index(known.pos)]!=0 else known.duplicate(true)
	var best={}; var dist=INF
	for ent in entities:
		if not ent.alive or ent.category!="resource": continue
		if kind=="wood" and ent.kind not in ["pine","oak"]: continue
		if kind=="food" and ent.kind!="berry": continue
		if kind not in ["wood","food"] and ent.kind!=kind: continue
		if team>=0 and explored_cells[team][_cell_index(ent.pos)]==0: continue
		var d=ent.pos.distance_squared_to(p)
		if d<dist: dist=d; best=ent
	return best

func _valid_dropoff(ent,target):
	return not target.is_empty() and target.alive and target.built and target.team==ent.team and target.kind in ["town_center","storehouse"]

func _dropoff(ent):
	_refresh_work_memory()
	var best={}; var distance=INF
	for record in work_memory[ent.team].structures.values():
		if not record.built or record.kind not in ["town_center","storehouse"]: continue
		var d=record.pos.distance_squared_to(ent.pos)
		if d<distance or (d==distance and (best.is_empty() or record.id<best.id)):
			distance=d; best=record
	return best

func _cargo_idle(ent):
	_path_cancel_pending(ent); ent.state="idle"; ent.target=-1; ent.path=PackedVector3Array()
	if ent.team==0 and _cargo_amount(ent)>0: _message("沒有可交付路線，已保留負重。請建立交付點或重新落指令。",3)

func _route_to_dropoff(ent):
	var drop=_dropoff(ent)
	if drop.is_empty(): _cargo_idle(ent); return false
	# Automatic continuations never reset initial/retry history or a terminal limit.
	if ent.get("path_status","")==BoundedPath.NO_PATH and ent.state!="deliver": ent.path_status="IDLE"; ent.path_reason=""
	_order(ent,"deliver",drop.id); ent.work_any_target=true
	return true

func _deposit_cargo(ent,target,transaction_id="",expected_revision=-1):
	# Final world validation happens before entering the ledger commit region.
	if ent.is_empty() or not ent.alive or ent.kind!="villager" or not _valid_dropoff(ent,target):
		return {"ok":false,"applied":false,"reason":"invalid_dropoff"}
	if not _at_work_approach(ent,target):
		return {"ok":false,"applied":false,"reason":"dropoff_not_reached"}
	var cargo=economy.worker_view(ent.id)
	if expected_revision<0: expected_revision=cargo.cargo_revision
	if transaction_id.is_empty(): transaction_id="deposit:%d:%d" % [ent.id,expected_revision]
	var deposited=economy.deposit(transaction_id,ent.id,expected_revision)
	if deposited.applied:
		if ent.team==0: demo_tutorial.record("deposit")
		_project_economy_entity(ent); progress_serial+=1
	return deposited

func _attack_distance(position,target):
	if target.category=="building":
		var center=target.pos
		var half=Rules.FOOTPRINT.get(target.kind,3)/2.0
		var dx=maxf(0,absf(position.x-center.x)-half)
		var dz=maxf(0,absf(position.z-center.z)-half)
		return sqrt(dx*dx+dz*dz)
	return maxf(0,position.distance_to(target.pos)-target.radius)

func _nearest_enemy(ent,radius):
	var best={}; var distance=radius*radius
	for enemy in entities:
		if not enemy.alive or enemy.team!=1-ent.team or not _visible_to(enemy,ent.team): continue
		var d=enemy.pos.distance_squared_to(ent.pos)
		if d<distance: distance=d; best=enemy
	return best

func _attack_target_observed(target,team):
	# Revealing an empty coordinate later is not witnessing the death of an
	# enemy that disappeared there. Death knowledge is recorded at the event.
	if target.alive: return _visible_to(target,team)
	return target.get("death_observed_by",[false,false])[team]

func _release_attack(ent: Dictionary,target: Dictionary) -> Dictionary:
	# Single authoritative release gate. Failed attempts allocate nothing and do
	# not touch cooldown, resources, pending damage, presentation or audio.
	if paused or game_over or ent.is_empty() or target.is_empty():
		return {"ok":false,"applied":false,"reason":"INVALID_RELEASE"}
	if not ent.alive or ent.category!="unit" or not Rules.DAMAGE.has(ent.kind) or ent.team not in [0,1]:
		return {"ok":false,"applied":false,"reason":"INVALID_ATTACKER"}
	if not target.alive or target.team!=1-ent.team or not _visible_to(target,ent.team):
		return {"ok":false,"applied":false,"reason":"INVALID_TARGET"}
	if ent.cooldown_ticks>0 or _attack_distance(ent.pos,target)>Rules.RANGE[ent.kind]:
		return {"ok":false,"applied":false,"reason":"NOT_READY"}
	var bonus=3 if ent.kind=="archer" and target.kind=="spearman" else 0
	var damage=maxi(1,Rules.DAMAGE[ent.kind]+bonus-Rules.ARMOR.get(target.kind,0))
	var result=attack_ledger.issue(tick_count,ent.id,target.id,damage,ent.pos,target.pos)
	if result.applied:
		ent.cooldown_ticks=Rules.ATTACK_TICKS[ent.kind]
		_note_unit_action(ent,"attack",target.pos)
		if not test_mode: _attack_effect(ent,target)
	return result

func _replay_attack(event: Dictionary) -> Dictionary:
	# Private diagnostic/replay entry, not an executable game command. It can
	# only recognize an exact authority-issued attack_id, never create a hit.
	return attack_ledger.replay(event)

func _combat_snapshot() -> Dictionary:
	return attack_ledger.snapshot()

func _update_unit(ent,dt):
	ent.cooldown_ticks=maxi(0,ent.cooldown_ticks-1)
	if ent.state=="idle":
		if ent.mode in ["STOP","DEFEND"]:
			var enemy=_stance_target(ent)
			if not enemy.is_empty(): _order(ent,"attack",enemy.id,true)
		return
	if ent.state in ["move","return"]: return
	if ent.state in ["gather","deliver"]:
		_update_work(ent); return
	var target=_get_entity(ent.target)
	# Observation precedes liveness: an enemy's unseen death is not knowledge
	# the pursuer may use. It must behave exactly like an unseen living enemy.
	if ent.state=="attack" and not target.is_empty() and not _attack_target_observed(target,ent.team):
		if (ent.auto_target and ent.mode=="STOP") or _attack_distance(ent.pos,{"category":target.category,"kind":target.kind,"pos":ent.last_known,"radius":target.radius})<0.6: _finish_attack(ent)
		return
	if target.is_empty() or not target.alive:
		if ent.state=="attack": _finish_attack(ent); return
		if ent.state in ["gather","deliver"]:
			if _cargo_amount(ent)>0:
				_route_to_dropoff(ent); return
			var type=_gather_intent(ent)
			var resource=_nearest_resource(ent.pos,type,ent.team)
			if not resource.is_empty(): _order(ent,"gather",resource.id); return
		ent.state="idle"; return
	match ent.state:
		"attack":
			if ent.auto_target and ent.mode=="DEFEND" and target.pos.distance_to(ent.anchor)>3.0:
				_finish_attack(ent); return
			ent.last_known=target.pos
			var distance=_attack_distance(ent.pos,target)
			if distance<=Rules.RANGE[ent.kind]:
				_note_unit_action(ent,"attack_ready",target.pos)
				ent.path=PackedVector3Array()
				if ent.cooldown_ticks<=0: _release_attack(ent,target)
			elif ent.auto_target and ent.mode=="STOP": _finish_attack(ent)
		"repair":
			# REP01: insufficient wood stops on this authoritative work update,
			# even en route or during a later damage lockout, not at payment due.
			if economy.bank_milli(ent.team).wood<1000: ent.state="idle"; return
			if ent.kind!="villager" or target.team!=ent.team or target.category!="building" or target.hp>=target.max_hp or not target.built: ent.state="idle"; return
			var adjacent=_free_adjacent(target,ent.pos,false,ent.team,ent)
			if adjacent==Vector3.INF: ent.state="idle"; return
			if ent.pos.distance_to(adjacent)>0.3: return
			if tick_count-target.last_damage_tick<100: ent.work_ticks=0; return
			# Only an on-site eligible worker owns this tick; a distant or
			# route-blocked repair order must not veto actual repair work.
			for other in entities:
				if not other.alive or other.id>=ent.id or other.kind!="villager" or other.team!=ent.team or other.state!="repair" or other.target!=target.id: continue
				var other_adjacent=_free_adjacent(target,other.pos,false,other.team,other)
				if other_adjacent!=Vector3.INF and other.pos.distance_to(other_adjacent)<=0.3: return
			if ent.last_repair_tick==tick_count or target.get("last_repair_work_tick",-1)==tick_count: return
			ent.last_repair_tick=tick_count; target.last_repair_work_tick=tick_count; ent.work_ticks+=1
			_note_unit_action(ent,"repair",target.pos)
			if ent.work_ticks>=20:
				ent.work_ticks=0
				var payment=_pay({"wood":1},ent.team,Economy.REFUND_NONE,"repair","repair:%d:%d:%d" % [ent.id,target.id,tick_count])
				if payment.applied:
					target.hp=mini(target.max_hp,target.hp+5)
					if target.hp>=target.max_hp or economy.bank_milli(ent.team).wood<1000: ent.state="idle"
				else: ent.state="idle"
		"build":
			if target.built: ent.state="idle"; return
			var adjacent=_free_adjacent(target,ent.pos,false,ent.team,ent)
			if adjacent==Vector3.INF: ent.state="idle"; return
			if ent.pos.distance_to(adjacent)<0.3:
				# One builder per site in this Demo. No hidden multi-builder speed bonus.
				for other in entities:
					if other.alive and other.id<ent.id and other.state=="build" and other.target==target.id: return
				var total_ticks=roundi(Rules.BUILD_TIME[target.kind]/Rules.TICK)
				target.build_ticks=mini(total_ticks,target.build_ticks+1)
				_note_unit_action(ent,"build",target.pos)
				progress_serial+=1
				target.progress=float(target.build_ticks)/total_ticks
				var initial_hp=ceili(target.max_hp*0.1)
				var next_cap=initial_hp+floori((target.max_hp-initial_hp)*target.build_ticks/float(total_ticks))
				# Earn only the increase in the work-dependent HP cap. Missing HP stays missing.
				target.hp+=next_cap-target.construction_hcap
				target.construction_hcap=next_cap
				if target.progress>=1:
					var receipt_id=target.get("cost_receipt_id","")
					if not receipt_id.is_empty():
						var fulfilled=economy.fulfill_cost("fulfilled:"+receipt_id,receipt_id,target.team)
						if not fulfilled.applied: return
					target.built=true; completed_builds[ent.team]+=1; ent.state="idle"
					if target.team==0 and not receipt_id.is_empty() and target.kind in ["house","barracks"]: demo_tutorial.record(target.kind)
					if ent.team==0: _message(Rules.NAMES[target.kind]+"建造完成。",3)

func _kill(ent):
	if not ent.alive: return
	ent.death_observed_by=[_visible_to(ent,0),_visible_to(ent,1)]
	if ent.category=="unit" and ent.death_observed_by[0]:
		# Detached final observed pose only. This adds no corpse entity/blocker.
		pending_visual_deaths.append({"id":ent.id,"kind":ent.kind,"team":ent.team,"pos":ent.pos,"yaw":ent.body.rotation.y,"witnessed":true})
		if pending_visual_deaths.size()>CharacterPresenter.MAX_DEATH_VISUALS: pending_visual_deaths.pop_front()
	if ent.kind=="villager":
		economy.destroy_worker("death:%d" % ent.id,ent.id); _project_economy_entity(ent)
	for order in ent.queue:
		var receipt_id=order.get("receipt_id","")
		economy.destroy_cost("destroyed:"+receipt_id,receipt_id,ent.team)
	var site_receipt=ent.get("cost_receipt_id","")
	if not site_receipt.is_empty() and not ent.built:
		economy.destroy_cost("destroyed:"+site_receipt,site_receipt,ent.team)
	ent.alive=false; ent.queue.clear(); ent.node.visible=false; ent.path=PackedVector3Array()
	selected.erase(ent.id); action_key=""
	# Losing the final selected unit ends targeting before its Cancel control
	# disappears. Retire held pointers so a late release cannot become selection.
	if rally_building==ent.id or (touch_command and rally_building<0 and selected.is_empty()): _cancel_mode()
	if ent.category!="unit": _navigation_rebuild()

func _recovery_view(team):
	var bank=economy.bank_milli(team)
	# END predicate is still whole-unit, with floors safe at integer50 cutoff.
	var view={"living_units":0,"attack_buildings":0,"training_items":0,"food":economy.bank_units_floor(team).food,"refundable_food":0,"recovery_possible":false}
	var recoverable_stocks=bank.duplicate()
	var seen_site_receipts={}
	for ent in entities:
		if not ent.alive or ent.team!=team: continue
		if ent.category=="unit": view.living_units+=1
		elif ent.category=="building":
			if Rules.DAMAGE.get(ent.kind,0)>0 or ent.get("attack_damage",0)>0: view.attack_buildings+=1
			view.training_items+=ent.queue.size()
			var site_receipt=ent.get("cost_receipt_id","")
			if not ent.built and not site_receipt.is_empty() and not seen_site_receipts.has(site_receipt):
				seen_site_receipts[site_receipt]=true
				var refund=economy.quote_refund(site_receipt,team)
				for resource in refund: recoverable_stocks[resource]+=refund[resource]
				@warning_ignore("integer_division")
				view.refundable_food+=refund.food/Economy.SCALE
			# Future research is an already-calculated conservative recovery hook,
			# not permission to credit bank resources or invent a paid receipt.
			var research_refund=maxi(0,int(ent.get("research_refund_food",0)))
			view.refundable_food+=research_refund
			recoverable_stocks.food+=research_refund*Economy.SCALE
	# Food50 is sufficient, not necessary: preserve the25F45W archer path.
	for ent in entities:
		if not ent.alive or not ent.built or ent.team!=team or not Rules.PRODUCES.has(ent.kind): continue
		var affordable=true
		for resource in COSTS[Rules.PRODUCES[ent.kind]]:
			if recoverable_stocks.get(resource,0)<COSTS[Rules.PRODUCES[ent.kind]][resource]*Economy.SCALE: affordable=false
		if affordable: view.recovery_possible=true
	for event in future_recovery_events:
		if event.get("team",-1)==team and event.get("active",true): view.recovery_possible=true
	return view

func _check_end():
	if game_over: return
	var player_alive=not _first(0,"town_center").is_empty()
	var enemy_alive=not _first(1,"town_center").is_empty()
	# Accepted surrender promises that faction's defeat even if its outgoing
	# combat destroys the other keep, or a cap/recovery boundary falls this tick.
	var player_lost=_surrender_intent.has(0) if not _surrender_intent.is_empty() else not player_alive
	var enemy_lost=_surrender_intent.has(1) if not _surrender_intent.is_empty() else not enemy_alive
	end_reason="surrender" if not _surrender_intent.is_empty() else "keep_destroyed"
	if _surrender_intent.is_empty() and player_alive and enemy_alive:
		if tick_count>=roundi(Rules.TIME_LIMIT/Rules.TICK):
			player_lost=true; enemy_lost=true; end_reason="time_limit"
		else:
			player_lost=recovery_ticks[0]>=EndRules.IRRECOVERABLE_TICKS
			enemy_lost=recovery_ticks[1]>=EndRules.IRRECOVERABLE_TICKS
			if not player_lost and not enemy_lost: end_reason=""; return
			end_reason="irrecoverable"
	game_over=true
	outcome="draw" if player_lost==enemy_lost else ("defeat" if player_lost else "victory")
	victory=outcome=="victory"
	commands.clear(); _cancel_mode()
	if is_instance_valid(end_panel):
		end_title.text={"victory":"王旗再起","defeat":"聚落失守","draw":"戰事暫歇"}[outcome]
		if end_reason=="surrender":
			end_title.text={"victory":"敵方投降","defeat":"我方投降","draw":"雙方投降"}[outcome]
			end_body.text={"victory":"敵方已確認投降。","defeat":"你已確認投降。這局判定為失敗。","draw":"雙方已確認投降。和局。"}[outcome]
		elif end_reason=="irrecoverable":
			end_body.text={"victory":"敵方持續 60 秒沒有單位或任何復原途徑，已自動投降。","defeat":"我方持續 60 秒沒有單位或任何復原途徑，已自動投降。","draw":"雙方持續 60 秒沒有單位或任何復原途徑。和局。"}[outcome]
		else: end_body.text={"victory":"敵方主堡已倒下，霧谷由你守護。","defeat":"你的主堡已被摧毀。重新部署，再戰一局。","draw":"雙方同時失守，或已達 40 分鐘上限。和局。"}[outcome]
		end_panel.show()

# --- Fair, finite-frequency Demo AI01 ---
# Defaults are documented in AI_POLICY.md. This layer submits ordinary commands;
# it owns no economy, path, construction, combat or visibility authority.
const AI_RAID_INTERVAL_TICKS=1800
const AI_NEAR_KEEP_DISTANCE=6.0
const AI_HOME_THREAT_DISTANCE=6.0
var ai_opening_assigned=false
var ai_last_raid_tick=-AI_RAID_INTERVAL_TICKS
var ai_raid_members=[]
var ai_raid_departure_count=0
var ai_raid_keep={}
var ai_raid_retreating=false
var ai_scout_attempts={}
var ai_claimed_workers={}
var ai_build_submitted=false
var ai_budget={}
var ai_status={}
var ai_site_recovery={}
var owned_motion_witness_tick=-1

func _ai_records():
	var records=faction_views[1].records().values()
	records.sort_custom(func(a,b): return a.id<b.id)
	return records

func _ai_owned(records,kind):
	for ent in records:
		if ent.owned and ent.alive and ent.kind==kind: return ent
	return {}

func _ai_food_worker(ent):
	return ent.kind=="villager" and ent.state in ["gather","deliver"] and ent.get("gather_type","")=="food"

func _ai_food_count(records):
	var count=0
	for ent in records:
		if not ent.owned or ent.kind!="villager": continue
		if ai_claimed_workers.has(ent.id):
			if ai_claimed_workers[ent.id]=="food": count+=1
		elif _ai_food_worker(ent): count+=1
	return count

func _ai_builder(records):
	var food_count=_ai_food_count(records)
	# Idle first, then a working non-food gatherer, then surplus food. Never
	# commandeer an active builder, nor issue two jobs to one worker this turn.
	for idle_only in [true,false]:
		for ent in records:
			if not ent.owned or ent.kind!="villager" or ent.state=="build" or ai_claimed_workers.has(ent.id): continue
			if idle_only and ent.state!="idle": continue
			if _ai_food_worker(ent) and food_count<=2: continue
			return ent
	return {}

func _ai_can_budget(kind):
	for resource in COSTS[kind]:
		if ai_budget.get(resource,0)<COSTS[kind][resource]*Economy.SCALE: return false
	return true

func _ai_reserve_budget(kind):
	for resource in COSTS[kind]: ai_budget[resource]-=COSTS[kind][resource]*Economy.SCALE

func _assign_worker(ent,desired=""):
	if desired.is_empty(): desired="food"
	var resource={}; var distance=INF
	for known in faction_views[ent.team].records().values():
		if known.category!="resource" or _resource_type(known)!=desired: continue
		var d=known.pos.distance_squared_to(ent.pos)
		if d<distance or (d==distance and (resource.is_empty() or known.id<resource.id)): resource=known; distance=d
	if resource.is_empty():
		ai_status.worker="no_known_"+desired; return false
	_submit("order",{"ids":[ent.id],"target":-1 if resource.remembered else resource.id,"position":resource.pos},ent.team)
	ai_claimed_workers[ent.id]=desired
	return true

func _ai_build(kind):
	# Also callable by a diagnostic fixture, using the same paid command path.
	if ai_build_submitted: return false
	if ai_budget.is_empty(): ai_budget=economy.bank_milli(1).duplicate()
	if not _ai_can_budget(kind): ai_status.build="insufficient_"+kind+"_resources"; return false
	var builder=_ai_builder(_ai_records())
	if builder.is_empty(): ai_status.build="no_spare_builder"; return false
	var reasons=[]
	for p in MapRoutes.build_plots(1,Rules.FOOTPRINT[kind]):
		var reason=_placement_reason(kind,p,1,builder.id)
		if reason.is_empty():
			_submit("build",{"kind":kind,"position":p,"builder":builder.id},1)
			ai_claimed_workers[builder.id]="build"; ai_build_submitted=true; _ai_reserve_budget(kind)
			ai_status.build="submitted_"+kind; return true
		reasons.append(reason)
	ai_status.build="no_legal_plot"; ai_status.placement_reasons=reasons
	return false

func _ai_resource_gap(records,workers,capacity,committed):
	# No invented stockpile target: deficit of the next outstanding paid action.
	var desired="villager"
	var house_underway=false
	for ent in records:
		if ent.owned and ent.kind=="house" and not ent.built: house_underway=true
	if capacity-committed<=2 and capacity<Rules.POP_LIMIT and not house_underway: desired="house"
	elif _ai_owned(records,"barracks").is_empty(): desired="barracks"
	elif _ai_owned(records,"range").is_empty(): desired="range"
	elif workers<8: desired="villager"
	else:
		for ent in records:
			if ent.owned and ent.built and ent.kind in ["barracks","range"] and ent.queue.size()<2:
				desired=Rules.PRODUCES[ent.kind]; break
	var food=maxi(0,COSTS[desired].get("food",0)*Economy.SCALE-ai_budget.get("food",0))
	var wood=maxi(0,COSTS[desired].get("wood",0)*Economy.SCALE-ai_budget.get("wood",0))
	ai_status.resource_goal=desired
	return "wood" if wood>food else "food"

func _ai_scout(ent):
	if ent.state!="idle": return
	var point=Vector3.INF; var distance=INF; var chosen=-1
	# Bounded playable-map scan, no hidden occupancy or enemy coordinates. Each unknown
	# cell is attempted once per scout; ordinary path scheduling remains bounded.
	for y in range(Rules.MAP_BORDER,Rules.MAP_LAST_PLAYABLE+1):
		for x in range(Rules.MAP_BORDER,Rules.MAP_LAST_PLAYABLE+1):
			var index=y*Rules.MAP_SIZE+x
			if explored_cells[1][index]!=0 or ai_scout_attempts.has(index): continue
			var candidate=_point(Vector2i(x,y)); var d=ent.pos.distance_squared_to(candidate)
			if d<distance: point=candidate; distance=d; chosen=index
	if chosen<0: ai_status.scout="no_untried_unknown_cell"; return
	ai_scout_attempts[chosen]=true
	_submit("order",{"ids":[ent.id],"target":-1,"position":point},1)
	ai_status.scout="exploring_unknown"

func _ai_move_home(members,castle):
	var ids=[]
	for ent in members:
		if _attack_distance(ent.pos,castle)>3.0 and (ent.state!="move" or ent.dest.distance_to(castle.pos)>6.0): ids.append(ent.id)
	if not ids.is_empty(): _submit("order",{"ids":ids,"target":-1,"position":castle.pos},1)

func _ai_army(records,castle):
	var army=[]; var enemy_keep={}; var threat={}; var threat_distance=INF
	for ent in records:
		if ent.owned and ent.category=="unit" and ent.kind!="villager": army.append(ent)
		if ent.team==0 and ent.kind=="town_center" and enemy_keep.is_empty(): enemy_keep=ent
		if ent.team!=0 or ent.remembered or ent.category!="unit": continue
		for home in records:
			if not home.owned or home.category!="building": continue
			var distance=_attack_distance(ent.pos,home)
			if distance<=AI_HOME_THREAT_DISTANCE and distance<threat_distance: threat=ent; threat_distance=distance
	var survivors=[]
	for ent in army:
		if ent.id in ai_raid_members: survivors.append(ent)
	if not ai_raid_members.is_empty() and survivors.is_empty(): ai_raid_members.clear(); ai_raid_retreating=false
	# Visible home defense takes priority over an ongoing offensive order.
	if not threat.is_empty():
		for ent in army:
			if ent.state!="attack" or ent.target!=threat.id: _submit("order",{"ids":[ent.id],"target":threat.id,"position":threat.pos},1)
		if not ai_raid_members.is_empty(): ai_raid_retreating=true
		ai_status.army="home_defense"; return
	if not ai_raid_members.is_empty():
		var near_keep=false
		for ent in survivors:
			if _attack_distance(ent.pos,ai_raid_keep)<=AI_NEAR_KEEP_DISTANCE: near_keep=true
		if survivors.size()*2<ai_raid_departure_count and not near_keep: ai_raid_retreating=true
		if ai_raid_retreating:
			_ai_move_home(survivors,castle)
			var all_home=true
			for ent in survivors:
				if _attack_distance(ent.pos,castle)>3.0: all_home=false
			if all_home: ai_raid_members.clear(); ai_raid_retreating=false
			ai_status.army="retreat"; return
		# A remembered keep supports only a ground move, never a hidden target.
		# If observation retires its memory, return instead of using stale truth.
		if enemy_keep.is_empty(): ai_raid_retreating=true; _ai_move_home(survivors,castle); ai_status.army="keep_memory_retired"; return
		for ent in survivors:
			if not enemy_keep.remembered and (ent.state!="attack" or ent.target!=enemy_keep.id):
				_submit("order",{"ids":[ent.id],"target":enemy_keep.id,"position":enemy_keep.pos},1)
			elif enemy_keep.remembered and ent.state=="idle" and _attack_distance(ent.pos,enemy_keep)>1.1:
				_submit("order",{"ids":[ent.id],"target":-1,"position":enemy_keep.pos},1)
		ai_status.army="raid_active"; return
	# Only a finished scouting unit physically returned to muster can count.
	var mustered=[]
	for ent in army:
		if ent.state=="idle" and _attack_distance(ent.pos,castle)<=3.0: mustered.append(ent)
	if mustered.size()>=5 and not enemy_keep.is_empty() and tick_count-ai_last_raid_tick>=AI_RAID_INTERVAL_TICKS:
		ai_raid_members.clear()
		for ent in mustered: ai_raid_members.append(ent.id)
		ai_raid_departure_count=mustered.size(); ai_raid_keep=enemy_keep.duplicate(true); ai_last_raid_tick=tick_count; ai_raids+=1
		_submit("order",{"ids":ai_raid_members.duplicate(),"target":-1 if enemy_keep.remembered else enemy_keep.id,"position":enemy_keep.pos},1)
		ai_status.army="raid_departure"; return
	for ent in army:
		if ent.kind=="scout" and enemy_keep.is_empty(): _ai_scout(ent)
		else: _ai_move_home([ent],castle)
	ai_status.army="unknown_enemy_keep" if enemy_keep.is_empty() else ("muster_below_five" if mustered.size()<5 else "raid_cooldown")

func _ai_terminal_site_owner(owner,site):
	# A completed STATIC frontier for this exact current build command only.
	# Missing fields, pending searches, live traffic and bounded search limits
	# are not proof that this owner cannot reach this site.
	return owner.get("state","")=="build" and owner.get("target",-1)==site.id \
		and owner.get("path_status","")==BoundedPath.NO_PATH and owner.get("path_reason","")=="frontier_exhausted" \
		and not owner.get("path_pending",true) and owner.get("path",[]).is_empty() and not owner.get("traffic_route",true) \
		and owner.get("path_request_kind","")=="point" and owner.get("path_request_state","")=="build" \
		and owner.get("path_request_target",-1)==site.id and owner.get("work_epoch",-1)>=0 \
		and owner.get("path_request_epoch",-2)==owner.get("work_epoch",-1)

func _ai_site_cache(sites,workers):
	var live_sites={}; var live_workers={}
	for worker in workers: live_workers[worker.id]=true
	for site in sites:
		live_sites[site.id]=true
		if not ai_site_recovery.has(site.id):
			ai_site_recovery[site.id]={"attempts":{},"progress":site.progress,"progress_changed":false,"proof":[],"proof_tick":-1,"pending":{},"last_change":"new_site"}
		var entry=ai_site_recovery[site.id]
		entry.progress_changed=site.progress>entry.progress
		if entry.progress_changed:
			entry.attempts.clear(); entry.proof=[]; entry.proof_tick=-1; entry.last_change="actual_construction_progress"
		entry.progress=site.progress
		for id in entry.attempts.keys():
			if not live_workers.has(id): entry.attempts.erase(id)
	for id in ai_site_recovery.keys():
		if not live_sites.has(id): ai_site_recovery.erase(id)

func _ai_site_attempt(entry,worker):
	entry.attempts[worker.id]={"cell":_cell(worker.pos),"motion_tick":worker.get("last_native_motion_tick",-1)}

func _ai_site_retry_eligible(entry,worker):
	if not entry.attempts.has(worker.id): return true
	var attempt=entry.attempts[worker.id]
	# A changed coordinate, task epoch or global navigation revision alone
	# cannot recycle an attempt. Require retained OWN native movement evidence.
	return _cell(worker.pos)!=attempt.cell and worker.get("last_native_motion_tick",-1)>attempt.motion_tick \
		and worker.get("last_native_motion_position",Vector3.INF)==worker.pos

func _ai_terminal_site_builder(records,entry):
	var food_count=_ai_food_count(records)
	for idle_only in [true,false]:
		for worker in records:
			if not worker.owned or worker.kind!="villager" or worker.state=="build" or ai_claimed_workers.has(worker.id): continue
			if idle_only and worker.state!="idle": continue
			if worker.get("path_pending",false) or worker.get("path_status","") in [BoundedPath.NO_PATH,BoundedPath.LIMIT_REACHED]: continue
			if _ai_food_worker(worker) and food_count<=2: continue
			if _ai_site_retry_eligible(entry,worker): return worker
	return {}

func _ai_recover_terminal_site(site,owner,records):
	var entry=ai_site_recovery[site.id]
	var pending=entry.pending
	if not pending.is_empty() and tick_count>pending.tick:
		var ours=owner.id==pending.worker and owner.get("work_epoch",-1)==pending.expected_epoch and owner.state=="build" and owner.target==site.id
		entry.last_change="policy_takeover_observed" if ours else "takeover_not_observed_or_untracked_task_change"
		entry.pending={} # Neither result clears failed-worker history.
	var proof=[owner.id,owner.get("work_epoch",-1),owner.get("path_request_epoch",-2),owner.get("path_request_target",-1)]
	if pending.is_empty() and not entry.proof.is_empty() and entry.proof!=proof:
		entry.last_change="untracked_task_generation_changed" # Never inferred permission to recycle attempts.
	var terminal=_ai_terminal_site_owner(owner,site)
	var confirmed=terminal and not entry.progress_changed and entry.proof==proof and tick_count-entry.proof_tick==20
	entry.proof=proof if terminal and not entry.progress_changed else []
	entry.proof_tick=tick_count if terminal and not entry.progress_changed else -1
	if not terminal or entry.progress_changed:
		ai_status.site_recovery[site.id]={"state":"attached_active_or_unproven","owner":owner.id,"last_change":entry.last_change}; return false
	if not confirmed:
		ai_status.site_recovery[site.id]={"state":"observing_terminal_owner","owner":owner.id,"reason":owner.path_reason}; return false
	_ai_site_attempt(entry,owner)
	var worker=_ai_terminal_site_builder(records,entry)
	if worker.is_empty():
		var ids=entry.attempts.keys(); ids.sort()
		ai_status.site_recovery[site.id]={"state":"blocked","owner":owner.id,"reason":"no_eligible_untried_worker","terminal_reason":owner.path_reason,"attempted_workers":ids}; return false
	_ai_site_attempt(entry,worker)
	_submit("order",{"ids":[worker.id],"target":site.id,"position":site.pos},1)
	ai_claimed_workers[worker.id]="build"
	entry.pending={"worker":worker.id,"expected_epoch":maxi(0,worker.get("work_epoch",-1))+1,"tick":tick_count}
	ai_status.site_recovery[site.id]={"state":"takeover_submitted","old_owner":owner.id,"worker":worker.id,"reason":"confirmed_current_static_frontier"}
	return true

func _ai_update():
	ai_claimed_workers.clear(); ai_build_submitted=false; ai_budget=economy.bank_milli(1).duplicate(); ai_status={"tick":tick_count,"site_recovery":{}}
	var records=_ai_records(); var castle=_ai_owned(records,"town_center")
	var workers=[]; var sites=[]; var living=0; var reserved=0; var capacity=0
	var queued_workers=0
	for ent in records:
		if not ent.owned: continue
		if ent.category=="unit": living+=1
		else:
			reserved+=ent.queue.size()
			for item in ent.queue:
				if item.kind=="villager": queued_workers+=1
			if ent.built: capacity+=10 if ent.kind=="town_center" else (5 if ent.kind=="house" else 0)
			else: sites.append(ent)
		if ent.kind=="villager": workers.append(ent)
	capacity=mini(capacity,Rules.POP_LIMIT)
	_ai_site_cache(sites,workers)
	if castle.is_empty(): ai_status.blocked="no_own_keep"; return
	_ai_army(records,castle)
	if not ai_opening_assigned:
		for i in workers.size(): _assign_worker(workers[i],"food" if i<3 else "wood")
		ai_opening_assigned=true
	# Preserve at least two food workers before borrowing workers for recovery.
	for ent in workers:
		if _ai_food_count(records)>=mini(2,workers.size()): break
		if ent.state!="build" and not ai_claimed_workers.has(ent.id) and not _ai_food_worker(ent): _assign_worker(ent,"food")
	var house_underway=false
	for site in sites:
		if site.kind=="house": house_underway=true
	if capacity-living-reserved<=2 and capacity<Rules.POP_LIMIT and not house_underway: _ai_build("house")
	# Recover genuinely unattended sites before starting further construction.
	for site in sites:
		var owner={}
		for ent in workers:
			if ent.state=="build" and ent.target==site.id: owner=ent; break
		if not owner.is_empty():
			_ai_recover_terminal_site(site,owner,records); continue
		var builder=_ai_builder(records)
		if builder.is_empty(): ai_status.recovery="no_spare_builder"; continue
		_submit("order",{"ids":[builder.id],"target":site.id,"position":site.pos},1)
		ai_claimed_workers[builder.id]="build"; ai_status.recovery="resume_unattended_site"
		ai_site_recovery[site.id].pending={"worker":builder.id,"expected_epoch":maxi(0,builder.get("work_epoch",-1))+1,"tick":tick_count}
	if workers.size()<2: ai_status.food_floor="fewer_than_two_workers"
	elif _ai_food_count(records)<2: ai_status.food_floor="no_feasible_spare_worker_or_known_food"
	else: ai_status.food_floor="two_or_more_assigned"
	# Historical first-build time gates retained; no difficulty/content expansion.
	if not ai_build_submitted:
		if _ai_owned(records,"barracks").is_empty() and tick_count>400: _ai_build("barracks")
		elif _ai_owned(records,"range").is_empty() and tick_count>1800: _ai_build("range")
	var free_capacity=capacity-living-reserved
	if workers.size()+queued_workers<8 and castle.queue.is_empty() and free_capacity>0 and _ai_can_budget("villager"):
		_submit("train",{"building":castle.id,"kind":"villager"},1); _ai_reserve_budget("villager"); free_capacity-=1
	for building in records:
		if building.owned and building.built and building.kind in ["barracks","range"] and building.queue.size()<2 and free_capacity>0:
			var kind=Rules.PRODUCES[building.kind]
			if _ai_can_budget(kind): _submit("train",{"building":building.id,"kind":kind},1); _ai_reserve_budget(kind); free_capacity-=1
	for ent in workers:
		if ent.state=="idle" and not ai_claimed_workers.has(ent.id):
			_assign_worker(ent,_ai_resource_gap(records,workers.size()+queued_workers,capacity,living+reserved))

# --- Per-team visibility and ground fog ---
func _create_fog():
	for team in 2:
		visible_cells[team].resize(Rules.MAP_SIZE*Rules.MAP_SIZE); visible_cells[team].fill(0)
		explored_cells[team].resize(Rules.MAP_SIZE*Rules.MAP_SIZE); explored_cells[team].fill(0)
	fog_render_state.resize(Rules.MAP_SIZE*Rules.MAP_SIZE); fog_render_state.fill(255)
	fog=MultiMeshInstance3D.new()
	var mm=MultiMesh.new(); mm.transform_format=MultiMesh.TRANSFORM_3D; mm.use_colors=true
	var plane=PlaneMesh.new(); plane.size=Vector2(1.01,1.01)
	mm.mesh=plane; mm.instance_count=Rules.MAP_SIZE*Rules.MAP_SIZE
	var material=StandardMaterial3D.new()
	material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	material.vertex_color_use_as_albedo=true; material.no_depth_test=false
	plane.material=material
	for i in Rules.MAP_SIZE*Rules.MAP_SIZE:
		mm.set_instance_transform(i,Transform3D(Basis.IDENTITY,Vector3((i%Rules.MAP_SIZE)-Rules.MAP_HALF+0.5,0.11,floor(i/float(Rules.MAP_SIZE))-Rules.MAP_HALF+0.5)))
	fog.multimesh=mm; add_child(fog)

func _update_vision(refresh_render=true):
	if visible_cells[0].is_empty(): return
	for team in 2: visible_cells[team].fill(0)
	for ent in entities:
		if not ent.alive or ent.team<0: continue
		var radius: int = Rules.SIGHT[ent.kind]
		var c=_cell(ent.pos)
		for y in range(maxi(0,c.y-radius),mini(Rules.MAP_SIZE,c.y+radius+1)):
			for x in range(maxi(0,c.x-radius),mini(Rules.MAP_SIZE,c.x+radius+1)):
				if Vector2(x-c.x,y-c.y).length_squared()<=radius*radius:
					visible_cells[ent.team][y*Rules.MAP_SIZE+x]=1
					if explored_cells[ent.team][y*Rules.MAP_SIZE+x]==0: progress_serial+=1
					explored_cells[ent.team][y*Rules.MAP_SIZE+x]=1
	_refresh_work_memory()
	if refresh_render:
		_publish_faction_views()
		_refresh_fog()

func _refresh_fog():
	if is_instance_valid(fog):
		for i in Rules.MAP_SIZE*Rules.MAP_SIZE:
			var state=2 if visible_cells[0][i] else (1 if explored_cells[0][i] else 0)
			if fog_render_state[i]==state: continue
			fog_render_state[i]=state
			fog.multimesh.set_instance_color(i,Color(0.055,0.12,0.12,0.0 if state==2 else (0.65 if state==1 else 0.94)))

func _visible_to(ent,team):
	return ent.team==team or (not visible_cells[team].is_empty() and visible_cells[team][_cell_index(ent.pos)]!=0)

func _note_unit_action(ent: Dictionary, action: String, facing_point: Vector3=Vector3.INF) -> void:
	# Called only after a successful authority action. It can never cause one.
	for team in 2:
		if not _visible_to(ent,team): continue
		var cue: Dictionary=unit_action_cues[team].get(ent.id,{})
		if action=="attack_ready": cue.ready_tick=tick_count
		elif action in ["attack","hit"]: cue[action+"_tick"]=tick_count
		else: cue.work_tick=tick_count; cue.work_clip=action
		if facing_point!=Vector3.INF:
			var direction=facing_point-ent.pos
			cue.yaw=atan2(direction.x,direction.z)
		unit_action_cues[team][ent.id]=cue

func _publish_faction_views():
	for team in 2:
		var observed={}
		for ent in entities:
			# Gate before copying ANY current hidden entity fields.
			if not _visible_to(ent,team) or not ent.alive: continue
			var record={}
			for key in ["id","kind","team","category","pos","hp","max_hp","progress","built","radius"]: record[key]=ent[key]
			record.owned=ent.team==team; record.alive=true
			record.visual_yaw=ent.body.rotation.y
			if ent.category=="unit":
				# Public visible pose cues, never enemy command targets/path coordinates.
				record.visual_moving=not ent.path.is_empty()
				record.visual_working=ent.state in ["gather","build","repair"] and ent.path.is_empty()
				record.visual_fast=ent.state=="move" or not ent.path.is_empty()
				var cue: Dictionary=unit_action_cues[team].get(ent.id,{})
				record.visual_action=cue.get("work_clip","idle") if cue.get("work_tick",-1)==tick_count else "idle"
				record.visual_working=record.visual_action!="idle"
				record.visual_attack_tick=cue.get("attack_tick",-1)
				record.visual_hit_tick=cue.get("hit_tick",-1)
				record.visual_action_yaw=cue.get("yaw",record.visual_yaw)
				record.visual_carrying=record.owned and ent.kind=="villager" and _cargo_amount(ent)>0
				var anticipate_ticks=6
				record.visual_attack_ready=cue.get("ready_tick",-1)==tick_count and ent.state=="attack" and ent.path.is_empty() and ent.cooldown_ticks>0 and ent.cooldown_ticks<=anticipate_ticks and tick_count-record.visual_attack_tick<=Rules.ATTACK_TICKS[ent.kind]
				record.visual_anticipation=1.0-float(ent.cooldown_ticks)/anticipate_ticks
			if record.owned:
				record.rally_point=ent.get("rally_point",Vector3.INF)
				for key in ["state","queue","carry","carry_type","path","target","dest","gather_type","mode"]: record[key]=ent[key].duplicate(true) if ent[key] is Array or ent[key] is Dictionary else ent[key]
				if ent.category=="unit":
					for key in ["path_status","path_reason","path_pending","path_request_kind","path_request_state","path_request_target","path_request_epoch","work_epoch","traffic_route"]:
						var fallback=false if key in ["path_pending","traffic_route"] else (-1 if key in ["path_request_target","work_epoch"] else (-2 if key=="path_request_epoch" else ""))
						record[key]=ent.get(key,fallback)
					var prior=faction_views[team].get_record(ent.id)
					record.last_native_motion_tick=prior.get("last_native_motion_tick",-1) if prior.get("owned",false) else -1
					record.last_native_motion_position=prior.get("last_native_motion_position",ent.pos) if prior.get("owned",false) else ent.pos
					var segment=traffic_tick_segments.get(ent.id,[])
					if owned_motion_witness_tick==tick_count and segment.size()==2 and segment[0]!=segment[1] and segment[1]==ent.pos:
						record.last_native_motion_tick=tick_count; record.last_native_motion_position=segment[1]
				record.cargo_milli=_cargo_amount(ent) if ent.kind=="villager" else 0
			observed[ent.id]=record
		# Forget hidden action history before it can be replayed on reappearance.
		for id in unit_action_cues[team].keys():
			if not observed.has(id): unit_action_cues[team].erase(id)
		faction_views[team].publish(observed,visible_cells[team],tick_count)
	# Templates copied only while observed. Never resurrect the authority node.
	for record in faction_views[0].records().values():
		if record.owned or record.remembered or presentation_nodes.has(record.id): continue
		var source=_get_entity(record.id)
		var proxy=Node3D.new(); add_child(proxy)
		var body=source.body.duplicate(); proxy.add_child(body)
		var bar=null; var fill=null
		if is_instance_valid(source.bar):
			bar=source.bar.duplicate(); proxy.add_child(bar)
			fill=bar.get_child(1)
		presentation_nodes[record.id]={"node":proxy,"body":body,"bar":bar,"fill":fill,"remembered":false,"anim":source.anim}

func _gray_proxy(node, remembered):
	if node is MeshInstance3D:
		if not node.has_meta("observed_material_override"): node.set_meta("observed_material_override",node.material_override)
		node.material_override=_material(Color("777b79")) if remembered else node.get_meta("observed_material_override")
	for child in node.get_children(): _gray_proxy(child,remembered)

func _update_visuals(delta):
	for decoration in world_decor:
		decoration.visible=explored_cells[0][_cell_index(decoration.global_position)]!=0
	var records=faction_views[0].records()
	# Static condition only: no animation clock during pause/focus loss/end.
	building_damage_presenter.update(records,self)
	var running=not paused and not game_over and application_focused and not application_suspended
	_update_attack_effects(delta,running)
	character_presenter.consume_deaths(pending_visual_deaths,self,BLUE,RED)
	pending_visual_deaths.clear()
	character_presenter.reconcile(records)
	character_presenter.update_deaths(delta,not paused and application_focused and not application_suspended,func(p): return visible_cells[0][_cell_index(p)]!=0)
	for proxy in presentation_nodes.values(): proxy.node.visible=false
	for ent in entities:
		# Authority nodes for other factions are never presentation memory.
		ent.node.visible=false; ent.ring.visible=false
		if is_instance_valid(ent.bar): ent.bar.visible=false
		var record=records.get(ent.id,{})
		if record.is_empty(): continue
		if not record.owned:
			if not presentation_nodes.has(record.id): continue
			var proxy=presentation_nodes[record.id]
			proxy.node.visible=true; proxy.node.position=record.pos
			if record.category=="building": ConstructionVisual.apply(proxy.body,record.kind,record.built,record.progress)
			proxy.body.rotation.y=record.visual_yaw
			if record.category=="unit":
				character_presenter.present(record,proxy.body,RED if record.team==1 else BLUE,delta,running)
			if proxy.remembered!=record.remembered:
				_gray_proxy(proxy.body,record.remembered); proxy.remembered=record.remembered
			if is_instance_valid(proxy.bar):
				proxy.bar.visible=not record.remembered and record.hp<record.max_hp
				if not record.remembered: proxy.fill.scale.x=_health_bar_fill_scale(record,proxy.bar)
			continue
		ent.node.visible=true; ent.node.position=record.pos
		ent.ring.visible=record.id in selected
		if record.category=="building": ConstructionVisual.apply(ent.body,record.kind,record.built,record.progress)
		if record.category=="unit":
			character_presenter.present(record,ent.body,BLUE if record.team==0 else RED,delta,running)
		if is_instance_valid(ent.bar):
			ent.bar.visible=record.id in selected or record.hp<record.max_hp
			ent.bar_fill.scale.x=_health_bar_fill_scale(record,ent.bar)

func visual_evidence_snapshot() -> Dictionary:
	# Current visible presentation only, never hidden authority nodes.
	return character_presenter.visual_evidence_snapshot()

func _attack_effect(ent,target):
	if ent.kind!="archer": return
	if not _visible_to(ent,0) or not _visible_to(target,0): return
	if game_over: return
	if attack_effects.size()>=MAX_ATTACK_EFFECTS:
		_discard_attack_effect(0)
	var beam=Node3D.new(); add_child(beam)
	var start=ent.pos+Vector3(0,1,0); var finish=target.pos+Vector3(0,0.8,0)
	var direction=finish-start
	var mesh=BoxMesh.new(); mesh.size=Vector3(0.045,0.045,direction.length())
	_mesh(beam,mesh,Vector3.ZERO,GOLD if ent.team==0 else RED)
	beam.position=(start+finish)*0.5; beam.look_at(finish)
	# Copy only release-time positions. Never follow the authority target through fog.
	attack_effects.append({"node":beam,"origin":ent.pos,"endpoint":target.pos,
		"origin_owned":ent.team==0,"endpoint_owned":target.team==0,"age":0.0})

func _discard_attack_effect(index: int):
	var beam=attack_effects[index].node
	if is_instance_valid(beam):
		beam.visible=false; beam.queue_free()
	attack_effects.remove_at(index)

func _clear_attack_effects():
	while not attack_effects.is_empty(): _discard_attack_effect(attack_effects.size()-1)

func _update_attack_effects(delta: float,running: bool):
	if game_over:
		_clear_attack_effects(); return
	var elapsed=maxf(0.0,delta) if is_finite(delta) else 0.0
	for i in range(attack_effects.size()-1,-1,-1):
		var cue: Dictionary=attack_effects[i]
		# Revocation runs even while paused; exploration memory is not visibility.
		var origin_seen=cue.origin_owned or visible_cells[0][_cell_index(cue.origin)]!=0
		var endpoint_seen=cue.endpoint_owned or visible_cells[0][_cell_index(cue.endpoint)]!=0
		if not is_instance_valid(cue.node) or not origin_seen or not endpoint_seen:
			_discard_attack_effect(i); continue
		if running: cue.age+=elapsed
		if cue.age>=ATTACK_EFFECT_SECONDS: _discard_attack_effect(i)

# --- Responsive UI and input. Buttons never mutate economy directly. ---
func _style(color,border=Color("656653"),radius=5):
	var style=StyleBoxFlat.new(); style.bg_color=color; style.border_color=border
	style.set_border_width_all(1); style.set_corner_radius_all(radius)
	style.content_margin_left=14; style.content_margin_right=14
	style.content_margin_top=10; style.content_margin_bottom=10
	return style

func _label(text,size=16,color=CREAM):
	var label=Label.new(); label.text=text
	label.add_theme_color_override("font_color",color); label.add_theme_font_size_override("font_size",size)
	return label

func _button(text,callback,min_width=80):
	var button=Button.new(); button.text=text; button.custom_minimum_size=Vector2(min_width,46)
	button.add_theme_stylebox_override("normal",_style(Color("343b30")))
	button.add_theme_stylebox_override("hover",_style(Color("4c5745"),GOLD))
	button.add_theme_stylebox_override("pressed",_style(Color("687257"),GOLD))
	button.add_theme_stylebox_override("disabled",_style(Color("2b3228"),Color("454d3e")))
	button.add_theme_color_override("font_color",CREAM)
	button.add_theme_font_size_override("font_size",14)
	for style_name in ["normal","hover","pressed","disabled"]:
		var style=button.get_theme_stylebox(style_name)
		style.content_margin_top=2; style.content_margin_bottom=2; style.content_margin_left=8; style.content_margin_right=8
	button.pressed.connect(callback)
	button.gui_input.connect(func(event): _button_touch_input(button,event))
	return button

func _create_ui():
	var layer=CanvasLayer.new(); add_child(layer)
	ui=Control.new(); ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); ui.mouse_filter=Control.MOUSE_FILTER_IGNORE; layer.add_child(ui)
	var theme=Theme.new(); theme.default_font=body_font; theme.default_font_size=15; ui.theme=theme
	hud_top=PanelContainer.new(); hud_top.name="CompactResourceBar"; ui.add_child(hud_top); hud_top.add_theme_stylebox_override("panel",_compact_panel_style())
	compact_top_stack=VBoxContainer.new(); compact_top_stack.add_theme_constant_override("separation",3); hud_top.add_child(compact_top_stack)
	compact_top_line=HBoxContainer.new(); compact_top_line.add_theme_constant_override("separation",10); compact_top_stack.add_child(compact_top_line)
	compact_brand=_label("霧谷王旗",13,GOLD); compact_brand.tooltip_text=Rules.BUILD_ID; compact_top_line.add_child(compact_brand)
	top_resources=_label("",16); top_resources.size_flags_horizontal=Control.SIZE_EXPAND_FILL; compact_top_line.add_child(top_resources)
	time_label=_label("",14); compact_top_line.add_child(time_label)
	pause_button=_button("暫停",func(): _toggle_pause(),60); compact_top_line.add_child(pause_button)
	compact_menu_button=_button("選單",func(): _toggle_compact_menu(),60); compact_top_line.add_child(compact_menu_button)
	hud_bottom=PanelContainer.new(); hud_bottom.name="CompactContextPanel"; ui.add_child(hud_bottom); hud_bottom.add_theme_stylebox_override("panel",_compact_panel_style())
	compact_bottom_stack=VBoxContainer.new(); compact_bottom_stack.add_theme_constant_override("separation",4); hud_bottom.add_child(compact_bottom_stack)
	selection_row=HBoxContainer.new(); selection_row.add_theme_constant_override("separation",12); compact_bottom_stack.add_child(selection_row)
	selection_title=_label("",17,GOLD); selection_row.add_child(selection_title)
	selection_detail=_label("",14); selection_detail.size_flags_horizontal=Control.SIZE_EXPAND_FILL; selection_detail.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; selection_row.add_child(selection_detail)
	queue_label=_label("",14,Color("c8d4b3")); queue_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; selection_row.add_child(queue_label)
	compact_narrow_info=VBoxContainer.new(); compact_narrow_info.add_theme_constant_override("separation",2); compact_bottom_stack.add_child(compact_narrow_info)
	action_scroll=ScrollContainer.new(); action_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_AUTO; action_scroll.vertical_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED; action_scroll.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	var command_row=HBoxContainer.new(); command_row.add_theme_constant_override("separation",8); compact_bottom_stack.add_child(command_row); command_row.add_child(action_scroll)
	var action_line=HBoxContainer.new(); action_line.add_theme_constant_override("separation",10); action_scroll.add_child(action_line)
	actions=HBoxContainer.new(); actions.add_theme_constant_override("separation",8); action_line.add_child(actions)
	compact_unit_tools=HBoxContainer.new(); compact_unit_tools.add_theme_constant_override("separation",8); command_row.add_child(compact_unit_tools); command_row.move_child(compact_unit_tools,0)
	touch_button=_button("指令",_toggle_unit_command,54); compact_unit_tools.add_child(touch_button)
	compact_cancel_button=_button("取消",func(): _cancel_mode(),54); compact_unit_tools.add_child(compact_cancel_button)
	compact_menu_dismiss=Control.new(); compact_menu_dismiss.name="MenuDismissShield"; compact_menu_dismiss.mouse_filter=Control.MOUSE_FILTER_STOP; compact_menu_dismiss.gui_input.connect(_dismiss_compact_menu_input); ui.add_child(compact_menu_dismiss); compact_menu_dismiss.hide()
	compact_menu=PanelContainer.new(); compact_menu.name="ShortcutMenu"; ui.add_child(compact_menu); compact_menu.add_theme_stylebox_override("panel",_style(Color("1d241ef5")))
	var menu_scroll=ScrollContainer.new(); menu_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED; menu_scroll.vertical_scroll_mode=ScrollContainer.SCROLL_MODE_AUTO; compact_menu.add_child(menu_scroll)
	var menu_box=VBoxContainer.new(); menu_box.size_flags_horizontal=Control.SIZE_EXPAND_FILL; menu_box.add_theme_constant_override("separation",6); menu_scroll.add_child(menu_box)
	var menu_title=HBoxContainer.new(); menu_box.add_child(menu_title)
	var menu_heading=_label("霧谷王旗 · 快捷選單",17,GOLD); menu_heading.size_flags_horizontal=Control.SIZE_EXPAND_FILL; menu_title.add_child(menu_heading)
	menu_title.add_child(_button("關閉",func(): _toggle_compact_menu(),60))
	mission_label=_label("",14,Color("c8d4b3")); mission_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; menu_box.add_child(mission_label)
	var nav=HBoxContainer.new(); nav.add_theme_constant_override("separation",6); menu_box.add_child(nav)
	nav.add_child(_button("主堡",func(): _compact_menu_action(_home),78))
	nav.add_child(_button("閒置村民",func(): _compact_menu_action(func(): _select_group("idle")),96))
	nav.add_child(_button("全軍",func(): _compact_menu_action(func(): _select_group("army")),78))
	var nav2=HBoxContainer.new(); nav2.add_theme_constant_override("separation",6); menu_box.add_child(nav2)
	nav2.add_child(_button("所有村民",func(): _compact_menu_action(func(): _select_group("villagers")),96))
	nav2.add_child(_button("斥候",func(): _compact_menu_action(func(): _select_group("scout")),78))
	nav2.add_child(_button("小地圖",func(): compact_map_choice=0 if minimap.visible else 1; _layout_ui(),84))
	menu_box.add_child(_button("框選單位",func(): _compact_menu_action(_start_box_select),110))
	audio_button=_button("音效：關",_toggle_audio,110); audio_button.name="AudioToggle"; menu_box.add_child(audio_button)
	audio_button.tooltip_text="點按開啟原創提示音；暫停及背景時靜音"
	var nav3=HBoxContainer.new(); nav3.add_theme_constant_override("separation",6); menu_box.add_child(nav3)
	nav3.add_child(_button("取消模式",func(): _compact_menu_action(_cancel_mode),100))
	nav3.add_child(_button("移動／攻擊",func(): _compact_menu_action(_start_unit_command),110))
	nav3.add_child(_button("投降",func(): _compact_menu_action(_confirm_surrender),78))
	help_label=_label("",13,Color("c6cbbd")); help_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; menu_box.add_child(help_label)
	compact_menu.hide()
	toast_label=_label("",15,GOLD); ui.add_child(toast_label); toast_label.mouse_filter=Control.MOUSE_FILTER_IGNORE
	toast_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	toast_label.add_theme_color_override("font_shadow_color",Color("132823")); toast_label.add_theme_constant_override("shadow_offset_x",1); toast_label.add_theme_constant_override("shadow_offset_y",2)
	toast_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	minimap=load("res://scripts/minimap.gd").new(); minimap.game=self; ui.add_child(minimap)
	drag_rect=ReferenceRect.new(); drag_rect.border_color=GOLD; drag_rect.border_width=1.5; drag_rect.editor_only=false; drag_rect.mouse_filter=Control.MOUSE_FILTER_IGNORE; drag_rect.hide(); ui.add_child(drag_rect)
	end_panel=PanelContainer.new(); ui.add_child(end_panel); end_panel.add_theme_stylebox_override("panel",_style(Color("1d241ef5"),GOLD,14))
	var end_box=VBoxContainer.new(); end_box.add_theme_constant_override("separation",14); end_panel.add_child(end_box)
	end_title=_label("王旗再起",32,GOLD); end_title.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER; end_box.add_child(end_title)
	end_body=_label("",16); end_body.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; end_box.add_child(end_body)
	end_box.add_child(_button("再開一局",func(): get_tree().reload_current_scene()))
	end_panel.hide()
	# Child controls may bubble wheel events to their ScrollContainer, but the
	# owning UI boundary must consume leftovers (including at scroll limits).
	for boundary in [hud_top,hud_bottom,compact_menu,compact_menu_dismiss,minimap,end_panel]:
		boundary.mouse_force_pass_scroll_events=false
	get_viewport().size_changed.connect(_on_viewport_size_changed)
	get_viewport().gui_focus_changed.connect(_on_ui_camera_focus_changed)
	hud_top.minimum_size_changed.connect(_defer_layout); hud_bottom.minimum_size_changed.connect(_defer_layout)
	_layout_ui(); _update_hud(); call_deferred("_layout_ui")


# Web canvas dimensions are physical pixels; UX01 target sizes and drag slop
# are CSS pixels. Window scaling also converts OS input and Camera3D coordinates,
# keeping HUD, world picking and placement in one logical coordinate system.
func _sync_web_display_scale():
	if not OS.has_feature("web"): return
	var scale=maxf(1.0,DisplayServer.screen_get_scale())
	if not is_equal_approx(get_window().content_scale_factor,scale):
		get_window().content_scale_factor=scale

func _on_viewport_size_changed():
	if not is_inside_tree(): return
	_sync_web_display_scale()
	# Only real viewport changes cancel intent, not routine HUD relayouts.
	_cancel_mode()
	_layout_ui()

func _cancel_pointer_streams():
	box_cancel_press.clear(); box_cancel_repeat.clear()
	for index in all_touch_ids: canceled_touch_ids[index]=true
	for button_index in pressed_mouse_buttons: canceled_mouse_buttons[button_index]=true
	pressed_mouse_buttons.clear()
	touch_press_epochs.clear()
	_clear_box_select()
	# Native BaseButton ignores MouseButton.canceled. Clear its held attempt
	# without emitting its action, including when a modal loses focus or closes.
	if is_instance_valid(ui):
		for button in ui.find_children("*","BaseButton",true,false):
			if button.button_pressed and not button.toggle_mode and not button.disabled:
				button.disabled=true; button.disabled=false
	dragging=false; drag_active=false; middle_drag=false
	touch_points.clear(); all_touch_ids.clear(); gui_touch_press.clear(); action_touch_scroll.clear(); touch_gesture=false
	if is_instance_valid(drag_rect): drag_rect.hide()

func _defer_layout():
	call_deferred("_layout_ui")

func _layout_ui():
	if not is_inside_tree() or not is_instance_valid(ui): return
	var size=get_viewport().get_visible_rect().size
	short_ui=size.y<560; compact_ui=size.x<760 or short_ui
	var narrow=size.x<620
	var stack_resources=size.x<480
	if stack_resources and top_resources.get_parent()!=compact_top_stack:
		top_resources.reparent(compact_top_stack); compact_top_stack.move_child(top_resources,0)
	elif not stack_resources and top_resources.get_parent()!=compact_top_line:
		top_resources.reparent(compact_top_line); compact_top_line.move_child(top_resources,1)
	compact_brand.visible=size.x>=620 or stack_resources
	compact_brand.size_flags_horizontal=Control.SIZE_EXPAND_FILL if stack_resources else Control.SIZE_FILL
	compact_menu_button.text="收起" if compact_menu.visible else "選單"
	top_resources.add_theme_font_size_override("font_size",14 if narrow else 16)
	var info_parent=compact_narrow_info if narrow else selection_row
	for label in [selection_detail,queue_label]:
		if label.get_parent()!=info_parent: label.reparent(info_parent)
	queue_label.custom_minimum_size.x=0 if narrow or queue_label.text.is_empty() else 222
	compact_narrow_info.visible=narrow
	var margin=6.0 if short_ui or narrow else 8.0
	var width=size.x-margin*2
	hud_top.position=Vector2(margin,margin); hud_top.size=Vector2(width,0)
	hud_top.size.y=hud_top.get_combined_minimum_size().y
	hud_bottom.size=Vector2(width,0)
	var bottom_height=hud_bottom.get_combined_minimum_size().y
	hud_bottom.size.y=bottom_height; hud_bottom.position=Vector2(margin,size.y-bottom_height-margin)
	minimap.size=Vector2(124,124); minimap.position=Vector2(margin,hud_bottom.position.y-132)
	minimap.visible=compact_map_choice==1 or (compact_map_choice==-1 and size.x>=1000 and not short_ui)
	toast_label.position=Vector2(margin,hud_top.position.y+hud_top.size.y+5); toast_label.size=Vector2(width,42)
	compact_menu.position=Vector2(maxf(margin,size.x-380-margin),hud_top.position.y+hud_top.size.y+6)
	compact_menu.size=Vector2(minf(380,width),minf(340,size.y-compact_menu.position.y-margin))
	compact_menu_dismiss.position=Vector2(0,hud_top.position.y+hud_top.size.y)
	compact_menu_dismiss.size=Vector2(size.x,size.y-compact_menu_dismiss.position.y)
	if compact_menu.visible:
		ui.move_child(compact_menu_dismiss,ui.get_child_count()-1); ui.move_child(compact_menu,ui.get_child_count()-1)
	end_panel.position=Vector2(maxf(12,size.x/2-220),maxf(12,size.y/2-110))
	end_panel.size=Vector2(minf(440,size.x-24),220)
	_layout_tutorial()

func _selection_stance_summary(selection: Array) -> String:
	# Presentation only: caller supplies sanitized faction records, never entities.
	# Count only applied stances. Queued commands must not look committed early.
	var defending=0
	var stopped=0
	var owned_units=0
	for ent in selection:
		if not ent.get("owned",false) or not ent.get("alive",false) or ent.get("category","")!="unit": continue
		owned_units+=1
		if ent.get("mode","")=="DEFEND": defending+=1
		elif ent.get("mode","")=="STOP": stopped+=1
	if owned_units==1:
		return "守備" if defending==1 else ("停止" if stopped==1 else "")
	var parts=PackedStringArray()
	if defending>0: parts.append("守備 %d" % defending)
	if stopped>0: parts.append("停止 %d" % stopped)
	return " · ".join(parts)

func _update_hud():
	if not is_instance_valid(top_resources): return
	_refresh_tutorial()
	if game_over:
		compact_menu.hide(); compact_menu_dismiss.hide()
	var display_bank=economy.bank_units_floor(0)
	top_resources.text="食糧 %d   木材 %d   人口 %d/%d" % [display_bank.food,display_bank.wood,_population(0),_capacity(0)]
	time_label.text="%02d:%02d" % [floori(game_time/60),int(game_time)%60]
	pause_button.text="繼續" if paused else "暫停"
	mission_label.text="摧毀敵方主堡 • 探索黑霧尋找敵軍 • Demo "+Rules.VERSION
	if completed_builds[0]==0: mission_label.text="首要任務：採集資源，再建民居與兵營。"
	if delivered_total[0]==0: mission_label.text="首要任務：選取村民，向漿果或樹木落指令。"
	if game_time>=Rules.TIME_LIMIT-60 and not game_over: mission_label.text="尚餘 %d 秒到達對局上限，屆時和局。" % ceili(Rules.TIME_LIMIT-game_time)
	if game_time>=Rules.TIME_LIMIT-60 and not game_over: time_label.text+=" · 和局 %ds" % ceili(Rules.TIME_LIMIT-game_time)
	touch_button.text="指令中" if touch_command else "指令"
	var selection=[]
	for id in selected:
		var ent=faction_views[0].get_record(id)
		if not ent.is_empty() and ent.alive: selection.append(ent)
	# Preserve the reviewed conservative warning suppression for own queued intent.
	var own_command_pending=false
	for command in commands:
		if command.team==0: own_command_pending=true; break
	var missing_workers=0
	var route_failed_workers=0
	for worker in selection:
		if not WorkerIdleStatus.missing_resource(worker,faction_views[0].records(),own_command_pending).is_empty(): missing_workers+=1
		if not WorkerIdleStatus.route_failure(worker,own_command_pending).is_empty(): route_failed_workers+=1
	queue_label.text=""
	if selection.is_empty():
		selection_title.text="霧谷等你探索"
		selection_detail.text="選取主堡可訓練村民；選取村民可建造。"
	elif selection.size()==1:
		var ent=selection[0]
		selection_title.text=Rules.NAMES.get(ent.kind,ent.kind)
		var state_names={"idle":"待命","move":"移動","gather":"採集","deliver":"交付","build":"建造","repair":"修理","return":"返回守備點","attack":"攻擊"}
		var missing=WorkerIdleStatus.missing_resource(ent,faction_views[0].records(),own_command_pending)
		var status=state_names.get(ent.state,"") if missing.is_empty() else WorkerIdleStatus.label(missing)
		var route_failure=WorkerIdleStatus.route_failure(ent,own_command_pending)
		if not route_failure.is_empty(): status=route_failure
		selection_detail.text="生命 %d / %d   ·   %s" % [ceili(ent.hp),int(ent.max_hp),status]
		if ent.kind=="villager" and ent.cargo_milli>0: selection_detail.text+="   負重 %d / 10" % floori(ent.cargo_milli/1000.0)
		if ent.built and Rules.PRODUCES.has(ent.kind): selection_detail.text+=" · 集合點已設定，新單位自動移動" if ent.get("rally_point",Vector3.INF)!=Vector3.INF else " · 可設定新單位集合點"
		if not ent.built: selection_detail.text="施工 %d%% · 村民抵達後繼續建造" % int(ent.progress*100)
		if not ent.queue.is_empty():
			queue_label.text="訓練 %ds · 隊列 %d" % [ceili(ent.queue[0].remaining_ticks/20.0),ent.queue.size()]
			if ent.queue[0].remaining_ticks<=0:
				queue_label.text="訓練完成，等待人口空位" if _population(0,false)>=_capacity(0) else "訓練完成，出口受阻；選取出口單位，再按指令移開"
			elif _population(0)>_capacity(0): queue_label.text="缺少住房，訓練暫停"
	else:
		selection_title.text="已選取 %d 個單位" % selection.size()
		selection_detail.text=("%d 村民無已知採集點" % missing_workers) if missing_workers>0 else "向資源、空地或可見敵軍落指令。"
		if route_failed_workers>0:
			selection_detail.text=(selection_detail.text+" · " if missing_workers>0 else "")+("%d 村民工作路線停止" % route_failed_workers)
	var stance_summary=_selection_stance_summary(selection)
	if not stance_summary.is_empty(): selection_detail.text+=" · "+stance_summary
	var key=str(selected)+":"+build_mode+":"+str(compact_ui)+":"+str(short_ui)+":"+str(box_select_mode)+":"+str(rally_building)
	if selection.size()==1: key+=":"+str(selection[0].built)+":"+str(selection[0].queue.size())+":"+str(selection[0].get("rally_point",Vector3.INF))
	if key!=action_key: action_key=key; _rebuild_actions(selection)
	_refresh_return_cargo_button()
	queue_label.visible=not queue_label.text.is_empty()
	var has_unit=false
	for ent in selection:
		if ent.category=="unit": has_unit=true
	compact_unit_tools.visible=has_unit and build_mode.is_empty() and not box_select_mode
	compact_cancel_button.visible=touch_command
	# One guidance suffix. Eligibility belongs to each worker, not merely to
	# another selected worker making the delivery button available.
	var idle_return_available=false
	if compact_ui and not paused and not game_over:
		for order in ReturnCargoAction.orders(faction_views[0].records(),selected,commands):
			var worker=faction_views[0].get_record(order.ids[0])
			if worker.get("state","")=="idle": idle_return_available=true; break
	if build_mode.is_empty() and not box_select_mode and rally_building<0:
		if touch_command:
			if has_unit and compact_ui: selection_detail.text="點樹木或漿果採集，點空地移動；取消可返回選取。"
		elif idle_return_available:
			selection_detail.text+=" · 滑動底列，按交付資源"
		elif missing_workers>0:
			selection_detail.text+=" · 探索或落指令"
		elif route_failed_workers>0:
			selection_detail.text+=" · 請重新落指令"
		elif has_unit and compact_ui:
			selection_detail.text+=" · 按指令再點目標"
	if build_mode.is_empty():
		help_label.text="點選單位 → 指令 → 點目標。雙指平移／縮放。窄畫面可左右滑動底列，查看全部行動。" if compact_ui else "左鍵選取／框選 · 右鍵落指令 · WASD／方向鍵平移 · 滾輪縮放 · 空白鍵返回主堡"
		if touch_command: help_label.text="指令模式：點擊地面、資源或可見敵軍。取消可返回選取。"
	else:
		var reason=_placement_reason(build_mode,pointer_world,0,_selected_builder())
		help_label.text=("位置已選，按確認建造；點空地可重選。" if build_preview_held else "點選空地作預覽，再按確認建造。") if reason.is_empty() else "不可建造："+reason
		if Rules.PRODUCES.has(build_mode): selection_detail.text="生產建築需鄰接淺色保護通道；通道上不可建造。"
		if is_instance_valid(build_confirm): build_confirm.disabled=not reason.is_empty() or paused or not build_preview_held
		selection_title.text="建造 "+Rules.NAMES.get(build_mode,build_mode)
		selection_detail.text=help_label.text
		queue_label.text="木材 "+str(COSTS[build_mode].wood); queue_label.show()
	if rally_building>=0:
		selection_detail.text="點可見空地設定集合點；新單位自動移動。"
		help_label.text=selection_detail.text
	if box_select_mode:
		selection_title.text="框選單位"
		selection_detail.text="在戰場按住移動，選取框內單位；取消可返回選取。"
		queue_label.hide()
		help_label.text=selection_detail.text
	call_deferred("_layout_ui")

func _rebuild_actions(selection):
	for child in actions.get_children(): actions.remove_child(child); child.queue_free()
	build_confirm=null
	return_cargo_button=null
	if rally_building>=0:
		actions.add_child(_button("取消集合點",_cancel_mode,120)); return
	if box_select_mode:
		var cancel=_button("取消框選",_cancel_box_from_ui,120)
		cancel.gui_input.connect(func(event): _box_cancel_button_input(cancel,event))
		actions.add_child(cancel); return
	if not build_mode.is_empty():
		build_confirm=_button("確認建造",func(): _confirm_build(),120); actions.add_child(build_confirm)
		actions.add_child(_button("取消建造",func(): _cancel_mode(),110)); return
	if selection.is_empty():
		actions.add_child(_button("選取村民",func(): _select_group("villagers"),120))
		actions.add_child(_button("探索霧谷",func(): _select_group("scout"),120)); return
	if _selected_builder()>=0:
		for kind in ["house","barracks","range","storehouse"]:
			var choice=kind
			actions.add_child(_button(Rules.NAMES[kind]+"\n木材 "+str(COSTS[kind].wood),func(): _start_build(choice),90))
	elif selection.size()==1:
		var ent=selection[0]
		if not ent.built:
			actions.add_child(_button("取消施工\n退回 75%",func(): _submit("cancel_build",{"building":ent.id}),130))
		elif Rules.PRODUCES.has(ent.kind):
			actions.add_child(_button("集合點",func(): _start_ground_rally(ent.id),100))
			if ent.get("rally_point",Vector3.INF)!=Vector3.INF:
				actions.add_child(_button("取消集合點設定",func(): _submit("rally",{"building":ent.id,"clear":true}),120))
			var kind=Rules.PRODUCES[ent.kind]
			var price=""
			for resource in COSTS[kind]: price+=("食 " if resource=="food" else "木 ")+str(COSTS[kind][resource])+" "
			actions.add_child(_button("訓練"+Rules.NAMES[kind]+"\n"+price,func(): _submit("train",{"building":ent.id,"kind":kind}),120))
			if not ent.queue.is_empty(): actions.add_child(_button("取消最後一項",func(): _submit("cancel_train",{"building":ent.id}),130))
		if ent.owned and ent.category=="building" and ent.built and ent.kind!="town_center":
			actions.add_child(_button("拆除建築\n不退資源",func(): _confirm_demolish(ent.id),120))
	# Preserve the first build targets on narrow phones. Cargo delivery is
	# reachable through the existing horizontal action strip.
	return_cargo_button=_button("交付資源",_return_selected_cargo,100)
	actions.add_child(return_cargo_button)
	# Only targeting and Cancel are pinned. Secondary commands share the
	# scrollable action strip so even 320 CSS px leaves a whole build target.
	for ent in selection:
		if ent.category=="unit":
			actions.add_child(_button("停止",func(): _submit_selected_stance("stop"),54))
			actions.add_child(_button("守備",func(): _submit_selected_stance("defend"),54))
			break

func _refresh_return_cargo_button():
	if not is_instance_valid(return_cargo_button): return
	var records=faction_views[0].records()
	return_cargo_button.visible=ReturnCargoAction.has_villager(records,selected)
	# Refresh properties, not the node/action key: cargo, observations and
	# pending commands change without selection changing. Preserve touch grabs.
	return_cargo_button.disabled=paused or game_over or ReturnCargoAction.orders(records,selected,commands).is_empty()

func _return_selected_cargo():
	if paused or game_over or not build_mode.is_empty() or box_select_mode or rally_building>=0: return
	# Re-read the projection at activation, never a captured selection/target.
	var orders=ReturnCargoAction.orders(faction_views[0].records(),selected,commands)
	# An accepted explicit action also retires any unfinished world press.
	# A disabled/no-op Return must not cancel another targeting interaction.
	if not orders.is_empty(): _cancel_mode()
	for order in orders: _submit("order",order)
	_refresh_return_cargo_button()

func _start_unit_command():
	# Validate current projected selection before retiring another valid mode.
	# Selection and pending commands remain owned by the ordinary order path.
	if game_over:
		_message("戰役已結束。",5); return
	if paused:
		_message("已暫停。按繼續返回戰場。",5); return
	var has_unit=false
	for id in selected:
		var record=faction_views[0].get_record(id)
		if not record.is_empty() and record.get("owned",false) and record.get("alive",false) and record.get("team",-1)==0 and record.get("category","")=="unit" and not record.get("remembered",false):
			has_unit=true; break
	if not has_unit:
		_message("請選取自己的存活單位。",5); return
	_cancel_mode()
	touch_command=true; _update_hud()
	_message("點樹木或漿果採集，點空地移動；取消可返回選取。",5)

func _toggle_unit_command():
	if touch_command:
		_cancel_mode()
		_message("已取消指令。",5)
	else:
		_start_unit_command()

func _submit_selected_stance(type: String):
	# A deliberate Stop/Defend replaces the unfinished targeting interaction.
	# Retire held pointers too, so their late release cannot issue a new order.
	if not paused and not game_over and touch_command and build_mode.is_empty() and not box_select_mode and rally_building<0:
		_cancel_mode()
	_submit(type,{"ids":selected.duplicate()})

func _message(text,duration=4.0,build_guidance=false):
	# Ordinary feedback replaces any previous construction-mode guidance.
	toast_build_guidance=build_guidance
	if is_instance_valid(toast_label): toast_label.text=text
	toast_time=duration

func _select(ids):
	# Choosing a different group/building ends the previous builder preview.
	# Menu selection is also available while a held build preview is active.
	if not build_mode.is_empty(): _cancel_mode()
	box_cancel_repeat.clear()
	if box_select_mode and (touch_box_index>=0 or dragging): _cancel_pointer_streams()
	_clear_box_select()
	selected=[]
	for id in ids:
		var ent=faction_views[0].get_record(id)
		if not ent.is_empty() and ent.alive and ent.team==0: selected.append(id)
	for id in selected:
		if faction_views[0].get_record(id).kind=="villager": demo_tutorial.record("select")
	_sync_audio()
	audio_cues.selection(faction_views[0].records(),selected,Time.get_ticks_msec())
	action_key=""; touch_command=false; rally_building=-1; _update_hud()

func _box_cancel_button_input(button,event):
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and event.pressed:
		box_cancel_press={"source":"mouse","rect":button.get_global_rect()}
	elif event is InputEventScreenTouch and event.pressed and all_touch_ids.size()==1 and not touch_gesture:
		box_cancel_press={"source":"touch","rect":button.get_global_rect(),"index":event.index,"epoch":touch_press_epochs.get(event.index,0)}

func _cancel_box_from_ui():
	var continuation=box_cancel_press.duplicate()
	_cancel_mode()
	box_cancel_repeat=continuation

func _consume_box_cancel_repeat(event,viewport):
	var mouse_press=event is InputEventMouseButton and event.pressed
	var touch_press=event is InputEventScreenTouch and event.pressed
	if not mouse_press and not touch_press:
		if event is InputEventKey and event.pressed: box_cancel_press.clear(); box_cancel_repeat.clear()
		return false
	box_cancel_press.clear()
	var continuation=box_cancel_repeat
	box_cancel_repeat={}
	if continuation.is_empty() or viewport!=get_viewport(): return false
	if not continuation.rect.has_point(event.position): return false
	if mouse_press and continuation.source=="mouse" and event.button_index==MOUSE_BUTTON_LEFT and event.double_click:
		canceled_mouse_buttons[MOUSE_BUTTON_LEFT]=true
	elif touch_press and continuation.source=="touch" and event.double_tap:
		canceled_touch_ids[event.index]=true
	else: return false
	# Keep ownership for duplicate flagged continuations; the next ordinary
	# press (or a different source/location/key) starts fresh intent above.
	box_cancel_repeat=continuation
	viewport.set_input_as_handled()
	return true

func _start_box_select():
	if game_over: return
	_cancel_mode()
	box_previous_input_accumulation=Input.use_accumulated_input
	box_input_accumulation_owned=true
	Input.use_accumulated_input=false
	box_select_mode=true
	_update_hud()

func _restore_box_input_accumulation():
	if not box_input_accumulation_owned: return
	Input.use_accumulated_input=box_previous_input_accumulation
	box_input_accumulation_owned=false

func _exit_tree():
	building_damage_presenter.clear()
	_clear_attack_effects()
	character_presenter.clear()
	_restore_box_input_accumulation()
	if OS.has_feature("web"):
		JavaScriptBridge.eval("if(window.valleyTouchCancelHandler){window.removeEventListener('touchcancel',window.valleyTouchCancelHandler,true);delete window.valleyTouchCancelHandler;}delete window.valleyTouchCancel;")
	web_touch_cancel_callback=null

func _clear_box_select():
	_restore_box_input_accumulation()
	box_select_mode=false; touch_box_index=-1; touch_box_active=false
	if is_instance_valid(drag_rect): drag_rect.hide()

func _box_point_in_world(point):
	if not get_viewport().get_visible_rect().has_point(point): return false
	for boundary in [hud_top,hud_bottom,minimap,compact_menu_dismiss,end_panel,tutorial_panel]:
		if is_instance_valid(boundary) and boundary.is_visible_in_tree() and boundary.get_global_rect().has_point(point): return false
	return true

func _box_selection_ids(rect):
	var ids=[]
	for ent in faction_views[0].records().values():
		if ent.alive and ent.owned and ent.team==0 and ent.category=="unit" and not ent.remembered and rect.has_point(camera.unproject_position(ent.pos+Vector3(0,0.6,0))): ids.append(ent.id)
	return ids

func _selected_builder():
	for id in selected:
		var ent=faction_views[0].get_record(id)
		if not ent.is_empty() and ent.owned and ent.kind=="villager": return id
	return -1

func _select_group(kind):
	var ids=[]
	for ent in faction_views[0].records().values():
		if not ent.alive or ent.team!=0 or ent.category!="unit": continue
		if (kind=="idle" and ent.kind=="villager" and ent.state=="idle") or (kind=="army" and ent.kind!="villager") or (kind=="villagers" and ent.kind=="villager") or (kind=="scout" and ent.kind=="scout"): ids.append(ent.id)
	_select(ids)
	if not ids.is_empty(): camera_focus=faction_views[0].get_record(ids[0]).pos
	else: _message("沒有符合條件的單位。",2)

func _home():
	var castle=_first(0,"town_center")
	if not castle.is_empty(): camera_focus=castle.pos; _select([castle.id])

func _toggle_pause():
	if game_over: return
	if paused and (not application_focused or application_suspended):
		_message("請先返回遊戲視窗，再按繼續。",3); return
	paused=not paused; tick_accumulator=0
	_sync_audio()
	if paused: _cancel_mode(); _message("已暫停。按繼續返回戰場。",30)
	else:
		background_paused=false
		if inactivity_paused: no_progress_ticks=0; inactivity_paused=false
		_message("戰事繼續。",2)
	_update_hud()

func _notification(what):
	if test_mode or not is_instance_valid(ui): return
	if what==NOTIFICATION_APPLICATION_FOCUS_OUT or what==NOTIFICATION_APPLICATION_PAUSED:
		_quarantine_camera_keys()
		if what==NOTIFICATION_APPLICATION_FOCUS_OUT: application_focused=false
		else: application_suspended=true
		if not game_over: paused=true; background_paused=true; tick_accumulator=0
		_sync_audio()
		_cancel_mode(); _message("已自動暫停。返回後按繼續。",30)
	elif what==NOTIFICATION_APPLICATION_FOCUS_IN:
		if not application_focused or background_paused: discard_return_delta=true
		application_focused=true
	elif what==NOTIFICATION_APPLICATION_RESUMED:
		if application_suspended or background_paused: discard_return_delta=true
		application_suspended=false

func _camera_update():
	camera_focus.x=clampf(camera_focus.x,-Rules.CAMERA_LIMIT,Rules.CAMERA_LIMIT); camera_focus.z=clampf(camera_focus.z,-Rules.CAMERA_LIMIT,Rules.CAMERA_LIMIT)
	camera.position=camera_focus+Vector3(19,25,23)
	camera.look_at(camera_focus)
	camera.size=camera_zoom

func _ui_owns_camera_keys():
	if not is_instance_valid(ui): return false
	if compact_menu.is_visible_in_tree(): return true
	var focus=get_viewport().gui_get_focus_owner()
	if is_instance_valid(focus) and focus.is_visible_in_tree() and ui.is_ancestor_of(focus): return true
	# Embedded modal windows have their own viewport/focus and input stream.
	for child in ui.get_children():
		if child is Window and child.visible: return true
	return false

func _quarantine_camera_keys():
	for key in CAMERA_KEYS:
		if Input.is_physical_key_pressed(key) or Input.is_key_pressed(key): ui_camera_keys[key]=true

func _on_ui_camera_focus_changed(_control):
	if _ui_owns_camera_keys(): _quarantine_camera_keys()

func _track_camera_key(event,viewport):
	if not event is InputEventKey: return
	# Only the game viewport and its owned modal windows can claim/release keys.
	if viewport!=get_viewport() and not (viewport is Window and ui.is_ancestor_of(viewport)): return
	var key=event.physical_keycode if event.physical_keycode!=0 else event.keycode
	if key not in CAMERA_KEYS: return
	if not event.pressed: ui_camera_keys.erase(key)
	elif _ui_owns_camera_keys(): ui_camera_keys[key]=true
	elif not event.echo: ui_camera_keys.erase(key)

func _release_world_camera_focus():
	var focus=get_viewport().gui_get_focus_owner()
	if is_instance_valid(focus) and ui.is_ancestor_of(focus): focus.release_focus()

func _world_camera_key_pressed(key):
	return not ui_camera_keys.has(key) and Input.is_physical_key_pressed(key)

func _camera_input(delta):
	# OS focus loss can release a key without a game callback. Do not retain a
	# stale latch, but never turn a still-held UI press into world movement.
	for key in ui_camera_keys.keys():
		if not Input.is_physical_key_pressed(key) and not Input.is_key_pressed(key): ui_camera_keys.erase(key)
	if _ui_owns_camera_keys():
		_quarantine_camera_keys(); return
	var movement=Vector2.ZERO
	if _world_camera_key_pressed(KEY_A) or _world_camera_key_pressed(KEY_LEFT): movement.x-=1
	if _world_camera_key_pressed(KEY_D) or _world_camera_key_pressed(KEY_RIGHT): movement.x+=1
	if _world_camera_key_pressed(KEY_W) or _world_camera_key_pressed(KEY_UP): movement.y-=1
	if _world_camera_key_pressed(KEY_S) or _world_camera_key_pressed(KEY_DOWN): movement.y+=1
	if movement.length()>0: _pan_camera(movement.normalized()*delta*400)

func _pan_camera(pixels):
	var right=camera.global_basis.x; var forward=camera.global_basis.z
	right.y=0; forward.y=0
	camera_focus+=(right.normalized()*pixels.x+forward.normalized()*pixels.y)*(camera_zoom/get_viewport().get_visible_rect().size.y)

func _world_at(screen):
	var origin=camera.project_ray_origin(screen); var direction=camera.project_ray_normal(screen)
	if absf(direction.y)<0.0001: return camera_focus
	var p=origin+direction*(-origin.y/direction.y)
	return Vector3(clampf(p.x,-MAP_LIMIT,MAP_LIMIT),0,clampf(p.z,-MAP_LIMIT,MAP_LIMIT))

func _resource_mesh_faces(mesh_resource):
	# Shared public mesh assets are immutable. Cache local geometry only; each
	# visible proxy still supplies its own current presentation transform.
	var key=mesh_resource # Retain the immutable Resource, so identity cannot be reused.
	if not resource_pick_face_cache.has(key):
		var faces=mesh_resource.get_faces()
		if faces.size()%3!=0: return PackedVector3Array()
		for vertex in faces:
			if not vertex.is_finite(): return PackedVector3Array()
		resource_pick_face_cache[key]=faces
	return resource_pick_face_cache[key]

func _resource_ray_distance(record,ray_origin,ray_direction):
	# Gate BEFORE looking up any proxy. Hidden/remembered entities never supply
	# positions or geometry. This reads only the currently rendered resource.
	if record.category!="resource" or record.remembered or not record.alive: return INF
	if not ray_origin.is_finite() or not ray_direction.is_finite() or ray_direction.is_zero_approx(): return INF
	var proxy=presentation_nodes.get(record.id,{})
	if proxy.is_empty() or not is_instance_valid(proxy.node) or not proxy.node.is_visible_in_tree() or not is_instance_valid(proxy.get("body")): return INF
	var nearest=INF
	for mesh in proxy.body.find_children("*","MeshInstance3D",true,false):
		if not mesh.is_visible_in_tree() or mesh.mesh==null: continue
		var transform=mesh.global_transform
		if not transform.is_finite() or absf(transform.basis.determinant())<0.000001: continue
		var inverse=transform.affine_inverse()
		var origin=inverse*ray_origin
		var direction=(inverse.basis*ray_direction).normalized()
		if not origin.is_finite() or not direction.is_finite() or direction.is_zero_approx(): continue
		var bounds=mesh.mesh.get_aabb()
		if not bounds.position.is_finite() or not bounds.size.is_finite(): continue
		# The box is broad phase only: blank canopy-volume corners are NOT hits.
		if bounds.intersects_ray(origin,direction)==null: continue
		var faces=_resource_mesh_faces(mesh.mesh)
		for index in range(0,faces.size(),3):
			var hit=Geometry3D.ray_intersects_triangle(origin,direction,faces[index],faces[index+1],faces[index+2])
			if hit==null: continue
			var world_hit=transform*hit
			if world_hit.is_finite(): nearest=minf(nearest,ray_origin.distance_squared_to(world_hit))
	return nearest

func _pick(screen,allow_enemy=true):
	if not screen.is_finite(): return -1
	var best=-1; var distance=34.0 if compact_ui else 24.0
	var best_category=""
	var resources=[]
	for record in faction_views[0].records().values():
		if not record.alive or record.remembered or (record.team==1 and not allow_enemy): continue
		var p=camera.unproject_position(record.pos+Vector3(0,0.6 if record.category=="unit" else 1.0,0))
		if not p.is_finite(): continue
		var d=p.distance_to(screen)
		if record.category=="building": d-=12
		if d<distance or (d==distance and best>=0 and record.id<best):
			distance=d; best=record.id; best_category=record.category
		if allow_enemy and record.category=="resource": resources.append(record)
	# Selection remains the legacy point-pick path. Command targeting also
	# preserves a legacy unit/building winner, including its full 24/34px halo.
	if not allow_enemy or (best>=0 and best_category!="resource"): return best
	var ray_origin=camera.project_ray_origin(screen); var ray_direction=camera.project_ray_normal(screen)
	var resource=-1; var depth=INF
	for record in resources:
		var hit_distance=_resource_ray_distance(record,ray_origin,ray_direction)
		if is_finite(hit_distance) and (hit_distance<depth or (hit_distance==depth and (resource<0 or record.id<resource))):
			resource=record.id; depth=hit_distance
	# Closest visible resource mesh wins overlap; equal depths use stable ID.
	# A missed triangle keeps the existing resource-anchor touch tolerance.
	return resource if resource>=0 else best

func _start_ground_rally(id):
	if paused or game_over: return
	var record=faction_views[0].get_record(id)
	if record.is_empty() or not record.owned or not record.alive or not record.built or not Rules.PRODUCES.has(record.kind): return
	_cancel_mode()
	rally_building=id; touch_command=true; action_key=""; _update_hud()

func _send_world_order(screen):
	if rally_building>=0:
		_submit("rally",{"building":rally_building,"position":_world_at(screen)})
		_cancel_mode(); return

	if selected.is_empty(): return
	var p=_world_at(screen)
	_submit("order",{"ids":selected.duplicate(),"target":_pick(screen),"position":p})
	order_marker.position=p; marker_time=0.8; touch_command=false; rally_building=-1

func _tap(screen,is_touch):
	if game_over: return
	pointer_screen=screen; pointer_world=_point(_cell(_world_at(screen)))
	if box_select_mode: return # A tap is not a completed box-selection drag.
	if not paused and not build_mode.is_empty():
		# UX01: both mouse and touch choose a site; only Confirm submits the build.
		build_preview_held=true; _update_hud()
		return
	if not paused and touch_command:
		_send_world_order(screen); return
	var id=_pick(screen,false)
	if id>=0 and faction_views[0].get_record(id).team==0:
		if Input.is_physical_key_pressed(KEY_SHIFT) and not is_touch:
			var ids=selected.duplicate()
			if id in ids: ids.erase(id)
			else: ids.append(id)
			_select(ids)
		else: _select([id])
	elif is_touch and not selected.is_empty():
		# A novice target tap is not an implicit order and must not erase the
		# selection needed to follow the visible explicit-command instruction.
		var has_selected_unit=false
		for selected_id in selected:
			var record=faction_views[0].get_record(selected_id)
			if not record.is_empty() and record.owned and record.category=="unit": has_selected_unit=true
		_message("先按下方指令，再點樹木、漿果或空地。" if has_selected_unit else "已選取建築。先點選自己的單位，再按指令移動。",5)
		_update_hud()
	else: _select([])

func _input(event):
	_track_pointer_input(event,get_viewport())

func _track_pointer_input(event,viewport):
	if _consume_box_cancel_repeat(event,viewport): return
	_track_camera_key(event,viewport)
	# Consume interrupted input before GUI and world dispatch. A late drag must
	# not recreate touch_points, and a reused ID on a fresh press must work.
	if event is InputEventScreenTouch:
		if event.pressed:
			touch_press_serial+=1; touch_press_epochs[event.index]=touch_press_serial
			canceled_touch_ids.erase(event.index)
		elif canceled_touch_ids.has(event.index):
			canceled_touch_ids.erase(event.index)
			viewport.set_input_as_handled(); return
	elif event is InputEventScreenDrag and (canceled_touch_ids.has(event.index) or event.index not in all_touch_ids):
		viewport.set_input_as_handled(); return
	# GUI may ignore a release whose press began in the world. In explicit box
	# mode, crossing a UI boundary cancels the whole attempt before dispatch.
	if box_select_mode:
		var outside_touch=(event is InputEventScreenDrag or (event is InputEventScreenTouch and not event.pressed)) and event.index==touch_box_index and not _box_point_in_world(event.position)
		var outside_mouse=dragging and (event is InputEventMouseMotion or (event is InputEventMouseButton and not event.pressed and event.button_index==MOUSE_BUTTON_LEFT)) and not _box_point_in_world(event.position)
		if outside_touch or outside_mouse:
			_cancel_mode()
			if event is InputEventScreenTouch: canceled_touch_ids.erase(event.index)
			elif event is InputEventMouseButton: canceled_mouse_buttons.erase(event.button_index)
			viewport.set_input_as_handled(); return
	if event is InputEventMouseButton and event.button_index in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_RIGHT,MOUSE_BUTTON_MIDDLE]:
		if event.pressed:
			canceled_mouse_buttons.erase(event.button_index)
			pressed_mouse_buttons[event.button_index]=true
		else:
			pressed_mouse_buttons.erase(event.button_index)
			if canceled_mouse_buttons.has(event.button_index):
				canceled_mouse_buttons.erase(event.button_index)
				viewport.set_input_as_handled(); return
	# Releases consumed by HUD still clear a gesture started on the battlefield.
	if event is InputEventScreenTouch:
		if event.pressed:
			gui_touch_press.erase(event.index)
			if event.index not in all_touch_ids: all_touch_ids.append(event.index)
			if all_touch_ids.size()>1:
				if box_select_mode: _clear_box_select(); call_deferred("_update_hud")
				touch_gesture=true; touch_command=false; rally_building=-1
				for key in gui_touch_press: gui_touch_press[key].valid=false
		else:
			if event.canceled:
				if box_select_mode: _clear_box_select(); call_deferred("_update_hud")
				touch_gesture=true; touch_command=false; rally_building=-1
				if not build_mode.is_empty(): build_preview_held=false
			all_touch_ids.erase(event.index)
			call_deferred("_cleanup_touch_release",event.index,touch_press_epochs.get(event.index,0))
			call_deferred("_cleanup_button_touch",event.index,touch_press_epochs.get(event.index,0))
	if event is InputEventMouseButton and not event.pressed:
		if event.button_index==MOUSE_BUTTON_LEFT: call_deferred("_cleanup_mouse_release")
		if event.button_index==MOUSE_BUTTON_MIDDLE: middle_drag=false

	_track_action_scroll(event,viewport)

func _track_action_scroll(event,viewport):
	# Mouse emulation is disabled: route touch scrolling explicitly before GUI
	# button handling. A swipe must never also activate its starting button.
	if event is InputEventScreenTouch:
		if event.pressed:
			if all_touch_ids.size()!=1:
				action_touch_scroll.clear(); return
			var scroll_control=compact_menu.get_child(0) if compact_menu.visible else action_scroll
			var horizontal=not compact_menu.visible
			if is_instance_valid(scroll_control) and scroll_control.is_visible_in_tree() and scroll_control.get_global_rect().has_point(event.position) and not game_over:
				var bar=scroll_control.get_h_scroll_bar() if horizontal else scroll_control.get_v_scroll_bar()
				if bar.max_value>bar.page:
					action_touch_scroll[event.index]={"control":weakref(scroll_control),"horizontal":horizontal,"origin":event.position,"offset":scroll_control.scroll_horizontal if horizontal else scroll_control.scroll_vertical,"active":false}
		else:
			var scroll=action_touch_scroll.get(event.index,{})
			action_touch_scroll.erase(event.index)
			if not scroll.is_empty() and scroll.active:
				gui_touch_press.erase(event.index)
				viewport.set_input_as_handled()
	elif event is InputEventScreenDrag and action_touch_scroll.has(event.index):
		var scroll=action_touch_scroll[event.index]
		if all_touch_ids.size()!=1 or touch_gesture:
			action_touch_scroll.clear(); return
		var delta=event.position-scroll.origin
		if delta.length()>=14: scroll.active=true
		if scroll.active:
			gui_touch_press.erase(event.index)
			var control=scroll.control.get_ref()
			if is_instance_valid(control):
				if scroll.horizontal: control.scroll_horizontal=int(scroll.offset-delta.x)
				else: control.scroll_vertical=int(scroll.offset-delta.y)
			viewport.set_input_as_handled()

func _cleanup_touch_release(index,press_epoch):
	if touch_press_epochs.get(index,-1)!=press_epoch: return
	# A release consumed by HUD must not complete or retain a world rectangle.
	if touch_box_index==index:
		_clear_box_select(); _update_hud()
	touch_points.erase(index)
	if all_touch_ids.is_empty(): touch_gesture=false

func _cleanup_mouse_release():
	if box_cancel_press.get("source","")=="mouse" and not pressed_mouse_buttons.has(MOUSE_BUTTON_LEFT): box_cancel_press.clear()
	dragging=false; drag_active=false
	if is_instance_valid(drag_rect): drag_rect.hide()

func _unhandled_input(event):
	# Only a genuinely world-routed press releases lingering HUD focus. UI
	# buttons and dismissal shields consume their own presses before this.
	if (event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_RIGHT,MOUSE_BUTTON_MIDDLE]) or (event is InputEventScreenTouch and event.pressed):
		_release_world_camera_focus()
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode==KEY_ESCAPE:
			if not build_mode.is_empty() or touch_command or box_select_mode: _cancel_mode()
			else: _toggle_pause()
		if event.physical_keycode==KEY_F12: _capture_screenshot()
		if event.physical_keycode==KEY_P: _toggle_pause()
		if event.physical_keycode==KEY_SPACE: _home()
		if event.physical_keycode==KEY_X: _submit_selected_stance("stop")
		if event.physical_keycode>=KEY_1 and event.physical_keycode<=KEY_9:
			var key=event.physical_keycode-KEY_1
			if event.ctrl_pressed: groups[key]=selected.duplicate()
			elif groups.has(key):
				if dragging and build_mode.is_empty() and not box_select_mode and not touch_command and rally_building<0:
					if pressed_mouse_buttons.has(MOUSE_BUTTON_LEFT):
						canceled_mouse_buttons[MOUSE_BUTTON_LEFT]=true
						pressed_mouse_buttons.erase(MOUSE_BUTTON_LEFT)
					_cleanup_mouse_release()
				_select(groups[key])
	if event is InputEventMouseButton:
		if event.button_index==MOUSE_BUTTON_WHEEL_UP and event.pressed: camera_zoom=maxf(15,camera_zoom-2)
		elif event.button_index==MOUSE_BUTTON_WHEEL_DOWN and event.pressed: camera_zoom=minf(46,camera_zoom+2)
		elif event.button_index==MOUSE_BUTTON_MIDDLE: middle_drag=event.pressed
		elif event.button_index==MOUSE_BUTTON_RIGHT and event.pressed:
			if not build_mode.is_empty() or box_select_mode: _cancel_mode()
			elif not paused and not game_over: _send_world_order(event.position)
		elif event.button_index==MOUSE_BUTTON_LEFT:
			if event.pressed: drag_start=event.position; dragging=true; drag_active=false
			elif dragging:
				dragging=false; drag_rect.hide()
				if drag_active:
					var rect=Rect2(drag_start,event.position-drag_start).abs()
					_select(_box_selection_ids(rect))
				else: _tap(event.position,false)
	if event is InputEventMouseMotion:
		pointer_screen=event.position
		if build_mode.is_empty() or not build_preview_held:
			pointer_world=_point(_cell(_world_at(event.position)))
		if middle_drag: _pan_camera(-event.relative)
		if dragging and build_mode.is_empty() and event.position.distance_to(drag_start)>8:
			drag_active=true; var rect=Rect2(drag_start,event.position-drag_start).abs()
			drag_rect.position=rect.position; drag_rect.size=rect.size; drag_rect.show()
	if event is InputEventScreenTouch:
		if event.pressed:
			touch_points[event.index]=event.position
			if touch_points.size()==1:
				touch_origin=event.position; touch_gesture=all_touch_ids.size()>1
				if box_select_mode and not touch_gesture and not game_over:
					touch_box_index=event.index; touch_box_origin=event.position; touch_box_active=false
			if touch_points.size()>=2:
				touch_gesture=true; touch_command=false; rally_building=-1
				var values=touch_points.values(); touch_previous_center=(values[0]+values[1])*0.5; touch_previous_distance=values[0].distance_to(values[1])
		else:
			if box_select_mode and touch_box_index==event.index:
				var complete=touch_box_active and not touch_gesture and not event.canceled and touch_points.has(event.index) and not game_over
				touch_box_index=-1; touch_box_active=false; drag_rect.hide(); touch_points.erase(event.index)
				if complete: _select(_box_selection_ids(Rect2(touch_box_origin,event.position-touch_box_origin).abs()))
				return
			var should_tap=touch_points.has(event.index) and touch_points.size()==1 and not touch_gesture and event.position.distance_to(touch_origin)<14
			touch_points.erase(event.index)
			if should_tap: _tap(event.position,true)
			if touch_points.is_empty(): touch_gesture=false
	if event is InputEventScreenDrag:
		if not touch_points.has(event.index): return
		touch_points[event.index]=event.position
		if touch_points.size()>=2:
			var values=touch_points.values(); var center=(values[0]+values[1])*0.5; var distance=values[0].distance_to(values[1])
			_pan_camera(touch_previous_center-center)
			if touch_previous_distance>0: camera_zoom=clampf(camera_zoom*touch_previous_distance/maxf(1,distance),15,46)
			touch_previous_center=center; touch_previous_distance=distance
		elif box_select_mode and touch_box_index==event.index:
			if event.position.distance_to(touch_box_origin)>=14: touch_box_active=true
			if touch_box_active:
				var rect=Rect2(touch_box_origin,event.position-touch_box_origin).abs()
				drag_rect.position=rect.position; drag_rect.size=rect.size; drag_rect.show()
		# A camera gesture keeps ownership until every finger is released.
		elif not build_mode.is_empty() and not touch_gesture:
			pointer_world=_point(_cell(_world_at(event.position))); build_preview_held=true
		elif event.position.distance_to(touch_origin)>14:
			touch_gesture=true; touch_command=false; rally_building=-1; _pan_camera(-event.relative)

func _start_build(kind):
	if paused or game_over or _selected_builder()<0: return
	_cancel_pointer_streams()
	_clear_box_select()
	build_mode=kind; touch_command=false; rally_building=-1; build_preview_held=false
	var builder=faction_views[0].get_record(_selected_builder())
	pointer_world=_point(_cell(builder.pos+Vector3(3,0,0)))
	# Offer a visible, currently legal public plot instead of an invariably
	# occupied worker-adjacent default. This is guidance only: held remains
	# false, and normal tap/Confirm/authority checks are still mandatory.
	var nearest=INF
	for plot in MapRoutes.build_plots(0,Rules.FOOTPRINT[kind]):
		if not _box_point_in_world(camera.unproject_position(plot)): continue
		if not _placement_reason(kind,plot,0,builder.id).is_empty(): continue
		var distance=builder.pos.distance_squared_to(plot)
		if distance<nearest: nearest=distance; pointer_world=plot
	if is_instance_valid(ghost): ghost.queue_free()
	ghost=Node3D.new(); add_child(ghost)
	var box=BoxMesh.new(); var width=Rules.FOOTPRINT.get(kind,3); box.size=Vector3(width,0.12,width)
	_mesh(ghost,box,Vector3(0,0.15,0),Color("a4d899"))
	_message("可在任何目前可見的空地建造；避開樹木、漿果、建築和單位，留有施工通道。",6,true)
	action_key=""; _update_hud()

func _update_ghost():
	if not is_instance_valid(ghost): return
	ghost.position=_snap_build_position(build_mode,pointer_world)
	var reason=_placement_reason(build_mode,pointer_world,0,_selected_builder())
	placement_ok=reason.is_empty()
	ghost.get_child(0).material_override=_material(Color("92d389") if placement_ok else Color("d97c65"))
	if short_ui: _message(("位置已選，按確認建造。" if build_preview_held else "點選空地作預覽，再按確認建造。") if placement_ok else "不可建造："+reason,1,true)

func _confirm_build():
	if build_mode.is_empty() or paused or not build_preview_held or touch_gesture: return
	var reason=_placement_reason(build_mode,pointer_world,0,_selected_builder())
	if not reason.is_empty(): _message(reason); return
	_submit("build",{"kind":build_mode,"position":pointer_world,"builder":_selected_builder()})
	_cancel_mode()

func _cancel_mode():
	# Retire only mode-owned instructions, never later order/error feedback.
	if toast_build_guidance:
		toast_build_guidance=false; toast_time=0.0
		if is_instance_valid(toast_label): toast_label.text=""; toast_label.visible=false
	build_mode=""; build_preview_held=false; touch_command=false; rally_building=-1
	_cancel_pointer_streams()
	if is_instance_valid(ghost): ghost.queue_free(); ghost=null
	action_key=""; _update_hud()

# Read-only public Web QA projection. Private world/attack diagnostics stay separate.
func _on_web_touch_cancel(_args):
	# Godot 4.6.3 Web maps touchcancel to ordinary touchend. Capture before
	# the engine's canvas listener so the subsequent release cannot act.
	_cancel_mode()

func _install_web_bridge():
	if not OS.has_feature("web"): return
	web_touch_cancel_callback=JavaScriptBridge.create_callback(_on_web_touch_cancel)
	JavaScriptBridge.get_interface("window").valleyTouchCancel=web_touch_cancel_callback
	JavaScriptBridge.eval("if(window.valleyTouchCancelHandler){window.removeEventListener('touchcancel',window.valleyTouchCancelHandler,true);}window.valleyTouchCancelHandler=function(){if(window.valleyTouchCancel){window.valleyTouchCancel();}};window.addEventListener('touchcancel',window.valleyTouchCancelHandler,true);")
	qa_mode=JavaScriptBridge.eval("new URLSearchParams(location.search).has('qa')")
	if qa_mode:
		qa_callback=JavaScriptBridge.create_callback(_web_snapshot)
		JavaScriptBridge.get_interface("window").valleySnapshot=qa_callback

func _web_snapshot(_args):
	var state=_snapshot()
	state.audio=audio_cues.qa_status()
	JavaScriptBridge.eval("window.valleyState="+JSON.stringify(state)+";")

# Local faction 0 only: accepted commands waiting for execution, including AI/player
# callers on that faction. Enemy commands and private attack-ledger fields are absent.
func _snapshot():
	var own_pending_commands=0
	for command in commands:
		if command.team==0: own_pending_commands+=1
	return {"build":Rules.BUILD_ID,"version":Rules.VERSION,"tick":tick_count,"time":game_time,"paused":paused,"game_over":game_over,"outcome":outcome,"selected":selected,"food":stocks[0].food,"wood":stocks[0].wood,"bank_milli":economy.bank_milli(0),"economy_scale":Economy.SCALE,"population":_population(0),"capacity":_capacity(0),"delivered":delivered_total[0],"built":completed_builds[0],"trained":trained_total[0],"own_pending_commands":own_pending_commands,"touch_mode":touch_command,"build_mode":build_mode}

# --- Deterministic headless rule/regression suite ---
var test_results=[]
func _test_check(name,passed,detail=""):
	test_results.append({"name":name,"status":"PASS" if passed else "FAIL","detail":detail})
	print(("PASS " if passed else "FAIL ")+name+" "+detail)

func _test_reset(initial_stocks_units=INITIAL_STOCKS):
	demo_tutorial.reset()
	building_damage_presenter.clear()
	_clear_attack_effects()
	character_presenter.clear(); unit_action_cues=[{},{}]; pending_visual_deaths.clear()
	for proxy in presentation_nodes.values(): proxy.node.queue_free()
	presentation_nodes.clear()
	audio_cues.reset()
	faction_views=[FactionView.new(),FactionView.new()]
	for ent in entities:
		ent.node.queue_free()
	path_requests.clear(); path_budget_tick=-1; last_path_queries=0; last_path_expansions=0; path_expansion_budget=4096
	traffic_priority_order.clear(); traffic_tick_segments.clear()
	entities.clear(); selected.clear(); commands.clear(); next_id=0; tick_count=0; game_time=0
	attack_ledger=AttackLedger.new(); pending_damage.clear()
	command_sequence=0; processed_command_ids.clear(); next_queue_id=0; ready_cursor=-1; spawn_commit_order.clear(); game_over=false; victory=false; outcome=""; paused=false
	recovery_ticks=[0,0]; no_progress_ticks=0; progress_serial=0; inactivity_paused=false; future_recovery_events.clear(); end_reason=""
	_surrender_intent.clear()
	ai_opening_assigned=false; ai_last_raid_tick=-AI_RAID_INTERVAL_TICKS; ai_raids=0
	ai_raid_members.clear(); ai_raid_departure_count=0; ai_raid_keep.clear(); ai_raid_retreating=false
	ai_scout_attempts.clear(); ai_claimed_workers.clear(); ai_build_submitted=false; ai_budget.clear(); ai_status.clear(); ai_site_recovery.clear(); owned_motion_witness_tick=-1
	application_focused=true; application_suspended=false; background_paused=false; discard_return_delta=false; tick_accumulator=0.0
	for team in 2:
		visible_cells[team].fill(0); explored_cells[team].fill(0)
	work_memory=[WorkMemory.new(),WorkMemory.new()]
	_reset_economy(initial_stocks_units)
	completed_builds=[0,0]; trained_total=[0,0]
	ai_enabled=false; end_panel.hide(); rng.seed=824613; _seed_match(); _navigation_rebuild(); _update_vision()
	audio_cues.observe(faction_views[0].records(),tick_count,Time.get_ticks_msec())

func _test_advance(seconds):
	for i in int(seconds/Rules.TICK):
		if game_over: break
		_tick(Rules.TICK)

func _run_smoke_test():
	print("VALLEY_CROWN_RULE_TEST "+Rules.VERSION)
	_test_reset()
	_test_check("initial fair state",_population(0)==6 and _population(1)==6 and _capacity(0)==10 and stocks[0]==stocks[1])
	_test_reset([{"food":1000,"wood":200},{"food":150,"wood":200}])
	var castle=_first(0,"town_center")
	for i in 5: _submit("train",{"building":castle.id,"kind":"villager"})
	_tick(Rules.TICK)
	_test_check("population reserved on enqueue",castle.queue.size()==4 and _population(0)==10 and stocks[0].food==800)
	_cancel_train(castle.id,0)
	_test_check("unstarted queue refund once",castle.queue.size()==3 and stocks[0].food==850)
	while castle.queue.size()>1: _cancel_train(castle.id,0)
	var before=stocks[0].food
	_cancel_train(castle.id,0); _cancel_train(castle.id,0)
	_test_check("started refund 75 and no duplicate",stocks[0].food==before+37 and castle.queue.is_empty())
	_enqueue_train(castle.id,"villager",0); _test_advance(16)
	_test_check("production creates unit and releases reservation",_count(0,"villager")==6 and _population(0)==7 and castle.queue.is_empty(),"villagers="+str(_count(0,"villager"))+" queue="+str(castle.queue.size()))
	_test_reset([{"food":1000,"wood":200},{"food":150,"wood":200}])
	castle=_first(0,"town_center")
	var extra_house=_spawn("house",0,Vector3(-7.5,0,15.5)+MapRoutes.home_offset(0))
	for i in 5: _enqueue_train(castle.id,"villager",0)
	castle.queue[0].remaining_ticks=0; _kill(extra_house)
	_update_production(castle,Rules.TICK)
	_test_check("ready order spawns under live cap after house loss",_population(0,false)==7 and castle.queue.size()==4 and _population(0)==11 and _capacity(0)==10)
	var remaining=castle.queue[0].remaining_ticks
	_update_production(castle,2.0)
	_test_check("unready order pauses when committed population exceeds cap",castle.queue[0].remaining_ticks==remaining)
	_test_reset(); castle=_first(0,"town_center")
	_submit("train",{"building":castle.id,"kind":"villager","command_id":"duplicate-training"})
	_submit("train",{"building":castle.id,"kind":"villager","command_id":"duplicate-training"})
	_tick(Rules.TICK)
	_test_check("duplicate command ID commits only once",castle.queue.size()==1 and stocks[0].food==100)
	var before_invalid=stocks[0].duplicate(true)
	_submit("train",{"building":_first(1,"town_center").id,"kind":"villager"})
	_tick(Rules.TICK)
	_test_check("foreign building command rejected without cost",stocks[0]==before_invalid and _first(1,"town_center").queue.is_empty())
	_test_reset()
	var worker=_first(0,"villager")
	var berry=_nearest_resource(worker.pos,"food",0)
	_order(worker,"gather",berry.id)
	_test_advance(65)
	_test_check("gather carry deliver loop",delivered_total[0]>=20 and stocks[0].food>=170,"delivered="+str(delivered_total[0]))
	_test_reset(); worker=_first(0,"villager")
	berry=_nearest_resource(worker.pos,"food",0)
	worker.pos=_free_adjacent(berry,worker.pos); _order(worker,"gather",berry.id)
	_test_advance(5)
	var old_cargo=worker.carry
	var tree=_nearest_resource(worker.pos,"wood",0)
	_order(worker,"gather",tree.id)
	_test_check("resource switch first delivers original cargo",worker.state=="deliver" and worker.carry_type=="food" and worker.resource_target==tree.id)
	_test_advance(20)
	_test_check("resource switch cannot transmute carried food into wood",is_equal_approx(stocks[0].food,150+old_cargo) and old_cargo>0)
	_test_reset(); worker=_first(0,"villager")
	var wood_before=stocks[0].wood
	var overlap=_place_building("house",_first(0,"town_center").pos,worker.id,0)
	_test_check("invalid footprint does not debit",overlap.is_empty() and stocks[0].wood==wood_before)
	var location=Vector3(-7.5,0,15.5)+MapRoutes.home_offset(0)
	var house=_place_building("house",location,worker.id,0)
	_test_check("build atomically reserves and charges",not house.is_empty() and stocks[0].wood==150 and navigation.is_point_solid(_cell(location)))
	var duplicate=_place_building("house",location,worker.id,0)
	_test_check("duplicate site rejected",duplicate.is_empty() and stocks[0].wood==150)
	if not house.is_empty():
		_test_advance(32)
		_test_check("builder completes house",house.built and _capacity(0)==15,"progress="+str(house.progress))
	var blocked=navigation.get_id_path(_cell(Vector3(-15.5,0,10.5)+MapRoutes.home_offset(0)),_cell(Vector3(-5.5,0,10.5)+MapRoutes.home_offset(0)))
	var path_ok=blocked.size()>0
	for i in blocked.size():
		if navigation.is_point_solid(blocked[i]): path_ok=false
		if i>0:
			var from=blocked[i-1]; var to=blocked[i]
			if from.x!=to.x and from.y!=to.y:
				if navigation.is_point_solid(Vector2i(from.x,to.y)) or navigation.is_point_solid(Vector2i(to.x,from.y)): path_ok=false
	_test_check("path avoids buildings and corner cuts",path_ok)
	_test_reset(); worker=_first(0,"villager")
	house=_place_building("house",location,worker.id,0)
	if not house.is_empty():
		_execute({"type":"cancel_build","team":0,"building":house.id})
		_execute({"type":"cancel_build","team":0,"building":house.id})
		_test_check("construction refund releases site once",stocks[0].wood==187 and not navigation.is_point_solid(_cell(location)))
	else: _test_check("construction refund releases site once",false,"fixture placement failed")
	_test_reset(); worker=_first(0,"villager")
	house=_place_building("house",location,worker.id,0)
	if not house.is_empty():
		_test_advance(15); var progress=house.progress; _kill(worker); _test_advance(10)
		_test_check("builder death preserves unfinished work",house.alive and not house.built and house.progress==progress)
		var replacement=_first(0,"villager"); _order(replacement,"build",house.id); _test_advance(35)
		_test_check("replacement resumes construction",house.built)
	else:
		_test_check("builder death preserves unfinished work",false,"fixture placement failed")
		_test_check("replacement resumes construction",false,"fixture placement failed")
	_test_reset()
	var scout=_first(0,"scout"); var enemy=_first(1,"scout")
	_test_check("enemy hidden initially",not _visible_to(enemy,0))
	var enemy_position=enemy.pos
	_execute({"type":"order","team":0,"ids":[scout.id],"target":enemy.id,"position":Vector3(0,0,0)})
	_test_check("cannot target unseen enemy",scout.state=="idle" and scout.target==-1 and scout.dest.distance_to(enemy_position)>5)
	# A visible unit is commanded to attack, then escapes vision. Chase only the old point.
	enemy.pos=scout.pos+Vector3(2,0,0); _update_vision(); _order(scout,"attack",enemy.id)
	var remembered=scout.last_known
	enemy.pos=Vector3(18,0,-18); _update_vision(); _tick(Rules.TICK)
	_test_check("fog pursuit freezes last known position",scout.last_known==remembered and scout.dest.distance_to(enemy.pos)>10)
	_test_reset()
	# Direct simultaneous release through the real combat loop, not a forced outcome flag.
	var blue_castle=_first(0,"town_center"); var red_castle=_first(1,"town_center")
	blue_castle.hp=1; red_castle.hp=1
	var blue=_spawn("spearman",0,red_castle.pos+Vector3(3,0,0))
	var red=_spawn("spearman",1,blue_castle.pos+Vector3(3,0,0))
	_update_vision(); _order(blue,"attack",red_castle.id); _order(red,"attack",blue_castle.id)
	_tick(Rules.TICK)
	_test_check("same tick castle deaths draw",game_over and outcome=="draw",outcome)
	_test_reset()
	red_castle=_first(1,"town_center"); red_castle.hp=20
	blue=_spawn("spearman",0,red_castle.pos+Vector3(3,0,0)); _update_vision(); _order(blue,"attack",red_castle.id)
	_test_advance(10)
	_test_check("combat victory",game_over and outcome=="victory",outcome)
	_test_reset(); blue_castle=_first(0,"town_center"); blue_castle.hp=20
	red=_spawn("spearman",1,blue_castle.pos+Vector3(3,0,0)); _update_vision(); _order(red,"attack",blue_castle.id)
	_test_advance(10)
	_test_check("combat defeat",game_over and outcome=="defeat",outcome)
	_test_reset(); tick_count=roundi(Rules.TIME_LIMIT/Rules.TICK)-1; _tick(Rules.TICK)
	_test_check("explicit time limit draws",outcome=="draw")
	_test_reset()
	castle=_first(0,"town_center"); worker=_first(0,"villager")
	castle.hp=castle.max_hp-30; castle.last_damage_tick=tick_count
	worker.pos=_free_adjacent(castle,worker.pos); _order(worker,"repair",castle.id)
	var starting_wood=stocks[0].wood
	_test_advance(4.9)
	_test_check("repair blocked for five seconds after damage",castle.hp==castle.max_hp-30 and stocks[0].wood==starting_wood and worker.state!="repair")
	_test_advance(0.1)
	_order(worker,"repair",castle.id) # Fresh command after the rejected attempt.
	_test_advance(6.2)
	_test_check("repair costs one wood per five HP and caps",castle.hp==castle.max_hp and stocks[0].wood==starting_wood-6)
	_test_reset()
	castle=_first(0,"town_center")
	var approaches_ok=true
	for offset in [Vector3(8,0,0),Vector3(-8,0,0),Vector3(0,0,8),Vector3(0,0,-8)]:
		var adjacent=_free_adjacent(castle,castle.pos+offset)
		if _attack_distance(adjacent,castle)>Rules.RANGE.spearman: approaches_ok=false
	_test_check("melee reaches castle from each free edge",approaches_ok)
	_test_reset(); ai_enabled=true
	_test_advance(360)
	_test_check("AI economy has actual deliveries",delivered_total[1]>100,"delivered="+str(delivered_total[1]))
	_test_check("AI constructs and trains without free income",completed_builds[1]>=2 and trained_total[1]>=3,"built="+str(completed_builds[1])+" trained="+str(trained_total[1]))
	var crossed=false
	for ent in entities:
		if ent.alive and ent.team==1 and ent.category=="unit" and ent.kind!="villager" and ent.pos.x<0: crossed=true
	_test_check("AI reaches player half of map",crossed)
	_test_check("economy remains nonnegative",stocks[0].food>=0 and stocks[0].wood>=0 and stocks[1].food>=0 and stocks[1].wood>=0)
	_test_reset()
	_test_check("session reset clears outcome and progress",not game_over and game_time==0 and selected.is_empty() and commands.is_empty() and _population(0)==6 and delivered_total[0]==0)
	var failed=0
	for result in test_results:
		if result.status=="FAIL": failed+=1
	var report={"build":Rules.BUILD_ID,"version":Rules.VERSION,"seed":824613,"tick_hz":20,"results":test_results,"passed":test_results.size()-failed,"failed":failed,"not_run":["browser gameplay","real iPhone Safari","real Android Chrome","audio","public deployment"],"snapshot":_snapshot()}
	var file=FileAccess.open("res://reports/rule-tests.json",FileAccess.WRITE)
	if file: file.store_string(JSON.stringify(report,"  "))
	print("RESULT: %d passed, %d failed" % [test_results.size()-failed,failed])
	get_tree().quit(1 if failed else 0)

func _capture_screenshot():
	await RenderingServer.frame_post_draw
	var path="res://screenshots/gameplay-"+str(Time.get_unix_time_from_system()).replace(".","-")+".png"
	var error=get_viewport().get_texture().get_image().save_png(path)
	var meta=FileAccess.open(path+".json",FileAccess.WRITE)
	if meta: meta.store_string(JSON.stringify({"build":Rules.BUILD_ID,"version":Rules.VERSION,"source_sha256":FileAccess.get_sha256("res://scripts/game.gd"),"build_manifest_sha256":FileAccess.get_sha256("res://reports/build-manifest.json"),"capture_kind":"genuine_native_gameplay_viewport","capture_error":error,"viewport":str(get_viewport().get_visible_rect().size),"top_size":str(hud_top.size),"bottom_size":str(hud_bottom.size),"snapshot":_snapshot()},"  "))
	print("GAMEPLAY_SCREENSHOT "+path+" result="+str(error))

func _confirm_demolish(building_id):
	if paused or game_over:
		_reject_command(0,"目前已暫停，請按繼續。" if paused else "戰役已結束。")
		return
	var target=_get_entity(building_id)
	if not _can_demolish(target,0): return
	# Repeated activation must not stack confirmations or capture another target.
	for child in ui.get_children():
		if child is Window and child.visible: return
	_quarantine_camera_keys()
	_cancel_pointer_streams()
	var dialog=ConfirmationDialog.new(); ui.add_child(dialog)
	var bridge=ModalInputBridge.new(); bridge.game=self; dialog.add_child(bridge)
	dialog.focus_exited.connect(_cancel_pointer_streams)
	dialog.title="拆除"+Rules.NAMES.get(target.kind,target.kind)
	dialog.dialog_text="確定拆除這座建築？建築及訓練隊列不退資源，人口容量可能減少。"
	dialog.ok_button_text="確定拆除"; dialog.cancel_button_text="保留建築"
	dialog.add_theme_constant_override("buttons_min_width",130); dialog.add_theme_constant_override("buttons_min_height",46)
	for button in [dialog.get_ok_button(),dialog.get_cancel_button()]:
		button.gui_input.connect(func(event): _button_touch_input(button,event))
	dialog.set_meta("submitted",false)
	dialog.confirmed.connect(func():
		if dialog.get_meta("submitted"): return
		dialog.set_meta("submitted",true)
		# The dialog is bound to this entity instance, not an ID recycled by reset.
		if is_same(_get_entity(building_id),target): _submit("demolish",{"building":building_id})
	)
	dialog.confirmed.connect(dialog.queue_free); dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered(Vector2i(mini(440,int(get_viewport().get_visible_rect().size.x)-24),180))

func _confirm_surrender():
	if paused or game_over:
		_reject_command(0,"目前已暫停，請按繼續。" if paused else "戰役已結束。")
		return
	_quarantine_camera_keys()
	_cancel_pointer_streams()
	var dialog=ConfirmationDialog.new(); ui.add_child(dialog)
	var bridge=ModalInputBridge.new(); bridge.game=self; dialog.add_child(bridge)
	dialog.focus_exited.connect(_cancel_pointer_streams)
	dialog.title="退出這場戰役"; dialog.dialog_text="確定投降？這場會判為落敗，可以再開一局。"
	dialog.ok_button_text="確定投降"; dialog.cancel_button_text="繼續戰役"
	dialog.add_theme_constant_override("buttons_min_width",130); dialog.add_theme_constant_override("buttons_min_height",46)
	for button in [dialog.get_ok_button(),dialog.get_cancel_button()]:
		button.gui_input.connect(func(event): _button_touch_input(button,event))
	dialog.confirmed.connect(func(): _submit("surrender"))
	dialog.confirmed.connect(dialog.queue_free); dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered(Vector2i(mini(400,int(get_viewport().get_visible_rect().size.x)-24),160))

func _compact_panel_style():
	var style=_style(Color("1d241ee8"))
	style.content_margin_left=10; style.content_margin_right=10; style.content_margin_top=4; style.content_margin_bottom=4
	return style


func _toggle_compact_menu():
	compact_menu.visible=not compact_menu.visible
	if compact_menu.visible:
		_quarantine_camera_keys()
		if box_select_mode: _cancel_mode()
	compact_menu_dismiss.visible=compact_menu.visible
	compact_menu_button.text="收起" if compact_menu.visible else "選單"
	_layout_ui()


func _compact_menu_action(callback:Callable):
	compact_menu.hide(); compact_menu_dismiss.hide(); compact_menu_button.text="選單"; callback.call()


func _dismiss_compact_menu_input(event:InputEvent):
	# Keep the shield through release, so dismissal never becomes a world tap/order.
	compact_menu_dismiss.accept_event()
	if (event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and not event.pressed) or (event is InputEventScreenTouch and not event.pressed):
		if compact_menu.visible: _toggle_compact_menu.call_deferred()

func _cleanup_button_touch(index,press_epoch):
	if touch_press_epochs.get(index,-1)!=press_epoch: return
	if box_cancel_press.get("source","")=="touch" and box_cancel_press.index==index and box_cancel_press.epoch==press_epoch: box_cancel_press.clear()
	gui_touch_press.erase(index)
	touch_press_epochs.erase(index)

func _button_touch_input(button:Button,event:InputEvent):
	# The project disables mouse-from-touch to avoid duplicate world commands.
	# Give ordinary GUI buttons an explicit, single-pointer release path instead.
	if Input.emulate_mouse_from_touch or ProjectSettings.get_setting("input_devices/pointing/emulate_mouse_from_touch",true): return
	if event is InputEventScreenTouch:
		button.accept_event()
		if event.pressed:
			if button.disabled or all_touch_ids.size()!=1 or touch_gesture: return
			gui_touch_press[event.index]={"button":weakref(button),"origin":event.position,"valid":true}
		else:
			var press=gui_touch_press.get(event.index,{})
			gui_touch_press.erase(event.index)
			if press.is_empty() or press.button.get_ref()!=button: return
			if press.valid and not event.canceled and not button.disabled and not touch_gesture and all_touch_ids.is_empty() and event.position.distance_to(press.origin)<14 and Rect2(Vector2.ZERO,button.size).has_point(event.position):
				button.grab_focus(); button.pressed.emit()
	elif event is InputEventScreenDrag:
		button.accept_event()
		if gui_touch_press.has(event.index):
			var press=gui_touch_press[event.index]
			if press.button.get_ref()==button and (event.position.distance_to(press.origin)>=14 or touch_gesture or all_touch_ids.size()!=1): press.valid=false

# Tutorial controls only their own presentation state. Existing input routing is reused.
func _create_tutorial_ui():
	tutorial_panel=PanelContainer.new(); tutorial_panel.name="DemoTutorial"
	tutorial_panel.mouse_filter=Control.MOUSE_FILTER_STOP
	tutorial_panel.mouse_force_pass_scroll_events=false
	var style=_style(Color("20261f"),GOLD)
	style.content_margin_left=8; style.content_margin_right=8
	style.content_margin_top=4; style.content_margin_bottom=4
	tutorial_panel.add_theme_stylebox_override("panel",style)
	ui.add_child(tutorial_panel)
	var row=HBoxContainer.new(); row.add_theme_constant_override("separation",8)
	row.mouse_filter=Control.MOUSE_FILTER_PASS; tutorial_panel.add_child(row)
	tutorial_label=_label("",14); tutorial_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	tutorial_label.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	tutorial_label.mouse_filter=Control.MOUSE_FILTER_IGNORE; row.add_child(tutorial_label)
	tutorial_skip=_button("跳過",_skip_tutorial,56); tutorial_skip.name="SkipTutorial"
	row.add_child(tutorial_skip)
	_refresh_tutorial()
	_layout_tutorial()

func _skip_tutorial():
	demo_tutorial.skip()
	_refresh_tutorial()

func _refresh_tutorial():
	if not is_instance_valid(tutorial_panel): return
	tutorial_panel.visible=not demo_tutorial.skipped and not game_over and not compact_menu.visible
	tutorial_label.text=demo_tutorial.text(paused)
	tutorial_skip.text="收起" if demo_tutorial.step()==6 else "跳過"

func _layout_tutorial():
	if not is_instance_valid(tutorial_panel): return
	_refresh_tutorial()
	var viewport_size=get_viewport().get_visible_rect().size
	var width=minf(560,viewport_size.x-12)
	tutorial_panel.position=Vector2(viewport_size.x-width-6,hud_top.position.y+hud_top.size.y+4)
	tutorial_panel.size=Vector2(width,0)
	# Container wrapping settles on the following layout pass; no world reads.
	if tutorial_panel.visible:
		toast_label.position.y=tutorial_panel.position.y+tutorial_panel.size.y+4

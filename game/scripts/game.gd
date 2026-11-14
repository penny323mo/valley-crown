extends Node3D
signal main_menu_requested
signal restart_requested
## Original RTS vertical slice. All game state is deterministic and available to smoke tests.
const ArmyFormation = preload("res://scripts/army_formation.gd")
const WorkerIdleStatus = preload("res://scripts/worker_idle_status.gd")
const IdleWorkerSelection = preload("res://scripts/idle_worker_selection.gd")
const BattleAlerts = preload("res://scripts/battle_alerts.gd")
const MatchReport = preload("res://scripts/match_report.gd")
const SquadSelection = preload("res://scripts/squad_selection.gd")
const RaidTactics = preload("res://scripts/raid_tactics.gd")
const ScoutFrontier=preload("res://scripts/scout_frontier.gd")
const HomeDefense = preload("res://scripts/home_defense.gd")
const ArmyComposition = preload("res://scripts/army_composition.gd")
const ConstructionStatus = preload("res://scripts/construction_status.gd")
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
const INITIAL_STOCKS = [{"food":150,"wood":200,"stone":100,"iron":0},{"food":150,"wood":200,"stone":100,"iron":0}]
const ResourceVisuals = preload("res://scripts/resource_visuals.gd")
const ProgressionVisuals = preload("res://scripts/progression_visuals.gd")
const AdvancedBuildingVisuals = preload("res://scripts/advanced_building_visuals.gd")
var age_completed_tick=[-1,-1]
var military_tech_completed=[{},{}]
const RestRecovery=preload("res://scripts/rest_recovery.gd")
const WorkerSafety=preload("res://scripts/worker_safety.gd")
var worker_safety_enabled=true
var worker_evacuations={}
var worker_manual_until={}
var worker_safety_hits={}
var large_route_cache=[{},{}]
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
var squad_selection=SquadSelection.new()
var squad_buttons=[]
var idle_worker_cursor=-1
var idle_worker_button: Button
var next_id = 0
var economy = Economy.new()
var economy_sequence = 0
# Compatibility projections only. Every authoritative economic read uses economy.
var stocks:
	get:
		var display=[]
		for team in 2:
			var bank=economy.bank_milli(team)
			display.append({"food":bank.get("food",0)/1000.0,"wood":bank.get("wood",0)/1000.0,"stone":bank.get("stone",0)/1000.0,"iron":bank.get("iron",0)/1000.0})
		return display
var camera: Camera3D
var camera_ground: MeshInstance3D
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
var unit_command_kind="order"
var advance_formation=""
var rally_building=-1
var rally_mode="move"
# UX01 selection intent only; no simulation command or world-state mutation.
var box_select_mode=false
var touch_box_index=-1
var touch_box_origin=Vector2.ZERO
var touch_box_active=false
const TOUCH_HOLD_MSEC=350
var touch_hold={}
var touch_box_automatic=false
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
var queue_actions=[]
var repeat_train_button: Button
var repeat_train_cursor=[0,0]
var actions: HBoxContainer
var minimap: Control
var drag_rect: ReferenceRect
var end_panel: Panel
var end_scroll: ScrollContainer
var end_report_label: Label
var end_tabs: HBoxContainer
var end_actions: HBoxContainer
var end_report_page="overview"
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
var touch_world_epochs={} # World-owned press lifetime, distinct from GUI reuse.
var touch_camera_pair=[] # Two (index, epoch) identities; positions stay in touch_points.
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
var stop_button: Button
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
var battle_alerts=BattleAlerts.new()
var match_report=MatchReport.new()
var last_match_report={}
var attack_alert_button: Button
var attack_ledger=AttackLedger.new()
var delivered_total:
	get:
		var display=[]
		for team in 2:
			var stats=economy.stats_view(team)
			var delivered=stats.get("delivered",{"food":0,"wood":0})
			display.append((delivered.food+delivered.wood+delivered.get("stone",0)+delivered.get("iron",0))/1000.0)
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


const SkirmishPolicy=preload("res://scripts/skirmish_policy.gd")
var skirmish_mode="standard"
const ControlPoint=preload("res://scripts/control_point.gd")
var victory_mode="conquest"
var control_point=ControlPoint.new()
var control_point_marker: Node3D
var control_point_flag: MeshInstance3D
var objective_button: Button
var ai_control_targets={}

func _ready():
	skirmish_mode=SkirmishPolicy.valid(skirmish_mode)
	victory_mode=valid_victory_mode(victory_mode)
	if victory_mode=="control": skirmish_mode="standard"
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
	camera_ground=MatureWorld.create_ground(ground,ground_trails)
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
	_create_control_point_marker()

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
	# Candidate mineral layout: antipodal cell-centered pairs, available in Age I.
	# Four near-base deposits and two forward deposits of each mineral per side.
	for team in 2:
		var sign_team=1.0 if team==0 else -1.0
		for kind in ["stone","iron"]:
			for point in Rules.MINERAL_POINTS[kind]: _spawn(kind,-1,Vector3(point[0],0,point[1])*sign_team)
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
	var category="unit" if kind in Rules.UNIT_KINDS else ("resource" if kind in Rules.RESOURCE_KINDS else "building")
	if category=="building": p=_snap_build_position(kind,p)
	var n=Node3D.new(); add_child(n); n.position=p
	var e={"path":PackedVector3Array(),"path_version":-1,"last_damage_tick":-1000,"mode":"DEFEND","anchor":p,"auto_target":false,"stuck":0.0,"last_known":p,"id":next_id,"kind":kind,"team":team,"pos":p,"node":n,"category":category,"alive":true,"hp":MAX_HP.get(kind,200) if complete else ceili(MAX_HP.get(kind,200)*0.1),"max_hp":MAX_HP.get(kind,200),"state":"idle","target":-1,"dest":p,"cooldown_ticks":0,"carry":0.0,"carry_type":"","resource_target":-1,"queue":[],"next_spawn_check_tick":0,"build_ticks":0,"construction_hcap":MAX_HP.get(kind,200) if complete else ceili(MAX_HP.get(kind,200)*0.1),"progress":1.0 if complete else 0.0,"built":complete,"ring":null,"body":null,"bar":null,"bar_fill":null,"anim":rng.randf()*TAU,"radius":Rules.UNIT_RADII.get(kind,Rules.UNIT_RADIUS)}
	next_id+=1; entities.append(e)
	e.death_observed_by=[false,false]
	e.cost_receipt_id=""; e.work_ticks=0; e.last_repair_tick=-1
	e.gather_type=""; e.farm_id=-1
	e.dropoff_failures={}; e.dropoff_failure_revision=work_memory[team].revision if team>=0 else -1
	if kind=="villager":
		var registered=economy.register_worker(e.id,team)
		assert(registered.ok)
	elif kind=="farm" and complete:
		var registered=economy.register_farm(e.id,team)
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
		elif kind in ["stone","iron","berry"]:
			ResourceVisuals.build(body,kind)
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
		e.radius=Rules.FOOTPRINT.get(kind,2)/2.0
		if not complete: ConstructionVisual.apply(body,kind,false,0.0)
	var ring_root=Node3D.new(); n.add_child(ring_root)
	var ring=TorusMesh.new(); ring.inner_radius=e.radius+0.16; ring.outer_radius=e.radius+0.23; ring.rings=32; ring.ring_segments=5
	_mesh(ring_root,ring,Vector3(0,0.09,0),GOLD if team!=1 else RED)
	ring_root.visible=false; e.ring=ring_root
	if category!="resource":
		var bar=Node3D.new(); n.add_child(bar); bar.position.y=1.95 if category=="unit" else AdvancedBuildingVisuals.health_bar_height(kind)
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
	if kind in AdvancedBuildingVisuals.KINDS:
		parent.add_child(AdvancedBuildingVisuals.instantiate_asset(kind,RED if team==1 else BLUE)); return
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
	for ent in entities:
		if ent.alive and ent.built and ent.kind=="tower": _update_tower(ent)
	# Settle issued attack IDs once, after all work, then resolve deaths together.
	pending_damage=attack_ledger.settle()
	# Every attack on this tick observes the same live set. Resolve deaths together.
	for id in pending_damage:
		var target=_get_entity(id)
		if not target.is_empty() and target.alive:
			target.hp-=pending_damage[id]; target.last_damage_tick=tick_count
			battle_alerts.record_hit(target,pending_damage[id],tick_count)
			match_report.record_settled_loss(target,pending_damage[id])
			if pending_damage[id]>0 and target.hp>0 and target.category=="unit": _note_unit_action(target,"hit")
			if pending_damage[id]>0: progress_serial+=1
	for ent in entities:
		if ent.alive and ((ent.category=="resource" and economy.node_view(ent.id).remaining_milli<=0) or (ent.category!="resource" and ent.hp<=0)): _kill(ent)
	_update_rest_recovery()
	if victory_mode=="control" and control_point.advance(entities,tick_count): progress_serial+=1
	_publish_faction_views()
	_update_worker_safety()
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
	_update_repeat_training()

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
			# Contextual farm work is explicit intent, never an implicit repair.
			var farm_gather=command.has("farm_gather")
			if farm_gather and (typeof(command.farm_gather)!=TYPE_BOOL or not command.farm_gather or target.is_empty() or not target.alive or target.team!=team or target.category!="building" or target.kind!="farm" or not target.built):
				return _reject_command(team,"目標已失效或不在視野內，請重新落指令。")
			var scout_policy=command.has("ai_scout_explore")
			if scout_policy and (typeof(command.ai_scout_explore)!=TYPE_BOOL or not command.ai_scout_explore or team!=1 or not target.is_empty() or typeof(command.get("ids",null))!=TYPE_ARRAY or command.ids.size()!=1 or typeof(command.ids[0])!=TYPE_INT):
				return _reject_command(team,"斥候探索指令已失效。")
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
				if farm_gather and ent.kind!="villager": continue
				var intent="gather" if farm_gather else _target_order_intent(ent,target,team)
				if intent=="repair" and not _repair_order_allowed(ent,target):
					_reject_command(team,"受傷後五秒內無法開始修理。")
					index+=1
					continue
				# Farm refusal must be atomic, before resetting a player route budget.
				if intent=="gather" and target.kind=="farm" and economy.farm_view(target.id).get("worker_id",-1) not in [-1,ent.id]:
					_reject_command(team,"這片農田已有村民耕作。")
					index+=1
					continue
				# The intent marker survives cache retirement. Missing/stale policy
				# provenance must reject, never fall through as an ordinary MOVE.
				var scout_move=ai_scout_moves.get(ent.id,{})
				var tracked_scout=scout_policy and team==1 and ent.kind=="scout" and target.is_empty() and command.get("sequence",-1)==scout_move.get("pending_sequence",-2) and command.get("position",Vector3.INF)==scout_move.get("requested_goal",Vector3.INF)
				if scout_policy and not tracked_scout:
					continue
				var recover_scout=tracked_scout and scout_move.get("recover_static",false)
				if recover_scout and not _ai_static_failed_scout(ent):
					ai_scout_moves.erase(ent.id)
					continue
				if scout_policy:
					# Same bounded known-clear destination resolver as ordinary MOVE,
					# not a path search. Refuse aliases of earlier explored goals
					# before retiring the actor's current task or retry budgets.
					var resolved_scout=_nearest_free(command.position,8,ent.team,ent,reserved_destinations,order_ids)
					var prior_goal=resolved_scout!=Vector3.INF and ai_scout_attempts.has(_cell_index(resolved_scout)) and _cell(resolved_scout)!=_cell(command.position)
					if resolved_scout==Vector3.INF or prior_goal or (recover_scout and resolved_scout==scout_move.goal):
						if recover_scout:
							for key in ["pending_sequence","requested_goal","recover_static"]: scout_move.erase(key)
							ai_scout_moves[ent.id]=scout_move
						else: ai_scout_moves.erase(ent.id)
						continue
				if team==0: _path_new_command(ent)
				elif intent=="attack": _retire_ai_attack_failure(ent,target)
				if intent!="move": _order(ent,intent,target.id)
				elif not target.is_empty(): _order_move(ent,command.position)
				else:
					_order_move(ent,command.position,reserved_destinations,order_ids)
					reserved_destinations[_cell(ent.dest)]=true
				if team==1 and ent.kind=="scout":
					ai_scout_moves.erase(ent.id)
					if tracked_scout and ent.state=="move" and (not recover_scout or ent.dest!=scout_move.get("goal",Vector3.INF)):
						if recover_scout:
							# New known goal, not a fresh player command. Preserve
							# rolling retry timestamps, counters and next-attempt gate.
							ent.path_status="IDLE"; ent.path_reason=""
						ai_scout_moves[ent.id]={"work_epoch":ent.work_epoch,"goal":ent.dest}
						ai_scout_attempts[_cell_index(ent.dest)]=true
				index+=1
			if index==0: return _reject_command(team,"請選取自己的存活單位。")
		"advance": _order_advance(command.get("ids",[]),command.get("position",Vector3.INF),team,command.get("formation",""))
		"patrol": _order_patrol(command.get("ids",[]),command.get("position",Vector3.INF),team)
		"stop":
			var applied=false
			for id in command.ids:
				var ent=_get_entity(id)
				if not ent.is_empty() and ent.alive and ent.team==team and ent.category=="unit":
					if team==0: _path_new_command(ent)
					_set_stance(ent,"STOP")
					if team==1 and ent.kind=="scout": ai_scout_moves.erase(ent.id)
					applied=true
			if not applied: return _reject_command(team,"請選取自己的存活單位。")
		"defend":
			var applied=false
			for id in command.ids:
				var ent=_get_entity(id)
				if not ent.is_empty() and ent.alive and ent.team==team and ent.category=="unit":
					if team==0: _path_new_command(ent)
					_set_stance(ent,"DEFEND")
					if team==1 and ent.kind=="scout": ai_scout_moves.erase(ent.id)
					applied=true
			if not applied: return _reject_command(team,"請選取自己的存活單位。")
		"rally": _set_ground_rally(command.get("building",-1),command.get("position",Vector3.INF),team,command.get("clear",false),command.get("target",-1),command.get("mode","move"))
		"repeat_train": _set_repeat_training(command.get("building",-1),command.get("kind",null),team)
		"train":
			if not command.has("repeat_generation") or _repeat_train_current(command): _enqueue_train(command.building,command.kind,team)
		"research": _enqueue_research(command.get("building",-1),team)
		"military_research": _enqueue_military_research(command.get("building",-1),command.get("kind",""),team)
		"cancel_train": _cancel_train(command.building,team)
		"cancel_queue_item": _cancel_queue_item(command.get("building",-1),command.get("queue_id",-1),command.get("expected_refund",null),team)
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

func _retire_ai_attack_failure(ent,target):
	# A newly accepted AI military target must not inherit another target's
	# completed static frontier. This is not a fresh player-command budget.
	if ent.team!=1 or ent.category!="unit" or ent.kind=="villager" or ent.state!="attack" or ent.mode!="ATTACK" or ent.auto_target: return false
	if target.is_empty() or not target.alive or target.team!=0 or target.category not in ["unit","building"] or target.id==ent.target or not _visible_to(target,ent.team): return false
	if ent.path_status!=BoundedPath.NO_PATH or ent.path_reason!="frontier_exhausted" or not ent.path_has_attempt or ent.path_pending or ent.traffic_route or not ent.path.is_empty(): return false
	if ent.path_request_kind!="point" or ent.path_request_state!="attack" or ent.path_request_target!=ent.target or ent.path_request_epoch!=ent.work_epoch or ent.path_revision!=work_memory[ent.team].revision: return false
	var failed=ent.get("path_resolved_goal",Vector3.INF)
	if not failed.is_finite(): return false
	if _attack_distance(ent.pos,target)>Rules.RANGE[ent.kind]:
		var approach=_attack_approach(ent,target) if target.category=="building" else target.pos
		if approach==Vector3.INF: return false
		var resolved=_nearest_free(approach,8,ent.team,ent)
		if resolved==Vector3.INF or _cell(resolved)==_cell(failed): return false
	# In-range combat needs no movement resolver. The following ordinary
	# _order invalidates the old proof/epoch exactly once in either case.
	# Keep all search counters, failures, retry timestamps and next gate.
	ent.path_status="IDLE"; ent.path_reason=""
	return true

func _retire_ai_attack_move_failure(ent,destination):
	# A different resolved ground destination does not share the exhausted
	# frontier of this exact previous explicit attack. Keep its search budget.
	if ent.team!=1 or ent.category!="unit" or ent.kind=="villager" or ent.state!="attack" or ent.mode!="ATTACK" or ent.auto_target or ent.target<0: return false
	if ent.path_status!=BoundedPath.NO_PATH or ent.path_reason!="frontier_exhausted" or not ent.path_has_attempt or ent.path_pending or ent.traffic_route or not ent.path.is_empty(): return false
	if ent.path_request_kind!="point" or ent.path_request_state!="attack" or ent.path_request_target!=ent.target or ent.path_request_epoch!=ent.work_epoch or ent.path_revision!=work_memory[ent.team].revision: return false
	var failed=ent.get("path_resolved_goal",Vector3.INF)
	if not failed.is_finite() or not destination.is_finite() or _cell(destination)==_cell(failed): return false
	# No old-target lookup, fresh command budget or extra path search.
	# The normal MOVE below invalidates the old epoch exactly once.
	ent.path_status="IDLE"; ent.path_reason=""
	return true

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
		elif include_reserved:
			for item in ent.queue:
				if not item.get("research",false): result+=1
	return result

func _capacity(team):
	var total=0
	for ent in entities:
		if ent.alive and ent.team==team and ent.built:
			if ent.kind=="town_center": total+=10
			elif ent.kind=="house": total+=5
	return mini(total,Rules.POP_LIMIT)

func _reset_economy(initial_stocks_units):
	economy=Economy.new(Economy.FOUR_RESOURCE_TYPES); economy_sequence=0; age_completed_tick=[-1,-1]; military_tech_completed=[{},{}]; large_route_cache=[{},{}]
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

# Producer-owned ground or natural-resource plan. Validate current faction
# knowledge; no spawn override, path probe or pre-authorized harvest is stored.
func _set_ground_rally(id,p,team,clear=false,target_id=-1,mode="move"):
	var building=_get_entity(id)
	if building.is_empty() or not building.alive or building.team!=team or not building.built or not Rules.PRODUCES.has(building.kind):
		return _reject_command(team,"請選取自己的已完成生產建築。")
	if typeof(mode)!=TYPE_STRING or mode not in ["move","advance"]: return _reject_command(team,"集合點指令已失效。")
	if clear:
		building.erase("rally_point"); building.erase("rally_target"); building.erase("rally_mode")
		if team==0: _message("已取消集合點；新單位在出口待命。")
		return true
	if typeof(target_id)!=TYPE_INT or target_id < -1: return _reject_command(team,"集合目標已失效。")
	if mode=="advance" and ("villager" in Rules.products_for(building.kind) or target_id>=0): return _reject_command(team,"警戒集合點需要軍事生產建築與可見空地。")
	if target_id>=0:
		var target=_get_entity(target_id)
		if "villager" not in Rules.products_for(building.kind) or target.is_empty() or not _visible_to(target,team) or not target.alive or target.category!="resource" or _resource_type(target).is_empty():
			return _reject_command(team,"主堡採集集合點需要可見的自然資源。")
		# Store only this accepted observed resource, never the imprecise tap.
		building.rally_point=target.pos; building.rally_target=target.id; building.rally_mode="move"
		if team==0: _message("採集集合點已設定；新村民自動採集。",4)
		return true
	if not p is Vector3 or not p.is_finite(): return _reject_command(team,"請點可見空地。")
	# Reject outside points before _cell's clamping. Height carries no intent.
	if absf(p.x)>=Rules.MAP_HALF-Rules.MAP_BORDER or absf(p.z)>=Rules.MAP_HALF-Rules.MAP_BORDER:
		return _reject_command(team,"請在戰場設定集合點。")
	var cell=_cell(p)
	if visible_cells[team][_cell_index(p)]==0: return _reject_command(team,"請點可見空地。")
	_refresh_work_memory()
	if work_memory[team].grid.is_point_solid(cell): return _reject_command(team,"集合點需要空地。")
	building.rally_point=_point(cell); building.erase("rally_target"); building.rally_mode=mode
	if team==0: _message("警戒集合點已設定；新軍隊警戒前進。" if mode=="advance" else "集合點已設定；新單位自動移動。",4)
	return true

func _apply_newborn_rally(unit,building):
	if not building.has("rally_point"): return
	if building.get("rally_mode","move")=="advance" and unit.kind in Rules.UNIT_KINDS and unit.kind!="villager":
		# Queue the ordinary military command only after the paid birth.
		# A later player order has a later sequence and supersedes it normally.
		_submit("advance",{"ids":[unit.id],"position":building.rally_point},unit.team)
		return
	if unit.kind=="villager" and building.get("rally_target",-1)>=0:
		# Read only current faction knowledge. The ordinary queued command
		# revalidates visibility/liveness next tick; never read hidden truth.
		var known=faction_views[unit.team].get_record(building.rally_target)
		if not known.is_empty() and known.alive and not known.remembered and known.category=="resource" and not _resource_type(known).is_empty():
			_submit("order",{"ids":[unit.id],"target":known.id,"position":known.pos},unit.team)
			return
	# Scouts, other troops, and unobserved/depleted resources retain ordinary
	# ground routing to the last accepted point. No automatic target search.
	_order_move(unit,building.rally_point)

# Opt-in production policy. No payment or population reservation is made here.
func _set_repeat_training(id,kind,team):
	if team not in [0,1] or typeof(id)!=TYPE_INT or typeof(kind)!=TYPE_STRING: return false
	var building=_get_entity(id)
	if building.is_empty() or not building.alive or building.team!=team or building.category!="building" or not building.built or not Rules.PRODUCES.has(building.kind) or "villager" in Rules.products_for(building.kind): return false
	if not kind.is_empty() and (kind not in Rules.products_for(building.kind) or not _kind_unlocked(kind,team)): return false
	if building.get("repeat_kind","")==kind: return true
	building.repeat_generation=building.get("repeat_generation",0)+1
	building.repeat_kind=kind
	return true

func _stop_repeat_training(building):
	if not building.get("repeat_kind","").is_empty():
		building.repeat_generation=building.get("repeat_generation",0)+1
		building.repeat_kind=""

func _repeat_training_pending(id,team):
	for command in commands:
		if command.get("team",-1)!=team: continue
		if command.get("type","")=="surrender": return true
		if command.get("building",-1)==id and command.get("type","") in ["train","research","repeat_train","cancel_train","cancel_queue_item","demolish"]: return true
	return false

func _repeat_train_current(command):
	var building=_get_entity(command.get("building",-1))
	if building.is_empty() or not building.alive or not building.built or building.team!=command.get("team",-1) or not building.queue.is_empty(): return false
	var kind=building.get("repeat_kind","")
	# Reject stale automatically queued intent after Stop/reconfiguration. A
	# manual train has no generation and keeps the original authority path.
	return not kind.is_empty() and kind==command.get("kind","") and typeof(command.get("repeat_generation",null))==TYPE_INT and command.repeat_generation==building.get("repeat_generation",0) and _kind_unlocked(kind,building.team) and _population(building.team)<_capacity(building.team) and _can_pay(COSTS[kind],building.team)

func _update_repeat_training():
	if paused or game_over or tick_count%20!=0: return
	var budgets=[economy.bank_milli(0).duplicate(),economy.bank_milli(1).duplicate()]
	var slots=[_capacity(0)-_population(0),_capacity(1)-_population(1)]
	# Keep proposal priority after the last accepted producer for each team.
	# Funds and population are still rechecked by ordinary train execution.
	# A tick-derived rotation aliases with training durations; a successful
	# proposal advances the cursor even when an earlier command later spends.
	if entities.is_empty(): return
	for team in [0,1]:
		var start=repeat_train_cursor[team]%entities.size()
		for offset in range(entities.size()):
			var building=entities[(start+offset)%entities.size()]
			var kind=building.get("repeat_kind","")
			if kind.is_empty() or not building.alive or building.category!="building" or not building.built or building.team not in [0,1] or not building.queue.is_empty(): continue
			if building.team!=team: continue
			if "villager" in Rules.products_for(building.kind) or kind not in Rules.products_for(building.kind) or not _kind_unlocked(kind,team) or slots[team]<=0 or _repeat_training_pending(building.id,team): continue
			var affordable=true
			for resource in COSTS[kind]:
				if budgets[team].get(resource,0)<COSTS[kind][resource]*Economy.SCALE: affordable=false
			if not affordable: continue
			var sequence=command_sequence
			_submit("train",{"building":building.id,"kind":kind,"repeat_generation":building.get("repeat_generation",0)},team)
			if command_sequence==sequence: continue
			repeat_train_cursor[team]=(building.id+1)%entities.size()
			slots[team]-=1
			for resource in COSTS[kind]: budgets[team][resource]-=COSTS[kind][resource]*Economy.SCALE

func _enqueue_train(id,kind,team):
	var building=_get_entity(id)
	if building.is_empty() or not building.alive or building.team!=team or not building.built:
		return _reject_command(team,"請選取自己的已完成生產建築。")
	if kind not in Rules.products_for(building.kind): return _reject_command(team,"這座建築不能訓練該兵種。")
	if not _kind_unlocked(kind,team): return _reject_command(team,"需要先在主堡研究城防時代。")
	if building.queue.size()>=5: return _reject_command(team,"生產隊列已滿。")
	if _population(team)>=_capacity(team):
		if team==0: _message("人口已滿，先建民居。每方最多 50 人。")
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
	if Rules.UNIT_RADII.get(order.kind,Rules.UNIT_RADIUS)>0.5:
		var expanded={}
		for first in candidates:
			for dx in [-1,0,1]:
				for dy in [-1,0,1]: expanded[first+Vector2i(dx,dy)]=true
		candidates=expanded.keys(); candidates.sort_custom(func(a,b): return a.x<b.x or (a.x==b.x and a.y<b.y))
	for cell in candidates:
		spawn_candidate_checks+=1
		if cell.x<Rules.MAP_BORDER or cell.y<Rules.MAP_BORDER or cell.x>Rules.MAP_LAST_PLAYABLE or cell.y>Rules.MAP_LAST_PLAYABLE or navigation.is_point_solid(cell): continue
		var point=_point(cell); var blocked=false
		for unit in entities:
			if unit.alive and unit.category=="unit" and unit.pos.distance_to(point)<unit.radius+Rules.UNIT_RADII.get(order.kind,Rules.UNIT_RADIUS): blocked=true; break
		if not blocked and _static_unit_step_is_free({"pos":point,"radius":Rules.UNIT_RADII.get(order.kind,Rules.UNIT_RADIUS)},point): return point
	return Vector3.INF

func _cancel_train(id,team):
	var building=_get_entity(id)
	if building.is_empty() or not building.alive or building.team!=team or building.queue.is_empty():
		return _reject_command(team,"沒有可取消的己方生產項目。")
	var order=building.queue.back()
	var receipt_id=order.get("receipt_id","")
	economy_sequence+=1
	var refund=economy.cancel_cost("cancel:%s:%d" % [receipt_id,economy_sequence],receipt_id,team)
	if not refund.applied: return false
	building.queue.pop_back()
	_stop_repeat_training(building)
	return true

func _cancel_queue_item(id,queue_id,expected_refund,team):
	# Exact identity and displayed refund are compared before any ledger mutation.
	# A completed/started/replaced order must not inherit an old cancellation.
	if team not in [0,1] or typeof(id)!=TYPE_INT or id<0 or typeof(queue_id)!=TYPE_INT or queue_id<0: return _reject_command(team,"生產項目已失效。")
	if typeof(expected_refund)!=TYPE_DICTIONARY or expected_refund.size()!=Economy.FOUR_RESOURCE_TYPES.size(): return _reject_command(team,"請重新查看退款資源。")
	for resource in Economy.FOUR_RESOURCE_TYPES:
		if not expected_refund.has(resource) or typeof(expected_refund[resource])!=TYPE_INT or expected_refund[resource]<0: return _reject_command(team,"請重新查看退款資源。")
	var building=_get_entity(id)
	if building.is_empty() or not building.alive or building.team!=team or building.category!="building" or not building.built: return _reject_command(team,"沒有可取消的己方生產項目。")
	for index in range(building.queue.size()):
		var order=building.queue[index]
		if order.queue_id!=queue_id: continue
		var receipt_id=order.get("receipt_id","")
		if economy.quote_refund(receipt_id,team)!=expected_refund: return _reject_command(team,"退款資源已改變，請重新點選。")
		economy_sequence+=1
		var refund=economy.cancel_cost("cancel:%s:%d" % [receipt_id,economy_sequence],receipt_id,team)
		if not refund.applied: return false
		building.queue.remove_at(index)
		_stop_repeat_training(building)
		return true
	return _reject_command(team,"生產項目已完成或已取消。")

func _update_production(ent,dt,commit_ready=true):
	if not ent.built or ent.queue.is_empty() or ent.get("production_tick",-1)==tick_count: return
	ent.production_tick=tick_count
	var order=ent.queue[0]
	if not order.get("research",false) and order.remaining_ticks>0 and _population(ent.team)>_capacity(ent.team): return
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
	if order.get("research",false):
		var receipt_id=order.get("receipt_id","")
		if not economy.fulfill_cost("fulfilled:"+receipt_id,receipt_id,ent.team).applied: return
		ent.queue.pop_front(); progress_serial+=1
		if order.kind=="age2":
			age_completed_tick[ent.team]=tick_count
			if ent.team==0: _message("城防時代研究完成。下一步可建馬廄與工坊。",6)
		elif order.kind in Rules.MILITARY_TECHS:
			military_tech_completed[ent.team][order.kind]=tick_count
			if ent.team==0: _message(Rules.NAMES[order.kind]+"完成："+Rules.TECH_DETAILS[order.kind],6)
		return
	order.next_retry_tick=tick_count+20
	spawn_availability_polls+=1
	if _population(ent.team,false)>=_capacity(ent.team): return
	var spawn_point=_spawn_exit(ent,order)
	if spawn_point==Vector3.INF: return
	# This is the commit point. Prior commits are already in entities/population.
	if _population(ent.team,false)>=_capacity(ent.team) or navigation.is_point_solid(_cell(spawn_point)): return
	for unit in entities:
		if unit.alive and unit.category=="unit" and unit.pos.distance_to(spawn_point)<unit.radius+Rules.UNIT_RADII.get(order.kind,Rules.UNIT_RADIUS): return
	var receipt_id=order.get("receipt_id","")
	var fulfilled=economy.fulfill_cost("fulfilled:"+receipt_id,receipt_id,ent.team)
	if not fulfilled.applied: return
	ent.queue.pop_front()
	spawn_commit_order.append({"building":ent.id,"queue":order.queue_id,"tick":tick_count})
	var unit=_spawn(order.kind,ent.team,spawn_point)
	# Birth/receipt commit above is unchanged. Only the newborn inherits the
	# current plan once, through a queued gather order or bounded ground MOVE.
	if ent.has("rally_point"): _apply_newborn_rally(unit,ent)
	trained_total[ent.team]+=1
	match_report.record_training(unit)
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
	var grid=navigation if team<0 else (_route_grid(mover) if not mover.is_empty() else work_memory[team].grid)
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
	if ent.radius>0.5 and _route_grid(ent).is_point_solid(_cell(point)): return false
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
	var grid=navigation if team<0 else (_route_grid(mover) if not mover.is_empty() else work_memory[team].grid)
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
			# Physical intersection observation matches presentation/commands:
			# a building visibly crossing the fog edge is an observed blocker.
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
	var records=_gather_records(ent.team) if ent.state=="gather" else work_memory[ent.team].structures
	return records.get(ent.target,{})

func _nearest_known_resource(p,kind,team):
	var best={}; var distance=INF
	for known in _gather_records(team).values():
		if not known.alive or (_resource_type(known)!=kind and known.kind!=kind): continue
		if known.kind=="farm" and economy.farm_view(known.id).get("worker_id",-1)>=0: continue
		var d=known.pos.distance_squared_to(p)
		if d<distance or (d==distance and (best.is_empty() or known.id<best.id)):
			distance=d; best=known
	return best

func _work_candidates(ent):
	var records=_gather_records(ent.team) if ent.state=="gather" else work_memory[ent.team].structures
	var ranked=[]
	for known in records.values():
		if not known.alive: continue
		if ent.state=="gather" and _resource_type(known)!=_gather_intent(ent): continue
		if ent.state=="gather" and (known.kind=="farm" or ent.get("farm_id",-1)>=0) and known.id!=ent.get("farm_id",-1): continue
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
	var known=_gather_records(ent.team).get(ent.resource_target,{})
	var original=not known.is_empty() and known.alive and _resource_type(known)==_gather_intent(ent)
	if original and known.kind=="farm" and economy.farm_view(known.id).get("worker_id",-1) not in [-1,ent.id]: original=false
	if not original: known=_nearest_known_resource(ent.pos,_gather_intent(ent),ent.team)
	if known.is_empty(): _release_farm(ent); _path_cancel_pending(ent); ent.state="idle"; ent.target=-1; return
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
		else: _release_farm(ent); _path_cancel_pending(ent); ent.state="idle"
		return
	if not _at_work_approach(ent,known,true): return
	# Resource authority is consulted only for a currently observed local action.
	if ent.state=="gather" and visible_cells[ent.team][_cell_index(known.pos)]==0: return
	var target=_get_entity(known.id)
	if ent.state=="gather":
		if target.is_empty() or not target.alive: _refresh_work_memory(); return
		var gathered=economy.farm_tick(ent.id,target.id,tick_count) if target.kind=="farm" else economy.gather_tick(ent.id,target.id,tick_count)
		if gathered.applied:
			if ent.team==0: demo_tutorial.record("gather")
			_note_unit_action(ent,"gather_wood" if _resource_type(target)=="wood" else "gather_food",target.pos)
			ent.path=PackedVector3Array(); progress_serial+=1
			_project_economy_entity(ent); _project_economy_entity(target)
		if target.category=="resource" and economy.node_view(target.id).remaining_milli<=0: _kill(target)
	else:
		if not _valid_dropoff(ent,target): _route_to_dropoff(ent); return
		if _cargo_amount(ent)>0 and not _deposit_cargo(ent,target).applied: return
		_resume_gather(ent)

func _path_state(ent):
	if ent.has("path_status"): return
	ent.path_status="IDLE"; ent.path_reason=""; ent.path_pending=false
	ent.path_request_goal=ent.pos; ent.path_resolved_goal=Vector3.INF; ent.path_revision=work_memory[ent.team].revision
	ent.path_has_attempt=false; ent.path_retry_ticks=[]; ent.path_failures=0
	ent.path_next_attempt_tick=0; ent.path_searches=0; ent.path_initial_searches=0; ent.path_retry_searches=0; ent.path_expanded=0
	ent.path_request_kind="point"; ent.work_epoch=0; ent.path_request_epoch=0
	ent.work_approach=Vector3.INF; ent.work_target_id=-1; ent.work_route_revision=-1; ent.work_any_target=false
	ent.traffic_goal=Vector3.INF; ent.traffic_best_distance=INF; ent.traffic_progress_tick=tick_count
	ent.traffic_replans=0; ent.traffic_last_replan=tick_count; ent.traffic_route=false; ent.work_slot_wait=-1; ent.traffic_path_length=0; ent.traffic_command_origin=ent.pos; ent.traffic_gate_since=-1

func _path_new_command(ent):
	# Accepted explicit player intents win over evacuation and its old job.
	if ent.get("kind","")=="villager":
		worker_evacuations.erase(ent.id)
		worker_manual_until[ent.id]=tick_count+WorkerSafety.MANUAL_GRACE_TICKS
		worker_safety_hits[ent.id]=ent.get("last_damage_tick",-1000)
	_path_state(ent)
	path_requests.erase(ent.id)
	ent.path_pending=false; ent.path_status="IDLE"; ent.path_reason=""; ent.path_resolved_goal=Vector3.INF
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
		var route_grid=_route_grid(ent)
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
		var goal=Vector3.INF if work else _point_route_goal(ent)
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
		# Exact resolved endpoint for this request identity, not a later re-snap.
		ent.path_resolved_goal=Vector3.INF if work else goal
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
	_release_farm(ent)
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
	else:
		# A combat target's original observed aim can differ from the free
		# endpoint. Local yielding must preserve that request identity.
		_plan_path(ent,ent.path_request_goal if ent.state=="attack" else ent.dest)

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
	# A known occupied target cell may resolve to a neighboring free endpoint.
	# Compare both the resolved endpoint and the original request; an unchanged
	# requested target must not invalidate its own still-usable path every tick.
	var goal_changed=ent.dest.distance_to(destination)>1.1 and ent.path_request_goal.distance_to(destination)>1.1
	if ent.path_version!=work_memory[ent.team].revision or goal_changed or ent.path.is_empty():
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

# A site requires sight of its actual occupied cells, not an extra arbitrary
# halo based on the largest building in the catalog. Physical intersection
# observation in _visible_to makes every overlapping blocker observable.
func _placement_visibility_cells(footprint):
	return footprint

func _placement_reason(kind,p,team,builder_id,check_resources=true):
	p=_snap_build_position(kind,p)
	if victory_mode=="control" and p.distance_to(ControlPoint.CENTER)<ControlPoint.RADIUS+Rules.FOOTPRINT.get(kind,1): return "中央據點範圍須留作爭奪，不可建造。"
	if not Rules.BUILD_TIME.has(kind): return "未知建築"
	if not _kind_unlocked(kind,team): return "需要城防時代"
	if kind=="tower" and _count(team,"tower")>=2: return "每方最多兩座守望塔"
	var mock={"pos":p,"kind":kind,"category":"building"}
	var footprint=_occupied_cells(mock)
	for c in footprint:
		if c.x<Rules.MAP_BORDER+1 or c.y<Rules.MAP_BORDER+1 or c.x>Rules.MAP_LAST_PLAYABLE-1 or c.y>Rules.MAP_LAST_PLAYABLE-1: return "地圖邊界"
	for c in _placement_visibility_cells(footprint):
		# Out-of-map envelope cells are public boundary, not observable cells.
		# Bounds precede indexing even if the public size catalog grows.
		if c.x<0 or c.y<0 or c.x>=Rules.MAP_SIZE or c.y>=Rules.MAP_SIZE: continue
		if visible_cells[team][c.y*Rules.MAP_SIZE+c.x]==0: return "先派村民探索建築範圍"
	var builder=_get_entity(builder_id)
	if builder.is_empty() or not builder.alive or builder.team!=team or builder.kind!="villager": return "請先選取村民"
	if check_resources and not _can_pay(COSTS[kind],team): return "資源不足"
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
	path_requests.erase(ent.id); ent.path_pending=false; ent.path_resolved_goal=Vector3.INF
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
		if target.kind=="farm": return "gather"
	return "move"

func _repair_order_allowed(ent,target):
	return not target.is_empty() and target.alive and ent.kind=="villager" and target.team==ent.team and target.category=="building" and target.built and target.hp<target.max_hp and tick_count-target.last_damage_tick>=100

func _order(ent,state,target_id,automatic=false):
	if ent.is_empty() or not ent.alive: return false
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
	if ent.kind=="villager":
		var requested=_get_entity(target_id)
		if state=="gather" and not requested.is_empty() and requested.kind=="farm":
			if not requested.alive or not requested.built or requested.team!=ent.team: return false
			var occupant=economy.farm_view(target_id).get("worker_id",-1)
			if occupant>=0 and occupant!=ent.id: return _reject_command(ent.team,"這片農田已有村民耕作。")
		if state!="deliver" and (state!="gather" or target_id!=ent.get("farm_id",-1)): _release_farm(ent)
		if state=="gather" and not requested.is_empty() and requested.kind=="farm" and ent.get("farm_id",-1)<0 and (_cargo_amount(ent)==0 or _cargo_type(ent)=="food"):
			economy_sequence+=1
			if not economy.assign_farm("farm_assign:%d" % economy_sequence,ent.id,target_id).applied: return false
			ent.farm_id=target_id
	_path_cancel_pending(ent)
	ent.erase("patrol_points"); ent.erase("patrol_index")
	ent.advance_engaged=false
	ent.auto_target=automatic
	if not automatic: ent.mode="ATTACK" if state=="attack" else "WORK"
	ent.state=state; ent.target=target_id; ent.work_ticks=0; ent.last_repair_tick=-1; ent.path=PackedVector3Array(); ent.path_version=-1; ent.stuck=0
	ent.path_request_kind="work" if state in ["gather","deliver"] else "point"; ent.work_any_target=false
	if state in ["gather","deliver"]: ent.path_revision=work_memory[ent.team].revision
	var target=_get_entity(target_id)
	if state=="gather":
		_refresh_work_memory()
		var known=_gather_records(ent.team).get(target_id,{})
		ent.resource_target=target_id
		ent.gather_type=_resource_type(known) if not known.is_empty() else ""
		if not known.is_empty(): ent.last_known=known.pos
		if _cargo_amount(ent)>0 and not known.is_empty() and _cargo_type(ent)!=_resource_type(known): _route_to_dropoff(ent)
	elif not target.is_empty(): ent.last_known=target.pos

func _order_advance(ids,position,team,formation=""):
	if typeof(formation)!=TYPE_STRING or formation not in ["","line","spread"]: return _reject_command(team,"陣形指令已失效。")
	# Explicit military intent. Ordinary MOVE and workers keep their semantics.
	if typeof(ids)!=TYPE_ARRAY or ids.size()>Rules.POP_LIMIT or not position is Vector3 or not position.is_finite(): return _reject_command(team,"請選取軍隊並點選地圖目的地。")
	if absf(position.x)>=Rules.MAP_WORLD_LIMIT or absf(position.z)>=Rules.MAP_WORLD_LIMIT: return _reject_command(team,"目的地超出地圖。")
	var military=[]; var seen={}
	for id in ids:
		if typeof(id)!=TYPE_INT: return _reject_command(team,"部隊選取已失效。")
		if seen.has(id): continue
		seen[id]=true
		var ent=_get_entity(id)
		if not ent.is_empty() and ent.alive and ent.team==team and ent.category=="unit" and ent.kind in Rules.UNIT_KINDS and ent.kind!="villager": military.append(id)
	if military.is_empty(): return _reject_command(team,"請選取自己的軍事單位。")
	military.sort()
	var members=[]
	for id in military: members.append(_get_entity(id))
	var slots=ArmyFormation.plan(members,position,formation) if formation!="" else {}
	var reserved={}
	for id in military:
		var ent=_get_entity(id)
		if team==0: _path_new_command(ent)
		_order_move(ent,slots.get(id,position),reserved,military)
		if ent.state=="move":
			ent.mode="ADVANCE"
			reserved[_cell(ent.dest)]=true
	return true

func _order_patrol(ids,position,team):
	# Patrol is explicit military intent, never inferred from a normal ground tap.
	if team not in [0,1] or typeof(ids)!=TYPE_ARRAY or ids.size()>Rules.POP_LIMIT or not position is Vector3 or not position.is_finite(): return _reject_command(team,"請選取軍隊並點選巡邏目的地。")
	if absf(position.x)>=Rules.MAP_WORLD_LIMIT or absf(position.z)>=Rules.MAP_WORLD_LIMIT: return _reject_command(team,"目的地超出地圖。")
	var military=[]; var seen={}
	for id in ids:
		if typeof(id)!=TYPE_INT: return _reject_command(team,"部隊選取已失效。")
		if seen.has(id): continue
		seen[id]=true
		var ent=_get_entity(id)
		if not ent.is_empty() and ent.alive and ent.team==team and ent.category=="unit" and ent.kind in Rules.UNIT_KINDS and ent.kind!="villager": military.append(id)
	military.sort()
	var reserved={}; var applied=false
	for id in military:
		var ent=_get_entity(id)
		var origin=ent.pos
		var goal=_nearest_free(position,8,team,ent,reserved,military)
		# Refuse a zero/tiny circuit before disturbing the previous order.
		if goal==Vector3.INF or origin.distance_to(goal)<2.0: continue
		if team==0: _path_new_command(ent)
		_order_move(ent,goal,reserved,military)
		if ent.state!="move": continue
		ent.patrol_points=[origin,ent.dest]; ent.patrol_index=1; ent.mode="PATROL"
		reserved[_cell(ent.dest)]=true; applied=true
	if not applied: return _reject_command(team,"請選取自己的軍隊，並選擇較遠的可用目的地。")
	return true

func _point_route_goal(ent):
	if ent.mode!="PATROL": return _nearest_free(ent.path_request_goal,8,ent.team,ent)
	var points=ent.get("patrol_points",[])
	var index=ent.get("patrol_index",-1)
	if points.size()!=2 or index not in [0,1]: return Vector3.INF
	# Every search re-resolves around the ORIGINAL endpoint, not the previous
	# fallback slot. Ordinary traffic/search gates still own the actual query.
	return _nearest_free(points[index],2,ent.team,ent)

func _patrol_next_leg(ent):
	# Called only after ordinary arrival. A failed leg is not a new command.
	if ent.mode!="PATROL" or ent.state!="move" or ent.get("path_status","") in [BoundedPath.NO_PATH,BoundedPath.LIMIT_REACHED]: return false
	var points=ent.get("patrol_points",[])
	var index=ent.get("patrol_index",-1)
	if points.size()!=2 or index not in [0,1]:
		_set_stance(ent,"STOP"); return false
	if ent.pos.distance_to(ent.dest)>=0.001: return false
	var next_index=1-index
	# At a blocked endpoint only its immediate two-cell neighborhood is eligible.
	# No remote reroute, polling loop, new search allowance or hidden occupancy.
	var goal=_nearest_free(points[next_index],2,ent.team,ent)
	if goal==Vector3.INF or ent.pos.distance_to(goal)<1.0:
		_set_stance(ent,"STOP")
		if ent.team==0: _message("巡邏端點受阻，已停止。請重新落指令。",3)
		return false
	_order_move(ent,goal)
	if ent.state!="move": return false
	ent.patrol_points=points; ent.patrol_index=next_index; ent.mode="PATROL"
	return true

func _advance_target(ent):
	if ent.mode not in ["ADVANCE","PATROL"] or ent.state!="move" or ent.kind=="villager" or ent.kind not in Rules.UNIT_KINDS: return {}
	if ent.get("path_status","") in [BoundedPath.NO_PATH,BoundedPath.LIMIT_REACHED]: return {}
	var best={}; var distance=INF
	# Detached faction observations only. Fire revalidates live visibility/range.
	for record in faction_views[ent.team].records().values():
		if record.get("team",-1)!=1-ent.team or not record.get("alive",false) or record.get("remembered",false) or record.get("category","") not in ["unit","building"]: continue
		if not Rules.CONTENT.resolve_damage(ent.kind,record.kind).get("ok",false): continue
		var d=_attack_distance(ent.pos,record)
		if d>Rules.RANGE[ent.kind]: continue
		if d<distance or (is_equal_approx(d,distance) and (best.is_empty() or record.id<best.id)):
			best=record; distance=d
	return best

func _advance_combat(ent):
	var observed=_advance_target(ent)
	if observed.is_empty(): return
	var target=_get_entity(observed.id)
	if target.is_empty() or not _visible_to(target,ent.team): return
	if not target.alive or target.team!=1-ent.team or target.category not in ["unit","building"] or _attack_distance(ent.pos,target)>Rules.RANGE[ent.kind]: return
	ent.advance_engaged=true
	_note_unit_action(ent,"attack_ready",target.pos)
	if ent.cooldown_ticks<=0: _release_attack(ent,target)

func _order_move(ent,p,reserved={},ignore_orders=[]):
	ent.rest_ticks=0; ent.rest_base=-1
	# Resolve once with the ordinary owned/observed geometry and reservations.
	var destination=_nearest_free(p,8,ent.team,ent,reserved,ignore_orders)
	_retire_ai_attack_move_failure(ent,destination)
	_release_farm(ent)
	_path_cancel_pending(ent)
	ent.erase("patrol_points"); ent.erase("patrol_index")
	ent.mode="MOVE"; ent.auto_target=false; ent.advance_engaged=false; ent.path_request_kind="point"
	ent.state="move"; ent.target=-1; ent.dest=destination; ent.path=PackedVector3Array(); ent.path_version=-1; ent.stuck=0
	if ent.dest==Vector3.INF: ent.dest=ent.pos; _set_stance(ent,"STOP")

func _set_stance(ent,mode):
	ent.rest_ticks=0; ent.rest_base=-1
	_release_farm(ent)
	_path_cancel_pending(ent)
	ent.path_request_kind="point"
	ent.erase("patrol_points"); ent.erase("patrol_index")
	ent.mode=mode; ent.state="idle"; ent.anchor=ent.pos; ent.auto_target=false; ent.advance_engaged=false
	ent.target=-1; ent.path=PackedVector3Array(); ent.path_version=-1

func _finish_attack(ent):
	if ent.auto_target and ent.mode=="DEFEND":
		ent.target=-1; ent.auto_target=false
		# Retire the completed pursuit even when already at the anchor.
		# A different visible target must not inherit this goal's terminal
		# result. Keep the rolling search/failure history and next-attempt gate.
		_path_cancel_pending(ent)
		ent.path_status="IDLE"; ent.path_reason=""
		var recent_retries=[]
		for retry_tick in ent.path_retry_ticks:
			if tick_count-retry_tick<20: recent_retries.append(retry_tick)
		if recent_retries.size()>=3:
			ent.path_next_attempt_tick=maxi(ent.path_next_attempt_tick,recent_retries[recent_retries.size()-3]+20)
		ent.path=PackedVector3Array(); ent.path_version=-1
		if ent.pos.distance_to(ent.anchor)>0.2:
			ent.state="return"; ent.dest=ent.anchor
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
	ent.advance_engaged=false
	if ent.state=="move":
		if ent.mode=="PATROL" and ent.get("path_status","") in [BoundedPath.NO_PATH,BoundedPath.LIMIT_REACHED]: return
		if not _advance_target(ent).is_empty():
			ent.advance_engaged=true
			# Deliberate combat pause is not blocked navigation. Exclude only
			# this held tick from elapsed traffic clocks, not retry/search gates.
			ent.traffic_progress_tick=mini(tick_count,ent.traffic_progress_tick+1)
			if ent.traffic_gate_since>=0: ent.traffic_gate_since=mini(tick_count,ent.traffic_gate_since+1)
			return
		if _move(ent,ent.dest,dt):
			if ent.mode=="PATROL": _patrol_next_leg(ent)
			else:
				var evacuating=worker_evacuations.has(ent.id) and worker_evacuations[ent.id].epoch==ent.work_epoch
				_set_stance(ent,"STOP")
				if evacuating:
					worker_evacuations[ent.id].epoch=ent.work_epoch
					ent.mode="MOVE" # Shelter wait must not auto-chase the attacker.
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
		var goal=_attack_approach(ent,remembered,not observed) if target.category!="unit" else ent.last_known
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
	if ent.kind in ["berry","farm"]: return "food"
	if ent.kind in ["stone","iron"]: return ent.kind
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
	_release_farm(ent)
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
	if not ent.alive or (ent.category!="unit" and (ent.kind!="tower" or not ent.built)) or not Rules.DAMAGE.has(ent.kind) or ent.team not in [0,1]:
		return {"ok":false,"applied":false,"reason":"INVALID_ATTACKER"}
	if not target.alive or target.team!=1-ent.team or not _visible_to(target,ent.team):
		return {"ok":false,"applied":false,"reason":"INVALID_TARGET"}
	if ent.cooldown_ticks>0 or _attack_distance(ent.pos,target)>Rules.RANGE[ent.kind]:
		return {"ok":false,"applied":false,"reason":"NOT_READY"}
	var resolved=Rules.CONTENT.resolve_damage(ent.kind,target.kind)
	if not resolved.ok: return {"ok":false,"applied":false,"reason":"INVALID_PROFILE"}
	var damage=maxi(1,resolved.base+resolved.bonus+_military_attack_bonus(ent.kind,ent.team)-resolved.armor)
	var result=attack_ledger.issue(tick_count,ent.id,target.id,damage,ent.pos,target.pos)
	if result.applied:
		ent.last_attack_tick=tick_count
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

func _recover_observed_attack_goal(ent,target):
	# A completed static frontier belongs to one observed pursuit goal,
	# not every future position of the same enemy. Never reset a search cap.
	if ent.state!="attack" or (ent.auto_target and ent.mode!="DEFEND") or (not ent.auto_target and ent.mode!="ATTACK"): return false
	if target.is_empty() or not target.alive or target.category!="unit" or target.id!=ent.target or target.team!=1-ent.team or not _visible_to(target,ent.team): return false
	if _attack_distance(ent.pos,target)<=Rules.RANGE[ent.kind]: return false
	if ent.auto_target and target.pos.distance_to(ent.anchor)>3.0: return false
	if ent.path_status!=BoundedPath.NO_PATH or ent.path_reason!="frontier_exhausted" or ent.path_pending or ent.traffic_route or not ent.path.is_empty(): return false
	if ent.path_request_kind!="point" or ent.path_request_state!="attack" or ent.path_request_target!=ent.target or ent.path_request_epoch!=ent.work_epoch or ent.path_revision!=work_memory[ent.team].revision: return false
	var failed=ent.get("path_resolved_goal",Vector3.INF)
	var requested=ent.get("path_request_goal",Vector3.INF)
	if not failed.is_finite() or not requested.is_finite() or _cell(target.pos)==_cell(requested): return false
	# The ordinary known-clear resolver can map different target cells to
	# the same failed endpoint. Such aliases are not a new pursuit goal.
	var goal=_nearest_free(target.pos,8,ent.team,ent)
	if goal==Vector3.INF or _cell(goal)==_cell(failed): return false
	_path_cancel_pending(ent)
	ent.path_status="IDLE"; ent.path_reason=""
	# Retry timestamps, failures, counters and next-attempt gate survive.
	return true

func _update_unit(ent,dt):
	ent.cooldown_ticks=maxi(0,ent.cooldown_ticks-1)
	if ent.state=="idle":
		if ent.mode in ["STOP","DEFEND"]:
			var enemy=_stance_target(ent)
			if not enemy.is_empty(): _order(ent,"attack",enemy.id,true)
		return
	if ent.state=="move":
		if ent.mode in ["ADVANCE","PATROL"]: _advance_combat(ent)
		return
	if ent.state=="return": return
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
				# Reaching an observed firing/melee position ends movement work.
				# Otherwise an old deferred traffic search can later cancel this
				# live attack. Retire it once, without resetting retry budgets.
				if ent.path_pending or not ent.path.is_empty() or ent.traffic_route:
					_path_cancel_pending(ent)
				_note_unit_action(ent,"attack_ready",target.pos)
				ent.path=PackedVector3Array()
				if ent.cooldown_ticks<=0: _release_attack(ent,target)
			elif ent.auto_target and ent.mode=="STOP": _finish_attack(ent)
			else: _recover_observed_attack_goal(ent,target)
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
					match_report.record_completion(target)
					if target.kind=="farm":
						var registered=economy.register_farm(target.id,target.team)
						assert(registered.ok)
						# Finishing this field continues its builder into ordinary farm
						# work. No harvest this tick, cargo conversion or retry reset.
						# An earlier player command already replaced build before here.
						if registered.ok: _order(ent,"gather",target.id)
					if target.team==0 and not receipt_id.is_empty() and target.kind in ["house","barracks"]: demo_tutorial.record(target.kind)
					if ent.team==0: _message(Rules.NAMES[target.kind]+"建造完成。",3)

func _kill(ent):
	if not ent.alive: return
	worker_evacuations.erase(ent.id); worker_manual_until.erase(ent.id); worker_safety_hits.erase(ent.id)
	ai_scout_moves.erase(ent.id)
	ent.death_observed_by=[_visible_to(ent,0),_visible_to(ent,1)]
	if ent.category=="unit" and ent.kind in MatureVisuals.UNIT_KINDS and ent.death_observed_by[0]:
		# Detached final observed pose only. This adds no corpse entity/blocker.
		pending_visual_deaths.append({"id":ent.id,"kind":ent.kind,"team":ent.team,"pos":ent.pos,"yaw":ent.body.rotation.y,"witnessed":true})
		if pending_visual_deaths.size()>CharacterPresenter.MAX_DEATH_VISUALS: pending_visual_deaths.pop_front()
	if ent.kind=="farm" and ent.built: economy.destroy_farm("farm_death:%d" % ent.id,ent.id)
	if ent.kind=="villager":
		economy.destroy_worker("death:%d" % ent.id,ent.id); _project_economy_entity(ent)
	for order in ent.queue:
		var receipt_id=order.get("receipt_id","")
		economy.destroy_cost("destroyed:"+receipt_id,receipt_id,ent.team)
	var site_receipt=ent.get("cost_receipt_id","")
	if not site_receipt.is_empty() and not ent.built:
		economy.destroy_cost("destroyed:"+site_receipt,site_receipt,ent.team)
	ent.alive=false; ent.queue.clear(); ent.node.visible=false; ent.path=PackedVector3Array()
	# Unrelated deaths must not replace a button beneath a held GUI press.
	# Selected deaths still invalidate controls before any stale release.
	if ent.id in selected:
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
			for item in ent.queue:
				if not item.get("research",false): view.training_items+=1
				else:
					var refund=economy.quote_refund(item.get("receipt_id",""),team)
					view.refundable_food+=int(refund.get("food",0)/Economy.SCALE)
					for resource in refund: recoverable_stocks[resource]+=refund[resource]
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
		if victory_mode=="control" and control_point.winner()>=0:
			player_lost=control_point.winner()==1; enemy_lost=control_point.winner()==0; end_reason="control_point"
		elif tick_count>=roundi(Rules.TIME_LIMIT/Rules.TICK):
			player_lost=true; enemy_lost=true; end_reason="time_limit"
		else:
			player_lost=recovery_ticks[0]>=EndRules.IRRECOVERABLE_TICKS
			enemy_lost=recovery_ticks[1]>=EndRules.IRRECOVERABLE_TICKS
			if not player_lost and not enemy_lost: end_reason=""; return
			end_reason="irrecoverable"
	game_over=true
	outcome="draw" if player_lost==enemy_lost else ("defeat" if player_lost else "victory")
	victory=outcome=="victory"
	last_match_report=match_report.make_report(outcome,end_reason,tick_count,age_completed_tick[0],economy.stats_view(0),economy.bank_milli(0))
	last_match_report.skirmish_mode=skirmish_mode
	last_match_report.victory_mode=victory_mode
	last_match_report.control_ticks=control_point.scores.duplicate()
	commands.clear(); _cancel_mode()
	if is_instance_valid(end_panel):
		end_title.text={"victory":"王旗再起","defeat":"聚落失守","draw":"戰事暫歇"}[outcome]
		if end_reason=="surrender":
			end_title.text={"victory":"敵方投降","defeat":"我方投降","draw":"雙方投降"}[outcome]
			end_body.text={"victory":"敵方已確認投降。","defeat":"你已確認投降。這局判定為失敗。","draw":"雙方已確認投降。和局。"}[outcome]
		elif end_reason=="control_point":
			end_title.text="王旗歸我" if victory else "王旗失守"
			end_body.text=("我軍" if victory else "敵軍")+"累積控制中央據點 180 秒，取得勝利。"
		elif end_reason=="irrecoverable":
			end_body.text={"victory":"敵方持續 60 秒沒有單位或任何復原途徑，已自動投降。","defeat":"我方持續 60 秒沒有單位或任何復原途徑，已自動投降。","draw":"雙方持續 60 秒沒有單位或任何復原途徑。和局。"}[outcome]
		else: end_body.text={"victory":"敵方主堡已倒下，霧谷由你守護。","defeat":"你的主堡已被摧毀。重新部署，再戰一局。","draw":"雙方同時失守，或已達 40 分鐘上限。和局。"}[outcome]
		_show_match_report_page("overview"); end_panel.show(); _layout_ui()

func _show_match_report_page(page: String):
	if not game_over or last_match_report.is_empty() or page not in ["overview","economy","units","buildings"]: return
	_cancel_pointer_streams()
	end_report_page=page; end_scroll.scroll_vertical=0
	end_report_label.text=MatchReport.page_text(last_match_report,page)
	for button in end_tabs.get_children():
		button.disabled=button.get_meta("report_page")==page

func _layout_end_report(view_size: Vector2):
	if not is_instance_valid(end_panel): return
	var extent=Vector2(minf(540,view_size.x-24),minf(560,view_size.y-24))
	end_panel.position=(view_size-extent)*0.5; end_panel.size=extent
	var inner=extent.x-32
	end_title.position=Vector2(16,12); end_title.size=Vector2(inner,36)
	end_tabs.position=Vector2(16,56); end_tabs.size=Vector2(inner,46)
	end_scroll.position=Vector2(16,112); end_scroll.size=Vector2(inner,maxf(1,extent.y-180))
	end_actions.position=Vector2(16,extent.y-58); end_actions.size=Vector2(inner,46)

# --- Fair, finite-frequency Demo AI01 ---
# Defaults are documented in AI_POLICY.md. This layer submits ordinary commands;
# it owns no economy, path, construction, combat or visibility authority.
const AI_RAID_INTERVAL_TICKS=1800
const AI_NEAR_KEEP_DISTANCE=6.0
const AI_HOME_THREAT_DISTANCE=6.0
var ai_opening_assigned=false
var ai_last_raid_tick=-AI_RAID_INTERVAL_TICKS
var ai_raid_members=[]
var ai_home_defense_targets={}
var ai_raid_departure_count=0
var ai_raid_keep={}
var ai_raid_retreating=false
var ai_scout_attempts={}
var ai_scout_moves={}
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
			if ent.get("path_status","") in [BoundedPath.NO_PATH,BoundedPath.LIMIT_REACHED]: continue
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
		if _resource_type(known)!=desired: continue
		if known.category!="resource" and not (known.owned and known.built and known.kind=="farm"): continue
		if known.kind=="farm" and economy.farm_view(known.id).get("worker_id",-1) not in [-1,ent.id]: continue
		var d=known.pos.distance_squared_to(ent.pos)
		if d<distance or (d==distance and (resource.is_empty() or known.id<resource.id)): resource=known; distance=d
	if resource.is_empty():
		ai_status.worker="no_known_"+desired; return false
	# Ordinary AI orders preserve terminal budgets. Only the existing visible
	# full/foreign cargo handoff can leave NO_PATH for a deposit route.
	var status=ent.get("path_status","")
	var carried=ent.get("cargo_milli",0)
	var delivery_handoff=not resource.remembered and (carried>=Economy.CARGO_CAP or (carried>0 and ent.get("carry_type","")!=_resource_type(resource)))
	if status in [BoundedPath.LIMIT_REACHED,"NO_WORK"] or (status==BoundedPath.NO_PATH and not delivery_handoff):
		ai_status.worker="terminal_work_route"; return false
	var order={"ids":[ent.id],"target":-1 if resource.remembered else resource.id,"position":resource.pos}
	if desired=="food" and resource.kind=="farm" and resource.owned and resource.built and not resource.remembered: order.farm_gather=true
	_submit("order",order,ent.team)
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
	for p in _ai_progression_plots(kind):
		var reason=_placement_reason(kind,p,1,builder.id)
		if reason.is_empty():
			_submit("build",{"kind":kind,"position":p,"builder":builder.id},1)
			ai_claimed_workers[builder.id]="build"; ai_build_submitted=true; _ai_reserve_budget(kind)
			ai_status.build="submitted_"+kind; return true
		reasons.append(reason)
	ai_status.build="no_legal_plot"; ai_status.placement_reasons=reasons
	return false

func _ai_keep_repair(records,castle):
	# A policy choice only. HP, work, lockout, route and wood remain ordinary
	# authority. Own damage timing is published only inside the owned view.
	if castle.is_empty() or not castle.get("owned",false) or not castle.get("alive",false) or castle.get("team",-1)!=1 or castle.get("kind","")!="town_center" or not castle.get("built",false): return false
	if castle.get("hp",0)<=0 or castle.get("hp",0)>=castle.get("max_hp",0): return false
	var assigned=false; var working=false
	for worker in records:
		if not worker.get("owned",false) or not worker.get("alive",false) or worker.get("team",-1)!=1 or worker.get("kind","")!="villager" or worker.get("state","")!="repair" or worker.get("target",-1)!=castle.id: continue
		# Do not let housing, site recovery or resource balancing steal the
		# one-second repair interval before its paid work can commit.
		ai_claimed_workers[worker.id]="repair"; assigned=true
		if worker.get("path_status","") in [BoundedPath.NO_PATH,BoundedPath.LIMIT_REACHED]:
			_submit("stop",{"ids":[worker.id]},1)
		else: working=true
	if assigned:
		if working and ai_budget.get("wood",0)>=Economy.SCALE: ai_budget.wood-=Economy.SCALE
		ai_status.keep_repair="working" if working else "route_failed_stop_requested"
		return true
	if ai_budget.get("wood",0)<Economy.SCALE or tick_count-castle.get("last_damage_tick",tick_count)<100: return false
	for observed in records:
		if observed.get("team",-1)==0 and observed.get("alive",false) and not observed.get("remembered",false) and observed.get("category","")=="unit" and _attack_distance(observed.pos,castle)<=AI_HOME_THREAT_DISTANCE: return false
	var food_count=_ai_food_count(records)
	if food_count<2: return false
	var chosen={}; var best_distance=INF
	for idle_only in [true,false]:
		for worker in records:
			if not worker.get("owned",false) or not worker.get("alive",false) or worker.get("team",-1)!=1 or worker.get("category","")!="unit" or worker.get("kind","")!="villager" or worker.get("remembered",false): continue
			if ai_claimed_workers.has(worker.id) or worker.get("state","") not in ["idle","gather"] or worker.get("cargo_milli",0)>0: continue
			if worker.get("path_status","") in [BoundedPath.NO_PATH,BoundedPath.LIMIT_REACHED,"NO_WORK"]: continue
			if idle_only and worker.state!="idle": continue
			if _ai_food_worker(worker) and food_count<=2: continue
			var distance=worker.pos.distance_squared_to(castle.pos)
			if distance<best_distance or (distance==best_distance and (chosen.is_empty() or worker.id<chosen.id)):
				chosen=worker; best_distance=distance
		if not chosen.is_empty(): break
	if chosen.is_empty(): return false
	var sequence=command_sequence
	_submit("order",{"ids":[chosen.id],"target":castle.id,"position":castle.pos},1)
	if command_sequence==sequence: return false
	ai_claimed_workers[chosen.id]="repair"
	# Policy budget only: retain one wood for the next normal work payment.
	# No reservation/debit is made in the ledger, no HP or repair tick is added.
	ai_budget.wood-=Economy.SCALE; ai_status.keep_repair="requested"
	return true

func _ai_recover_worker_slot(records,castle,workers,queued_workers,capacity,committed):
	# Losing the final worker can leave every birth slot occupied by paid
	# military reservations. One exact cancellation may restore a worker,
	# but never sacrifice a live unit or cancel a batch that cannot recover.
	if workers!=0 or queued_workers!=0 or committed<capacity or committed-1>=capacity: return false
	if castle.is_empty() or not castle.get("owned",false) or not castle.get("alive",false) or castle.get("team",-1)!=1 or castle.get("kind","")!="town_center" or not castle.get("built",false): return false
	var funds=economy.bank_milli(1)
	var chosen={}; var best_rank=2
	for building in records:
		if not building.get("owned",false) or not building.get("alive",false) or building.get("team",-1)!=1 or building.get("category","")!="building" or not building.get("built",false): continue
		# A different producer's cancellation cannot open a full keep queue.
		if castle.queue.size()>=5 and building.id!=castle.id: continue
		for order in building.get("queue",[]):
			if order.get("research",false) or order.get("kind","") not in Rules.UNIT_KINDS or order.kind=="villager" or order.get("queue_id",-1)<0: continue
			var refund=economy.quote_refund(order.get("receipt_id",""),1)
			# Closed/missing/foreign receipts quote zero. Every real military
			# product has a positive ordinary refund, even after it has started.
			if refund.get("food",0)+refund.get("wood",0)+refund.get("stone",0)+refund.get("iron",0)<=0: continue
			var affordable=true
			for resource in COSTS.villager:
				if funds.get(resource,0)+refund.get(resource,0)<COSTS.villager[resource]*Economy.SCALE: affordable=false
			if not affordable: continue
			var rank=1 if order.get("started",false) else 0
			if chosen.is_empty() or rank<best_rank or (rank==best_rank and (building.id<chosen.building or (building.id==chosen.building and order.queue_id<chosen.queue_id))):
				chosen={"building":building.id,"queue_id":order.queue_id,"expected_refund":refund}; best_rank=rank
	if chosen.is_empty(): return false
	var previous_sequence=command_sequence
	_submit("cancel_queue_item",chosen,1)
	if command_sequence==previous_sequence: return false
	# Exact queue identity/refund are revalidated by ordinary execution.
	# Do not spend the quote or train in this policy turn. Observe committed
	# cancellation and actual bank/population on the next regular AI update.
	ai_status.worker_recovery="military_slot_refund_requested"
	return true

func _ai_recover_worker_funding(castle,workers,queued_workers,capacity,committed):
	# With no worker left, paid research may hold the only viable recovery
	# funds. Do not abandon research when a replacement is already possible.
	if workers!=0 or queued_workers!=0 or committed>=capacity or _ai_can_budget("villager"): return false
	if castle.is_empty() or not castle.owned or not castle.alive or castle.team!=1 or castle.kind!="town_center" or not castle.built: return false
	# Military research can be behind another item. Cancel its exact receipt,
	# never accidentally remove the queue head or assume the quoted money exists.
	for queued in castle.queue:
		if not queued.get("research",false) or queued.get("kind","") not in Rules.MILITARY_TECHS: continue
		var quote=economy.quote_refund(queued.get("receipt_id",""),1)
		if ai_budget.get("food",0)+quote.get("food",0)<COSTS.villager.food*Economy.SCALE: continue
		var sequence=command_sequence
		_submit("cancel_queue_item",{"building":castle.id,"queue_id":queued.queue_id,"expected_refund":quote},1)
		if command_sequence==sequence: return false
		ai_status.worker_recovery="research_refund_requested"
		return true
	if castle.queue.size()!=1: return false
	var order=castle.queue[0]
	if not order.get("research",false) or order.get("kind","")!="age2": return false
	var refund=economy.quote_refund(order.get("receipt_id",""),1)
	for resource in COSTS.villager:
		if ai_budget.get(resource,0)+refund.get(resource,0)<COSTS.villager[resource]*Economy.SCALE: return false
	var previous_sequence=command_sequence
	_submit("cancel_train",{"building":castle.id},1)
	if command_sequence==previous_sequence: return false
	# Cancellation is still authoritative and may fail. Never pre-credit or
	# spend this quote; the next AI turn reads the actual bank and queue.
	ai_status.worker_recovery="research_refund_requested"
	return true

func _ai_resource_gap(records,workers,capacity,committed):
	var desired=_ai_progression_goal(records,workers,capacity,committed)
	ai_status.resource_goal=desired
	var chosen="food"; var gap=-1
	for resource in ["food","wood","iron","stone"]:
		var deficit=maxi(0,COSTS[desired].get(resource,0)*Economy.SCALE-ai_budget.get(resource,0))
		if deficit>gap: gap=deficit; chosen=resource
	return chosen

func _ai_static_failed_scout(ent):
	# Only a completed static frontier for our exact accepted exploration MOVE.
	# A stale task, another order, traffic or a search limit grants no retry.
	var tracked=ai_scout_moves.get(ent.get("id",-1),{})
	return tracked.has("work_epoch") and tracked.has("goal") \
		and ent.get("team",-1)==1 and ent.get("kind","")=="scout" and ent.get("alive",false) \
		and ent.get("state","")=="move" and ent.get("mode","")=="MOVE" and ent.get("target",-2)==-1 \
		and ent.get("path_status","")==BoundedPath.NO_PATH and ent.get("path_reason","")=="frontier_exhausted" \
		and not ent.get("path_pending",true) and not ent.get("traffic_route",true) and ent.get("path",[Vector3.INF]).is_empty() \
		and ent.get("path_request_kind","")=="point" and ent.get("path_request_state","")=="move" \
		and ent.get("path_request_target",-2)==-1 and ent.get("work_epoch",-1)>=0 \
		and ent.get("path_request_epoch",-2)==ent.get("work_epoch",-1) \
		and tracked.work_epoch==ent.get("work_epoch",-1) and tracked.goal==ent.get("dest",Vector3.INF)

func _ai_scout(ent):
	if paused or game_over or not ent.get("owned",false) or ent.get("team",-1)!=1 or ent.get("kind","")!="scout": return
	var recover_static=_ai_static_failed_scout(ent)
	if ent.state!="idle" and not recover_static: return
	if ent.state=="idle" and ent.get("path_status","") in [BoundedPath.NO_PATH,BoundedPath.LIMIT_REACHED,"NO_WORK"]: return
	# Do not queue exploration across a pending explicit order or stance.
	for queued in commands:
		if queued.get("team",-1)==1 and ent.id in queued.get("ids",[]) and queued.get("type","") in ["order","stop","defend"]:
			ai_status.scout="pending_order"; return
	var point=Vector3.INF; var distance=INF; var chosen=-1
	var own_keep=_ai_owned(_ai_records(),"town_center")
	var own_home=own_keep.get("pos",Vector3.ZERO)
	# Finite shared attempted-cell set for the match. Inspect explored public
	# cells only; no hidden occupancy, enemy coordinates or path probe.
	for y in range(Rules.MAP_BORDER,Rules.MAP_LAST_PLAYABLE+1):
		for x in range(Rules.MAP_BORDER,Rules.MAP_LAST_PLAYABLE+1):
			var index=y*Rules.MAP_SIZE+x
			if explored_cells[1][index]!=0 or ai_scout_attempts.has(index): continue
			var candidate=_point(Vector2i(x,y))
			if recover_static and _cell(candidate)==_cell(ent.dest): continue
			var d=ScoutFrontier.score(ent.pos,candidate,own_home,float(Rules.SIGHT.scout))
			if d<distance: point=candidate; distance=d; chosen=index
	if chosen<0: ai_status.scout="no_untried_unknown_cell"; return
	var previous_sequence=command_sequence
	_submit("order",{"ids":[ent.id],"target":-1,"position":point,"ai_scout_explore":true},1)
	if command_sequence==previous_sequence: return
	ai_scout_attempts[chosen]=true
	var tracked=ai_scout_moves.get(ent.id,{}).duplicate(true)
	tracked.pending_sequence=command_sequence; tracked.requested_goal=point; tracked.recover_static=recover_static
	ai_scout_moves[ent.id]=tracked
	ai_status.scout="recovering_static_frontier" if recover_static else "exploring_unknown"

func _ai_move_home(members,castle):
	var ids=[]
	for ent in members:
		if _attack_distance(ent.pos,castle)>3.0 and (ent.state!="move" or ent.dest.distance_to(castle.pos)>6.0): ids.append(ent.id)
	if not ids.is_empty(): _submit("order",{"ids":ids,"target":-1,"position":castle.pos},1)

func _ai_raid_order(ent,records,enemy_keep):
	# Escort combat uses current faction observations, never hidden authority.
	# Siege keeps its strategic objective; other military can clear defenders.
	var defender=RaidTactics.choose(ent,records)
	if not defender.is_empty():
		if ent.state!="attack" or ent.target!=defender.id:
			_submit("order",{"ids":[ent.id],"target":defender.id,"position":defender.pos},1)
		return
	if not enemy_keep.remembered:
		if ent.state!="attack" or ent.target!=enemy_keep.id:
			_submit("order",{"ids":[ent.id],"target":enemy_keep.id,"position":enemy_keep.pos},1)
	elif ent.state=="idle" or (ent.state=="attack" and ent.target!=enemy_keep.id):
		# An expired interception must not keep pursuing an unseen unit while
		# the raid still has a legitimate remembered destination. Ground only.
		if _attack_distance(ent.pos,enemy_keep)>1.1:
			_submit("order",{"ids":[ent.id],"target":-1,"position":enemy_keep.pos},1)
		elif ent.state=="attack": _submit("stop",{"ids":[ent.id]},1)

func _ai_raid_static_blocked(survivors,records):
	# Strategic cohort retirement, not permission to retry a route. Use only
	# current owned request identities and observed attack ranges. New troops
	# must still muster, meet the existing size/cooldown and issue normal orders.
	if survivors.is_empty(): return false
	for ent in survivors:
		if not ent.get("owned",false) or not ent.get("alive",false) or ent.get("remembered",true) or ent.get("team",-1)!=1 or ent.get("category","")!="unit" or ent.get("kind","") not in Rules.UNIT_KINDS or ent.kind=="villager": return false
		if ent.get("state","")!="attack" or ent.get("mode","")!="ATTACK" or ent.get("target",-1)<0: return false
		if ent.get("path_status","")!=BoundedPath.NO_PATH or ent.get("path_reason","")!="frontier_exhausted" or ent.get("path_pending",true) or ent.get("traffic_route",true) or not ent.get("path",[Vector3.INF]).is_empty(): return false
		if ent.get("path_request_kind","")!="point" or ent.get("path_request_state","")!="attack" or ent.get("path_request_target",-1)!=ent.target or ent.get("work_epoch",-1)<0 or ent.get("path_request_epoch",-2)!=ent.work_epoch: return false
		# A newly selected defender/changed objective can legitimately supersede
		# this proof. Do not discard that already-submitted ordinary action.
		for command in commands:
			if command.get("team",-1)==1 and command.get("type","") in ["order","stop","defend","advance","patrol"] and ent.id in command.get("ids",[]): return false
		for target in records:
			if target.get("id",-1)!=ent.target or not target.get("alive",false) or target.get("remembered",true) or target.get("team",-1)!=0 or target.get("category","") not in ["unit","building"]: continue
			# A failed movement route does not prevent legitimate in-range fire.
			if _attack_distance(ent.pos,target)<=Rules.RANGE[ent.kind]: return false
	return true

func _ai_army(records,castle):
	var army=[]; var enemy_keep={}
	for ent in records:
		if ent.owned and ent.alive and ent.category=="unit" and ent.kind!="villager": army.append(ent)
		if ent.team==0 and ent.kind=="town_center" and enemy_keep.is_empty(): enemy_keep=ent
	var threats=HomeDefense.threats(records,AI_HOME_THREAT_DISTANCE)
	var survivors=[]
	for ent in army:
		if ent.id in ai_raid_members: survivors.append(ent)
	if not ai_raid_members.is_empty() and survivors.is_empty(): ai_raid_members.clear(); ai_raid_retreating=false
	# Visible home defense takes priority over an ongoing offensive order.
	if not threats.is_empty():
		ai_control_targets.clear()
		var assignments={}
		for ent in army:
			var threat=HomeDefense.choose(ent,threats)
			if threat.is_empty(): continue
			assignments[ent.id]=threat.id
			if ent.state!="attack" or ent.target!=threat.id: _submit("order",{"ids":[ent.id],"target":threat.id,"position":threat.pos},1)
		ai_home_defense_targets=assignments
		if not ai_raid_members.is_empty(): ai_raid_retreating=true
		ai_status.army="home_defense"; return
	# Cancel only an unchanged defensive target we previously assigned. Once
	# it leaves the observed home threat zone, do not pursue it across the map.
	# Retire via ordinary Stop; the next AI turn resumes existing muster/retreat.
	var released=false
	for ent in army:
		if ai_home_defense_targets.get(ent.id,-1)==ent.get("target",-2) and ent.state=="attack" and ent.get("mode","")=="ATTACK":
			_submit("stop",{"ids":[ent.id]},1); released=true
	ai_home_defense_targets.clear()
	if released:
		ai_status.army="home_defense_released"; return
	if victory_mode=="control":
		_ai_control_point_orders(army,records)
		return
	if not SkirmishPolicy.offensive(skirmish_mode):
		_ai_move_home(army,castle)
		ai_status.army="defensive_practice"; return
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
				elif (ent.state=="attack" and ent.mode=="ATTACK") or (ent.state=="move" and _attack_distance(ent.dest,castle)>3.0):
					# Arrival does not cancel an old outbound command by itself.
					# Retire it through ordinary AI Stop before the next motion
					# phase; preserve bounded automatic combat and homebound moves.
					_submit("stop",{"ids":[ent.id]},1)
			if all_home: ai_raid_members.clear(); ai_raid_retreating=false
			ai_status.army="retreat"; return
		# A remembered keep supports only a ground move, never a hidden target.
		# If observation retires its memory, return instead of using stale truth.
		if enemy_keep.is_empty(): ai_raid_retreating=true; _ai_move_home(survivors,castle); ai_status.army="keep_memory_retired"; return
		for ent in survivors: _ai_raid_order(ent,records,enemy_keep)
		if _ai_raid_static_blocked(survivors,records):
			# Leave every survivor and its search history untouched. A later
			# policy turn may send a fresh normally-mustered cohort instead.
			ai_raid_members.clear(); ai_raid_retreating=false
			ai_status.army="raid_static_frontier_retired"; return
		ai_status.army="raid_active"; return
	# Only a finished scouting unit physically returned to muster can count.
	var mustered=[]
	for ent in army:
		if ent.state=="idle" and _attack_distance(ent.pos,castle)<=3.0: mustered.append(ent)
	if mustered.size()>=SkirmishPolicy.muster(skirmish_mode) and not enemy_keep.is_empty() and tick_count-ai_last_raid_tick>=SkirmishPolicy.interval(skirmish_mode):
		ai_raid_members.clear()
		for ent in mustered: ai_raid_members.append(ent.id)
		ai_raid_departure_count=mustered.size(); ai_raid_keep=enemy_keep.duplicate(true); ai_last_raid_tick=tick_count; ai_raids+=1
		_submit("order",{"ids":ai_raid_members.duplicate(),"target":-1 if enemy_keep.remembered else enemy_keep.id,"position":enemy_keep.pos},1)
		ai_status.army="raid_departure"; return
	for ent in army:
		if ent.kind=="scout" and enemy_keep.is_empty(): _ai_scout(ent)
		else: _ai_move_home([ent],castle)
	ai_status.army="unknown_enemy_keep" if enemy_keep.is_empty() else ("muster_below_five" if mustered.size()<SkirmishPolicy.muster(skirmish_mode) else "raid_cooldown")

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
			for item in ent.queue:
				if not item.get("research",false): reserved+=1
				if item.kind=="villager": queued_workers+=1
			if ent.built: capacity+=10 if ent.kind=="town_center" else (5 if ent.kind=="house" else 0)
			else: sites.append(ent)
		if ent.kind=="villager": workers.append(ent)
	capacity=mini(capacity,Rules.POP_LIMIT)
	_ai_site_cache(sites,workers)
	if castle.is_empty(): ai_status.blocked="no_own_keep"; return
	_ai_army(records,castle)
	if _ai_recover_worker_slot(records,castle,workers.size(),queued_workers,capacity,living+reserved): return
	if _ai_recover_worker_funding(castle,workers.size(),queued_workers,capacity,living+reserved): return
	if not ai_opening_assigned:
		for i in workers.size(): _assign_worker(workers[i],"food" if i<3 else "wood")
		ai_opening_assigned=true
	_ai_keep_repair(records,castle)
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
	var goal=_ai_progression_goal(records,workers.size()+queued_workers,capacity,living+reserved)
	ai_status.progression_goal=goal; ai_status.age=2 if _age2(1) else 1
	if Rules.BUILD_TIME.has(goal):
		if not ai_build_submitted: _ai_build(goal)
	elif goal=="age2":
		if not _research_pending(1) and castle.queue.size()<5 and _ai_can_budget(goal):
			_submit("research",{"building":castle.id},1); _ai_reserve_budget(goal)
	else:
		for building in records:
			if not building.owned or not building.built or goal not in Rules.products_for(building.kind): continue
			if (building.queue.size()<2 or (goal=="villager" and workers.is_empty() and queued_workers==0 and building.kind=="town_center" and building.queue.size()<5)) and capacity-living-reserved>0 and _ai_can_budget(goal):
				_submit("train",{"building":building.id,"kind":goal},1); _ai_reserve_budget(goal)
				break
	_ai_military_research(records,castle,workers.size())
	var desired=_ai_resource_gap(records,workers.size()+queued_workers,capacity,living+reserved)
	# Keep two food gatherers; balance the rest toward the next real paid goal.
	# Reassign one compatible worker per turn, not every worker on every tick.
	var assigned={"food":0,"wood":0,"stone":0,"iron":0}
	for worker in workers:
		var resource=ai_claimed_workers.get(worker.id,worker.get("gather_type",""))
		if worker.state in ["gather","deliver"] or ai_claimed_workers.has(worker.id):
			if assigned.has(resource): assigned[resource]+=1
	for worker in workers:
		if worker.state=="idle" and not ai_claimed_workers.has(worker.id):
			_assign_worker(worker,desired)
	var wanted=mini(3,maxi(1,workers.size()-2)) if desired in ["iron","stone"] else maxi(2,int(workers.size()/2))
	if assigned[desired]<wanted:
		for worker in workers:
			if ai_claimed_workers.has(worker.id) or worker.state not in ["idle","gather"] or worker.get("gather_type","")==desired: continue
			if _ai_food_worker(worker) and _ai_food_count(records)<=2: continue
			if _assign_worker(worker,desired): break

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
	if ent.team==team: return true
	if visible_cells[team].is_empty(): return false
	if visible_cells[team][_cell_index(ent.pos)]!=0: return true
	# Observe actual geometry intersecting current sight. This is NOT a sight
	# extension: entirely hidden objects still contribute nothing to knowledge.
	var cells=_occupied_cells(ent)
	if ent.category=="unit":
		cells=[]
		var radius=ent.get("radius",Rules.UNIT_RADIUS)
		var center=_cell(ent.pos)
		for y in range(center.y-ceili(radius),center.y+ceili(radius)+1):
			for x in range(center.x-ceili(radius),center.x+ceili(radius)+1):
				var c=Vector2i(x,y)
				if _box_distance_squared(ent.pos,c)<radius*radius-0.0000001: cells.append(c)
	for cell in cells:
		if cell.x<0 or cell.y<0 or cell.x>=Rules.MAP_SIZE or cell.y>=Rules.MAP_SIZE: continue
		if visible_cells[team][cell.y*Rules.MAP_SIZE+cell.x]!=0: return true
	return false

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
				record.visual_moving=not ent.path.is_empty() and not ent.get("advance_engaged",false)
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
				record.visual_attack_ready=cue.get("ready_tick",-1)==tick_count and (ent.state=="attack" or (ent.mode in ["ADVANCE","PATROL"] and ent.get("advance_engaged",false))) and not record.visual_moving and ent.cooldown_ticks>0 and ent.cooldown_ticks<=anticipate_ticks and tick_count-record.visual_attack_tick<=Rules.ATTACK_TICKS[ent.kind]
				record.visual_anticipation=1.0-float(ent.cooldown_ticks)/anticipate_ticks
			if record.owned:
				record.last_damage_tick=ent.last_damage_tick
				record.rest_ticks=ent.get("rest_ticks",0)
				record.rally_point=ent.get("rally_point",Vector3.INF)
				record.rally_target=ent.get("rally_target",-1)
				record.rally_mode=ent.get("rally_mode","move")
				record.repeat_kind=ent.get("repeat_kind","")
				record.repeat_generation=ent.get("repeat_generation",0)
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
				if record.kind in MatureVisuals.UNIT_KINDS: character_presenter.present(record,proxy.body,RED if record.team==1 else BLUE,delta,running)
				else: ProgressionVisuals.present(record,proxy.body,RED if record.team==1 else BLUE,delta,running)
			if proxy.remembered!=record.remembered:
				if record.category == "resource":
					preload("res://scripts/remembered_material.gd").apply(proxy.body,record.remembered)
				else:
					_gray_proxy(proxy.body,record.remembered)
				proxy.remembered=record.remembered
			if is_instance_valid(proxy.bar):
				proxy.bar.visible=not record.remembered and record.hp<record.max_hp
				if not record.remembered: proxy.fill.scale.x=_health_bar_fill_scale(record,proxy.bar)
			continue
		ent.node.visible=true; ent.node.position=record.pos
		ent.ring.visible=record.id in selected
		if record.category=="building": ConstructionVisual.apply(ent.body,record.kind,record.built,record.progress)
		if record.category=="unit":
			if record.kind in MatureVisuals.UNIT_KINDS: character_presenter.present(record,ent.body,BLUE if record.team==0 else RED,delta,running)
			else: ProgressionVisuals.present(record,ent.body,BLUE if record.team==0 else RED,delta,running)
		if is_instance_valid(ent.bar):
			ent.bar.visible=record.id in selected or record.hp<record.max_hp
			ent.bar_fill.scale.x=_health_bar_fill_scale(record,ent.bar)

func visual_evidence_snapshot() -> Dictionary:
	# Current visible presentation only, never hidden authority nodes.
	return character_presenter.visual_evidence_snapshot()

func _attack_effect(ent,target):
	if ent.kind not in ["archer","tower"]: return
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
	compact_brand=_label(SkirmishPolicy.title(skirmish_mode),13,GOLD); compact_brand.tooltip_text=Rules.BUILD_ID+" · "+SkirmishPolicy.title(skirmish_mode); compact_top_line.add_child(compact_brand)
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
	touch_button=_button("指定",_toggle_unit_command,54); compact_unit_tools.add_child(touch_button)
	compact_cancel_button=_button("取消",func(): _cancel_mode(),54); compact_unit_tools.add_child(compact_cancel_button)
	objective_button=_button("",_focus_control_point,0); objective_button.name="ControlPointScore"; objective_button.clip_text=true; objective_button.visible=victory_mode=="control"; compact_top_stack.add_child(objective_button)
	compact_menu_dismiss=Control.new(); compact_menu_dismiss.name="MenuDismissShield"; compact_menu_dismiss.mouse_filter=Control.MOUSE_FILTER_STOP; compact_menu_dismiss.gui_input.connect(_dismiss_compact_menu_input); ui.add_child(compact_menu_dismiss); compact_menu_dismiss.hide()
	compact_menu=PanelContainer.new(); compact_menu.name="ShortcutMenu"; ui.add_child(compact_menu); compact_menu.add_theme_stylebox_override("panel",_style(Color("1d241ef5")))
	var menu_scroll=ScrollContainer.new(); menu_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED; menu_scroll.vertical_scroll_mode=ScrollContainer.SCROLL_MODE_AUTO; compact_menu.add_child(menu_scroll)
	var menu_box=VBoxContainer.new(); menu_box.size_flags_horizontal=Control.SIZE_EXPAND_FILL; menu_box.add_theme_constant_override("separation",6); menu_scroll.add_child(menu_box)
	var menu_title=HBoxContainer.new(); menu_box.add_child(menu_title)
	var menu_heading=_label("霧谷王旗 · 快捷選單",17,GOLD); menu_heading.size_flags_horizontal=Control.SIZE_EXPAND_FILL; menu_title.add_child(menu_heading)
	menu_title.add_child(_button("關閉",func(): _toggle_compact_menu(),60))
	attack_alert_button=_button("前往受襲位置",_focus_attack_alert,110); attack_alert_button.name="AttackAlert"; menu_box.add_child(attack_alert_button); attack_alert_button.hide()
	mission_label=_label("",14,Color("c8d4b3")); mission_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; menu_box.add_child(mission_label)
	idle_worker_button=_button("閒置村民 0 · 下一位",_focus_idle_worker,160); idle_worker_button.name="IdleWorkerCycle"; menu_box.add_child(idle_worker_button)
	idle_worker_button.tooltip_text="選取一位閒置村民，不改動任何指令。"
	var nav=HFlowContainer.new(); nav.add_theme_constant_override("h_separation",6); nav.add_theme_constant_override("v_separation",6); menu_box.add_child(nav)
	nav.add_child(_button("主堡",func(): _compact_menu_action(_home),78))
	nav.add_child(_button("全選閒置",func(): _compact_menu_action(func(): _select_group("idle")),96))
	if victory_mode=="control": menu_box.add_child(_button("中央王旗",func(): _compact_menu_action(_focus_control_point),100))
	nav.add_child(_button("全軍",func(): _compact_menu_action(func(): _select_group("army")),78))
	var nav2=HFlowContainer.new(); nav2.add_theme_constant_override("h_separation",6); nav2.add_theme_constant_override("v_separation",6); menu_box.add_child(nav2)
	nav2.add_child(_button("所有村民",func(): _compact_menu_action(func(): _select_group("villagers")),96))
	nav2.add_child(_button("斥候",func(): _compact_menu_action(func(): _select_group("scout")),78))
	nav2.add_child(_button("小地圖",func(): compact_map_choice=0 if minimap.visible else 1; _layout_ui(),84))
	menu_box.add_child(_button("框選單位",func(): _compact_menu_action(_start_box_select),110))
	var squad_help=_label("軍隊編組：先選部隊再存入；重選不會落指令。",13)
	squad_help.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; menu_box.add_child(squad_help)
	for slot in range(SquadSelection.SLOT_COUNT):
		var group_slot=slot
		var row=HBoxContainer.new(); row.add_theme_constant_override("separation",6); menu_box.add_child(row)
		var recall=_button("",func(): _activate_squad(group_slot,false),150)
		recall.size_flags_horizontal=Control.SIZE_EXPAND_FILL; recall.name="RecallSquad%d" % (slot+1); row.add_child(recall)
		var save=_button("存入 %d 隊" % (slot+1),func(): _activate_squad(group_slot,true),100)
		save.name="SaveSquad%d" % (slot+1); row.add_child(save)
		save.tooltip_text="以目前選取的軍隊取代本隊；不含村民，關閉戰役後不保留。"
		squad_buttons.append({"recall":recall,"save":save})
	audio_button=_button("音效：關",_toggle_audio,110); audio_button.name="AudioToggle"; menu_box.add_child(audio_button)
	audio_button.tooltip_text="點按開啟原創提示音；暫停及背景時靜音"
	var nav3=HFlowContainer.new(); nav3.add_theme_constant_override("h_separation",6); nav3.add_theme_constant_override("v_separation",6); menu_box.add_child(nav3)
	nav3.add_child(_button("取消模式",func(): _compact_menu_action(_cancel_mode),100))
	nav3.add_child(_button("移動／攻擊",func(): _compact_menu_action(_start_unit_command),110))
	nav3.add_child(_button("投降",func(): _compact_menu_action(_confirm_surrender),78))
	help_label=_label("",13,Color("c6cbbd")); help_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; menu_box.add_child(help_label)
	menu_box.add_child(_button("主選單", _request_main_menu, 110))
	compact_menu.hide()
	toast_label=_label("",15,GOLD); ui.add_child(toast_label); toast_label.mouse_filter=Control.MOUSE_FILTER_IGNORE
	toast_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	toast_label.add_theme_color_override("font_shadow_color",Color("132823")); toast_label.add_theme_constant_override("shadow_offset_x",1); toast_label.add_theme_constant_override("shadow_offset_y",2)
	toast_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	minimap=load("res://scripts/minimap.gd").new(); minimap.game=self; ui.add_child(minimap)
	drag_rect=ReferenceRect.new(); drag_rect.border_color=GOLD; drag_rect.border_width=1.5; drag_rect.editor_only=false; drag_rect.mouse_filter=Control.MOUSE_FILTER_IGNORE; drag_rect.hide(); ui.add_child(drag_rect)
	end_panel=Panel.new(); end_panel.name="MatchReport"; ui.add_child(end_panel); end_panel.add_theme_stylebox_override("panel",_style(Color("1d241ef5"),GOLD,5))
	end_title=_label("王旗再起",28,GOLD); end_title.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER; end_panel.add_child(end_title)
	end_tabs=HBoxContainer.new(); end_tabs.add_theme_constant_override("separation",6); end_panel.add_child(end_tabs)
	var report_pages=["overview","economy","units","buildings"]
	var report_names=["總覽","經濟","軍隊","建築"]
	for index in report_pages.size():
		var choice=report_pages[index]
		var tab=_button(report_names[index],func(): _show_match_report_page(choice),54)
		tab.set_meta("report_page",choice); tab.size_flags_horizontal=Control.SIZE_EXPAND_FILL; end_tabs.add_child(tab)
	end_scroll=ScrollContainer.new(); end_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED; end_scroll.vertical_scroll_mode=ScrollContainer.SCROLL_MODE_AUTO; end_scroll.mouse_force_pass_scroll_events=false; end_panel.add_child(end_scroll)
	var end_content=VBoxContainer.new(); end_content.size_flags_horizontal=Control.SIZE_EXPAND_FILL; end_content.add_theme_constant_override("separation",12); end_scroll.add_child(end_content)
	end_body=_label("",15); end_body.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; end_content.add_child(end_body)
	end_report_label=_label("",15); end_report_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; end_report_label.add_theme_constant_override("line_spacing",4); end_content.add_child(end_report_label)
	end_actions=HBoxContainer.new(); end_actions.add_theme_constant_override("separation",8); end_panel.add_child(end_actions)
	var restart=_button("再開一局",_request_restart,110); restart.size_flags_horizontal=Control.SIZE_EXPAND_FILL; end_actions.add_child(restart)
	var menu=_button("主選單",_request_main_menu,110); menu.size_flags_horizontal=Control.SIZE_EXPAND_FILL; end_actions.add_child(menu)
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
	touch_points.clear(); touch_world_epochs.clear(); touch_camera_pair.clear()
	all_touch_ids.clear(); gui_touch_press.clear(); action_touch_scroll.clear(); touch_gesture=false
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
	compact_menu_button.text=_shortcut_menu_caption()
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
	_layout_end_report(size)
	_layout_tutorial()

func _selection_stance_summary(selection: Array) -> String:
	# Presentation only: caller supplies sanitized faction records, never entities.
	# Count only applied stances. Queued commands must not look committed early.
	var defending=0
	var stopped=0
	var advancing=0
	var patrolling=0
	var owned_units=0
	for ent in selection:
		if not ent.get("owned",false) or not ent.get("alive",false) or ent.get("category","")!="unit": continue
		owned_units+=1
		if ent.get("mode","")=="DEFEND": defending+=1
		elif ent.get("mode","")=="STOP": stopped+=1
		elif ent.get("mode","")=="ADVANCE": advancing+=1
		elif ent.get("mode","")=="PATROL": patrolling+=1
	if owned_units==1:
		if patrolling==1: return "巡邏"
		return "警戒前進" if advancing==1 else ("守備" if defending==1 else ("停止" if stopped==1 else ""))
	var parts=PackedStringArray()
	if defending>0: parts.append("守備 %d" % defending)
	if stopped>0: parts.append("停止 %d" % stopped)
	if advancing>0: parts.append("警戒前進 %d" % advancing)
	if patrolling>0: parts.append("巡邏 %d" % patrolling)
	return " · ".join(parts)

func _rally_detail(record):
	if record.get("rally_point",Vector3.INF)==Vector3.INF: return " · 可設定新單位集合點"
	if record.get("rally_mode","move")=="advance": return " · 警戒集合點，新軍隊警戒前進"
	return " · 採集集合點，新村民自動採集" if record.get("rally_target",-1)>=0 else " · 集合點已設定，新單位自動移動"

func _update_hud():
	if not is_instance_valid(top_resources): return
	_refresh_control_point_marker()
	_refresh_idle_worker_button()
	_refresh_attack_alert()
	_refresh_squad_buttons()
	_refresh_tutorial()
	if game_over:
		compact_menu.hide(); compact_menu_dismiss.hide()
	var display_bank=economy.bank_units_floor(0)
	top_resources.text="食 %d  木 %d  石 %d  鐵 %d  人口 %d/%d" % [display_bank.food,display_bank.wood,display_bank.stone,display_bank.iron,_population(0),_capacity(0)]
	if compact_ui and get_viewport().get_visible_rect().size.x<480:
		top_resources.text="食 %d  木 %d  人口 %d/%d\n石 %d  鐵 %d  %s" % [display_bank.food,display_bank.wood,_population(0),_capacity(0),display_bank.stone,display_bank.iron,"城防時代" if _age2(0) else "聚落時代"]
	time_label.text="%02d:%02d" % [floori(game_time/60),int(game_time)%60]
	time_label.tooltip_text=SkirmishPolicy.title(skirmish_mode)
	pause_button.text="繼續" if paused else "暫停"
	mission_label.text=("城防時代：建馬廄出騎兵，建工坊出攻城車，摧毀敵方主堡。" if _age2(0) else "聚落時代：採鐵，於主堡研究城防時代，解鎖騎兵與攻城車。")
	if completed_builds[0]==0: mission_label.text="首要任務：採集資源，再建民居與兵營。"
	if delivered_total[0]==0: mission_label.text="首要任務：選取村民，向漿果或樹木落指令。"
	if victory_mode=="control": mission_label.text=control_point.caption()
	if game_time>=Rules.TIME_LIMIT-60 and not game_over: mission_label.text="尚餘 %d 秒到達對局上限，屆時和局。" % ceili(Rules.TIME_LIMIT-game_time)
	if game_time>=Rules.TIME_LIMIT-60 and not game_over: time_label.text+=" · 和局 %ds" % ceili(Rules.TIME_LIMIT-game_time)
	touch_button.text=("巡邏中" if unit_command_kind=="patrol" else ("前進中" if unit_command_kind=="advance" else "指定中")) if touch_command else "指定"
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
		if ent.owned and _military_attack_bonus(ent.kind,0)>0: selection_detail.text+=" · 軍備攻擊 +%d" % _military_attack_bonus(ent.kind,0)
		var rest_label=RestRecovery.label(ent)
		if not rest_label.is_empty(): selection_detail.text+=" · "+rest_label
		if ent.kind=="town_center": selection_detail.text+=" · 步兵／弓手／騎兵在堡旁安全待命 10 秒後，每 2 秒回 1 生命"
		if worker_evacuations.has(ent.id): selection_detail.text+=" · "+_worker_safety_label(ent)
		if ent.kind=="farm" and ent.built: selection_detail.text+=" · 選村民後點農田耕作，每田一人"
		if ent.kind=="villager" and ent.cargo_milli>0: selection_detail.text+="   負重 %d / 10" % floori(ent.cargo_milli/1000.0)
		if ent.built and Rules.PRODUCES.has(ent.kind):
			selection_detail.text+=_rally_detail(ent)
			if not ent.get("repeat_kind","").is_empty(): selection_detail.text+=" · 自動訓練每次 "+Rules.cost_label(ent.repeat_kind)+"；資源或人口不足會等待。關閉保留隊列，取消訓練會關閉。"
		if not ent.built: selection_detail.text=ConstructionStatus.detail(ent,faction_views[0].records(),own_command_pending,paused)
		if not ent.queue.is_empty():
			queue_label.text="%s %ds · 隊列 %d" % [Rules.NAMES[ent.queue[0].kind],ceili(ent.queue[0].remaining_ticks/20.0),ent.queue.size()]
			if ent.queue[0].remaining_ticks<=0:
				queue_label.text="訓練完成，等待人口空位" if _population(0,false)>=_capacity(0) else "訓練完成，出口受阻；選取出口單位，再點空地移開"
			elif not ent.queue[0].get("research",false) and _population(0)>_capacity(0): queue_label.text="缺少住房，訓練暫停"
	else:
		selection_title.text="已選取 %d 個單位" % selection.size()
		selection_detail.text=("%d 村民無已知採集點" % missing_workers) if missing_workers>0 else "向資源、空地或可見敵軍落指令。"
		if route_failed_workers>0:
			selection_detail.text=(selection_detail.text+" · " if missing_workers>0 else "")+("%d 村民工作路線停止" % route_failed_workers)
	var stance_summary=_selection_stance_summary(selection)
	if not stance_summary.is_empty(): selection_detail.text+=" · "+stance_summary
	var key=str(worker_safety_enabled)+":"+str(military_tech_completed[0])+":"+str(_age2(0))+":"+str(_research_pending(0))+":"+str(selected)+":"+build_mode+":"+str(compact_ui)+":"+str(short_ui)+":"+str(box_select_mode)+":"+str(rally_building)
	if selection.size()==1: key+=":"+str(selection[0].built)+":"+_queue_action_identity(selection[0])+":"+str(selection[0].get("rally_point",Vector3.INF))+":"+str(selection[0].get("rally_target",-1))+":"+str(selection[0].get("rally_mode","move"))+":"+str(selection[0].get("repeat_kind",""))+":"+str(selection[0].get("repeat_generation",0))
	if key!=action_key: action_key=key; _rebuild_actions(selection)
	_refresh_return_cargo_button()
	_refresh_queue_actions()
	_refresh_repeat_train_button()
	queue_label.visible=not queue_label.text.is_empty()
	var has_unit=false
	for ent in selection:
		if ent.category=="unit": has_unit=true
	compact_unit_tools.visible=has_unit and build_mode.is_empty() and not box_select_mode
	compact_cancel_button.visible=touch_command
	_refresh_stop_button()
	# One guidance suffix. Eligibility belongs to each worker, not merely to
	# another selected worker making the delivery button available.
	var idle_return_available=false
	if compact_ui and not paused and not game_over:
		for order in ReturnCargoAction.orders(faction_views[0].records(),selected,commands):
			var worker=faction_views[0].get_record(order.ids[0])
			if worker.get("state","")=="idle": idle_return_available=true; break
	if build_mode.is_empty() and not box_select_mode and rally_building<0:
		if touch_command:
			if has_unit and compact_ui: selection_detail.text="點資源採集或點農田耕作，點空地移動；取消可返回選取。"
		elif idle_return_available:
			selection_detail.text+=" · 滑動底列，按交付資源"
		elif missing_workers>0:
			selection_detail.text+=" · 探索或落指令"
		elif route_failed_workers>0:
			selection_detail.text+=" · 請重新落指令"
		elif has_unit and compact_ui:
			selection_detail.text+=" · 點空地移動／敵軍攻擊／資源採集"
	if build_mode.is_empty():
		help_label.text="點選單位，再點空地移動、敵軍攻擊或資源採集。單指按住再拖曳框選；雙指拖曳平移、張合縮放。窄畫面可左右滑動底列，查看全部行動。" if compact_ui else "左鍵選取／框選，再點目標落指令 · 右鍵亦可落指令 · WASD／方向鍵平移 · 滾輪縮放 · 空白鍵返回主堡"
		if touch_command: help_label.text="指定目標：點擊地面、資源或可見敵軍；一般移動和攻擊毋須按此鈕。"
	else:
		var reason=_placement_reason(build_mode,pointer_world,0,_selected_builder())
		help_label.text=("位置已選，按確認建造；點空地可重選。" if build_preview_held else "點選空地作預覽，再按確認建造。") if reason.is_empty() else "不可建造："+reason
		if Rules.PRODUCES.has(build_mode): selection_detail.text="生產建築需鄰接淺色保護通道；通道上不可建造。"
		if is_instance_valid(build_confirm): build_confirm.disabled=not reason.is_empty() or paused or not build_preview_held
		selection_title.text="建造 "+Rules.NAMES.get(build_mode,build_mode)
		selection_detail.text=help_label.text
		queue_label.text=Rules.cost_label(build_mode)+(" · 資源不足" if not _can_pay(COSTS[build_mode],0) else ""); queue_label.show()
	if rally_building>=0:
		selection_detail.text="警戒集合點：點可見空地；新軍隊射程內迎擊，敵軍離開後繼續前進，不追擊。" if rally_mode=="advance" else "點可見空地設定集合點；主堡亦可點資源，讓新村民自動採集。"
		help_label.text=selection_detail.text
	if touch_command and unit_command_kind=="advance":
		selection_detail.text=("分散" if advance_formation=="spread" else "橫列")+"前進：點目的地，近戰在前、遠程在後；地形會調整落點。" if advance_formation!="" else "警戒前進：點目的地；射程內迎擊，敵軍離開後繼續，不追擊。"
		help_label.text=selection_detail.text
	if touch_command and unit_command_kind=="patrol":
		selection_detail.text="巡邏：點另一端，在原位與目的地來回；射程內迎擊，不追擊。停止或新指令可結束。"
		help_label.text=selection_detail.text
	if box_select_mode:
		selection_title.text="框選單位"
		selection_detail.text="在戰場按住移動，選取框內單位；取消可返回選取。"
		queue_label.hide()
		help_label.text=selection_detail.text
	call_deferred("_layout_ui")

func _rebuild_actions(selection):
	# Stop may occupy the auxiliary slot outside the action strip. Recreate it
	# with the selection so a held press cannot act on a replacement selection.
	if is_instance_valid(stop_button):
		stop_button.get_parent().remove_child(stop_button); stop_button.queue_free()
	stop_button=null
	for child in actions.get_children(): actions.remove_child(child); child.queue_free()
	build_confirm=null
	return_cargo_button=null
	queue_actions.clear()
	repeat_train_button=null
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
		for kind in Rules.BUILDABLE_KINDS:
			var choice=kind
			var button=_button(Rules.NAMES[kind]+"\n"+Rules.cost_label(kind)+( "\n建成後自動耕作" if kind=="farm" else "")+( "\n需城防時代" if not _kind_unlocked(kind,0) else ""),func(): _start_build(choice),100)
			button.disabled=not _kind_unlocked(kind,0); actions.add_child(button)
	elif selection.size()==1:
		var ent=selection[0]
		if not ent.built:
			actions.add_child(_button("取消施工\n退回 75%",func(): _submit("cancel_build",{"building":ent.id}),130))
		elif Rules.PRODUCES.has(ent.kind):
			actions.add_child(_button("集合點",func(): _start_ground_rally(ent.id),100))
			if "villager" not in Rules.products_for(ent.kind):
				actions.add_child(_button("警戒集合點",func(): _start_ground_rally(ent.id,"advance"),120))
			if ent.get("rally_point",Vector3.INF)!=Vector3.INF:
				actions.add_child(_button("取消集合點設定",func(): _submit("rally",{"building":ent.id,"clear":true}),120))
			for kind in Rules.products_for(ent.kind):
				var choice=kind
				actions.add_child(_button("訓練"+Rules.NAMES[kind]+"\n"+Rules.cost_label(kind),func(): _submit("train",{"building":ent.id,"kind":choice}),120))
			if "villager" not in Rules.products_for(ent.kind):
				var repeat_product=Rules.PRODUCES[ent.kind]
				var repeat_generation=ent.get("repeat_generation",0)
				var repeat_next=repeat_product if ent.get("repeat_kind","").is_empty() else ""
				repeat_train_button=_button(("自動訓練"+Rules.NAMES[repeat_product]+"\n每次 "+Rules.cost_label(repeat_product)) if repeat_next!="" else "關閉自動訓練\n保留已付款隊列",func(): _repeat_train_request(ent.id,repeat_generation,repeat_next),160)
				repeat_train_button.name="RepeatTraining"; repeat_train_button.set_meta("building",ent.id); repeat_train_button.set_meta("generation",repeat_generation)
				actions.add_child(repeat_train_button)
			if ent.kind=="town_center":
				var safety=_button("村民自動避難："+("開" if worker_safety_enabled else "關"),_toggle_worker_safety,200)
				safety.tooltip_text="採集村民受可見敵人襲擊時撤向附近安全主堡／守望塔；原工作區重新可見且連續安全五秒後回工。新指令優先。"
				safety.name="WorkerSafety"; actions.add_child(safety)
			if ent.kind=="town_center" and not _age2(0):
				var research=_button("城防時代\n"+Rules.cost_label("age2"),func(): _submit("research",{"building":ent.id}),160)
				research.disabled=_research_pending(0); actions.add_child(research)
			if ent.kind=="town_center" and _age2(0):
				for technology in Rules.MILITARY_TECHS:
					var tech=technology
					var completed=military_tech_completed[0].has(tech)
					var pending=_military_research_pending(tech,0)
					var label=Rules.NAMES[tech]+(" · 已完成" if completed else (" · 研究中" if pending else " · 45 秒"))+"\n"+Rules.TECH_DETAILS[tech]
					if not completed and not pending: label+="\n"+Rules.cost_label(tech)
					var button=_button(label,func(): _submit("military_research",{"building":ent.id,"kind":tech}),200)
					button.disabled=completed or pending; button.name=tech; actions.add_child(button)
			for item in ent.queue:
				var queue_id=item.queue_id
				var cancel=_button("",func(): _queue_cancel_request(ent.id,queue_id),220 if item.kind=="age2" else 150)
				cancel.name="CancelQueue%d" % queue_id
				actions.add_child(cancel); queue_actions.append({"building":ent.id,"queue_id":queue_id,"button":cancel})
		if ent.owned and ent.category=="building" and ent.built and ent.kind!="town_center":
			actions.add_child(_button("拆除建築\n不退資源",func(): _confirm_demolish(ent.id),120))
	# Preserve the first build targets on narrow phones. Cargo delivery is
	# reachable through the existing horizontal action strip.
	actions.add_child(_button("取消選取",func(): _select([]),100))
	return_cargo_button=_button("交付資源",_return_selected_cargo,100)
	actions.add_child(return_cargo_button)
	if _has_selected_military():
		actions.add_child(_button("警戒前進",_start_advance_command,100))
		actions.add_child(_button("橫列前進",func(): _start_formation_command("line"),100))
		actions.add_child(_button("分散前進",func(): _start_formation_command("spread"),100))
		actions.add_child(_button("巡邏",_start_patrol_command,100))
	# Stop shares Cancel's unused compact slot; never add a third pinned target.
	# During targeting it stays in the strip, preserving the ordinary Cancel.
	for ent in selection:
		if ent.category=="unit":
			stop_button=_button("停止",func(): _submit_selected_stance("stop"),54)
			actions.add_child(stop_button)
			actions.add_child(_button("守備",func(): _submit_selected_stance("defend"),54))
			break

func _refresh_repeat_train_button():
	if not is_instance_valid(repeat_train_button): return
	var building=repeat_train_button.get_meta("building",-1)
	var record=_queue_selected_record(building)
	var blocked=paused or game_over or not application_focused or application_suspended or record.is_empty() or record.get("repeat_generation",0)!=repeat_train_button.get_meta("generation",-1) or _repeat_training_pending(building,0)
	if repeat_train_button.get_meta("blocked",true)!=blocked:
		for index in gui_touch_press.keys():
			if gui_touch_press[index].button.get_ref()==repeat_train_button: gui_touch_press.erase(index)
		if repeat_train_button.button_pressed: repeat_train_button.disabled=true; repeat_train_button.disabled=false
		repeat_train_button.set_meta("blocked",blocked)
	repeat_train_button.disabled=blocked

func _repeat_train_request(building,generation,kind):
	if paused or game_over or not application_focused or application_suspended: return
	var record=_queue_selected_record(building)
	if record.is_empty() or record.get("repeat_generation",0)!=generation or _repeat_training_pending(building,0): return
	if not is_instance_valid(repeat_train_button) or repeat_train_button.disabled or repeat_train_button.get_meta("building",-1)!=building or repeat_train_button.get_meta("generation",-1)!=generation: return
	_cancel_mode()
	_submit("repeat_train",{"building":building,"kind":kind},0)
	_refresh_repeat_train_button()

func _queue_action_identity(record):
	var ids=[]
	for item in record.queue: ids.append(item.queue_id)
	return str(ids)

func _queue_selected_record(building):
	if selected.size()!=1 or selected[0]!=building: return {}
	var record=faction_views[0].get_record(building)
	if not record.get("owned",false) or not record.get("alive",false) or record.get("remembered",false) or record.get("team",-1)!=0 or record.get("category","")!="building" or not record.get("built",false): return {}
	return record

func _queue_item(record,queue_id):
	for item in record.get("queue",[]):
		if item.queue_id==queue_id: return item
	return {}

func _queue_cancel_pending(building,queue_id):
	for command in commands:
		if command.get("team",-1)==0 and command.get("type","")=="cancel_queue_item" and command.get("building",-1)==building and command.get("queue_id",-1)==queue_id: return true
	return false

func _queue_refund_text(refund):
	var parts=PackedStringArray()
	for resource in Economy.FOUR_RESOURCE_TYPES:
		if refund.get(resource,0)>0: parts.append(Rules.RESOURCE_NAMES[resource]+" "+str(floori(refund[resource]/float(Economy.SCALE))))
	return "不退資源" if parts.is_empty() else "退回 "+"  ".join(parts)

func _refresh_queue_actions():
	for action in queue_actions:
		var button=action.button
		if not is_instance_valid(button): continue
		var record=_queue_selected_record(action.building)
		var order=_queue_item(record,action.queue_id)
		var refund={} if order.is_empty() else economy.quote_refund(order.get("receipt_id",""),0)
		var blocked=paused or game_over or not application_focused or application_suspended or order.is_empty() or _queue_cancel_pending(action.building,action.queue_id)
		if button.get_meta("queue_refund",{})!=refund or button.get_meta("queue_blocked",true)!=blocked:
			for index in gui_touch_press.keys():
				if gui_touch_press[index].button.get_ref()==button: gui_touch_press.erase(index)
			if button.button_pressed:
				button.disabled=true; button.disabled=false
			button.set_meta("queue_refund",refund.duplicate(true)); button.set_meta("queue_blocked",blocked)
		button.disabled=blocked
		if not order.is_empty():
			var remaining=" · %ds" % ceili(order.remaining_ticks/20.0) if order.get("started",false) and order.remaining_ticks>0 else ""
			button.text="取消"+Rules.NAMES.get(order.kind,order.kind)+remaining+"\n"+_queue_refund_text(refund)

func _queue_cancel_request(building,queue_id):
	if paused or game_over or not application_focused or application_suspended: return
	var record=_queue_selected_record(building)
	var order=_queue_item(record,queue_id)
	if order.is_empty() or _queue_cancel_pending(building,queue_id): return
	for action in queue_actions:
		if action.building!=building or action.queue_id!=queue_id: continue
		var button=action.button
		if not is_instance_valid(button) or button.disabled: return
		var refund=economy.quote_refund(order.get("receipt_id",""),0)
		if button.get_meta("queue_refund",{})!=refund:
			_refresh_queue_actions(); return
		_cancel_mode()
		_submit("cancel_queue_item",{"building":building,"queue_id":queue_id,"expected_refund":refund},0)
		_refresh_queue_actions()
		return

func _refresh_stop_button():
	if not is_instance_valid(stop_button): return
	var parent=compact_unit_tools if compact_ui and not touch_command else actions
	if stop_button.get_parent()!=parent:
		# A moving control cannot inherit a press from its old coordinates.
		for index in gui_touch_press.keys():
			if gui_touch_press[index].button.get_ref()==stop_button: gui_touch_press.erase(index)
		if stop_button.button_pressed: stop_button.disabled=true; stop_button.disabled=false
		stop_button.reparent(parent)
		# Keep desktop/targeting action order unchanged: Cargo, Stop, Defend.
		if parent==actions: actions.move_child(stop_button,actions.get_child_count()-2)
	stop_button.disabled=paused or game_over

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

func _has_selected_military():
	for id in selected:
		var record=faction_views[0].get_record(id)
		if record.get("owned",false) and record.get("alive",false) and record.get("team",-1)==0 and record.get("category","")=="unit" and record.get("kind","") in Rules.UNIT_KINDS and record.kind!="villager" and not record.get("remembered",false): return true
	return false

func _start_patrol_command():
	if paused or game_over or not application_focused or application_suspended or not _has_selected_military(): return
	_cancel_mode()
	unit_command_kind="patrol"; touch_command=true
	_update_hud()
	_message("巡邏：點另一端，在原位與目的地來回；射程內迎擊，不追擊。停止或新指令可結束。",6)

func _start_advance_command():
	if paused or game_over or not _has_selected_military(): return
	_cancel_mode()
	unit_command_kind="advance"; touch_command=true
	_update_hud()
	_message("警戒前進：點目的地；射程內迎擊，敵軍離開後繼續，不追擊。",6)

func _start_formation_command(style):
	if style not in ArmyFormation.TYPES or paused or game_over or not _has_selected_military(): return
	_start_advance_command()
	advance_formation=style
	_update_hud()
	_message("點目的地：近戰前排、弓手與攻城器後排；沿途警戒迎擊。地形會調整落點，不保證行軍時保持陣形。",7)

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
	_message("點資源採集或點農田耕作，點空地移動；取消可返回選取。",5)

func _toggle_unit_command():
	if touch_command:
		_cancel_mode()
		_message("已取消指令。",5)
	else:
		_start_unit_command()

func _submit_selected_stance(type: String):
	# A deliberate Stop/Defend replaces the unfinished targeting interaction.
	# Retire held pointers too, so their late release cannot issue a new order.
	if not paused and not game_over and build_mode.is_empty() and not box_select_mode and rally_building<0:
		if touch_command: _cancel_mode()
		else:
			# Ordinary contextual Stop still retires unfinished world/UI presses,
			# but has no mode to cancel. Keep its live HUD control for repeat taps.
			_cancel_pointer_streams()
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
	# A selection replacement retires any held world/UI press. Its release
	# must never order the newly selected group.
	_cancel_pointer_streams()
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

func _touch_hold_clock():
	return Time.get_ticks_msec()

func _clear_touch_hold():
	if not touch_hold.is_empty(): _restore_box_input_accumulation()
	touch_hold.clear()
	if touch_box_automatic:
		touch_box_index=-1; touch_box_active=false
		if is_instance_valid(drag_rect): drag_rect.hide()
	touch_box_automatic=false

func _clear_box_select():
	_clear_touch_hold()
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
	_cover_camera_ground()

func _cover_camera_ground():
	# Extend only the public visual surface, never playable cells or camera limits.
	# Ground shader uses world coordinates, so scaling does not stretch its detail.
	if not is_instance_valid(camera_ground): return
	var viewport_size=get_viewport().get_visible_rect().size
	if not viewport_size.is_finite() or viewport_size.x<=0.0 or viewport_size.y<=0.0: return
	var half_size=(camera_ground.mesh as PlaneMesh).size*0.5
	var required=half_size
	for screen in [Vector2.ZERO,Vector2(viewport_size.x,0),viewport_size,Vector2(0,viewport_size.y)]:
		var origin=camera.project_ray_origin(screen)
		var direction=camera.project_ray_normal(screen)
		if absf(direction.y)<0.0001: continue
		var point=origin+direction*((camera_ground.position.y-origin.y)/direction.y)
		required.x=maxf(required.x,absf(point.x)+1.0)
		required.y=maxf(required.y,absf(point.z)+1.0)
	camera_ground.scale=Vector3(required.x/half_size.x,1.0,required.y/half_size.y)

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

func _start_ground_rally(id,mode="move"):
	if paused or game_over: return
	var record=faction_views[0].get_record(id)
	if record.is_empty() or not record.owned or not record.alive or not record.built or not Rules.PRODUCES.has(record.kind): return
	if mode not in ["move","advance"] or (mode=="advance" and "villager" in Rules.products_for(record.kind)): return
	_cancel_mode()
	rally_building=id; rally_mode=mode; touch_command=true; action_key=""; _update_hud()

func _send_world_order(screen,contextual=false):
	if rally_building>=0:
		var rally_order={"building":rally_building,"position":_world_at(screen),"mode":rally_mode}
		var rally_record=faction_views[0].get_record(_pick(screen))
		var rally_producer=faction_views[0].get_record(rally_building)
		if rally_mode=="move" and "villager" in Rules.products_for(rally_producer.get("kind","")) and rally_record.get("category","")=="resource" and rally_record.get("alive",false) and not rally_record.get("remembered",false): rally_order.target=rally_record.id
		_submit("rally",rally_order)
		_cancel_mode(); return

	if touch_command and unit_command_kind in ["advance","patrol"]:
		var destination=_world_at(screen)
		var payload={"ids":selected.duplicate(),"position":destination}
		if unit_command_kind=="advance" and advance_formation!="": payload.formation=advance_formation
		_submit(unit_command_kind,payload)
		_cancel_mode()
		order_marker.position=destination; marker_time=0.8
		return
	if selected.is_empty(): return
	var p=_world_at(screen)
	var target_id=_pick(screen)
	var ids=selected.duplicate()
	var tapped=faction_views[0].get_record(target_id)
	if contextual and (tapped.get("category","")=="resource" or (tapped.get("kind","")=="farm" and tapped.get("owned",false))):
		# Resource taps task capable workers only; escorts keep their orders.
		ids=ids.filter(func(id):
			var record=faction_views[0].get_record(id)
			return record.get("owned",false) and record.get("alive",false) and record.get("team",-1)==0 and record.get("category","")=="unit" and record.get("kind","")=="villager" and not record.get("remembered",false))
		if ids.is_empty(): return
	var order={"ids":ids,"target":target_id,"position":p}
	if contextual and tapped.get("owned",false) and tapped.get("alive",false) and not tapped.get("remembered",false) and tapped.get("kind","")=="farm" and tapped.get("built",false):
		order.farm_gather=true
	_submit("order",order)
	order_marker.position=p; marker_time=0.8; touch_command=false; rally_building=-1

func _tap(screen,is_touch):
	# Primary click and touch share contextual orders at every viewport size.
	# Do not depend on a browser correctly reporting touch capabilities.
	var contextual_pointer=true
	if game_over: return
	pointer_screen=screen; pointer_world=_point(_cell(_world_at(screen)))
	if box_select_mode: return # A tap is not a completed box-selection drag.
	if not paused and not build_mode.is_empty():
		# UX01: both mouse and touch choose a site; only Confirm submits the build.
		build_preview_held=true; _update_hud()
		return
	if not paused and touch_command:
		_send_world_order(screen); return
	var id=_pick(screen,contextual_pointer)
	var tapped=faction_views[0].get_record(id)
	if contextual_pointer and not paused and tapped.get("owned",false) and tapped.get("kind","")=="farm" and tapped.get("built",false) and _selected_builder()>=0:
		_send_world_order(screen,true); _update_hud(); return
	if id>=0 and faction_views[0].get_record(id).team==0:
		if Input.is_physical_key_pressed(KEY_SHIFT) and not is_touch:
			var ids=selected.duplicate()
			if id in ids: ids.erase(id)
			else: ids.append(id)
			_select(ids)
		else: _select([id])
	elif contextual_pointer and not selected.is_empty():
		# Normal touch is contextual. Friendly taps above select; explicit
		# targeting remains available for repair/delivery to friendly buildings.
		# Use the ordinary order path: authority resolves each unit's capability.
		if not paused and build_mode.is_empty() and _has_selected_unit():
			_send_world_order(screen,true)
		_update_hud()
	else: _select([])

func _has_selected_unit():
	for id in selected:
		var record=faction_views[0].get_record(id)
		if record.get("owned",false) and record.get("alive",false) and record.get("team",-1)==0 and record.get("category","")=="unit" and not record.get("remembered",false): return true
	return false

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
	if box_select_mode or not touch_hold.is_empty() or touch_box_automatic:
		var outside_touch=(event is InputEventScreenDrag or (event is InputEventScreenTouch and not event.pressed)) and (event.index==touch_box_index or event.index==touch_hold.get("index",-1)) and not _box_point_in_world(event.position)
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
				_clear_touch_hold()
				if box_select_mode: _clear_box_select(); call_deferred("_update_hud")
				touch_gesture=true; touch_command=false; rally_building=-1
				for key in gui_touch_press: gui_touch_press[key].valid=false
		else:
			if event.canceled:
				_clear_touch_hold()
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
			var report_scroll=game_over and end_panel.visible
			var scroll_control=end_scroll if report_scroll else (compact_menu.get_child(0) if compact_menu.visible else action_scroll)
			var horizontal=not report_scroll and not compact_menu.visible
			if is_instance_valid(scroll_control) and scroll_control.is_visible_in_tree() and scroll_control.get_global_rect().has_point(event.position) and (not game_over or report_scroll):
				var bar=scroll_control.get_h_scroll_bar() if horizontal else scroll_control.get_v_scroll_bar()
				if bar.max_value>bar.page:
					action_touch_scroll[event.index]={"control":weakref(scroll_control),"horizontal":horizontal,"origin":event.position,"offset":scroll_control.scroll_horizontal if horizontal else scroll_control.scroll_vertical,"active":false}
		else:
			var scroll=action_touch_scroll.get(event.index,{})
			action_touch_scroll.erase(event.index)
			if not scroll.is_empty() and scroll.active:
				gui_touch_press.erase(event.index)
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

func _sync_touch_camera_pair():
	# A GUI press may reuse an ID before deferred cleanup removes its old
	# world point. Pair only still-held, same-lifetime WORLD presses.
	var ids=[]
	for index in touch_points:
		if index not in all_touch_ids or touch_world_epochs.get(index,-1)!=touch_press_epochs.get(index,-2): continue
		ids.append(index)
	var pair=[]
	if ids.size()>=2:
		for index in [ids[0],ids[1]]: pair.append([index,touch_world_epochs[index]])
	if pair!=touch_camera_pair:
		touch_camera_pair=pair
		if pair.size()==2:
			# Called before the next drag replaces its stored position.
			var first=touch_points[ids[0]]; var second=touch_points[ids[1]]
			touch_previous_center=(first+second)*0.5
			touch_previous_distance=first.distance_to(second)
	return ids

func _cleanup_touch_release(index,press_epoch):
	if touch_press_epochs.get(index,-1)!=press_epoch: return
	# A release consumed by HUD must not complete or retain a world rectangle.
	if touch_box_index==index:
		_clear_box_select(); _update_hud()
	if touch_hold.get("index",-1)==index: _clear_touch_hold()
	touch_points.erase(index); touch_world_epochs.erase(index)
	_sync_touch_camera_pair()
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
			touch_world_epochs[event.index]=touch_press_epochs.get(event.index,-1)
			var active_world_ids=_sync_touch_camera_pair()
			if active_world_ids.size()==1:
				touch_origin=event.position; touch_gesture=all_touch_ids.size()>1
				if box_select_mode and not touch_gesture and not game_over:
					touch_box_index=event.index; touch_box_origin=event.position; touch_box_active=false
				elif not touch_gesture and not game_over and build_mode.is_empty() and not touch_command and rally_building<0:
					box_previous_input_accumulation=Input.use_accumulated_input
					box_input_accumulation_owned=true
					Input.use_accumulated_input=false
					touch_hold={"index":event.index,"epoch":touch_press_epochs.get(event.index,-1),"started":_touch_hold_clock(),"origin":event.position}
			if active_world_ids.size()>=2:
				touch_gesture=true; touch_command=false; rally_building=-1
		else:
			if (box_select_mode or touch_box_automatic) and touch_box_index==event.index:
				var complete=touch_box_active and not touch_gesture and not event.canceled and touch_points.has(event.index) and not game_over
				var rectangle=Rect2(touch_box_origin,event.position-touch_box_origin).abs()
				if touch_box_automatic and not rectangle.has_area(): complete=false
				touch_box_index=-1; touch_box_active=false; drag_rect.hide(); touch_points.erase(event.index); touch_world_epochs.erase(event.index)
				_clear_touch_hold()
				if complete: _select(_box_selection_ids(rectangle))
				return
			var held=touch_hold.get("index",-1)==event.index and _touch_hold_clock()-touch_hold.get("started",0)>=TOUCH_HOLD_MSEC
			var should_tap=not held and not event.canceled and touch_points.has(event.index) and touch_points.size()==1 and not touch_gesture and event.position.distance_to(touch_origin)<14
			touch_points.erase(event.index); touch_world_epochs.erase(event.index)
			_sync_touch_camera_pair()
			if touch_hold.get("index",-1)==event.index: _clear_touch_hold()
			if should_tap: _tap(event.position,true)
			if touch_points.is_empty(): touch_gesture=false
	if event is InputEventScreenDrag:
		var active_world_ids=_sync_touch_camera_pair()
		if event.index not in active_world_ids: return
		touch_points[event.index]=event.position
		if active_world_ids.size()>=2:
			var first=touch_points[active_world_ids[0]]; var second=touch_points[active_world_ids[1]]
			var center=(first+second)*0.5; var distance=first.distance_to(second)
			_pan_camera(touch_previous_center-center)
			if touch_previous_distance>0: camera_zoom=clampf(camera_zoom*touch_previous_distance/maxf(1,distance),15,46)
			touch_previous_center=center; touch_previous_distance=distance
		elif (box_select_mode or touch_box_automatic) and touch_box_index==event.index:
			if event.position.distance_to(touch_box_origin)>=14: touch_box_active=true
			if touch_box_active:
				var rect=Rect2(touch_box_origin,event.position-touch_box_origin).abs()
				drag_rect.position=rect.position; drag_rect.size=rect.size; drag_rect.show()
		# A multi-finger gesture remains quarantined until all fingers release.
		elif not build_mode.is_empty() and not touch_gesture:
			pointer_world=_point(_cell(_world_at(event.position))); build_preview_held=true
		elif not touch_gesture and touch_hold.get("index",-1)==event.index and touch_hold.get("epoch",-1)==touch_press_epochs.get(event.index,-2):
			var distance=event.position.distance_to(touch_hold.origin)
			if _touch_hold_clock()-touch_hold.started>=TOUCH_HOLD_MSEC:
				if distance>=14:
					touch_box_automatic=true; touch_box_index=event.index; touch_box_origin=touch_hold.origin; touch_box_active=true
					var rect=Rect2(touch_box_origin,event.position-touch_box_origin).abs()
					drag_rect.position=rect.position; drag_rect.size=rect.size; drag_rect.show()
			elif distance>=14:
				_clear_touch_hold(); touch_gesture=true
		elif touch_gesture or event.position.distance_to(touch_origin)>=14:
			# Single-finger movement never pans or becomes a late tap/order.
			touch_gesture=true; touch_command=false; rally_building=-1

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
	var site_clear=_placement_reason(build_mode,pointer_world,0,_selected_builder(),false).is_empty()
	ghost.get_child(0).material_override=_material(Color("92d389") if placement_ok else (Color("e4bc68") if site_clear else Color("d97c65")))
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
	build_mode=""; build_preview_held=false; touch_command=false; unit_command_kind="order"; advance_formation=""; rally_building=-1; rally_mode="move"
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
	if not qa_mode: return
	var state=_snapshot()
	state.audio=audio_cues.qa_status()
	state.hud=_qa_hud_snapshot()
	JavaScriptBridge.eval("window.valleyState="+JSON.stringify(state)+";")

func _qa_visible_rect(control: Control) -> Rect2:
	if not qa_mode or not is_instance_valid(control) or not control.is_visible_in_tree(): return Rect2()
	var rect=control.get_global_rect().intersection(get_viewport().get_visible_rect())
	var parent=control.get_parent()
	while parent is Control:
		if parent.clip_contents or parent is ScrollContainer: rect=rect.intersection(parent.get_global_rect())
		parent=parent.get_parent()
	# Do not offer a covered control as a touch target under an open overlay.
	for cover in [compact_menu,end_panel,tutorial_panel]:
		if is_instance_valid(cover) and cover.is_visible_in_tree() and cover!=control and not cover.is_ancestor_of(control) and rect.intersects(cover.get_global_rect()): return Rect2()
	if is_instance_valid(compact_menu_dismiss) and compact_menu_dismiss.is_visible_in_tree() and not compact_menu.is_ancestor_of(control) and rect.intersects(compact_menu_dismiss.get_global_rect()): return Rect2()
	return rect

func _qa_rect_values(rect: Rect2) -> Array:
	return [rect.position.x,rect.position.y,rect.size.x,rect.size.y]

func _qa_hud_snapshot() -> Dictionary:
	# Read-only screen observations for ordinary-touch QA. No authority lookup,
	# commands, placement search, clock control or generic callable bridge.
	if not qa_mode or not is_instance_valid(ui) or not is_instance_valid(camera): return {}
	var viewport=get_viewport().get_visible_rect().size
	var result={"schema":2,"viewport":[viewport.x,viewport.y],"camera":{"focus":[camera_focus.x,camera_focus.y,camera_focus.z],"zoom":camera.size},"context_targets":[],"ground_points":[],"selection_detail":"","selected_own":[],"own_targets":[],"preview":null,"buttons":[],"action_scroll":{"rect":[0,0,0,0],"scroll_horizontal":0}}
	# Public tappable projections only. No authority lookup, fog memory, path
	# feasibility, resource search, order mutation or test-only command API.
	for record in faction_views[0].records().values():
		if not record.get("alive",false) or record.get("remembered",false): continue
		if record.get("team",-1)!=1 and record.get("category","")!="resource": continue
		var position=record.pos+Vector3(0,0.6 if record.category=="unit" else 1.0,0)
		if camera.is_position_behind(position): continue
		var screen=camera.unproject_position(position)
		if not screen.is_finite() or not _box_point_in_world(screen) or _pick(screen)!=record.id: continue
		result.context_targets.append({"id":record.id,"kind":record.kind,"category":record.category,"team":record.team,"screen":[screen.x,screen.y]})
	# Nine fixed screen probes describe visible empty ground, not a navigation
	# or placement search. A point carries no promise of reachability.
	for y in [0.3,0.45,0.6]:
		for x in [0.25,0.5,0.75]:
			var screen=Vector2(viewport.x*x,viewport.y*y)
			if not _box_point_in_world(screen): continue
			var world=_world_at(screen)
			if not world.is_finite() or absf(world.x)>=Rules.MAP_HALF or absf(world.z)>=Rules.MAP_HALF: continue
			if visible_cells[0].is_empty() or visible_cells[0][_cell_index(world)]==0 or _pick(screen)>=0: continue
			result.ground_points.append([screen.x,screen.y])
	if _qa_visible_rect(selection_detail).has_area(): result.selection_detail=selection_detail.text
	for record in faction_views[0].records().values():
		if not record.get("owned",false) or not record.get("alive",false) or record.get("remembered",false) or record.get("team",-1)!=0: continue
		var site=record.get("category","")=="building"
		var summary={"id":record.id,"kind":record.kind,"category":record.category,"built":record.built,"progress":record.progress}
		if site and record.id in selected: result.selected_own.append(summary.duplicate())
		if record.kind!="villager" and not (site and not record.built): continue
		var position=record.pos+Vector3(0,1.0 if site else 0.6,0)
		if camera.is_position_behind(position): continue
		var screen=camera.unproject_position(position)
		if not screen.is_finite() or not _box_point_in_world(screen) or _pick(screen,false)!=record.id: continue
		summary.screen=[screen.x,screen.y]; result.own_targets.append(summary)
	if not build_mode.is_empty() and is_instance_valid(ghost) and ghost.is_visible_in_tree() and not camera.is_position_behind(ghost.global_position):
		var screen=camera.unproject_position(ghost.global_position)
		if screen.is_finite() and _box_point_in_world(screen): result.preview={"screen":[screen.x,screen.y],"placement_ok":placement_ok,"held":build_preview_held}
	for button in ui.find_children("*","Button",true,false):
		var rect=_qa_visible_rect(button)
		if not rect.has_area(): continue
		result.buttons.append({"text":button.text,"rect":_qa_rect_values(rect),"disabled":button.disabled,"in_action_scroll":action_scroll.is_ancestor_of(button)})
	var scroll_rect=_qa_visible_rect(action_scroll)
	if scroll_rect.has_area(): result.action_scroll={"rect":_qa_rect_values(scroll_rect),"scroll_horizontal":action_scroll.scroll_horizontal}
	return result

# Local faction 0 only: accepted commands waiting for execution, including AI/player
# callers on that faction. Enemy commands and private attack-ledger fields are absent.
func _snapshot():
	var own_pending_commands=0
	for command in commands:
		if command.team==0: own_pending_commands+=1
	return {"build":Rules.BUILD_ID,"version":Rules.VERSION,"victory_mode":victory_mode,"control_ticks":control_point.scores.duplicate(),"tick":tick_count,"time":game_time,"paused":paused,"game_over":game_over,"outcome":outcome,"selected":selected,"food":stocks[0].food,"wood":stocks[0].wood,"stone":stocks[0].stone,"iron":stocks[0].iron,"age":2 if _age2(0) else 1,"military_techs":military_tech_completed[0].keys(),"bank_milli":economy.bank_milli(0),"economy_scale":Economy.SCALE,"population":_population(0),"capacity":_capacity(0),"delivered":delivered_total[0],"built":completed_builds[0],"trained":trained_total[0],"own_pending_commands":own_pending_commands,"touch_mode":touch_command,"build_mode":build_mode}

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
	control_point.reset();ai_control_targets.clear()
	worker_evacuations.clear(); worker_manual_until.clear(); worker_safety_hits.clear(); worker_safety_enabled=true
	entities.clear(); selected.clear(); squad_selection.reset(); idle_worker_cursor=-1; repeat_train_cursor=[0,0]; commands.clear(); next_id=0; tick_count=0; game_time=0
	attack_ledger=AttackLedger.new(); pending_damage.clear(); battle_alerts.reset(); match_report.reset(); last_match_report={}; end_report_page="overview"
	command_sequence=0; processed_command_ids.clear(); next_queue_id=0; ready_cursor=-1; spawn_commit_order.clear(); game_over=false; victory=false; outcome=""; paused=false
	recovery_ticks=[0,0]; no_progress_ticks=0; progress_serial=0; inactivity_paused=false; future_recovery_events.clear(); end_reason=""
	_surrender_intent.clear()
	ai_opening_assigned=false; ai_last_raid_tick=-AI_RAID_INTERVAL_TICKS; ai_raids=0
	ai_home_defense_targets.clear(); ai_raid_members.clear(); ai_raid_departure_count=0; ai_raid_keep.clear(); ai_raid_retreating=false
	ai_scout_attempts.clear(); ai_scout_moves.clear(); ai_claimed_workers.clear(); ai_build_submitted=false; ai_budget.clear(); ai_status.clear(); ai_site_recovery.clear(); owned_motion_witness_tick=-1
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
	var directory="user://screenshots"
	var path=directory+"/gameplay-"+str(Time.get_unix_time_from_system()).replace(".","-")+".png"
	var directory_error=DirAccess.make_dir_recursive_absolute(directory)
	if directory_error!=OK:
		print("GAMEPLAY_SCREENSHOT "+path+" result="+str(directory_error)+" stage=directory metadata=not_written")
		return
	var error=get_viewport().get_texture().get_image().save_png(path)
	if error!=OK:
		print("GAMEPLAY_SCREENSHOT "+path+" result="+str(error)+" stage=png metadata=not_written")
		return
	var meta=FileAccess.open(path+".json",FileAccess.WRITE)
	if meta==null:
		print("GAMEPLAY_SCREENSHOT "+path+" result="+str(error)+" metadata=open_failed metadata_error="+str(FileAccess.get_open_error()))
		return
	var manifest_path="res://reports/build-manifest.json"
	var manifest_sha256=""
	var manifest_status="missing"
	if FileAccess.file_exists(manifest_path):
		manifest_sha256=FileAccess.get_sha256(manifest_path)
		manifest_status="available" if not manifest_sha256.is_empty() else "unreadable"
	meta.store_string(JSON.stringify({"build":Rules.BUILD_ID,"version":Rules.VERSION,"source_sha256":FileAccess.get_sha256("res://scripts/game.gd"),"build_manifest_sha256":manifest_sha256,"build_manifest_status":manifest_status,"capture_kind":"genuine_native_gameplay_viewport","capture_error":error,"viewport":str(get_viewport().get_visible_rect().size),"top_size":str(hud_top.size),"bottom_size":str(hud_bottom.size),"snapshot":_snapshot()},"  "))
	var metadata_error=meta.get_error()
	meta.flush()
	if metadata_error==OK: metadata_error=meta.get_error()
	meta.close()
	if metadata_error!=OK:
		print("GAMEPLAY_SCREENSHOT "+path+" result="+str(error)+" metadata=write_failed metadata_error="+str(metadata_error))
		return
	print("GAMEPLAY_SCREENSHOT "+path+" result="+str(error)+" metadata=written")

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


func _shortcut_menu_caption() -> String:
	if compact_menu.visible: return "收起"
	if not game_over and not battle_alerts.peek(tick_count).is_empty(): return "受襲"
	if not game_over and is_instance_valid(idle_worker_button) and not idle_worker_button.get_meta("idle_ids",[]).is_empty(): return "閒置"
	return "選單"

func _refresh_attack_alert():
	if not is_instance_valid(attack_alert_button): return
	var current={} if game_over else battle_alerts.peek(tick_count)
	var sequence=current.get("sequence",-1)
	if attack_alert_button.get_meta("alert_sequence",-1)!=sequence:
		# A different/expired destination must not inherit a held touch or mouse.
		for index in gui_touch_press.keys():
			if gui_touch_press[index].button.get_ref()==attack_alert_button: gui_touch_press.erase(index)
		if attack_alert_button.button_pressed:
			attack_alert_button.disabled=true; attack_alert_button.disabled=false
		attack_alert_button.set_meta("alert_sequence",sequence)
	attack_alert_button.visible=not current.is_empty()
	attack_alert_button.disabled=paused or game_over or not application_focused or application_suspended
	if not current.is_empty():
		attack_alert_button.text="前往受襲位置 · "+Rules.NAMES.get(current.kind,current.kind)
	compact_menu_button.text=_shortcut_menu_caption()

func _focus_attack_alert():
	if paused or game_over or not application_focused or application_suspended or not is_instance_valid(attack_alert_button): return
	# Revalidate the displayed identity before consuming anything or canceling intent.
	var current=battle_alerts.acknowledge(attack_alert_button.get_meta("alert_sequence",-1),tick_count)
	if current.is_empty(): return
	_cancel_mode()
	compact_menu.hide(); compact_menu_dismiss.hide()
	camera_focus=current.position
	_camera_update()
	_refresh_attack_alert()
	# Camera navigation only: selection, queued orders and all authority stay intact.

func _refresh_idle_worker_button():
	if not is_instance_valid(idle_worker_button): return
	var ids=[] if game_over else IdleWorkerSelection.eligible(faction_views[0].records(),commands)
	var target=IdleWorkerSelection.next_id(ids,idle_worker_cursor)
	var blocked=game_over or not application_focused or application_suspended
	# A replaced roster/target cannot inherit an old held touch or native click.
	if idle_worker_button.get_meta("idle_ids",[])!=ids or idle_worker_button.get_meta("idle_target",-1)!=target or idle_worker_button.get_meta("idle_blocked",true)!=blocked:
		for index in gui_touch_press.keys():
			if gui_touch_press[index].button.get_ref()==idle_worker_button: gui_touch_press.erase(index)
		if idle_worker_button.button_pressed:
			idle_worker_button.disabled=true; idle_worker_button.disabled=false
		idle_worker_button.set_meta("idle_ids",ids.duplicate())
		idle_worker_button.set_meta("idle_target",target)
		idle_worker_button.set_meta("idle_blocked",blocked)
	idle_worker_button.disabled=blocked or ids.is_empty()
	idle_worker_button.text="閒置村民 %d · 下一位" % ids.size()

func _focus_idle_worker():
	# Navigation remains available while paused, exactly like ordinary selection.
	# It never issues work, movement, retry, payment or combat commands.
	if game_over or not application_focused or application_suspended or not compact_menu.visible or not is_instance_valid(idle_worker_button): return
	var records=faction_views[0].records()
	var ids=IdleWorkerSelection.eligible(records,commands)
	var target=IdleWorkerSelection.next_id(ids,idle_worker_cursor)
	if idle_worker_button.disabled or ids.is_empty() or ids!=idle_worker_button.get_meta("idle_ids",[]) or target!=idle_worker_button.get_meta("idle_target",-1):
		_refresh_idle_worker_button(); return
	idle_worker_cursor=target
	_cancel_mode()
	compact_menu.hide(); compact_menu_dismiss.hide()
	_select([target])
	camera_focus=records[target].pos; _camera_update()
	_refresh_idle_worker_button()
	compact_menu_button.text=_shortcut_menu_caption()

func _squad_actions_available():
	return not paused and not game_over and application_focused and not application_suspended

func _bind_squad_button(button,ids,blocked):
	# Membership changes retire held touch/mouse; a new group cannot inherit it.
	if button.get_meta("squad_ids",[])!=ids or button.get_meta("squad_blocked",true)!=blocked:
		for index in gui_touch_press.keys():
			if gui_touch_press[index].button.get_ref()==button: gui_touch_press.erase(index)
		if button.button_pressed:
			button.disabled=true; button.disabled=false
		button.set_meta("squad_ids",ids.duplicate())
		button.set_meta("squad_blocked",blocked)
	button.disabled=blocked or ids.is_empty()

func _refresh_squad_buttons():
	if squad_buttons.size()!=SquadSelection.SLOT_COUNT: return
	var records=faction_views[0].records()
	var chosen=SquadSelection.eligible(records,selected)
	var blocked=not _squad_actions_available()
	for slot in range(SquadSelection.SLOT_COUNT):
		var pair=squad_buttons[slot]
		var members=squad_selection.members(slot,records)
		_bind_squad_button(pair.recall,members,blocked)
		_bind_squad_button(pair.save,chosen,blocked)
		pair.recall.text="%d 隊 · %d 人" % [slot+1,members.size()]
		pair.save.text=("存入 %d 隊" if members.is_empty() else "取代 %d 隊") % (slot+1)

func _activate_squad(slot,save):
	if not _squad_actions_available() or not compact_menu.visible: return
	if typeof(slot)!=TYPE_INT or slot<0 or slot>=squad_buttons.size(): return
	var records=faction_views[0].records()
	var pair=squad_buttons[slot]
	var button=pair.save if save else pair.recall
	var expected=button.get_meta("squad_ids",[])
	var current=SquadSelection.eligible(records,selected) if save else squad_selection.members(slot,records)
	# Validate the displayed selection again at activation, before canceling intent.
	if button.disabled or current.is_empty() or current!=expected:
		_refresh_squad_buttons(); return
	if save and not squad_selection.assign(slot,records,selected,expected): return
	_cancel_mode()
	compact_menu.hide(); compact_menu_dismiss.hide()
	if save:
		_message("已存入 %d 隊，共 %d 人；原有指令不變。" % [slot+1,current.size()],3)
	else:
		_select(current)
		camera_focus=records[current[0]].pos
		_camera_update()
	_refresh_squad_buttons()
	compact_menu_button.text=_shortcut_menu_caption()
	# Selection/camera only. No queued orders, new path budget, economy or AI mutation.

func _toggle_compact_menu():
	compact_menu.visible=not compact_menu.visible
	if compact_menu.visible:
		_quarantine_camera_keys()
		_refresh_idle_worker_button()
		_refresh_squad_buttons()
		if box_select_mode: _cancel_mode()
	compact_menu_dismiss.visible=compact_menu.visible
	compact_menu_button.text=_shortcut_menu_caption()
	_layout_ui()


func _compact_menu_action(callback:Callable):
	compact_menu.hide(); compact_menu_dismiss.hide(); callback.call()
	compact_menu_button.text=_shortcut_menu_caption()


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

# Standalone battlefield fixtures retain deliberate startup; the product shell
# owns navigation when connected. No game save or tutorial skip is implied.
func _request_main_menu():
	if main_menu_requested.has_connections(): main_menu_requested.emit()
	else: get_tree().change_scene_to_file("res://main_menu.tscn")

func _request_restart():
	if restart_requested.has_connections(): restart_requested.emit()
	else: get_tree().reload_current_scene()

# --- Integrated economy, age and military progression ---
func _age2(team: int) -> bool:
	return age_completed_tick[team]>=0 and tick_count>age_completed_tick[team]

func _kind_unlocked(kind: String,team: int) -> bool:
	return kind not in Rules.AGE2_KINDS or _age2(team)

func _research_pending(team: int) -> bool:
	if age_completed_tick[team]>=0: return true
	for ent in entities:
		if ent.alive and ent.team==team:
			for item in ent.queue:
				if item.get("research",false) and item.kind=="age2": return true
	return false

func _enqueue_research(id: int,team: int):
	var building=_get_entity(id)
	if building.is_empty() or not building.alive or not building.built or building.team!=team or building.kind!="town_center": return _reject_command(team,"請選取自己的已完成主堡。")
	if _research_pending(team): return _reject_command(team,"城防時代已在研究或已完成。")
	if building.queue.size()>=5: return _reject_command(team,"生產隊列已滿。")
	var payment=_pay(COSTS.age2,team)
	if not payment.applied: return _reject_command(team,"研究需要食糧 350、木材 150、鐵礦 50。")
	building.queue.append({"receipt_id":payment.receipt_id,"queue_id":next_queue_id,"kind":"age2","research":true,"remaining_ticks":Rules.TRAIN_TICKS.age2,"started":false,"next_retry_tick":0,"candidate_cursor":0})
	next_queue_id+=1
	return true

func _gather_records(team: int) -> Dictionary:
	var result=work_memory[team].resources.duplicate()
	for record in work_memory[team].structures.values():
		if record.team==team and record.alive and record.built and record.kind=="farm": result[record.id]=record
	return result

func _release_farm(ent: Dictionary) -> void:
	var farm_id=ent.get("farm_id",-1)
	if farm_id<0: return
	economy_sequence+=1
	economy.release_farm("farm_release:%d" % economy_sequence,ent.id,farm_id)
	ent.farm_id=-1

func _update_tower(ent: Dictionary) -> void:
	ent.cooldown_ticks=maxi(0,ent.cooldown_ticks-1)
	if ent.cooldown_ticks>0: return
	# Candidate policy: visible hostile units before buildings; distance then ID.
	var chosen={}; var best=Vector3(INF,INF,INF)
	for target in entities:
		if not target.alive or target.team!=1-ent.team or not _visible_to(target,ent.team): continue
		var distance=_attack_distance(ent.pos,target)
		if distance>Rules.RANGE.tower: continue
		var rank=0 if target.category=="unit" else 1
		if chosen.is_empty() or rank<best.x or (rank==best.x and (distance<best.y or (is_equal_approx(distance,best.y) and target.id<best.z))):
			chosen=target; best=Vector3(rank,distance,target.id)
	if not chosen.is_empty(): _release_attack(ent,chosen)

func _ai_progression_plots(kind: String) -> Array:
	var result: Array=MapRoutes.build_plots(1,Rules.FOOTPRINT[kind])
	var home=MapRoutes.home(1)
	# Fixed finite local ring hints. Actual placement rechecks all occupied cells.
	for radius in [7,11,15]:
		for direction in [Vector3.LEFT,Vector3.RIGHT,Vector3.FORWARD,Vector3.BACK,Vector3(-1,0,-1),Vector3(1,0,-1),Vector3(-1,0,1),Vector3(1,0,1)]:
			result.append(_snap_build_position(kind,home+direction*radius))
	return result

func _ai_progression_goal(records: Array,workers: int,capacity: int,committed: int) -> String:
	# Rebuild the two-food-worker floor plus a spare builder after attrition.
	# Count queued villagers too. Only prioritize a currently affordable birth;
	# otherwise preserve the farm route that may be needed to restore food.
	if workers<3 and committed<capacity and _ai_can_budget("villager"): return "villager"
	var counts={}; var known_food=0; var known_enemy_keep=false
	for record in records:
		if record.team==0 and record.category=="building" and record.kind=="town_center": known_enemy_keep=true
		if record.category=="resource" and record.kind=="berry": known_food+=1
		if not record.owned: continue
		counts[record.kind]=counts.get(record.kind,0)+1
		for item in record.get("queue",[]): counts[item.kind]=counts.get(item.kind,0)+1
	if capacity-committed<=2 and capacity<Rules.POP_LIMIT:
		var unfinished=false
		for record in records:
			if record.owned and record.kind=="house" and not record.built: unfinished=true
		if not unfinished: return "house"
	if known_food<=3 and counts.get("farm",0)<4: return "farm"
	if workers<8: return "villager"
	if counts.get("barracks",0)==0: return "barracks"
	if counts.get("range",0)==0: return "range"
	if counts.get("spearman",0)+counts.get("archer",0)<4:
		var opening=ArmyComposition.plan(records,["spearman","archer"])
		ai_status.recruitment=opening
		return opening.kind
	# Restore reconnaissance before expensive age progression, after a viable
	# economy and four defenders. Queued scouts and remembered keeps count.
	if counts.get("scout",0)==0 and not known_enemy_keep: return "scout"
	if not _age2(1): return "age2"
	if counts.get("stable",0)==0: return "stable"
	if counts.get("workshop",0)==0: return "workshop"
	if counts.get("tower",0)<2: return "tower"
	if workers<12: return "villager"
	if counts.get("siege",0)<2: return "siege"
	if counts.get("cavalry",0)<4: return "cavalry"
	if counts.get("scout",0)==0: return "scout"
	var composition=ArmyComposition.plan(records)
	ai_status.recruitment=composition
	return composition.kind

func _route_grid(ent: Dictionary) -> AStarGrid2D:
	var memory=work_memory[ent.team]
	if ent.get("radius",Rules.UNIT_RADIUS)<=0.5: return memory.grid
	var cached=large_route_cache[ent.team]
	if cached.get("revision",-1)==memory.revision: return cached.grid
	var grid=AStarGrid2D.new(); grid.region=memory.grid.region; grid.cell_size=Vector2.ONE
	grid.diagonal_mode=AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	grid.default_compute_heuristic=AStarGrid2D.HEURISTIC_OCTILE
	grid.default_estimate_heuristic=AStarGrid2D.HEURISTIC_OCTILE
	grid.update()
	for y in Rules.MAP_SIZE:
		for x in Rules.MAP_SIZE:
			var cell=Vector2i(x,y)
			if not memory.grid.is_point_solid(cell): continue
			for offset in [Vector2i.ZERO,Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
				if grid.region.has_point(cell+offset): grid.set_point_solid(cell+offset)
	large_route_cache[ent.team]={"revision":memory.revision,"grid":grid}
	return grid

func _attack_approach(ent: Dictionary,target: Dictionary,inspect_site=false) -> Vector3:
	if ent.radius<=0.5 and ent.kind!="archer": return _free_adjacent(target,ent.pos,false,ent.team,ent)
	var best=Vector3.INF; var distance=INF
	# Archers need a clear firing slot, not a vacant melee perimeter cell.
	# The public footprint/range bound is at most 225 cells; no path probe.
	# Large actors retain their original swept-clearance envelope.
	var center=_cell(target.pos); var extent=int(Rules.FOOTPRINT.get(target.kind,3)/2)+(ceili(Rules.RANGE.archer) if ent.kind=="archer" else 3)
	var inspect_archer=ent.kind=="archer" and inspect_site
	var site_visible=inspect_archer and visible_cells[ent.team][_cell_index(target.pos)]!=0
	for y in range(center.y-extent,center.y+extent+1):
		for x in range(center.x-extent,center.x+extent+1):
			var cell=Vector2i(x,y)
			if not _route_grid(ent).region.has_point(cell) or _route_grid(ent).is_point_solid(cell): continue
			var point=_point(cell)
			if inspect_archer:
				# Regain center sight without demanding a vacant melee ring.
				# Only an already revealed but unobserved site needs the old
				# close-inspection rule; site visibility never grants death knowledge.
				if site_visible:
					if _attack_distance(point,target)>=0.6: continue
				elif (cell-center).length_squared()>Rules.SIGHT.archer*Rules.SIGHT.archer: continue
			if ent.kind=="archer" and point.distance_squared_to(ent.pos)>=distance: continue
			if _attack_distance(point,target)>Rules.RANGE[ent.kind] or not _known_destination_clear(ent,point): continue
			var d=point.distance_squared_to(ent.pos)
			if d<distance: distance=d; best=point
	return best

# Research uses the ordinary paid queue, receipts, cancellation, and next-tick
# activation. No per-unit mutation: existing and future troops share the bonus.
func _military_research_pending(kind: String,team: int) -> bool:
	if military_tech_completed[team].has(kind): return true
	for building in entities:
		if not building.alive or building.team!=team: continue
		for item in building.queue:
			if item.get("research",false) and item.kind==kind: return true
	return false

func _enqueue_military_research(id,kind,team):
	if team not in [0,1] or typeof(kind)!=TYPE_STRING or kind not in Rules.MILITARY_TECHS: return false
	var building=_get_entity(id)
	if building.is_empty() or not building.alive or not building.built or building.team!=team or building.kind!="town_center": return _reject_command(team,"請選取自己的已完成主堡。")
	if not _age2(team): return _reject_command(team,"軍備科技需要城防時代。")
	if _military_research_pending(kind,team): return _reject_command(team,"這項軍備科技已在研究或已完成。")
	if building.queue.size()>=5: return _reject_command(team,"生產隊列已滿。")
	var payment=_pay(COSTS[kind],team)
	if not payment.applied: return _reject_command(team,Rules.NAMES[kind]+"需要 "+Rules.cost_label(kind))
	building.queue.append({"receipt_id":payment.receipt_id,"queue_id":next_queue_id,"kind":kind,"research":true,"remaining_ticks":Rules.TRAIN_TICKS[kind],"started":false,"next_retry_tick":0,"candidate_cursor":0})
	next_queue_id+=1
	return true

func _military_attack_bonus(kind: String,team: int) -> int:
	if team not in [0,1]: return 0
	for tech in Rules.MILITARY_TECHS:
		if kind in Rules.TECH_UNITS[tech] and military_tech_completed[team].has(tech) and tick_count>military_tech_completed[team][tech]: return Rules.TECH_BONUS
	return 0

func _ai_military_research(records: Array,castle: Dictionary,worker_count: int):
	if castle.is_empty() or not _age2(1) or worker_count<6 or castle.queue.size()>=2: return
	for tech in Rules.MILITARY_TECHS:
		if _military_research_pending(tech,1) or not _ai_can_budget(tech): continue
		if ai_budget.get("food",0)-COSTS[tech].get("food",0)*Economy.SCALE<150*Economy.SCALE: continue
		var eligible=0
		for record in records:
			if record.get("owned",false) and record.get("alive",false) and record.get("kind","") in Rules.TECH_UNITS[tech]: eligible+=1
		if eligible<4: continue
		_submit("military_research",{"building":castle.id,"kind":tech},1)
		_ai_reserve_budget(tech)
		return

func _toggle_worker_safety():
	worker_safety_enabled=not worker_safety_enabled
	if not worker_safety_enabled: worker_evacuations.clear()
	action_key=""

func _worker_pending_intent(id):
	for command in commands:
		if command.get("team",-1)==0 and (id in command.get("ids",[]) or command.get("builder",-1)==id): return true
	return false

func _update_worker_safety():
	if not worker_safety_enabled or paused or game_over: return
	var records=faction_views[0].records()
	for record in records.values():
		if not record.get("owned",false) or not record.get("alive",false) or record.kind!="villager": continue
		var worker=_get_entity(record.id) # Owned authority only, after observation filter.
		if _worker_pending_intent(worker.id): continue
		if worker_evacuations.has(worker.id):
			var saved=worker_evacuations[worker.id]
			if worker.work_epoch!=saved.epoch:
				worker_evacuations.erase(worker.id); continue
			if worker.path_status in [BoundedPath.NO_PATH,BoundedPath.LIMIT_REACHED]:
				worker_evacuations.erase(worker.id); continue # Never reset terminal route budgets.
			# Require five continuously observed safe seconds after arrival.
			# Fog is not proof the raider left; it also resets the clear timer.
			if worker.state!="idle" or worker.last_damage_tick==tick_count or visible_cells[0][_cell_index(saved.origin)]==0 or not WorkerSafety.threats(records,0,worker.pos).is_empty() or not WorkerSafety.threats(records,0,saved.origin).is_empty():
				saved.safe_since_tick=-1; continue
			if saved.get("safe_since_tick",-1)<0:
				saved.safe_since_tick=tick_count; continue
			if tick_count-saved.safe_since_tick<WorkerSafety.SAFE_TICKS: continue
			worker_evacuations.erase(worker.id)
			var resources=_gather_records(0)
			if resources.has(saved.resource):
				_order(worker,"gather",saved.resource)
			elif _cargo_amount(worker)>0:
				_route_to_dropoff(worker)
			# A missing/depleted old resource is not permission to discover a
			# hidden replacement or steal another worker's farm.
			continue
		if tick_count<worker_manual_until.get(worker.id,-1) or worker.state not in ["gather","deliver"]: continue
		if worker.last_damage_tick<=worker_safety_hits.get(worker.id,-1000) or tick_count-worker.last_damage_tick>20: continue
		worker_safety_hits[worker.id]=worker.last_damage_tick
		if worker.path_status in [BoundedPath.NO_PATH,BoundedPath.LIMIT_REACHED]: continue
		var threats=WorkerSafety.threats(records,0,worker.pos)
		if threats.is_empty(): continue
		var resource=worker.get("resource_target",-1)
		if resource<0: continue
		var resources=_gather_records(0)
		if not resources.has(resource): continue
		# Farming has exclusive occupancy; leave it to explicit player orders
		# rather than release and later take somebody else's work slot.
		if resources[resource].get("kind","")=="farm": continue
		for refuge in WorkerSafety.refuges(records,record):
			var away=(refuge.pos-worker.pos).normalized()
			var destination=_nearest_free(refuge.pos+away*(refuge.radius+1.0),3,0,worker)
			if destination==Vector3.INF or destination.distance_to(worker.pos)<1.0 or not WorkerSafety.threats(records,0,destination).is_empty(): continue
			_order_move(worker,destination)
			worker_evacuations[worker.id]={"epoch":worker.work_epoch,"resource":resource,"origin":resources[resource].pos}
			_message("採集村民遇襲，正撤往安全據點；安全後自動回工。",3)
			break

func _worker_safety_label(record):
	var saved=worker_evacuations.get(record.id,{})
	if saved.is_empty(): return ""
	if record.state=="move": return "自動避難中"
	if visible_cells[0][_cell_index(saved.origin)]==0: return "等待原工作區重新可見"
	if saved.get("safe_since_tick",-1)<0: return "等待威脅離開"
	return "安全確認 %d / 5 秒" % mini(5,int((tick_count-saved.safe_since_tick)/20))

static func valid_victory_mode(value: String) -> String:
	return value if value in ["conquest","control"] else "conquest"

func _create_control_point_marker():
	control_point_marker=Node3D.new();control_point_marker.name="CentralControlPoint";add_child(control_point_marker)
	var ring=TorusMesh.new();ring.inner_radius=ControlPoint.RADIUS-0.10;ring.outer_radius=ControlPoint.RADIUS+0.10;ring.rings=48;ring.ring_segments=6
	_mesh(control_point_marker,ring,Vector3(0,0.08,0),GOLD)
	_cylinder(control_point_marker,Vector3(0,1.5,0),0.08,3.0,Color("b6ad91"),0.08,8)
	var banner=BoxMesh.new();banner.size=Vector3(1.6,0.9,0.08)
	control_point_flag=_mesh(control_point_marker,banner,Vector3(0.8,2.5,0),GOLD)
	control_point_marker.visible=victory_mode=="control"

func _refresh_control_point_marker():
	if not is_instance_valid(control_point_marker):return
	control_point_marker.visible=victory_mode=="control"
	if is_instance_valid(objective_button): objective_button.visible=victory_mode=="control"
	if victory_mode!="control":return
	if is_instance_valid(objective_button):
		var status="爭奪中，停止計時" if control_point.contested else ("我軍控制" if control_point.owner==0 else ("敵軍控制" if control_point.owner==1 else "至少兩名軍人進圈"))
		objective_button.text="王旗 我 %d/180 · 敵 %d/180 秒\n%s · 點此定位" % [control_point.scores[0]/20,control_point.scores[1]/20,status]
		objective_button.tooltip_text=control_point.caption()
	var color=BLUE if control_point.owner==0 else (RED if control_point.owner==1 else GOLD)
	if control_point_flag.get_meta("owner",-2)!=control_point.owner:
		control_point_flag.material_override=_material(color)
		control_point_flag.set_meta("owner",control_point.owner)

func _focus_control_point():
	camera_focus=ControlPoint.CENTER;_camera_update()

func _ai_control_point_orders(army: Array,records: Array):
	ai_status.army="control_point"
	if army.size()<2 and ai_control_targets.is_empty():
		ai_status.army="control_point_mustering";return
	var threats=[]
	for record in records:
		if record.get("team",-1)==0 and record.get("alive",false) and not record.get("remembered",true) and record.get("category","")=="unit" and record.pos.distance_to(ControlPoint.CENTER)<ControlPoint.RADIUS+3: threats.append(record)
	var assignments={}
	for unit in army:
		var tracked=unit.state=="attack" and ai_control_targets.get(unit.id,-1)==unit.get("target",-2)
		var old_target_visible=false
		for threat in threats:
			if threat.id==unit.get("target",-1):old_target_visible=true;break
		if tracked and not old_target_visible:
			_submit("stop",{"ids":[unit.id]},1);continue
		if unit.get("path_status","") in [BoundedPath.NO_PATH,BoundedPath.LIMIT_REACHED]:
			if tracked:assignments[unit.id]=unit.target
			continue
		var target=HomeDefense.choose(unit,threats)
		if not target.is_empty():
			assignments[unit.id]=target.id
			if unit.state!="attack" or unit.target!=target.id:_submit("order",{"ids":[unit.id],"target":target.id,"position":target.pos},1)
		elif unit.pos.distance_to(ControlPoint.CENTER)>3.0:
			if unit.state=="move" and unit.get("dest",Vector3.INF).distance_to(ControlPoint.CENTER)<3.0:continue
			var angle=float(unit.id%8)*TAU/8.0
			_submit("advance",{"ids":[unit.id],"position":ControlPoint.CENTER+Vector3(cos(angle),0,sin(angle))*2.0},1)

	ai_control_targets=assignments


func _update_rest_recovery():
	if paused or game_over: return
	var bases=[[],[]]
	var threats=[[],[]]
	for entity in entities:
		if not entity.alive or entity.team not in [0,1]: continue
		if entity.kind=="town_center" and entity.built: bases[entity.team].append(entity)
		# Current visibility only. This list is never made from hidden authority.
		if _visible_to(entity,1-entity.team): threats[1-entity.team].append(entity)
	for unit in entities:
		if unit.category!="unit" or unit.team not in [0,1]: continue
		if unit.get("rest_update_tick",-1)>=tick_count: continue
		var consecutive=unit.get("rest_update_tick",-1)==tick_count-1
		unit.rest_update_tick=tick_count
		var base=RestRecovery.base_for(unit,bases[unit.team])
		var reason=RestRecovery.blocked(unit,base,threats[unit.team],tick_count)
		if not reason.is_empty():
			unit.rest_ticks=0; unit.rest_base=-1; continue
		if not consecutive or unit.get("rest_base",-1)!=base.id or unit.get("rest_pos",Vector3.INF)!=unit.pos:
			unit.rest_ticks=0
		unit.rest_base=base.id; unit.rest_pos=unit.pos
		unit.rest_ticks=int(unit.get("rest_ticks",0))+1
		# No stacking from overlapping keeps; first point is after 10 s + 2 s.
		if unit.rest_ticks>RestRecovery.SAFE_TICKS and (unit.rest_ticks-RestRecovery.SAFE_TICKS)%RestRecovery.HEAL_TICKS==0:
			if tick_count-maxi(unit.last_damage_tick,maxi(base.last_damage_tick,unit.get("last_attack_tick",-1000)))<RestRecovery.SAFE_TICKS: continue
			unit.hp=mini(unit.max_hp,unit.hp+1); progress_serial+=1

extends SceneTree
## PREPARED ONLY. Run on guarded hosted Godot after clean import, never locally.
## Actual production publish/presenter methods and real Node3D signals.
## Controlled state setup is not gameplay, pixel, timing, or performance evidence.
const BASELINE_SHA = "0596a611029fc7c8867ab4f18e73709aa0f982f6e47909649ee3e96e9dd51d0f"
const CANDIDATE_SHA = "32b16b322d99e4922eb421143714b16a65fb35ad6088114132fe92b840aa0dfc"
const MAX_SIGNAL_SAMPLES = 128
const MAX_REPORT_BYTES = 128 * 1024
var game
var variant := ""
var checks: Array = []
var signal_counts: Dictionary = {}
var signal_samples: Array = []
var signal_batches: Array = []
var projection_states: Array = []
var phase := ""
var forbidden_authority_events := 0
var signal_events_seen := 0

func _initialize() -> void: call_deferred("run")

func check(label: String, okay: bool) -> void:
	checks.append({"name":label,"passed":okay})
	if not okay: push_error(label)

func publish() -> void:
	game._publish_faction_views()
	game._update_visuals(0.0)

func reveal(ent: Dictionary, value: int) -> void:
	game.visible_cells[0][game._cell_index(ent.pos)] = value

func visibility_listeners(node: Node) -> int:
	var count := node.get_signal_connection_list("visibility_changed").size() if node is Node3D else 0
	for child in node.get_children(): count += visibility_listeners(child)
	return count

func record_for(ent: Dictionary) -> Dictionary:
	return game.faction_views[0].get_record(ent.id)

func watch(node: Node3D, label: String, forbidden_authority := false) -> void:
	node.visibility_changed.connect(func():
		signal_events_seen += 1
		signal_counts[label] = signal_counts.get(label,0) + 1
		if signal_samples.size() < MAX_SIGNAL_SAMPLES:
			signal_samples.append({"phase":phase,"node":label,"visible":node.visible,"in_tree":node.is_visible_in_tree()})
		if forbidden_authority and node.is_visible_in_tree(): forbidden_authority_events += 1
	)

func watch_actor(ent: Dictionary, label: String, forbidden_authority := false) -> void:
	watch(ent.node,label+".root",forbidden_authority)
	watch(ent.ring,label+".ring",forbidden_authority)
	# Enemy body/bar are later duplicate() sources. Do not let test-only signal
	# connections be copied into presentation nodes or alter clone behavior.
	if not forbidden_authority:
		watch(ent.body,label+".body")
		if is_instance_valid(ent.bar): watch(ent.bar,label+".bar")

func watch_proxy(proxy: Dictionary, label: String) -> void:
	watch(proxy.node,label+".root")
	watch(proxy.body,label+".body")
	if is_instance_valid(proxy.bar): watch(proxy.bar,label+".bar")

func materials(node: Node) -> Array:
	var result: Array = []
	if node is MeshInstance3D:
		var material: Material = node.material_override
		result.append("none" if material == null else (material.albedo_color.to_html() if material is StandardMaterial3D else material.get_class()))
	for child in node.get_children(): result.append_array(materials(child))
	return result

func capture(label: String, ent: Dictionary) -> void:
	# Only the public projection contributes values. Hidden authority positions,
	# HP, commands and action history are never serialized into this report.
	var record: Dictionary = record_for(ent)
	var state: Dictionary = {"label":label,"record":record,"authority_visible":ent.node.visible,
		"authority_in_tree":ent.node.is_visible_in_tree(),"ring":ent.ring.visible,
		"bar":ent.bar.visible if is_instance_valid(ent.bar) else null}
	var body: Node3D = null
	if record.get("owned",false):
		body = ent.body
		state.position = str(ent.node.position)
		state.fill = ent.bar_fill.scale.x if is_instance_valid(ent.bar_fill) else null
	if game.presentation_nodes.has(ent.id):
		var proxy: Dictionary = game.presentation_nodes[ent.id]
		state.proxy_visible = proxy.node.visible
		state.proxy_in_tree = proxy.node.is_visible_in_tree()
		state.proxy_bar = proxy.bar.visible if is_instance_valid(proxy.bar) else null
		if proxy.node.visible:
			body = proxy.body
			state.position = str(proxy.node.position)
			state.remembered = proxy.remembered
			state.fill = proxy.fill.scale.x if is_instance_valid(proxy.fill) else null
	if body != null:
		state.body_rotation = str(body.rotation)
		state.materials = materials(body)
		state.construction_stage = body.get_meta("construction_stage",-1)
	if game.character_presenter.controllers.has(ent.id):
		var controller = game.character_presenter.controllers[ent.id]
		state.clip = controller.clip
		state.pose = controller.visual_evidence_snapshot().pose_sha256
	projection_states.append(state)

func stable(label: String, root_label: String, repeats := 3) -> void:
	phase = label
	signal_counts.clear()
	var snapshot: Dictionary = game._snapshot().duplicate(true)
	var rng_before: int = game.rng.state
	var frame_before: int = game.frame_counter
	for i in repeats: game._update_visuals(0.0)
	var expected: int = 0 if variant == "candidate" else repeats * 2
	check(label+" real root signal count",signal_counts.get(root_label,0) == expected)
	if variant == "candidate":
		check(label+" descendant signals match source contract",signal_counts.is_empty())
	else:
		check(label+" descendant signals match source contract",not signal_counts.is_empty())
	check(label+" snapshot RNG and frame counter unchanged",game._snapshot() == snapshot and game.rng.state == rng_before and game.frame_counter == frame_before)
	signal_batches.append({"phase":label,"repeats":repeats,"counts":signal_counts.duplicate()})

func run() -> void:
	var source_sha := FileAccess.get_sha256("res://scripts/game.gd")
	if source_sha == BASELINE_SHA: variant = "baseline"
	elif source_sha == CANDIDATE_SHA: variant = "candidate"
	else:
		push_error("Source is neither exact reviewed baseline nor candidate")
		quit(2); return
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false); game.test_mode = true; game.ai_enabled = false
	game.paused = false; game.game_over = false
	game.application_focused = true; game.application_suspended = false
	for team in 2: game.visible_cells[team].fill(0)
	publish()
	check("production Node3D visibility listeners absent before probes",visibility_listeners(game) == 0)
	var own: Dictionary = game._first(0,"scout")
	var enemy: Dictionary = game._first(1,"scout")
	check("seeded controlled subjects exist",not own.is_empty() and not enemy.is_empty())
	if own.is_empty() or enemy.is_empty(): finish(); return
	game.selected = [own.id]; own.hp = own.max_hp / 2
	publish()
	watch_actor(own,"own")
	watch_actor(enemy,"enemy_authority",true)
	watch(game.character_presenter.controllers[own.id].rig,"own.rig")
	check("selected damaged own root ring and bar visible",own.node.is_visible_in_tree() and own.ring.is_visible_in_tree() and own.bar.is_visible_in_tree())
	var own_controller = game.character_presenter.controllers[own.id]
	check("actual actor animation stays manually driven",own_controller.player.callback_mode_process == AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL and own_controller.player.process_mode == Node.PROCESS_MODE_DISABLED)
	capture("own selected damaged",own)
	stable("own selected damaged","own.root")
	game.selected.clear(); own.hp = own.max_hp; publish()
	check("own deselect heal hides ring and bar only",own.node.is_visible_in_tree() and not own.ring.visible and not own.bar.visible)
	capture("own deselected healed",own)
	own.hp -= 1; publish()
	check("own unselected damage reveals health bar",own.bar.is_visible_in_tree())
	capture("own unselected damaged",own)
	for flag in ["paused","game_over","application_suspended","application_focused"]:
		game.set(flag,flag != "application_focused")
		var controller = game.character_presenter.controllers[own.id]
		var before: Dictionary = controller.visual_evidence_snapshot()
		var tick_before: int = game.tick_count
		var frame_before: int = game.frame_counter
		game._update_visuals(0.1)
		check(flag+" freezes pose without advancing tick or frame",controller.visual_evidence_snapshot().pose_sha256 == before.pose_sha256 and game.tick_count == tick_before and game.frame_counter == frame_before)
		stable(flag+" repeated presentation","own.root",2)
		capture(flag,own)
		game.set(flag,flag == "application_focused")
	publish()
	check("unseen enemy root and rig excluded",record_for(enemy).is_empty() and not enemy.node.is_visible_in_tree() and not game.character_presenter.controllers.has(enemy.id))
	enemy.hp -= 1; reveal(enemy,1); publish()
	check("observed enemy has one legal root",not enemy.node.visible and game.presentation_nodes.has(enemy.id) and game.presentation_nodes[enemy.id].node.is_visible_in_tree())
	if not game.presentation_nodes.has(enemy.id): finish(); return
	var proxy: Dictionary = game.presentation_nodes[enemy.id]
	watch_proxy(proxy,"enemy_proxy")
	var old_controller = game.character_presenter.controllers[enemy.id]
	var old_rig: Node3D = old_controller.rig
	watch(old_rig,"enemy_proxy.rig")
	check("observed enemy damaged bar and observed pose",proxy.bar.is_visible_in_tree() and proxy.node.position == record_for(enemy).pos and proxy.body.rotation.y == record_for(enemy).visual_yaw)
	capture("enemy observed damaged",enemy)
	stable("enemy observed damaged","enemy_proxy.root")
	var public_position: Vector3 = proxy.node.position
	var public_fill: float = proxy.fill.scale.x
	reveal(enemy,0); game.tick_count += 1; publish()
	check("fog retires live rig and proxy before return",not is_instance_valid(old_rig) and not old_controller.occlusion.enabled and not proxy.node.is_visible_in_tree() and record_for(enemy).is_empty())
	check("enemy unit is not remembered",not game.faction_views[0].memory.has(enemy.id))
	enemy.pos += Vector3(3,0,0); enemy.hp = 1; enemy.body.rotation.y += 1.0
	game.unit_action_cues[0][enemy.id] = {"attack_tick":game.tick_count}
	publish()
	check("hidden mutation cannot refresh position fill or action history",proxy.node.position == public_position and proxy.fill.scale.x == public_fill and not game.unit_action_cues[0].has(enemy.id) and not game.visual_evidence_snapshot().live.has(str(enemy.id)))
	capture("enemy hidden mutated",enemy)
	game.paused = true; game.application_focused = false
	game._update_visuals(0.1)
	check("fog revocation stays effective during pause focus loss",not proxy.node.is_visible_in_tree() and not game.character_presenter.controllers.has(enemy.id))
	game.paused = false; game.application_focused = true
	reveal(enemy,1); publish()
	check("reappearance uses new observed pose and fresh controller",proxy.node.position == enemy.pos and proxy.body.rotation.y == enemy.body.rotation.y and game.character_presenter.controllers[enemy.id] != old_controller)
	check("hidden attack cannot replay on reappearance",game.character_presenter.controllers[enemy.id].last_attack_tick == -1)
	capture("enemy reobserved",enemy)
	var missing: Dictionary = game.presentation_nodes[enemy.id]
	missing.node.visible = false; game.presentation_nodes.erase(enemy.id)
	game._update_visuals(0.0)
	check("missing proxy never falls back to enemy authority",not enemy.node.visible and not enemy.ring.visible and not enemy.bar.visible and not missing.node.is_visible_in_tree())
	game.presentation_nodes[enemy.id] = missing
	publish()
	reveal(enemy,0); publish()
	var deaths_before: int = game.character_presenter.corpses.size()
	game._kill(enemy); publish()
	check("hidden death produces no corpse or presentation",game.pending_visual_deaths.is_empty() and game.character_presenter.corpses.size() == deaths_before and not proxy.node.is_visible_in_tree())
	capture("enemy hidden dead",enemy)
	game._kill(own); publish()
	check("own death hides root ring bar and removes live rig",not own.node.visible and not own.ring.visible and not own.bar.visible and not game.character_presenter.controllers.has(own.id))
	check("own death keeps exactly one observed detached corpse",game.character_presenter.corpses.size() == deaths_before + 1)
	capture("own dead",own)
	var victim: Dictionary = game._spawn("scout",1,Vector3(0,0,3))
	reveal(victim,1); publish()
	var victim_proxy: Dictionary = game.presentation_nodes[victim.id]
	game._kill(victim); publish()
	check("observed enemy death retires live root and creates one corpse",not victim_proxy.node.visible and not game.character_presenter.controllers.has(victim.id) and game.character_presenter.corpses.size() == deaths_before + 2)
	capture("enemy observed dead",victim)
	reveal(victim,0); publish()
	check("enemy corpse revoked on fog while own corpse remains",game.character_presenter.corpses.size() == deaths_before + 1)
	resource_lifecycle()
	orphan_lifecycle()
	check("enemy authority never becomes visible in real signal callbacks",forbidden_authority_events == 0)
	finish()

func resource_lifecycle() -> void:
	# Use actual seeded assets, including every no-health-bar resource kind.
	for kind in ["pine","oak","berry","stone","iron"]:
		var ent: Dictionary = game._first(-1,kind)
		check(kind+" seeded resource exists",not ent.is_empty())
		if ent.is_empty(): continue
		game.visible_cells[0].fill(0)
		# Earlier initial vision may have left a legal static memory. Start this
		# subject fresh in the controlled fixture, not in product/gameplay code.
		game.faction_views[0].memory.erase(ent.id)
		publish()
		check(kind+" unseen resource authority and proxy hidden",record_for(ent).is_empty() and not ent.node.visible and (not game.presentation_nodes.has(ent.id) or not game.presentation_nodes[ent.id].node.visible))
		capture(kind+" unseen",ent)
		watch_actor(ent,kind+".authority",true)
		reveal(ent,1); publish()
		check(kind+" resource proxy created",game.presentation_nodes.has(ent.id))
		if not game.presentation_nodes.has(ent.id): continue
		var proxy: Dictionary = game.presentation_nodes[ent.id]
		watch_proxy(proxy,kind+".proxy")
		check(kind+" no bars and exactly one presented root",not is_instance_valid(ent.bar) and not is_instance_valid(proxy.bar) and not ent.node.visible and proxy.node.is_visible_in_tree())
		var observed: Dictionary = record_for(ent).duplicate(true)
		var original_materials: Array = materials(proxy.body)
		capture(kind+" observed",ent)
		stable(kind+" stable observed",kind+".proxy.root",2)
		reveal(ent,0); publish()
		check(kind+" static memory remains visible and gray",record_for(ent).remembered and proxy.remembered and proxy.node.is_visible_in_tree() and materials(proxy.body) != original_materials)
		var remembered_materials: Array = materials(proxy.body)
		ent.hp = 1; ent.body.rotation.y += 0.5
		publish()
		check(kind+" hidden HP yaw cannot alter memory",record_for(ent).hp == observed.hp and proxy.body.rotation.y == observed.visual_yaw and materials(proxy.body) == remembered_materials)
		capture(kind+" remembered hidden mutation",ent)
		stable(kind+" stable remembered",kind+".proxy.root",2)
		reveal(ent,1); publish()
		check(kind+" reobservation restores materials and public values",not proxy.remembered and materials(proxy.body) == original_materials and proxy.body.rotation.y == ent.body.rotation.y and record_for(ent).hp == ent.hp)
		capture(kind+" reobserved",ent)
		reveal(ent,0); publish()
		ent.alive = false # Controlled unseen resource removal, not harvest proof.
		publish()
		check(kind+" hidden destruction preserves last static memory",record_for(ent).remembered and proxy.node.is_visible_in_tree() and not ent.node.visible)
		capture(kind+" hidden dead remembered",ent)
		reveal(ent,1); publish()
		check(kind+" observed empty cell retires memory and proxy",record_for(ent).is_empty() and not game.faction_views[0].memory.has(ent.id) and not proxy.node.visible and not ent.node.visible)
		capture(kind+" visible empty",ent)

func orphan_lifecycle() -> void:
	# Product keeps dead entities indexed. Explicitly exercise the defensive
	# removed-entity case with a final appended unit, preserving all earlier IDs.
	var ent: Dictionary = game._spawn("scout",1,Vector3.ZERO)
	reveal(ent,1); publish()
	check("orphan fixture starts observed",game.presentation_nodes.has(ent.id))
	if not game.presentation_nodes.has(ent.id): return
	var proxy: Dictionary = game.presentation_nodes[ent.id]
	var root_node: Node3D = proxy.node
	watch_proxy(proxy,"orphan.proxy")
	check("removed subject is final entity",game.entities.back().id == ent.id)
	game.entities.pop_back()
	publish()
	check("removed entity surviving proxy retired without deletion",game.presentation_nodes.has(ent.id) and is_instance_valid(root_node) and not root_node.visible and record_for(ent).is_empty())
	check("removed entity has no live controller",not game.character_presenter.controllers.has(ent.id))
	capture("orphan retired",ent)
	game._update_visuals(0.0); game._update_visuals(0.0)
	check("repeated orphan retirement is stable",not root_node.visible)

func finish() -> void:
	var failed: int = checks.filter(func(row): return not row.passed).size()
	var hashes: Dictionary = {}
	for path in ["scripts/game.gd","scripts/faction_view.gd","scripts/observed_character_presenter.gd","scripts/action_character.gd","scripts/observed_occlusion.gd","scripts/building_damage_presenter.gd","scripts/construction_visual.gd"]:
		hashes[path] = FileAccess.get_sha256("res://"+path)
	var report: Dictionary = {"suite":"visibility_once_lifecycle","build":game.Rules.BUILD_ID,
		"scope":"Controlled actual-engine signals, final visibility and observation lifecycle. Not rendered pixels, ordinary gameplay or performance.",
		"variant":variant,"source_sha256":hashes,"fixture_sha256":FileAccess.get_sha256(get_script().resource_path),
		"engine":Engine.get_version_info(),"passed":checks.size()-failed,"failure_count":failed,"checks":checks,
		"signal_batches":signal_batches,"signal_samples":signal_samples,"signal_events_seen":signal_events_seen,
		"signal_sample_limit":MAX_SIGNAL_SAMPLES,"projection_states":projection_states}
	var encoded: String = JSON.stringify(report)
	if encoded.to_utf8_buffer().size() > MAX_REPORT_BYTES:
		push_error("Visibility fixture report exceeds unchanged 128 KiB contract ceiling")
		game.free(); quit(2); return
	print(encoded)
	game.free()
	quit(1 if failed else 0)

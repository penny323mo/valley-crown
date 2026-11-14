extends SceneTree
# PREPARED ONLY. Exercise real game projection/lifecycle, not hidden authority damage.
const Game = preload("res://scripts/game.gd")
const Rules = preload("res://scripts/rules.gd")
const EXPECTED_BUILD = "vc-9bbce6eb24d8"
var failures := 0
func check(label: String, ok: bool) -> void:
	if not ok: failures += 1; push_error(label)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	check("exact source identity", Rules.BUILD_ID == EXPECTED_BUILD)
	var g = Game.new()
	g.test_mode = true
	root.add_child(g)
	g.set_process(false)
	g._test_reset()
	var records: Dictionary = g.faction_views[0].records().duplicate(true)
	var id := -1
	for key in records:
		if records[key].kind == "town_center" and records[key].owned: id = key; break
	check("fixture keep", id >= 0)
	if id < 0: g.free(); quit(1); return
	var authority_hp = g._get_entity(id).hp
	records[id].hp = int(records[id].max_hp * 0.2)
	g.faction_views[0].current = records
	g._update_visuals(0.1)
	check("projection-only damage despite full authority HP", g.building_damage_presenter.nodes.has(id) and g._get_entity(id).hp == authority_hp)
	var node = g.building_damage_presenter.nodes[id]
	for flag in ["paused","game_over","application_suspended"]:
		g.set(flag,true); g._update_visuals(999.0)
		check(flag + " static no catchup", g.building_damage_presenter.nodes[id] == node)
		g.set(flag,false)
	g.application_focused = false; g._update_visuals(999.0)
	check("focus loss static",g.building_damage_presenter.nodes[id] == node)
	g.application_focused = true
	records[id].remembered = true
	g._update_visuals(0.1)
	check("remembered never retains cue",g.building_damage_presenter.nodes.is_empty())
	records[id].remembered = false; records[id].built = false
	g._update_visuals(0.1)
	check("construction excluded",g.building_damage_presenter.nodes.is_empty())
	records[id].built = true
	g._update_visuals(0.1)
	g._test_reset()
	check("restart clears",g.building_damage_presenter.nodes.is_empty() and g.building_damage_presenter.meshes.is_empty())
	# Actual observed enemy proxy, never a hidden authority node.
	g.visible_cells[0].fill(1)
	g._publish_faction_views()
	var enemy_records: Dictionary = g.faction_views[0].records().duplicate(true)
	var enemy_id := -1
	for key in enemy_records:
		if enemy_records[key].kind == "town_center" and not enemy_records[key].owned: enemy_id = key; break
	check("enemy fixture",enemy_id >= 0)
	if enemy_id >= 0:
		g.faction_views[0].current = enemy_records
		var r: Dictionary = enemy_records[enemy_id]
		r.hp = int(r.max_hp * 0.2); r.built = false; r.progress = 0.5
		g._update_visuals(0.1)
		check("enemy incomplete excluded",not g.building_damage_presenter.nodes.has(enemy_id))
		r.built = true; r.progress = 1.0
		g._update_visuals(0.1)
		var proxy = g.presentation_nodes[enemy_id]
		var original_overrides: Dictionary = {}
		collect_materials(proxy.body,original_overrides)
		check("cue is game sibling not model/proxy child",g.building_damage_presenter.nodes[enemy_id].get_parent() == g)
		r.remembered = true; g._update_visuals(0.1)
		check("actual gray proxy has no stale cue",proxy.remembered and not g.building_damage_presenter.nodes.has(enemy_id))
		r.hp = 1; g._update_visuals(999.0)
		check("remembered progression cannot create cue",not g.building_damage_presenter.nodes.has(enemy_id))
		r.remembered = false; g._update_visuals(0.1)
		var restored: Dictionary = {}
		collect_materials(proxy.body,restored)
		check("reveal restores overrides and cue",restored == original_overrides and g.building_damage_presenter.nodes.has(enemy_id))
		enemy_records.erase(enemy_id); g._update_visuals(0.1)
		check("projected death removes cue",not g.building_damage_presenter.nodes.has(enemy_id))
	g.free()
	print("BUILDING_DAMAGE_PROJECTION ", EXPECTED_BUILD," failures=",failures)
	quit(1 if failures else 0)

func collect_materials(node: Node, result: Dictionary) -> void:
	if node is MeshInstance3D: result[node.get_instance_id()] = node.material_override
	for child in node.get_children(): collect_materials(child,result)

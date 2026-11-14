extends SceneTree
# PREPARED ONLY: requires native execution; no engine run is claimed.
const Presenter = preload("res://scripts/building_damage_presenter.gd")
const Rules = preload("res://scripts/rules.gd")
const EXPECTED_BUILD = "vc-be8c3c2f8ca5"
var failures := 0
var check_rows: Array = []
func check(label: String, ok: bool) -> void:
	check_rows.append({"name":label,"pass":ok})
	if not ok: failures += 1; push_error(label)
func record(id: int, kind: String = "house", hp: int = 40) -> Dictionary:
	return {"id":id,"kind":kind,"category":"building","remembered":false,"alive":true,"built":true,"hp":hp,"max_hp":100,"owned":true,"pos":Vector3.ZERO}
func _initialize() -> void:
	check("exact source identity", Rules.BUILD_ID == EXPECTED_BUILD)
	var host := Node3D.new()
	root.add_child(host)
	var p := Presenter.new()
	for kind in Rules.FOOTPRINT:
		for level in [1,2]:
			var mesh := Presenter.make_mesh(kind,level)
			check("three surfaces", mesh.get_surface_count() == 3)
			var aabb := mesh.get_aabb()
			var half := float(Rules.FOOTPRINT[kind]) * 0.5
			check("footprint containment", aabb.position.x >= -half and aabb.end.x <= half and aabb.position.z >= -half and aabb.end.z <= half)
			check("low debris", aabb.position.y >= 0 and aabb.end.y <= 0.105)
	for pair in [[100,0],[56,0],[55,1],[26,1],[25,2],[1,2],[0,0]]:
		check("HP boundary " + str(pair), Presenter.tier(record(1,"house",pair[0])) == pair[1])
	for invalid in [{"remembered":true},{"built":false},{"alive":false},{"category":"unit"},{"kind":"unknown"},{"max_hp":0},{"hp":NAN},{"hp":-1},{"max_hp":INF},{"max_hp":NAN}]:
		var r := record(1); r.merge(invalid,true)
		check("reject " + str(invalid), Presenter.tier(r) == 0)
	var current := record(1)
	p.update({1:current},host)
	var node = p.nodes[1]
	var mesh = node.mesh
	for i in 50: p.update({1:current},host)
	check("static pause/end equivalent, no elapsed input", p.nodes[1] == node and p.nodes[1].mesh == mesh and node.position == Vector3.ZERO)
	current.owned = false
	p.update({1:current},host)
	check("visible enemy allowed", p.nodes.size() == 1)
	current.remembered = true
	p.update({1:current},host)
	check("fog retirement immediate", p.nodes.is_empty() and host.get_child_count() == 0 and not is_instance_valid(node))
	current.hp = 1
	p.update({1:current},host)
	check("hidden changes ignored", p.nodes.is_empty())
	current.remembered = false
	p.update({1:current},host)
	check("reveal current severe", p.nodes.size() == 1)
	current.hp = 56
	p.update({1:current},host)
	check("repair clears", p.nodes.is_empty())
	for cycle in 10:
		var records: Dictionary = {}
		for i in 100: records[i+cycle*100] = record(i+cycle*100)
		p.update(records,host)
		check("hard node cap", p.nodes.size() == 64 and host.get_child_count() == 64)
		p.update({},host)
		check("same-frame death/hide no deferred nodes", host.get_child_count() == 0)
	check("mesh cache bounded", p.meshes.size() <= 10)
	p.clear()
	check("restart/teardown clears cache", p.nodes.is_empty() and p.meshes.is_empty())
	host.free()
	print(JSON.stringify({"suite":"building_damage_component","build":EXPECTED_BUILD,"checks":check_rows,"passed":check_rows.size()-failures,"failed":failures}))
	quit(1 if failures else 0)

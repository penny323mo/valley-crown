extends RefCounted
## Static damage condition, not fire or an ongoing-damage effect.
## Caller supplies faction-0 value projections only. Never attached to asset bodies.
const Rules = preload("res://scripts/rules.gd")
const SOOT_SHADER = preload("res://assets/mature/shaders/building_damage_soot.gdshader")
const MAX_ACTIVE := 64
const MAX_MESHES := 18 # Nine building profiles, two damage tiers; bounded cache.
var nodes: Dictionary = {}
var meshes: Dictionary = {}

static func tier(record: Dictionary) -> int:
	if record.get("category", "") != "building" or record.get("remembered", true): return 0
	if not record.get("alive", false) or not record.get("built", false): return 0
	if not Rules.FOOTPRINT.has(record.get("kind", "")): return 0
	var hp := float(record.get("hp", 0))
	var maximum := float(record.get("max_hp", 0))
	if not is_finite(hp) or not is_finite(maximum) or maximum <= 0 or hp <= 0: return 0
	var ratio := hp / maximum
	return 2 if ratio <= 0.25 else (1 if ratio <= 0.55 else 0)

func update(records: Dictionary, parent: Node3D) -> void:
	# Retire before allocating replacements, including capacity-priority changes.
	var eligible := records.keys()
	eligible.sort()
	var keep: Dictionary = {}
	for id in eligible:
		if tier(records[id]) > 0 and keep.size() < MAX_ACTIVE: keep[id] = true
	for id in nodes.keys():
		if not keep.has(id): _remove(id)
	var wanted: Dictionary = {}
	var ids := records.keys()
	ids.sort()
	for id in ids:
		var record: Dictionary = records[id]
		var level := tier(record)
		if level == 0 or wanted.size() >= MAX_ACTIVE: continue
		wanted[id] = true
		var key := str(record.kind) + ":" + str(level)
		if not meshes.has(key):
			assert(meshes.size() < MAX_MESHES)
			meshes[key] = make_mesh(record.kind, level)
		if not nodes.has(id):
			var instance := MeshInstance3D.new()
			instance.name = "ObservedBuildingDamage_" + str(id)
			instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			parent.add_child(instance)
			nodes[id] = instance
		var instance: MeshInstance3D = nodes[id]
		instance.mesh = meshes[key]
		instance.position = record.pos
		# Footprints are world-aligned; do not rotate debris into legal egress.
	for id in nodes.keys():
		if not wanted.has(id): _remove(id)

func _remove(id) -> void:
	var instance: MeshInstance3D = nodes[id]
	# Immediate retirement; repeated hide/reveal cannot accumulate queued nodes.
	instance.visible = false
	if instance.get_parent() != null: instance.get_parent().remove_child(instance)
	instance.free()
	nodes.erase(id)

func clear() -> void:
	for id in nodes.keys(): _remove(id)
	meshes.clear()

static func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1.0
	return material

static func make_mesh(kind: String, level: int) -> ArrayMesh:
	assert(Rules.FOOTPRINT.has(kind) and level in [1, 2])
	var half := float(Rules.FOOTPRINT[kind]) * 0.5
	var soot := SurfaceTool.new()
	soot.begin(Mesh.PRIMITIVE_TRIANGLES)
	var material := ShaderMaterial.new()
	material.shader = SOOT_SHADER
	soot.set_material(material)
	var stone := SurfaceTool.new()
	stone.begin(Mesh.PRIMITIVE_TRIANGLES)
	stone.set_material(_material(Color("777366")))
	var timber := SurfaceTool.new()
	timber.begin(Mesh.PRIMITIVE_TRIANGLES)
	timber.set_material(_material(Color("34322c")))
	# Fixed low discrepancy offsets: no game RNG, no time or remembered state.
	# Three/six irregular ground patches and six/twelve small fragments.
	for i in range(3 * level):
		var angle := float(i) * 2.399963 + float(kind.length()) * 0.31
		var direction := Vector3(cos(angle), 0, sin(angle))
		# Corner apron, independent of shifted halls and their taller roof bounds.
		var anchors := [Vector2(-1,-1),Vector2(1,1),Vector2(-1,1),Vector2(1,-1),Vector2(1,0.6),Vector2(-0.6,-1)]
		var center := Vector3(anchors[i].x, 0, anchors[i].y) * (half - 0.15)
		center.y = 0.085 if kind == "farm" else 0.024
		for j in range(8):
			var a := float(j) * TAU / 8.0
			var b := float(j + 1) * TAU / 8.0
			var radius_a := 0.11 + 0.015 * float((j + i) % 3)
			var radius_b := 0.11 + 0.015 * float((j + i + 1) % 3)
			for vertex in [Vector3.ZERO, Vector3(cos(b)*radius_b, 0, sin(b)*radius_b*0.65), Vector3(cos(a)*radius_a, 0, sin(a)*radius_a*0.65)]:
				soot.set_uv(Vector2(vertex.x / 0.14, vertex.z / 0.092))
				soot.set_normal(Vector3.UP)
				soot.add_vertex(center + vertex)
		var chip := BoxMesh.new()
		chip.size = Vector3(0.07 + 0.012 * float(i % 3), 0.09, 0.10)
		stone.append_from(chip, 0, Transform3D(Basis(Vector3.UP, angle), center + Vector3(0, 0.035, 0)))
		var splinter := BoxMesh.new()
		splinter.size = Vector3(0.04, 0.055, 0.14 + 0.015 * float(i % 2))
		timber.append_from(splinter, 0, Transform3D(Basis(Vector3.UP, angle + 0.8), center + direction * 0.03 + Vector3(0, 0.01, 0)))
	var mesh := soot.commit()
	stone.commit(mesh)
	timber.commit(mesh)
	return mesh

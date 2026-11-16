extends SceneTree
## Actual game observation/picking regression for an authorized hosted run.
## Controlled fixtures only, not an ordinary-match or rendered acceptance test.
const Visuals = preload("res://scripts/advanced_building_visuals.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(label: String, value: bool) -> void:
	checks += 1
	if not value: failures.append(label)

func publish(game) -> void:
	game._publish_faction_views()
	game._update_visuals(0.0)

func run() -> void:
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game.test_mode = true
	game.ai_enabled = false
	for index in range(Visuals.KINDS.size()):
		var kind: String = Visuals.KINDS[index]
		var point := Vector3(-8.0+index*5.0,0,12)
		game.visible_cells[0].fill(0)
		var enemy: Dictionary = game._spawn(kind,1,point,false)
		publish(game)
		check(kind+" unseen creates no proxy",not game.presentation_nodes.has(enemy.id) and not enemy.node.visible)
		enemy.progress = 0.3
		game.visible_cells[0][game._cell_index(enemy.pos)] = 1
		publish(game)
		check(kind+" observed proxy created",game.presentation_nodes.has(enemy.id))
		if not game.presentation_nodes.has(enemy.id): continue
		var proxy: Dictionary = game.presentation_nodes[enemy.id]
		check(kind+" observed frame",proxy.node.visible and proxy.body.get_meta("construction_stage") == 1)
		game.visible_cells[0][game._cell_index(enemy.pos)] = 0
		publish(game)
		var site := proxy.body.get_node("ConstructionSite") as MeshInstance3D
		var remembered_mesh: Mesh = site.mesh
		check(kind+" remembered gray scaffold",proxy.remembered and site.material_override != null)
		enemy.built = true
		enemy.progress = 1.0
		publish(game)
		check(kind+" hidden completion does not leak",proxy.body.get_meta("construction_stage") == 1 and site.mesh == remembered_mesh and not game.faction_views[0].get_record(enemy.id).built)
		game.visible_cells[0][game._cell_index(enemy.pos)] = 1
		publish(game)
		check(kind+" reveal completed asset",not proxy.remembered and proxy.body.get_child(0).visible and not site.visible)
		check(kind+" bar uses measured top",is_equal_approx(proxy.bar.position.y,Visuals.health_bar_height(kind)))
		var screen: Vector2 = game.camera.unproject_position(enemy.pos+Vector3(0,1,0))
		check(kind+" existing selection anchor picks observed building",game._pick(screen) == enemy.id)
		enemy.hp = enemy.max_hp/5
		publish(game)
		check(kind+" observed low health damage",game.building_damage_presenter.nodes.has(enemy.id) and proxy.bar.visible)
		game.visible_cells[0][game._cell_index(enemy.pos)] = 0
		publish(game)
		check(kind+" hidden health damage suppressed",not game.building_damage_presenter.nodes.has(enemy.id) and not proxy.bar.visible)
		for mesh: MeshInstance3D in proxy.body.get_child(0).find_children("*","MeshInstance3D",true,false):
			check(kind+" remembered complete mesh gray",mesh.material_override != null)
		enemy.alive = false
		publish(game)
		check(kind+" unseen destruction preserves memory",proxy.node.visible and proxy.remembered)
		game.visible_cells[0][game._cell_index(enemy.pos)] = 1
		publish(game)
		check(kind+" observed empty site hides memory",not proxy.node.visible)
	game.free()
	print(JSON.stringify({"suite":"advanced_building_observation","checks":checks,"failures":failures,"ordinary_gameplay_visual":"NOT_TESTED"}))
	quit(0 if failures.is_empty() else 1)

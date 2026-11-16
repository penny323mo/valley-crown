extends SceneTree
## Hosted-only geometry/visibility contract. Not visual acceptance or gameplay QA.
const Visual = preload("res://assets/mature/visual_library.gd")
const Construction = preload("res://scripts/construction_visual.gd")
var checks := 0
var failures: Array = []
var check_rows: Array = []
func check(value: bool, label: String) -> void:
	checks += 1
	check_rows.append({"name":label,"pass":value})
	if not value:
		failures.append(label)
		push_error(label)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 1 or FileAccess.file_exists(args[0]):
		push_error("Expected one new report output path")
		quit(1)
		return
	for pair in [[0.0,0],[0.1499,0],[0.15,1],[0.6499,1],[0.65,2],[0.9999,2],[1.0,2]]:
		check(Construction.stage_for(false,pair[0]) == pair[1],"stage follows observed progress")
	check(Construction.stage_for(true,0.0) == 3,"built flag alone controls completion")
	for kind in Visual.BUILDING_KINDS:
		var body := Node3D.new()
		root.add_child(body)
		var finished := Visual.instantiate_asset(kind)
		body.add_child(finished)
		var before := finished.transform
		check(Construction._material(body,"stone") != null,"existing stone material present")
		check(Construction._material(body,"oak") != null,"existing oak material present")
		for progress in [0.0,0.25,0.90]:
			Construction.apply(body,kind,false,progress)
			var site := body.get_node("ConstructionSite") as MeshInstance3D
			check(site.visible and not finished.visible,"only construction mesh visible")
			check(body.scale == Vector3.ONE and finished.transform == before,"no architecture squash")
			check(site.mesh.get_surface_count() == 2,"two surface draw ceiling")
			var triangles := 0
			for surface in site.mesh.get_surface_count():
				check(site.mesh.surface_get_material(surface) != null,"retained existing material")
				var arrays := site.mesh.surface_get_arrays(surface)
				triangles += arrays[Mesh.ARRAY_INDEX].size()/3 if arrays[Mesh.ARRAY_INDEX].size() > 0 else arrays[Mesh.ARRAY_VERTEX].size()/3
			check(triangles <= 192,"bounded triangle budget")
			var bounds := site.mesh.get_aabb()
			var dimensions: Vector3 = Construction.DIMENSIONS[kind]
			check(bounds.position.y >= -0.001,"no underground mesh")
			check(bounds.size.x <= dimensions.x+0.001 and bounds.size.z <= dimensions.z+0.001,"site stays within authored footprint")
			var proxy := body.duplicate() as Node3D
			root.add_child(proxy)
			Construction.apply(proxy,kind,false,progress)
			check(proxy.get_node("ConstructionSite").visible and not proxy.get_child(0).visible,"duplicated observed site stage survives")
			proxy.visible = false
			Construction.apply(proxy,kind,true,1.0)
			check(not proxy.visible,"presentation never reveals a hidden entity")
			check(not proxy.get_node("ConstructionSite").visible and proxy.get_child(0).visible,"proxy completion restores original")
			proxy.free()
		Construction.apply(body,kind,true,1.0)
		check(finished.visible and finished.transform == before,"completed model restored unchanged")
		check(not body.get_node("ConstructionSite").visible,"no site draws after completion")
		body.free()
	fog_lifecycle()
	var report := {"passed":checks-failures.size(),"failed":failures.size(),"checks":check_rows,"build":load("res://scripts/rules.gd").BUILD_ID,"scope":"controlled geometry and actual observation lifecycle; not ordinary gameplay or visual acceptance"}
	var file := FileAccess.open(args[0],FileAccess.WRITE)
	if file == null:
		push_error("Cannot create construction contract report")
		quit(1)
		return
	file.store_string(JSON.stringify(report,"  ")+"\n")
	file.close()
	print("CONSTRUCTION_VISUAL_CONTRACT passed=",report.passed," failed=",report.failed)
	quit(0 if failures.is_empty() else 1)

func publish(game) -> void:
	game._publish_faction_views()
	game._update_visuals(0.0)

func fog_lifecycle() -> void:
	# Controlled authority and visibility setup, kept out of normal touch capture.
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game.test_mode = true
	game.ai_enabled = false
	game.visible_cells[0].fill(0)
	var enemy: Dictionary = game._spawn("house",1,Vector3.ZERO,false)
	publish(game)
	check(not game.faction_views[0].records().has(enemy.id) and not game.presentation_nodes.has(enemy.id) and not enemy.node.visible,"unseen site creates no presentation")
	enemy.progress = 0.25
	game.visible_cells[0][game._cell_index(enemy.pos)] = 1
	publish(game)
	check(game.presentation_nodes.has(enemy.id),"visible site creates observed proxy")
	if not game.presentation_nodes.has(enemy.id):
		game.free()
		return
	var proxy: Dictionary = game.presentation_nodes[enemy.id]
	var site := proxy.body.get_node("ConstructionSite") as MeshInstance3D
	check(proxy.node.visible and proxy.body.get_meta("construction_stage") == 1 and site.visible,"observed wall stage uses actual published progress")
	game.visible_cells[0][game._cell_index(enemy.pos)] = 0
	publish(game)
	var remembered_mesh: Mesh = site.mesh
	check(proxy.remembered and site.material_override != null,"remembered frame uses existing gray override")
	enemy.progress = 0.9
	publish(game)
	check(game.faction_views[0].get_record(enemy.id).progress == 0.25 and proxy.body.get_meta("construction_stage") == 1 and site.mesh == remembered_mesh,"hidden progress cannot advance remembered frame")
	enemy.progress = 1.0
	enemy.built = true
	publish(game)
	check(not game.faction_views[0].get_record(enemy.id).built and proxy.body.get_meta("construction_stage") == 1 and site.visible,"hidden completion cannot reveal finished architecture")
	game.visible_cells[0][game._cell_index(enemy.pos)] = 1
	publish(game)
	check(not proxy.remembered and proxy.body.get_meta("construction_stage") == 3 and not site.visible and proxy.body.get_child(0).visible,"reobservation restores original completed architecture")
	check(site.material_override == null,"reobservation clears remembered site override")
	game.visible_cells[0][game._cell_index(enemy.pos)] = 0
	publish(game)
	enemy.alive = false # Controlled unseen destruction, not combat evidence.
	publish(game)
	check(game.faction_views[0].get_record(enemy.id).remembered and proxy.node.visible,"unseen destruction retains static memory")
	game.visible_cells[0][game._cell_index(enemy.pos)] = 1
	publish(game)
	check(not game.faction_views[0].records().has(enemy.id) and not proxy.node.visible,"visible empty site retires remembered construction")
	game.free()

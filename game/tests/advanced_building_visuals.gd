extends SceneTree
## Component/resource checks for an authorized hosted Godot run. Not visual QA.
const Visuals = preload("res://scripts/advanced_building_visuals.gd")
const Construction = preload("res://scripts/construction_visual.gd")
const Damage = preload("res://scripts/building_damage_presenter.gd")
const Rules = preload("res://scripts/rules.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(label: String, value: bool) -> void:
	checks += 1
	if not value: failures.append(label)

func collect_bounds(node: Node3D) -> AABB:
	var initialized := false
	var result := AABB()
	for child: MeshInstance3D in node.find_children("*","MeshInstance3D",true,false):
		var transform := node.global_transform.affine_inverse() * child.global_transform
		for vertex in child.mesh.get_faces():
			var point: Vector3 = transform * vertex
			if not initialized:
				result = AABB(point,Vector3.ZERO)
				initialized = true
			else: result = result.expand(point)
	return result

func run() -> void:
	for kind in Visuals.KINDS:
		var body := Node3D.new()
		root.add_child(body)
		var blue := Color("435d6c")
		var red := Color("9b4c42")
		var model: Node3D = Visuals.instantiate_asset(kind,blue)
		body.add_child(model)
		var red_model: Node3D = Visuals.instantiate_asset(kind,red)
		root.add_child(red_model)
		check(kind+" has no collider",model.find_children("*","CollisionObject3D",true,false).is_empty())
		check(kind+" has no animation controller",model.find_children("*","AnimationPlayer",true,false).is_empty())
		var bounds := collect_bounds(model)
		var half := float(Rules.FOOTPRINT[kind])*0.5
		check(kind+" complete bounds fit footprint",bounds.position.x >= -half and bounds.end.x <= half and bounds.position.z >= -half and bounds.end.z <= half)
		check(kind+" foundation grounded",absf(bounds.position.y) < 0.003)
		check(kind+" measured top",absf(bounds.end.y-float(Visuals.HEIGHTS[kind])) < 0.004)
		check(kind+" health bar clears all geometry",Visuals.health_bar_height(kind)-0.035 > bounds.end.y+0.20)
		var meshes := model.find_children("*","MeshInstance3D",true,false)
		var red_meshes := red_model.find_children("*","MeshInstance3D",true,false)
		var surfaces := 0
		var faction_surfaces := 0
		for index in range(meshes.size()):
			var mesh: MeshInstance3D = meshes[index]
			var red_mesh: MeshInstance3D = red_meshes[index]
			surfaces += mesh.mesh.get_surface_count()
			for surface in range(mesh.mesh.get_surface_count()):
				var source: Material = mesh.mesh.surface_get_material(surface)
				var standard := source as StandardMaterial3D
				check(kind+" material has exact name",source.resource_name in ["stone","oak","plaster","slate","clay","palette","team_blue"])
				check(kind+" opaque material",standard != null and standard.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED)
				if source.resource_name == "team_blue":
					faction_surfaces += 1
					var blue_material := mesh.get_active_material(surface) as StandardMaterial3D
					var red_material := red_mesh.get_active_material(surface) as StandardMaterial3D
					check(kind+" blue cloth override",blue_material != null and blue_material.albedo_color.is_equal_approx(blue))
					check(kind+" red cloth override",red_material != null and red_material.albedo_color.is_equal_approx(red))
					check(kind+" immutable shared cloth",source != mesh.get_active_material(surface) and source != red_mesh.get_active_material(surface))
				else:
					check(kind+" neutral roof and surfaces",mesh.get_surface_override_material(surface) == null and red_mesh.get_surface_override_material(surface) == null)
		check(kind+" material budget",surfaces <= 6)
		check(kind+" exactly one cloth batch",faction_surfaces == 1)
		for stage in range(3):
			Construction.apply(body,kind,false,[0.0,0.3,0.8][stage])
			var site := body.get_node("ConstructionSite") as MeshInstance3D
			check(kind+" construction hides completed asset",not model.visible and site.visible)
			var site_bounds := site.mesh.get_aabb()
			check(kind+" construction bounds fit footprint",site_bounds.position.x >= -half and site_bounds.end.x <= half and site_bounds.position.z >= -half and site_bounds.end.z <= half)
			check(kind+" construction bar clearance",site_bounds.end.y < Visuals.health_bar_height(kind)-0.035)
			for surface in range(site.mesh.get_surface_count()):
				check(kind+" construction materials resolved",site.mesh.surface_get_material(surface) != null)
		Construction.apply(body,kind,true,1.0)
		check(kind+" completed asset restored",model.visible and not body.get_node("ConstructionSite").visible)
		for tier in [1,2]:
			var damage := Damage.make_mesh(kind,tier)
			var damage_bounds := damage.get_aabb()
			check(kind+" damage footprint",damage_bounds.position.x >= -half and damage_bounds.end.x <= half and damage_bounds.position.z >= -half and damage_bounds.end.z <= half)
			if kind == "farm": check("farm soot above soil",damage.surface_get_arrays(0)[Mesh.ARRAY_VERTEX][0].y > 0.07)
		body.free()
		red_model.free()
	print(JSON.stringify({"suite":"advanced_building_visuals","checks":checks,"failures":failures,"visual_acceptance":"NOT_TESTED"}))
	quit(0 if failures.is_empty() else 1)

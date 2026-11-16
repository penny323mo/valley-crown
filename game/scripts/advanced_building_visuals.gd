extends RefCounted
## Static, presentation-only buildings. No entity, navigation or economy access.
## The importer creates shared immutable meshes. Only faction cloth is overridden.
const MatureVisuals = preload("res://assets/mature/visual_library.gd")
const KINDS = ["stable", "workshop", "tower", "farm"]
const SCENES = {
	"stable": preload("res://assets/advanced_buildings/stable.gltf"),
	"workshop": preload("res://assets/advanced_buildings/workshop.gltf"),
	"tower": preload("res://assets/advanced_buildings/tower.gltf"),
	"farm": preload("res://assets/advanced_buildings/farm.gltf"),
}
# Measured source bounds include every eave, banner, wheel, rail and grain ear.
const HEIGHTS = {"stable": 2.375, "workshop": 3.020, "tower": 3.910, "farm": 0.727}

static func instantiate_asset(kind: String, team: Color) -> Node3D:
	assert(SCENES.has(kind))
	var scene: PackedScene = SCENES[kind]
	var root := scene.instantiate() as Node3D
	root.name = "AdvancedBuilding"
	root.set_meta("asset_kind", kind)
	MatureVisuals.apply_team_color(root, team)
	return root

static func health_bar_height(kind: String) -> float:
	return float(HEIGHTS.get(kind, 4.25)) + 0.25

extends RefCounted
## Presentation-only loader. It never reads or writes game state.
const ROOT="res://assets/mature/models/"
const UNIT_KINDS=["villager","scout","spearman","archer"]
const BUILDING_KINDS=["town_center","house","storehouse","barracks","range"]
const DEFAULT_TEAM=Color("435d6c")
static func instantiate_asset(kind: String,variant: int=0,team_color: Color=DEFAULT_TEAM) -> Node3D:
	var suffix:="_"+str(posmod(variant,3)) if kind=="pine" else ("_"+str(posmod(variant,2)) if kind=="oak" else "")
	var path:=ROOT+kind+suffix+".scn"
	if not ResourceLoader.exists(path):
		push_error("Missing original visual asset: "+path)
		return null
	var root:Node3D=(load(path) as PackedScene).instantiate()
	apply_team_color(root,team_color)
	return root
static func apply_team_color(node: Node,team_color: Color) -> void:
	if node is MeshInstance3D:
		for surface in range(node.mesh.get_surface_count()):
			var material=node.mesh.surface_get_material(surface)
			if material is StandardMaterial3D and material.resource_name=="team_blue":
				var instance:StandardMaterial3D=material.duplicate()
				instance.albedo_color=team_color
				node.set_surface_override_material(surface,instance)
	for child in node.get_children():apply_team_color(child,team_color)

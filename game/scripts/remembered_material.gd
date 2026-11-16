extends RefCounted
## Dim observed materials, preserving leaf cutouts, textures and surface layout.
## Never mutates shared source resources; restoring visibility restores originals.
static func dim_material(source: Material) -> Material:
	if source is BaseMaterial3D:
		var result = source.duplicate() as BaseMaterial3D
		result.albedo_color = source.albedo_color * Color(0.48,0.52,0.50,1.0)
		return result
	if source != null:
		return source # Unknown shaders must retain their transparency contract.
	var fallback = StandardMaterial3D.new()
	fallback.albedo_color = Color("777b79")
	return fallback

static func apply(node: Node, remembered: bool) -> void:
	if node is MeshInstance3D:
		if not node.has_meta("observed_material_override"):
			node.set_meta("observed_material_override",node.material_override)
			var original_surfaces: Array = []
			if node.mesh != null:
				for i in node.mesh.get_surface_count():
					original_surfaces.append(node.get_surface_override_material(i))
			node.set_meta("observed_surface_overrides",original_surfaces)
		var original = node.get_meta("observed_material_override")
		var surfaces: Array = node.get_meta("observed_surface_overrides")
		if original != null:
			node.material_override = dim_material(original) if remembered else original
		elif node.mesh != null:
			node.material_override = null
			for i in node.mesh.get_surface_count():
				var source = surfaces[i] if i < surfaces.size() else null
				if remembered:
					if source == null: source = node.mesh.surface_get_material(i)
					node.set_surface_override_material(i,dim_material(source))
				else:
					node.set_surface_override_material(i,source)
	for child in node.get_children(): apply(child,remembered)

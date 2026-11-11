extends RefCounted
## Observed rigs only. Two transparent geometry passes, no scene-depth sampling.
## Stencil value 1 is reserved for the union of normally visible unit pixels.
## Never enable opaque stencil writes: GLES3 would force a world depth prepass.
const SHADER = preload("res://assets/mature/shaders/observed_occlusion.gdshader")
const MASK_SHADER = preload("res://assets/mature/shaders/observed_visibility_mask.gdshader")
const MASK_PRIORITY := 110
const SILHOUETTE_PRIORITY := 120
var overlays: Array[MeshInstance3D] = []
var material: ShaderMaterial
var mask_material: ShaderMaterial
var enabled := false
var owner_rig: Node3D
var source_surfaces := 0
var supported := false
var unsupported_reason := ""
var unsupported_mesh_path := ""

func bind(rig: Node3D, team_color: Color) -> void:
	assert(rig.get_meta("occlusion_authorized",false))
	release()
	owner_rig=rig
	var source_meshes=rig.find_children("*","MeshInstance3D",true,false)
	# Current normalized action rigs use opaque StandardMaterial3D and bone skinning.
	# Fail closed for new vertex-deformed/alpha assets instead of masking the wrong
	# pixels. Extend matched mask coverage before such art ships.
	for mesh: MeshInstance3D in source_meshes:
		unsupported_reason=_mask_failure(mesh)
		if not unsupported_reason.is_empty():
			unsupported_mesh_path=str(rig.get_path_to(mesh))
			return
	supported=not source_meshes.is_empty()
	if not supported: return
	material=ShaderMaterial.new(); material.shader=SHADER; material.render_priority=SILHOUETTE_PRIORITY
	var tint:=team_color.lightened(.55); tint.a=1.0
	material.set_shader_parameter("silhouette_color",tint)
	mask_material=ShaderMaterial.new(); mask_material.shader=MASK_SHADER
	mask_material.render_priority=MASK_PRIORITY; mask_material.next_pass=material
	# Identity children inherit source mesh TRS and visibility, including animated
	# tool changes, without per-frame synchronization. They resolve the SAME skin
	# skeleton from their new path. All masks precede all silhouettes globally.
	for mesh: MeshInstance3D in source_meshes:
		var overlay:=MeshInstance3D.new()
		overlay.name="ObservedOcclusionOnly"
		overlay.mesh=mesh.mesh; overlay.skin=mesh.skin
		overlay.transform=Transform3D.IDENTITY; overlay.layers=mesh.layers
		overlay.custom_aabb=mesh.custom_aabb
		overlay.extra_cull_margin=mesh.extra_cull_margin
		overlay.lod_bias=mesh.lod_bias
		overlay.material_override=mask_material
		overlay.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		overlay.set_meta("occlusion_overlay",true)
		var skeleton_node: Node=mesh.get_node_or_null(mesh.skeleton) if not mesh.skeleton.is_empty() else null
		mesh.add_child(overlay)
		overlay.skeleton=overlay.get_path_to(skeleton_node) if skeleton_node!=null else NodePath("")
		overlays.append(overlay); source_surfaces+=mesh.mesh.get_surface_count()
	set_authorized(true)

func _mask_failure(mesh: MeshInstance3D) -> String:
	if mesh.mesh==null or mesh.get_meta("occlusion_overlay",false): return "missing_or_overlay_mesh"
	if mesh.get_blend_shape_count()>0 or mesh.material_overlay!=null: return "blend_shape_or_material_overlay"
	if mesh.skin!=null and (mesh.skeleton.is_empty() or not mesh.get_node_or_null(mesh.skeleton) is Skeleton3D): return "unresolved_skin_skeleton"
	if mesh.transparency>0.0: return "instance_transparency"
	if mesh.visibility_range_begin!=0.0 or mesh.visibility_range_end!=0.0: return "visibility_range"
	for surface in mesh.mesh.get_surface_count():
		var source: Material=mesh.get_active_material(surface)
		if not source is BaseMaterial3D: return "custom_or_missing_material"
		var base:=source as BaseMaterial3D
		if base.transparency!=BaseMaterial3D.TRANSPARENCY_DISABLED or base.next_pass!=null: return "alpha_or_material_next_pass"
		# Current four licensed action GLBs are doubleSided=true. Both passes use
		# exactly this winding coverage. Other culling must get its own matched pair.
		if base.cull_mode!=BaseMaterial3D.CULL_DISABLED: return "unmatched_cull_mode"
		if base.grow or base.billboard_mode!=BaseMaterial3D.BILLBOARD_DISABLED or base.use_point_size: return "vertex_deformation"
		if base.use_particle_trails or base.use_z_clip_scale or base.use_fov_override: return "vertex_projection_override"
		if base.no_depth_test or base.depth_test!=BaseMaterial3D.DEPTH_TEST_DEFAULT: return "nonstandard_depth_test"
		if base.depth_draw_mode!=BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY: return "nonstandard_depth_write"
		if base.distance_fade_mode!=BaseMaterial3D.DISTANCE_FADE_DISABLED: return "distance_fade"
		if base.proximity_fade_enabled or base.refraction_enabled or base.shadow_to_opacity: return "alpha_effect"
		if base.stencil_mode!=BaseMaterial3D.STENCIL_MODE_DISABLED: return "reserved_stencil_conflict"
	return ""

func set_authorized(authorized: bool) -> void:
	# Metadata is the observation/death boundary. A debug toggle cannot reauthorize
	# a corpse or a released rig. Hidden ancestors cull both passes normally.
	enabled=authorized and supported and is_instance_valid(owner_rig) and owner_rig.get_meta("occlusion_authorized",false)
	for overlay in overlays: overlay.visible=enabled

func stats() -> Dictionary:
	return {"authorized":enabled,"supported":supported,"overlay_meshes":overlays.size(),
		"unsupported_reason":unsupported_reason,"unsupported_mesh_path":unsupported_mesh_path,
		"source_cull_mode":"disabled","source_transform_visibility":"inherited from source mesh parent",
		"source_surfaces":source_surfaces,"extra_surface_draws_max":source_surfaces*2,
		"extra_skinning_passes_max":2,"mask_priority":MASK_PRIORITY,"silhouette_priority":SILHOUETTE_PRIORITY,
		"depth_samples_per_fragment":0,"extra_viewports":0,"fullscreen_passes":0,
		"opaque_stencil_writes":false,"mode":"transparent visibility stencil then flat silhouette"}

func release() -> void:
	for overlay in overlays:
		if is_instance_valid(overlay): overlay.free()
	overlays.clear(); material=null; mask_material=null; owner_rig=null
	enabled=false; supported=false; source_surfaces=0
	unsupported_reason=""; unsupported_mesh_path=""

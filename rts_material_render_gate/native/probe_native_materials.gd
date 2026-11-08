extends SceneTree
# External data-only inspection. Never changes importer, runtime scripts or scenes.
const KINDS = ["villager", "spearman", "archer", "scout"]
func _initialize(): call_deferred("run")
func digest_bytes(data: PackedByteArray) -> String:
	var context = HashingContext.new()
	assert(context.start(HashingContext.HASH_SHA256) == OK)
	assert(context.update(data) == OK)
	return context.finish().hex_encode()
func field_arrays(scene: Node) -> Array:
	var result: Array = []
	for mesh in scene.find_children("*", "MeshInstance3D", true, false):
		for surface in mesh.mesh.get_surface_count():
			var material = mesh.get_active_material(surface)
			if material.resource_name == "field_textured":
				assert(result.is_empty())
				result = mesh.mesh.surface_get_arrays(surface)
	assert(not result.is_empty())
	return result
func run():
	var report = {}
	var baseline_mode = "--baseline" in OS.get_cmdline_user_args()
	var baseline = {}
	if not baseline_mode:
		baseline = JSON.parse_string(FileAccess.get_file_as_string("res://reports/native-material-baseline.json"))
	for kind in KINDS:
		var path = "res://assets/mature/models/" + kind + "_action.scn"
		var atlas_path = "res://art/action_characters/textures/" + kind + "_atlas.png"
		var packed = load(path) as PackedScene
		assert(packed != null)
		var scene = packed.instantiate()
		if baseline_mode:
			var team_count = 0
			for mesh in scene.find_children("*", "MeshInstance3D", true, false):
				for surface in mesh.mesh.get_surface_count():
					var mat = mesh.get_active_material(surface) as StandardMaterial3D
					assert(mat != null)
					if mat.resource_name == "team_blue":
						team_count += 1
						report[kind] = {"team_rgba":[mat.albedo_color.r,mat.albedo_color.g,mat.albedo_color.b,mat.albedo_color.a],"roughness":mat.roughness,"specular":mat.metallic_specular,"vertex_tint":mat.vertex_color_use_as_albedo,"has_texture":mat.albedo_texture != null,"native_sha256":FileAccess.get_sha256(path)}
			assert(team_count == 1)
			scene.free()
			continue
		var atlas = Image.load_from_file(atlas_path)
		assert(atlas != null and not atlas.is_empty())
		atlas = atlas.duplicate()
		atlas.clear_mipmaps()
		atlas.convert(Image.FORMAT_RGBA8)
		# Same reserved white sample checked by generated GLB validator.
		assert(atlas.get_pixel(128,127).is_equal_approx(Color.WHITE))
		var source_path = "res://art/action_characters/interchange/" + kind + ".glb"
		var doc = GLTFDocument.new()
		var state = GLTFState.new()
		assert(doc.append_from_file(source_path, state) == OK)
		var source_scene = doc.generate_scene(state,30.0,false,false)
		assert(source_scene != null)
		var expected_arrays = field_arrays(source_scene)
		var body_count = 0
		var prop_count = 0
		var field_state = {}
		var image_sha = ""
		var fields = 0
		var teams = 0
		for mesh in scene.find_children("*", "MeshInstance3D", true, false):
			for surface in mesh.mesh.get_surface_count():
				var material = mesh.get_active_material(surface) as StandardMaterial3D
				assert(material != null)
				assert(abs(material.roughness - .94) < .00001 and abs(material.metallic_specular - .15) < .00001)
				if material.resource_name == "field_textured":
					fields += 1
					assert(material.albedo_texture != null and material.albedo_color.is_equal_approx(Color.WHITE) and material.vertex_color_use_as_albedo)
					assert(not material.uv1_triplanar and material.uv1_scale.is_equal_approx(Vector3.ONE) and material.uv1_offset.is_equal_approx(Vector3.ZERO))
					var actual = material.albedo_texture.get_image()
					assert(actual != null and not actual.is_empty())
					actual = actual.duplicate()
					if actual.is_compressed(): assert(actual.decompress() == OK)
					actual.clear_mipmaps()
					actual.convert(Image.FORMAT_RGBA8)
					assert(actual.get_size() == atlas.get_size() and actual.get_data() == atlas.get_data())
					var arrays = mesh.mesh.surface_get_arrays(surface)
					assert(arrays[Mesh.ARRAY_TEX_UV] != null and arrays[Mesh.ARRAY_TEX_UV].size() == arrays[Mesh.ARRAY_VERTEX].size())
					assert(arrays[Mesh.ARRAY_COLOR] != null and arrays[Mesh.ARRAY_COLOR].size() == arrays[Mesh.ARRAY_VERTEX].size())
					assert(arrays[Mesh.ARRAY_VERTEX].size() == expected_arrays[Mesh.ARRAY_VERTEX].size())
					for index in arrays[Mesh.ARRAY_VERTEX].size():
						var uv = arrays[Mesh.ARRAY_TEX_UV][index]
						var color = arrays[Mesh.ARRAY_COLOR][index]
						assert(uv.is_equal_approx(expected_arrays[Mesh.ARRAY_TEX_UV][index]))
						assert(color.is_equal_approx(expected_arrays[Mesh.ARRAY_COLOR][index]))
						# glTF V is flipped from Blender's authored (.125,.875).
						if uv.is_equal_approx(Vector2(.125,.125)):
							prop_count += 1
						else:
							body_count += 1
							assert(color.is_equal_approx(Color.WHITE))
					assert(body_count > 0 and prop_count > 0)
					image_sha = digest_bytes(actual.get_data())
					field_state = {"vertex_tint":material.vertex_color_use_as_albedo,"roughness":material.roughness,"specular":material.metallic_specular,"albedo_rgba":[material.albedo_color.r,material.albedo_color.g,material.albedo_color.b,material.albedo_color.a],"uv1_triplanar":material.uv1_triplanar,"uv1_scale":[material.uv1_scale.x,material.uv1_scale.y,material.uv1_scale.z],"uv1_offset":[material.uv1_offset.x,material.uv1_offset.y,material.uv1_offset.z]}
				elif material.resource_name == "team_blue":
					teams += 1
					assert(not material.vertex_color_use_as_albedo and material.albedo_texture == null)
					var old = baseline[kind]
					assert(not old.vertex_tint and not old.has_texture)
					var c = old.team_rgba
					assert(material.albedo_color.is_equal_approx(Color(c[0],c[1],c[2],c[3])))
					assert(abs(material.roughness - old.roughness) < .00001 and abs(material.metallic_specular - old.specular) < .00001)
				else: assert(false, "Unknown native material")
		assert(fields == 1 and teams == 1)
		report[kind] = {"passed":true,"native_sha256":FileAccess.get_sha256(path),"atlas_sha256":FileAccess.get_sha256(atlas_path),"rgba_equal":true,"uv0":true,"white_body_vertex_tint":true,"source_prop_tint_equal":true,"team_unchanged":true,"source_glb_sha256":FileAccess.get_sha256(source_path),"native_rgba_sha256":image_sha,"atlas_rgba_sha256":digest_bytes(atlas.get_data()),"dimensions":[atlas.get_width(),atlas.get_height()],"body_vertices":body_count,"prop_vertices":prop_count,"field_vertices":body_count+prop_count,"field_surfaces":fields,"team_surfaces":teams,"field_state":field_state}
		source_scene.free()
		scene.free()
	var report_path = "res://reports/native-material-baseline.json" if baseline_mode else "res://reports/native-material-proof.json"
	var file = FileAccess.open(report_path, FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify(report,"  ")+"\n")
	file.close()
	print("NATIVE_MATERIAL_BASELINE_PASS" if baseline_mode else "NATIVE_MATERIAL_PROOF_PASS")
	quit()

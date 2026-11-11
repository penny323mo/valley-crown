extends SceneTree
## One-shot native pack of inspected GLBs from ignored source-art directory.
## Run only in the isolated candidate after staged Blender output is copied in.
const KINDS := ["villager", "scout", "spearman", "archer"]
const REQUIRED := ["idle", "walk", "attack", "hit", "death"]
func _initialize(): call_deferred("run")
func run() -> void:
	var report: Dictionary = {}
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://reports/asset_manifest.json"))
	assert(manifest.has("units"),"Missing reviewed Blender asset manifest")
	assert(FileAccess.file_exists("res://art/.gdignore") and FileAccess.get_file_as_string("res://art/.gdignore").is_empty(),"Editable Blender source must remain ignored")
	DirAccess.make_dir_recursive_absolute("res://assets/mature/models")
	for kind in KINDS:
		var source: String = "res://art/action_characters/interchange/"+kind+".glb"
		var expected: Dictionary = manifest.units[kind]
		assert(FileAccess.get_sha256(source)==expected.glb_sha256,"Reviewed GLB bytes changed: "+kind)
		var state := GLTFState.new()
		var doc := GLTFDocument.new()
		var error := doc.append_from_file(source,state)
		assert(error==OK,"GLB parse failed: "+source)
		# Retain default-valued TRS channels. A scale1 tool channel must restore
		# the visible tool after a prior clip explicitly shrank it to .001.
		var scene: Node3D = doc.generate_scene(state,30.0,false,false)
		assert(scene!=null)
		root.add_child(scene)
		var players := scene.find_children("*","AnimationPlayer",true,false)
		var skeletons := scene.find_children("*","Skeleton3D",true,false)
		assert(players.size()==1 and skeletons.size()==1)
		var player: AnimationPlayer = players[0]
		var skeleton: Skeleton3D = skeletons[0]
		assert(skeleton.get_bone_count()==expected.bones.size(),"Reviewed joint count changed: "+kind)
		for bone in skeleton.get_bone_count():
			assert(skeleton.get_bone_name(bone) in expected.bones,"Unexpected imported joint: "+skeleton.get_bone_name(bone))
		# Renaming a non-default skeleton would invalidate tracks: require authoring
		# pipeline to use normalized names, rather than silently patch path strings.
		var clips: Dictionary={}
		for required in REQUIRED: assert(player.has_animation(required),kind+" missing "+required)
		if kind=="villager":
			for required in ["carry_walk","gather_wood","gather_food","build","repair"]: assert(player.has_animation(required),kind+" missing "+required)
		for name in player.get_animation_list():
			var animation:=player.get_animation(name)
			animation.loop_mode=Animation.LOOP_LINEAR if name in ["idle","walk","carry_walk","gather_wood","gather_food","build","repair"] else Animation.LOOP_NONE
			var channels: Array=[]
			var joint_trs: Dictionary={}
			assert(animation.get_track_count()==expected.bones.size()*3,"Default TRS channels were discarded")
			for track in animation.get_track_count():
				assert(animation.track_get_type(track) in [Animation.TYPE_POSITION_3D,Animation.TYPE_ROTATION_3D,Animation.TYPE_SCALE_3D])
				assert(str(animation.track_get_path(track)).contains(":"),"Object/root animation forbidden")
				var bone_name: String=animation.track_get_path(track).get_subname(0)
				var track_kind: int=animation.track_get_type(track)
				assert(bone_name in expected.bones,"Non-joint channel")
				if not joint_trs.has(bone_name): joint_trs[bone_name]=[]
				assert(track_kind not in joint_trs[bone_name],"Duplicate joint TRS channel")
				joint_trs[bone_name].append(track_kind)
				channels.append(str(animation.track_get_path(track)))
			assert(joint_trs.size()==expected.bones.size(),"Missing joint TRS channels")
			clips[name]={"seconds":animation.length,"tracks":channels,"joint_trs":joint_trs}
		player.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		player.process_mode=Node.PROCESS_MODE_DISABLED
		var triangles:=0; var surfaces:=0; var meshes:=0
		for mesh: MeshInstance3D in scene.find_children("*","MeshInstance3D",true,false):
			meshes+=1
			for surface in mesh.mesh.get_surface_count():
				surfaces+=1
				var arrays:=mesh.mesh.surface_get_arrays(surface)
				triangles+=(arrays[Mesh.ARRAY_INDEX].size() if arrays[Mesh.ARRAY_INDEX]!=null else arrays[Mesh.ARRAY_VERTEX].size())/3
				var material: Material=mesh.mesh.surface_get_material(surface)
				if material is StandardMaterial3D:
					material.roughness=.94; material.metallic_specular=.15
					if material.resource_name=="team_blue": material.vertex_color_use_as_albedo=false
		assert(meshes==1 and surfaces<=2 and triangles<=6500 and skeleton.get_bone_count()<=32)
		assert(triangles==expected.triangles and surfaces==expected.material_surfaces,"Reviewed mesh budget changed: "+kind)
		assert(scene.find_children("*","CollisionObject3D",true,false).is_empty())
		scene.set_meta("visual_only",true)
		scene.set_meta("source_glb_sha256",FileAccess.get_sha256(source))
		scene.set_meta("source_blend_sha256",expected.blend_sha256)
		var packed:=PackedScene.new(); assert(packed.pack(scene)==OK)
		var destination: String = "res://assets/mature/models/"+kind+"_action.scn"
		assert(ResourceSaver.save(packed,destination)==OK)
		for dependency in ResourceLoader.get_dependencies(destination):
			assert(not str(dependency).contains("art/"),"Native scene retained source-art dependency")
		report[kind]={"source_glb_sha256":FileAccess.get_sha256(source),"native_sha256":FileAccess.get_sha256(destination),"bones":skeleton.get_bone_count(),"triangles":triangles,"surfaces":surfaces,"clips":clips}
		scene.free()
	var file:=FileAccess.open("res://reports/native-action-import.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  ")+"\n"); file.close()
	print("ACTION_CHARACTER_IMPORT_PASS ",JSON.stringify(report))
	quit()

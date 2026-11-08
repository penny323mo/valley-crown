extends "capture_material_base.gd"
func run():
	mode="material_studies";capture_kind="native_controlled_material_study"
	if not await initialize_scene() or size!=Vector2i(844,390):quit(2);return
	# Retain actual runtime environment and sun nodes, including every default.
	var environment=game.find_children("*","WorldEnvironment",false,false)[0]
	var sun=game.find_children("*","DirectionalLight3D",false,false)[0]
	var camera_basis=game.camera.global_basis
	var world=Node3D.new();root.add_child(world)
	environment.reparent(world);sun.reparent(world)
	game.free();game=null
	var camera=Camera3D.new();world.add_child(camera)
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=3.2
	camera.global_basis=camera_basis;camera.global_position=Vector3(0,0.85,0)+camera_basis.z*10;camera.current=true
	var canvas=CanvasLayer.new();root.add_child(canvas)
	var caption=Label.new();canvas.add_child(caption);caption.position=Vector2(12,8);caption.add_theme_font_size_override("font_size",18)
	for kind in Controller.KINDS:
		for view in ["front","rear"]:
			var body=Node3D.new();world.add_child(body)
			body.rotation.y=atan2(camera_basis.z.x,camera_basis.z.z)+(PI if view=="rear" else 0)
			var controller=Controller.new()
			if not controller.bind(body,kind,Color("435d6c")):check("native model bound",false);finish(8);return
			controller.occlusion.set_authorized(false);controller._start("idle",0.0,false,false)
			caption.text="CONTROLLED MATERIAL STUDY NOT GAMEPLAY | "+kind+" / "+view
			await settle()
			await capture(kind+"-"+view,camera,{"study_label":"CONTROLLED MATERIAL STUDY NOT GAMEPLAY","kind":kind,"view":view,"clip":"idle","unit_state":"controlled_paused_idle","camera_scope":"detail framing, not gameplay","body_yaw":body.rotation.y,"overlay_disabled":true,"animation_poses":[controller.visual_evidence_snapshot()],"materials":materials(controller.rig)})
			controller.release();body.free()
	finish(8)

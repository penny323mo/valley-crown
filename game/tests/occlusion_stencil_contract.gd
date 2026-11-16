extends SceneTree
## Small native lifecycle/API contract. No framebuffer or visual-pass claim.
const Controller=preload("res://scripts/action_character.gd")
const Presenter=preload("res://scripts/observed_character_presenter.gd")
const Occlusion=preload("res://scripts/observed_occlusion.gd")
var checks: Array=[]
func _initialize(): call_deferred("run")
func check(label: String, okay: bool, detail={}) -> void:
	checks.append({"name":label,"pass":okay,"detail":detail})
	if not okay: push_error(label+" "+str(detail))
func record(id: int, owned: bool) -> Dictionary:
	return {"id":id,"kind":"spearman","category":"unit","owned":owned,"remembered":false,"team":0 if owned else 1,"last_seen_tick":0,"pos":Vector3.ZERO,"visual_action":"idle"}
func run() -> void:
	for kind in Controller.KINDS:
		var body:=Node3D.new(); root.add_child(body)
		var c=Controller.new(); var bound: bool=c.bind(body,kind,Color("435d6c"))
		check(kind+" bind",bound)
		if not bound: body.free(); continue
		var state: Dictionary=c.occlusion.stats()
		check(kind+" supported original material",state.supported and state.authorized,state)
		if not state.supported: c.release(); body.free(); continue
		check(kind+" two passes per surface",state.extra_surface_draws_max==2*state.source_surfaces,state)
		check(kind+" no depth sampling or extra viewport",state.depth_samples_per_fragment==0 and state.extra_viewports==0 and not state.opaque_stencil_writes,state)
		check(kind+" global pass ordering",c.occlusion.mask_material.render_priority<c.occlusion.material.render_priority)
		check(kind+" material next pass",c.occlusion.mask_material.next_pass==c.occlusion.material)
		for overlay in c.occlusion.overlays:
			var source:=overlay.get_parent() as MeshInstance3D
			check(kind+" shared exact mesh skin and resolved skeleton",source!=null and source.mesh==overlay.mesh and source.skin==overlay.skin and source.get_node_or_null(source.skeleton)==overlay.get_node_or_null(overlay.skeleton))
			check(kind+" identity child starts aligned",overlay.transform==Transform3D.IDENTITY and overlay.global_transform==source.global_transform)
			check(kind+" no silhouette shadows",overlay.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
			var before: Transform3D=source.transform
			source.position+=Vector3(.13,.21,-.08); source.rotate_y(.17); source.scale*=Vector3(1.1,.9,1.05)
			check(kind+" animated local mesh TRS inherited",overlay.global_transform.is_equal_approx(source.global_transform))
			source.hide(); check(kind+" tool visibility hides overlay",not overlay.is_visible_in_tree())
			source.show(); check(kind+" tool visibility restores overlay",overlay.is_visible_in_tree())
			source.transform=before
		c.occlusion.set_authorized(false)
		check(kind+" toggle disables both passes",not c.occlusion.enabled and c.occlusion.overlays.all(func(n): return not n.visible))
		c.occlusion.set_authorized(true)
		check(kind+" toggle restores authorized live rig",c.occlusion.enabled)
		c.start_death(); c.occlusion.set_authorized(true)
		check(kind+" corpse cannot be reauthorized by toggle",not c.occlusion.enabled and c.occlusion.overlays.all(func(n): return not n.visible))
		c.release(); check(kind+" release clears references",c.occlusion.overlays.is_empty() and c.occlusion.owner_rig==null and not c.occlusion.enabled)
		body.free()
	var presenter=Presenter.new(); var own:=Node3D.new(); var enemy:=Node3D.new()
	root.add_child(own); root.add_child(enemy)
	presenter.present(record(1,true),own,Color.BLUE,0,false)
	presenter.present(record(2,false),enemy,Color.RED,0,false)
	check("own and currently visible enemy both eligible",presenter.occlusion_candidates().size()==2)
	enemy.hide(); check("hidden ancestor excluded",presenter.occlusion_candidates().size()==1)
	enemy.show(); var remembered:=record(2,false); remembered.remembered=true
	presenter.reconcile({1:record(1,true),2:remembered})
	check("remembered enemy releases overlay and controller",not presenter.controllers.has(2) and enemy.find_children("ObservedOcclusionOnly","MeshInstance3D",true,false).is_empty())
	presenter.reconcile({}); check("empty observation releases all",presenter.controllers.is_empty())
	presenter.clear(); own.free(); enemy.free()
	# Unsupported alpha unit art must leave original source material untouched.
	var rig:=Node3D.new(); root.add_child(rig); rig.set_meta("occlusion_authorized",true)
	var mesh:=MeshInstance3D.new(); var cube:=BoxMesh.new(); var alpha:=StandardMaterial3D.new()
	alpha.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA; alpha.cull_mode=BaseMaterial3D.CULL_DISABLED; cube.material=alpha; mesh.mesh=cube; rig.add_child(mesh)
	var overlay=Occlusion.new(); overlay.bind(rig,Color.BLUE)
	check("unsupported alpha source fails closed without warning",not overlay.supported and overlay.overlays.is_empty() and mesh.get_active_material(0)==alpha and overlay.stats().unsupported_reason=="alpha_or_material_next_pass")
	overlay.release()
	alpha.transparency=BaseMaterial3D.TRANSPARENCY_DISABLED
	for cull_mode in [BaseMaterial3D.CULL_BACK,BaseMaterial3D.CULL_FRONT]:
		alpha.cull_mode=cull_mode; overlay.bind(rig,Color.BLUE)
		check("unmatched winding fails closed "+str(cull_mode),not overlay.supported and overlay.overlays.is_empty() and overlay.stats().unsupported_reason=="unmatched_cull_mode")
		overlay.release()
	alpha.cull_mode=BaseMaterial3D.CULL_DISABLED; mesh.hide(); overlay.bind(rig,Color.BLUE)
	check("initially hidden tool can bind without revealing",overlay.supported and overlay.overlays.size()==1 and not overlay.overlays[0].is_visible_in_tree())
	mesh.show(); check("initially hidden tool follows source reveal",overlay.overlays[0].is_visible_in_tree())
	overlay.release(); rig.free()
	var failed:=checks.filter(func(row): return not row.pass).size()
	DirAccess.make_dir_recursive_absolute("res://reports")
	var args:=OS.get_cmdline_user_args()
	var report_path: String=args[0] if args.size()==1 else "res://reports/occlusion-stencil-contract.json"
	FileAccess.open(report_path,FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"passed":checks.size()-failed,"failed":failed,"build":load("res://scripts/rules.gd").BUILD_ID,"scope":"Native object/material/lifecycle only; rendered behavior and mobile cost not established"},"  ")+"\n")
	print("OCCLUSION_STENCIL_CONTRACT ",checks.size()," failed=",failed)
	quit(1 if failed else 0)

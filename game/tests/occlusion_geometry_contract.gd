extends SceneTree
## PREPARED ONLY. Small actual Godot object/API contract, no pixel claim.
const Occlusion=preload("res://scripts/observed_occlusion.gd")
var checks: Array=[]
func _initialize(): call_deferred("run")
func check(label: String, okay: bool, detail={}) -> void:
	checks.append({"name":label,"pass":okay,"detail":detail})
	if not okay: push_error(label+" "+str(detail))
func run() -> void:
	var rig:=Node3D.new(); root.add_child(rig); rig.set_meta("occlusion_authorized",true)
	var mesh:=MeshInstance3D.new(); var box:=BoxMesh.new(); var material:=StandardMaterial3D.new()
	material.cull_mode=BaseMaterial3D.CULL_DISABLED; box.material=material; mesh.mesh=box; rig.add_child(mesh)
	mesh.layers=4; mesh.custom_aabb=AABB(Vector3(-1,-1,-1),Vector3(2,2,2)); mesh.extra_cull_margin=.25; mesh.lod_bias=.75
	var effect=Occlusion.new(); effect.bind(rig,Color.BLUE)
	check("exact geometry test supported",effect.supported)
	if effect.supported:
		var copy: MeshInstance3D=effect.overlays[0]
		check("camera layers explicitly copied, not assumed inherited",copy.layers==mesh.layers)
		check("custom bounds and cull margin copied",copy.custom_aabb==mesh.custom_aabb and copy.extra_cull_margin==mesh.extra_cull_margin)
		check("LOD choice copied",copy.lod_bias==mesh.lod_bias)
	effect.release()
	for which in ["begin","end"]:
		mesh.visibility_range_begin=2.0 if which=="begin" else 0.0
		mesh.visibility_range_end=4.0 if which=="end" else 0.0
		effect.bind(rig,Color.BLUE)
		check("nonzero visibility range fails closed "+which,not effect.supported and effect.overlays.is_empty() and effect.stats().unsupported_reason=="visibility_range")
		effect.release()
	mesh.visibility_range_begin=0; mesh.visibility_range_end=0; mesh.transparency=.5
	effect.bind(rig,Color.BLUE)
	check("instance transparency fails closed",not effect.supported and effect.overlays.is_empty() and effect.stats().unsupported_reason=="instance_transparency")
	effect.release(); rig.free()
	var failed:=checks.filter(func(c): return not c.pass).size()
	FileAccess.open("res://reports/occlusion-geometry-contract.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"passed":checks.size()-failed,"failed":failed,"scope":"Geometry object/API contract only; no render/mobile acceptance","fixture_sha256":FileAccess.get_sha256("res://tests/occlusion_geometry_contract.gd"),"runtime_sha256":FileAccess.get_sha256("res://scripts/observed_occlusion.gd"),"engine":Engine.get_version_info()},"  ")+"\n")
	quit(1 if failed else 0)

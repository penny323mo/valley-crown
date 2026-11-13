extends SceneTree
const RememberedMaterial = preload("res://scripts/remembered_material.gd")
var checks=0
var failures=0
func check(ok:bool,label:String):
	checks+=1
	if not ok: failures+=1; push_error(label)
func _initialize():
	var material=StandardMaterial3D.new()
	material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	material.alpha_scissor_threshold=0.6
	material.cull_mode=BaseMaterial3D.CULL_DISABLED
	var image=Image.create(2,2,false,Image.FORMAT_RGBA8)
	image.fill(Color(0.1,0.7,0.2,0.0)); image.set_pixel(0,0,Color(0.1,0.7,0.2,1))
	material.albedo_texture=ImageTexture.create_from_image(image)
	var node=MeshInstance3D.new();node.mesh=QuadMesh.new();node.mesh.material=material
	RememberedMaterial.apply(node,true)
	var dim=node.get_surface_override_material(0)
	check(node.material_override==null,"no destructive global override")
	check(dim!=material,"duplicated material")
	check(dim.albedo_texture==material.albedo_texture,"texture preserved")
	check(dim.transparency==material.transparency,"alpha scissor preserved")
	check(dim.alpha_scissor_threshold==material.alpha_scissor_threshold,"cutout threshold preserved")
	check(dim.cull_mode==material.cull_mode,"double sided preserved")
	check(material.albedo_color==Color.WHITE,"source not mutated")
	check(dim.albedo_color.a==1,"alpha multiplier preserved")
	check(dim.albedo_color.g<1,"memory dimmed")
	RememberedMaterial.apply(node,false)
	check(node.get_surface_override_material(0)==null,"surface restored")
	check(node.get_active_material(0)==material,"original active material restored")
	node.material_override=material
	var other=MeshInstance3D.new();other.mesh=QuadMesh.new();other.material_override=material
	RememberedMaterial.apply(other,true);check(other.material_override!=material,"override copied")
	RememberedMaterial.apply(other,false);check(other.material_override==material,"override restored")
	node.free();other.free()
	print("FOG_MATERIAL_CONTRACT checks=",checks," failures=",failures)
	quit(0 if failures==0 else 1)

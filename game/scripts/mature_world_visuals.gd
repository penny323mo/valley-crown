extends RefCounted
## Pure presentation. It receives existing public map metadata, never entity state.
const Rules=preload("res://scripts/rules.gd")
const GROUND_SHADER=preload("res://assets/mature/terrain/ground.gdshader")
static func create_ground(parent:Node3D,corridors:Dictionary) -> MeshInstance3D:
	var image:=Image.create(Rules.MAP_SIZE,Rules.MAP_SIZE,false,Image.FORMAT_R8)
	image.fill(Color.BLACK)
	for cell in corridors:
		assert(cell.x>=0 and cell.x<Rules.MAP_SIZE and cell.y>=0 and cell.y<Rules.MAP_SIZE)
		image.set_pixel(cell.x,cell.y,Color.WHITE)
	var mat:=ShaderMaterial.new();mat.shader=GROUND_SHADER
	mat.set_shader_parameter("map_size",Rules.MAP_SIZE)
	mat.set_shader_parameter("grass_map",load("res://assets/mature/terrain/grass.png"))
	mat.set_shader_parameter("earth_map",load("res://assets/mature/terrain/earth.png"))
	mat.set_shader_parameter("public_corridor_mask",ImageTexture.create_from_image(image))
	var plane:=PlaneMesh.new();plane.size=Vector2(Rules.MAP_SIZE+8,Rules.MAP_SIZE+8)
	var mesh:=MeshInstance3D.new();mesh.name="MaturePublicGround";mesh.mesh=plane;mesh.material_override=mat
	mesh.position.y=.006;mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh.set_meta("public_corridor_cells",corridors.size());mesh.set_meta("visual_only",true)
	parent.add_child(mesh)
	return mesh

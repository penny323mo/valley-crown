extends RefCounted
const Data = preload("res://scripts/licensed_rock_data.gd")
const ROCK_TEXTURE = preload("res://assets/mature/resources/quaternius/Rocks_Diffuse.png")
static var materials: Dictionary = {}
static func make_mesh(kind: String, depletion: int, variant: int) -> ArrayMesh:
	var data: Dictionary = Data.MODELS[posmod(variant,3)]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Whole authored shape shrinks as observed remaining resource falls; no authority edits.
	var scale_factor: float = [1.0,0.83,0.66,0.46][clampi(depletion,0,3)]
	st.set_color(Color(0.20,0.22,0.25) if kind=="iron" else Color.WHITE)
	for index in data.i:
		var p: Array = data.p[index]
		var n: Array = data.n[index]
		var uv: Array = data.uv[index]
		st.set_normal(Vector3(n[0],n[1],n[2]))
		st.set_uv(Vector2(uv[0],uv[1]))
		st.add_vertex(Vector3(p[0],p[1],p[2])*scale_factor)
	if kind=="iron":
		for block in Data.BLOCKS[posmod(variant,3)]:_ore_block(st,block,scale_factor)
	if not materials.has(kind):
		var material := StandardMaterial3D.new()
		material.albedo_texture = ROCK_TEXTURE
		material.albedo_color = Color.WHITE
		material.vertex_color_use_as_albedo = true
		material.roughness = 0.94
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		materials[kind] = material
	st.set_material(materials[kind])
	return st.commit()

static func _ore_block(st: SurfaceTool, block: Dictionary, scale_factor: float) -> void:
	# 64px neutral atlas island with a measured 128px surrounding neutral region.
	# Real broad UV region, not a single white texel; no additional texture/material.
	var uv_corners: Array[Vector2] = [Vector2(1504.0,96.0)/2048.0,Vector2(1568.0,96.0)/2048.0,Vector2(1536.0,160.0)/2048.0]
	for face in block.f:
		var n := Vector3(face.n[0],face.n[1],face.n[2])
		var tint := Color.WHITE if n.y>0.65 else Color(0.70,0.77,0.84)
		st.set_color(tint)
		st.set_normal(n)
		for corner in 3:
			var p: Array = block.p[face.i[corner]]
			st.set_uv(uv_corners[corner])
			st.add_vertex(Vector3(p[0],p[1],p[2])*scale_factor)

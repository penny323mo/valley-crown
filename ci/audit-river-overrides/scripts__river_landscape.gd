extends RefCounted
const River=preload("res://scripts/river_terrain.gd")
const Rules=preload("res://scripts/rules.gd")
const RIVER_SHADER=preload("res://assets/mature/terrain/river_surface.gdshader")
## Single terrain mesh/draw under existing fog layer; same authoritative edges.
static func render(parent:Node3D) -> MeshInstance3D:
 var mesh=ImmediateMesh.new()
 var material=ShaderMaterial.new();material.shader=RIVER_SHADER
 mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES,material)
 _strip(mesh,-Rules.MAP_HALF-2.0,River.BRIDGE_X_MIN,.0)
 _strip(mesh,River.BRIDGE_X_MIN,River.BRIDGE_X_MAX,.5)
 _strip(mesh,River.BRIDGE_X_MAX,River.FORD_X_MIN,.0)
 _strip(mesh,River.FORD_X_MIN,River.FORD_X_MAX,1.0)
 _strip(mesh,River.FORD_X_MAX,Rules.MAP_HALF+2.0,.0)
 mesh.surface_end()
 var node=MeshInstance3D.new();node.name="PublicRiverSurfaces";node.mesh=mesh
 node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
 parent.add_child(node)
 return node
static func _strip(mesh:ImmediateMesh,left:float,right:float,style:float):
 var a=Vector3(left,.014,River.BANK_Z_MIN);var b=Vector3(right,.014,River.BANK_Z_MIN)
 var c=Vector3(right,.014,River.BANK_Z_MAX);var d=Vector3(left,.014,River.BANK_Z_MAX)
 for v in [a,b,c,a,c,d]:
  mesh.surface_set_normal(Vector3.UP);mesh.surface_set_color(Color(style,0,0,1));mesh.surface_add_vertex(v)

extends MeshInstance3D
# Presentation only. Original per-cell fog is retained without modification.
# Adds darkness exclusively INSIDE currently visible cells. No knowledge writes.
const EDGE_WIDTH = 0.65
const SHADER_CODE = """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
uniform sampler2D state_mask : filter_nearest, repeat_disable;
uniform float map_size = 80.0;
uniform float map_half = 40.0;
uniform float edge_width = 0.65;
varying vec2 ground_position;
void vertex() {
 ground_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz + vec2(map_half);
}
float cell_state(vec2 c) {
 if (c.x < 0.0 || c.y < 0.0 || c.x >= map_size || c.y >= map_size) { return 0.0; }
 return texture(state_mask, (c + vec2(0.5)) / map_size).r;
}
void fragment() {
 vec2 cell = floor(ground_position);
 float current = cell_state(cell);
 float opacity = 0.0;
 // Unknown/explored output stays zero; their original opacity is unchanged.
 if (current > 0.75) {
  for (int y = -1; y <= 1; y++) {
   for (int x = -1; x <= 1; x++) {
    if (x != 0 || y != 0) {
     vec2 n = cell + vec2(float(x), float(y));
     float s = cell_state(n);
     if (s < 0.75) {
      vec2 delta = max(max(n - ground_position, ground_position - (n + vec2(1.0))), vec2(0.0));
      float inward = 1.0 - smoothstep(0.0, edge_width, length(delta));
      opacity = max(opacity, (s > 0.25 ? 0.65 : 0.94) * inward);
     }
    }
   }
  }
 }
 ALBEDO = vec3(0.055, 0.12, 0.12);
 ALPHA = opacity;
}
"""
var state_texture: ImageTexture
var grid_size: int
var last_states := PackedByteArray()
func initialize(size: int) -> void:
 grid_size = size
 var plane := PlaneMesh.new()
 plane.size = Vector2(size,size)
 mesh = plane
 position.y = 0.115
 cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
 var image := Image.create(size,size,false,Image.FORMAT_R8)
 image.fill(Color.BLACK)
 state_texture = ImageTexture.create_from_image(image)
 var shader := Shader.new()
 shader.code = SHADER_CODE
 var material := ShaderMaterial.new()
 material.shader = shader
 material.set_shader_parameter('state_mask',state_texture)
 material.set_shader_parameter('map_size',float(size))
 material.set_shader_parameter('map_half',float(size)*0.5)
 material.set_shader_parameter('edge_width',EDGE_WIDTH)
 material_override = material
static func encode_states(states: PackedByteArray) -> PackedByteArray:
 var bytes:=PackedByteArray()
 bytes.resize(states.size())
 for i in states.size():
  assert(states[i]<=2)
  bytes[i]=255 if states[i]==2 else (128 if states[i]==1 else 0)
 return bytes
func refresh(states: PackedByteArray) -> bool:
 assert(states.size()==grid_size*grid_size)
 if states==last_states: return false
 last_states=states.duplicate()
 var image:=Image.create_from_data(grid_size,grid_size,false,Image.FORMAT_R8,encode_states(states))
 state_texture.update(image)
 return true

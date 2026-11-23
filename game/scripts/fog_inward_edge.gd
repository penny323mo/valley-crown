extends MeshInstance3D
# Presentation only. Original per-cell fog is retained without modification.
# Adds darkness inside visible cells and an unknown veil over visual-only ground
# outside the map. No knowledge writes.
const EDGE_WIDTH = 0.65
const BASE_TILE_Y = 0.11
const INWARD_LAYER_Y = 0.115
# Geometry is separated by 5 mm for overlay depth order. After projecting
# to the base tile plane, permit at most 1.5 mm overlap for raster rounding.
const JOIN_EPSILON = 0.0015
const SHADER_CODE = """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
uniform sampler2D state_mask : filter_nearest, repeat_disable;
uniform float map_size = 80.0;
uniform float map_half = 40.0;
uniform float edge_width = 0.65;
uniform float base_height_delta = -0.005;
uniform float join_rounding_guard = 0.0015;
varying vec2 ground_position;
varying vec2 base_projection;
void vertex() {
 ground_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz + vec2(map_half);
 // Main camera is orthographic. Project the seam onto the exact y of
 // the original 1x1 fog tiles, without affecting the in-field falloff.
 vec3 backwards = INV_VIEW_MATRIX[2].xyz;
 float vertical = abs(backwards.y) > 0.0001 ? backwards.y : 1.0;
 base_projection = ground_position + backwards.xz * (base_height_delta / vertical);
}
float cell_state(vec2 c) {
 if (c.x < 0.0 || c.y < 0.0 || c.x >= map_size || c.y >= map_size) { return 0.0; }
 return texture(state_mask, (c + vec2(0.5)) / map_size).r;
}
void fragment() {
 vec2 cell = floor(ground_position);
 bool exterior = any(lessThan(base_projection, vec2(join_rounding_guard))) ||
                 any(greaterThanEqual(base_projection, vec2(map_size - join_rounding_guard)));
 // Visual-only ground beyond the gameplay grid must not look revealed.
 // Inside the grid, original unknown/explored cells still contribute zero
 // to this helper, preserving the original per-cell fog exactly.
 float opacity = 0.94;
 if (!exterior) {
  opacity = 0.0;
  float current = cell_state(cell);
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
 position.y = INWARD_LAYER_Y
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
 material.set_shader_parameter('base_height_delta',BASE_TILE_Y-INWARD_LAYER_Y)
 material.set_shader_parameter('join_rounding_guard',JOIN_EPSILON)
 material_override = material
func cover_world(half_extents: Vector2) -> void:
 # Expand this same draw only; MODEL_MATRIX keeps map cell coordinates fixed.
 var half_grid := float(grid_size) * 0.5
 var extent := (half_extents / half_grid).max(Vector2.ONE)
 var desired := Vector3(extent.x,1.0,extent.y)
 if scale != desired: scale = desired
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

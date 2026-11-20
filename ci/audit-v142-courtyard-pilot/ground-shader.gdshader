shader_type spatial;
render_mode cull_back, diffuse_burley;
// One opaque ground draw. All layout inputs are immutable PUBLIC map metadata.
// This material never samples entities, vision, resources, navigation or game time.
uniform int map_size = 80;
uniform vec2 public_home_a = vec2(-25.0, 24.0);
uniform vec2 public_home_b = vec2(25.0, -24.0);
uniform sampler2D grass_map : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D earth_map : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D public_corridor_mask : filter_linear, repeat_disable;
varying vec3 world_position;

float hash21(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}
float meadow_noise(vec2 p) {
    vec2 cell = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash21(cell), hash21(cell + vec2(1.0, 0.0)), f.x),
               mix(hash21(cell + vec2(0.0, 1.0)), hash21(cell + vec2(1.0)), f.x), f.y);
}
void vertex() { world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
    vec2 p = world_position.xz;
    float broad = meadow_noise(p * 0.18);
    float patches = meadow_noise(p * 0.61 + vec2(7.2, 18.4));
    // Original generated albedo asset experiment. Two-metre repeat, no new samples.
    vec3 grass = texture(grass_map, p * 0.5).rgb * vec3(0.60, 0.78, 0.65); // Unverified palette correction: reduce yellow/red and overall brightness.
    vec3 earth_albedo = texture(earth_map, p * 0.5).rgb;
    float earth_grain = earth_albedo.r;

    // Linear reconstruction joins the old diagonal public route cells into a
    // continuous worn trail. It is decorative, not a placement or movement rule.
    vec2 grid_uv = (p + vec2(float(map_size) * 0.5)) / float(map_size);
    float corridor = texture(public_corridor_mask, grid_uv).r;
    float trail = smoothstep(0.10 + patches * 0.09, 0.48, corridor);
    float trail_core = smoothstep(0.40, 0.84, corridor);
    float rut = smoothstep(0.37, 0.48, corridor) * (1.0 - smoothstep(0.61, 0.74, corridor));
    vec3 soil = earth_albedo;
    soil *= 1.0 - rut * 0.0;
    vec3 terrain = mix(grass, soil, trail * 0.94);
    terrain = mix(terrain, soil * 1.08, trail_core * 0.35);

    // A weathered stone courtyard identifies each public starting settlement.
    // It remains after destruction and conveys no current/hidden building state.
    vec2 home_delta_a = (p - public_home_a) / vec2(4.8, 4.3);
    vec2 home_delta_b = (p - public_home_b) / vec2(4.8, 4.3);
    float home_distance = min(length(home_delta_a), length(home_delta_b));
    float irregular_edge = home_distance + (patches - 0.5) * 0.13;
    float apron = 1.0 - smoothstep(0.91, 1.09, irregular_edge);
    float earth_shoulder = 1.0 - smoothstep(1.04, 1.25, irregular_edge);
    terrain = mix(terrain, soil * 0.93, earth_shoulder * 0.64);

    // Old settlement flagstones: irregular broad courses, chipped corners
    // and a worn soil margin. This remains one decorative, opaque ground pass.
    float grit = patches - 0.5;
    vec2 stone_scale = p * vec2(1.18, 1.57);
    stone_scale += vec2(grit * 0.56, grit * 0.27);
    float pixel_span = max(fwidth(stone_scale.x), fwidth(stone_scale.y));
    float joint_aa = clamp(pixel_span * 0.5, 0.002, 0.25);
    vec2 stone_grid = stone_scale;
    float row = floor(stone_grid.y);
    float row_phase = fract(row * 0.618034);
    stone_grid.x += row_phase * 0.70 + mod(row, 2.0) * 0.46;
    vec2 stone_cell = floor(stone_grid);
    vec2 stone_uv = fract(stone_grid);
    float stone_seed = hash21(stone_cell + vec2(26.3, 9.7));
    vec2 stone_edge = min(stone_uv, vec2(1.0) - stone_uv);
    float edge_distance = min(stone_edge.x, stone_edge.y);
    float chipped_corner = (stone_edge.x + stone_edge.y - (0.10 + stone_seed * 0.17)) * 0.65;
    float edge_wear = grit * (0.034 + stone_seed * 0.022);
    float stone = smoothstep(0.026 - joint_aa, 0.066 + joint_aa, min(edge_distance, chipped_corner) + edge_wear);
    vec3 stone_color = mix(vec3(0.37, 0.35, 0.30), vec3(0.55, 0.505, 0.411), stone_seed);
    float bevel = (1.0 - smoothstep(0.08, 0.21, stone_uv.y)) * stone;
    stone_color = stone_color * (0.91 + earth_grain * 0.24 + grit * 0.15) + vec3(bevel * 0.037);
    vec3 mortar = mix(vec3(0.30, 0.281, 0.216), soil * 0.82, 0.39);
    vec3 courtyard = mix(mortar, stone_color, stone);
    float stone_detail = 1.0 - smoothstep(0.13, 0.32, pixel_span);
    courtyard = mix(vec3(0.402, 0.377, 0.31), courtyard, stone_detail);
    float abandoned_edge = 1.0 - smoothstep(0.79, 1.06, irregular_edge + grit * 0.31);
    // Lose groups of slabs in the walk-worn approach rather than drawing a
    // complete checkerboard under the keep. Both homes use mirrored public
    // coordinates and only this settlement apron is affected.
    bool use_home_a = dot(home_delta_a, home_delta_a) <= dot(home_delta_b, home_delta_b);
    vec2 home_local = use_home_a ? p - public_home_a : public_home_b - p;
    float approach_distance = abs(home_local.x + 0.43 * home_local.y + grit * 1.25);
    float worn_center = (1.0 - smoothstep(0.69, 1.55, approach_distance)) * smoothstep(0.0, 2.2, home_local.y);
    float edge_loss = smoothstep(0.62, 0.98, irregular_edge) * smoothstep(0.57, 0.81, patches);
    float paving = min(apron, abandoned_edge) * (1.0 - max(worn_center * 0.88, edge_loss * 0.75));
    terrain = mix(terrain, courtyard, paving);

    ALBEDO = terrain;
    ROUGHNESS = 0.95;
    SPECULAR = 0.10;
}

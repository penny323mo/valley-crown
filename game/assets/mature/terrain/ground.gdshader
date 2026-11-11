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
    float grain = texture(grass_map, p * 1.35).g;
    float earth_grain = texture(earth_map, p * 0.72).r;

    // Large, irregular green and straw islands survive the phone camera scale;
    // a second smaller scale gives close views grass/soil texture without noise shimmer.
    vec3 grass = mix(vec3(0.16, 0.245, 0.095), vec3(0.37, 0.425, 0.17),
                     smoothstep(0.12, 0.86, broad));
    grass = mix(grass, vec3(0.43, 0.405, 0.235),
                smoothstep(0.57, 0.87, patches) * 0.48);
    grass *= 0.90 + grain * 0.70;

    // Linear reconstruction joins the old diagonal public route cells into a
    // continuous worn trail. It is decorative, not a placement or movement rule.
    vec2 grid_uv = (p + vec2(float(map_size) * 0.5)) / float(map_size);
    float corridor = texture(public_corridor_mask, grid_uv).r;
    float trail = smoothstep(0.10 + patches * 0.09, 0.48, corridor);
    float trail_core = smoothstep(0.40, 0.84, corridor);
    float rut = smoothstep(0.37, 0.48, corridor) * (1.0 - smoothstep(0.61, 0.74, corridor));
    vec3 soil = mix(vec3(0.405, 0.275, 0.135), vec3(0.57, 0.425, 0.245), clamp(earth_grain * 1.8, 0.0, 1.0));
    soil *= 1.0 - rut * 0.17;
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

    // Staggered, individually colored stones with dark joints and a pale bevel.
    // No added meshes, shadows, particles, collision, or alpha-overdraw passes.
    vec2 stone_scale = p * vec2(1.62, 2.05);
    vec2 stone_grid = stone_scale;
    float pixel_span = max(fwidth(stone_scale.x), fwidth(stone_scale.y));
    float joint_aa = clamp(pixel_span * 0.5, 0.002, 0.25);
    stone_grid.x += mod(floor(stone_grid.y), 2.0) * 0.5;
    vec2 stone_cell = floor(stone_grid);
    vec2 stone_uv = fract(stone_grid);
    float stone_seed = hash21(stone_cell + vec2(26.3, 9.7));
    vec2 stone_edge = min(stone_uv, vec2(1.0) - stone_uv);
    float edge_distance = min(stone_edge.x, stone_edge.y);
    float stone = smoothstep(0.045 - joint_aa, 0.095 + stone_seed * 0.018 + joint_aa, edge_distance);
    vec3 stone_color = mix(vec3(0.34, 0.325, 0.27), vec3(0.58, 0.55, 0.435), stone_seed);
    float bevel = (1.0 - smoothstep(0.10, 0.20, stone_uv.y)) * stone;
    stone_color = stone_color * (0.94 + earth_grain * 0.30) + vec3(bevel * 0.065);
    vec3 courtyard = mix(vec3(0.20, 0.205, 0.125), stone_color, stone);
    // Filter procedural stone detail as the camera zooms out. Texture mipmaps
    // alone cannot antialias these shader-generated joints and stone colors.
    float stone_detail = 1.0 - smoothstep(0.13, 0.32, pixel_span);
    courtyard = mix(vec3(0.405, 0.393, 0.302), courtyard, stone_detail);
    terrain = mix(terrain, courtyard, apron);

    ALBEDO = terrain;
    ROUGHNESS = 0.95;
    SPECULAR = 0.10;
}

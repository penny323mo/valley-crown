shader_type spatial;
render_mode cull_back, diffuse_burley;
// Presentation only. The caller supplies the size-matched immutable visual trail mask.
uniform int map_size = 80;
uniform sampler2D grass_map : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D earth_map : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D public_corridor_mask : filter_nearest, repeat_disable;
varying vec3 world_position;
float corridor_at(ivec2 cell) {
    if (cell.x < 0 || cell.y < 0 || cell.x >= map_size || cell.y >= map_size) { return 0.0; }
    return texelFetch(public_corridor_mask, cell, 0).r;
}
void vertex() { world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
    vec2 grid = world_position.xz + vec2(float(map_size) * 0.5);
    ivec2 cell = ivec2(floor(grid));
    vec2 within = fract(grid);
    float road = corridor_at(cell);
    float edge = 1.0;
    if (corridor_at(cell + ivec2(-1,0)) < 0.5) { edge = min(edge, within.x); }
    if (corridor_at(cell + ivec2(1,0)) < 0.5) { edge = min(edge, 1.0-within.x); }
    if (corridor_at(cell + ivec2(0,-1)) < 0.5) { edge = min(edge, within.y); }
    if (corridor_at(cell + ivec2(0,1)) < 0.5) { edge = min(edge, 1.0-within.y); }
    vec3 grass = texture(grass_map,world_position.xz*.28).rgb;
    vec3 earth = texture(earth_map,world_position.xz*.42).rgb;
    float mottling = texture(grass_map,world_position.xz*1.7).g;
    // Worn edges stay INSIDE public corridor cells. Nothing invents extra roads.
    float wear = road * smoothstep(0.015,0.10+mottling*.10,edge);
    // Dry olive and warm earth, with broad low-contrast variation. No new
    // geometry, normal-map passes, water disks, or gameplay height changes.
    float coarse = texture(grass_map, world_position.xz * .035).g;
    vec3 dry_grass = mix(vec3(.333,.365,.251), vec3(.467,.486,.333), clamp(grass.g*.65+coarse*.35,0.0,1.0));
    vec3 dry_earth = vec3(.443,.380,.294) * (.88 + earth.r*.24);
    ALBEDO = mix(dry_grass,dry_earth,wear*.72);
    ROUGHNESS = 1.0;
    SPECULAR = 0.12;
}

shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;
// Static ground soot: no TIME, emission, particles, light or billboard.
void fragment() {
	float radius = length(UV);
	float grain = 0.86 + 0.14 * sin(UV.x * 31.0) * sin(UV.y * 23.0);
	ALBEDO = vec3(0.105, 0.100, 0.085);
	ALPHA = (1.0 - smoothstep(0.18, 1.0, radius)) * 0.48 * grain;
}

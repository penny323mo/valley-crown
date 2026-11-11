shader_type canvas_item;
render_mode unshaded;
// Static illustration, not a simulated battlefield or a gameplay screenshot.
// Screen-space scrims preserve contrast independently of the cover crop.
uniform bool landscape = false;
uniform bool inner_page = false;
uniform vec2 view_size = vec2(390.0, 844.0);
void fragment() {
    vec2 source_size = vec2(1024.0, 1536.0);
    float cover_scale = max(view_size.x / source_size.x, view_size.y / source_size.y);
    vec2 visible = view_size / (source_size * cover_scale);
    // A higher landscape crop retains the keep's battlements instead of its base.
    vec2 origin = (vec2(1.0) - visible) * vec2(0.5, landscape ? 0.33 : 0.5);
    vec4 art = texture(TEXTURE, origin + UV * visible);
    vec2 p = SCREEN_UV;
    float top = (1.0 - smoothstep(0.02, 0.36, p.y)) * 0.56;
    float bottom = smoothstep(0.49, 0.83, p.y) * 0.91;
    float edge = pow(abs(p.x - 0.5) * 2.0, 2.0) * 0.12;
    float shade = max(top, bottom) + edge;
    if (landscape) {
        shade = max(0.12, (1.0 - smoothstep(0.20, 0.68, p.x)) * 0.90);
        shade += smoothstep(0.78, 1.0, p.y) * 0.20;
    }
    if (inner_page) { shade = max(shade, 0.58); }
    COLOR = vec4(mix(art.rgb, vec3(0.035, 0.047, 0.051), clamp(shade, 0.0, 0.96)), art.a);
}

shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, depth_test_inverted, shadows_disabled, fog_disabled;
// All normally visible rig fragments have stencil 1 from priority 110. The
// priority 120 silhouette cannot touch ANY such pixel, including own limbs.
// Inverted hardware depth restricts remaining pixels to occluded geometry.
stencil_mode read, compare_not_equal, 1;
uniform vec4 silhouette_color : source_color = vec4(0.76, 0.83, 0.77, 1.0);
void fragment() {
    ALBEDO = silhouette_color.rgb;
    // Flat, not translucent: self-overlapping occluded triangles overwrite the
    // same color instead of accumulating alpha into limb stripes.
    // Writing ALPHA keeps this in the transparent queue even at exactly 1.0.
    ALPHA = 1.0;
}

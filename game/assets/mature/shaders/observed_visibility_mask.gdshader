shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, depth_test_default, shadows_disabled, fog_disabled;
// Run after opaque/cutout world geometry, before every silhouette. Hardware
// depth equality accepts the rig's visible front surface, not its hidden limbs.
// No color/depth change, opaque stencil write or scene-depth texture copy.
// Exact winding contract: source opaque materials must also use cull_disabled.
stencil_mode write, compare_always, 1;
void fragment() {
    ALPHA = 0.0;
}

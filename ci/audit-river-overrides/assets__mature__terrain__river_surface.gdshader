shader_type spatial;
render_mode cull_disabled, diffuse_burley;
varying vec2 terrain_pos;
varying float surface_class;
void vertex() {
    terrain_pos=(MODEL_MATRIX*vec4(VERTEX,1.0)).xz;
    surface_class=COLOR.r;
}
float tile_hash(vec2 p) {
    return fract(sin(dot(p,vec2(127.1,311.7))) * 43758.5453123);
}
void fragment() {
    vec2 p=terrain_pos;
    float rim=1.0-smoothstep(2.35,2.95,abs(p.y));
    float m=tile_hash(floor(p*2.4));
    if (surface_class<0.25) {
        float ripple=0.5+0.5*sin(p.y*12.5 + cos(p.x*1.48)*0.72 + 0.32*sin(p.x*2.5));
        float streak=smoothstep(0.68,0.96,ripple)*smoothstep(0.05,0.74,0.5+0.5*sin(p.x*1.12+p.y));
        ALBEDO=mix(vec3(0.22,0.33,0.32),vec3(0.09,0.25,0.28),rim)+streak*vec3(0.04,0.09,0.10)*rim;
        ROUGHNESS=0.58;
        SPECULAR=0.14;
    } else if (surface_class<0.75) {
        float gap=1.0-smoothstep(0.04,0.12,fract(p.y*4.0));
        float variation=tile_hash(vec2(floor((p.x+18.0)*0.62),floor(p.y*4.0)));
        float beam=1.0-smoothstep(0.15,0.31,min(abs(p.x+17.72),abs(p.x+8.28)));
        ALBEDO=(mix(vec3(0.19,0.105,0.054),vec3(0.42,0.28,0.14),variation)*0.70+vec3(0.11,0.075,0.035))*(1.0-gap*0.65)+beam*vec3(0.14,0.085,0.034);
        ROUGHNESS=0.91;
        SPECULAR=0.06;
    } else {
        float pebble=smoothstep(0.67,0.94,m);
        float shallow=0.5+0.5*sin(p.x*1.6+p.y*8.0);
        ALBEDO=mix(vec3(0.29,0.33,0.285),vec3(0.27,0.37,0.33),rim)+pebble*vec3(0.17,0.155,0.12)+shallow*vec3(0.02,0.04,0.033);
        ROUGHNESS=0.95;
        SPECULAR=0.07;
    }
}

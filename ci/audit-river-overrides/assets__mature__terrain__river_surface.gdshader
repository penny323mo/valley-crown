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
float basin_noise(vec2 p) {
    vec2 c=floor(p);
    vec2 f=fract(p);
    f=f*f*(3.0-2.0*f);
    return mix(mix(tile_hash(c),tile_hash(c+vec2(1.0,0.0)),f.x),
               mix(tile_hash(c+vec2(0.0,1.0)),tile_hash(c+vec2(1.0,1.0)),f.x),f.y);
}
void fragment() {
    vec2 p=terrain_pos;
    float rim=1.0-smoothstep(2.35,2.95,abs(p.y));
    float basin=basin_noise(p*0.43);
    if (surface_class<0.25) {
        float ripple=0.5+0.5*sin(p.y*6.8 + cos(p.x*0.73)*0.72 + basin*3.2);
        float streak=smoothstep(0.68,0.96,ripple)*smoothstep(0.46,0.82,basin);
        ALBEDO=mix(vec3(0.20,0.29,0.27),mix(vec3(0.055,0.18,0.23),vec3(0.115,0.30,0.32),basin),rim)+streak*vec3(0.04,0.08,0.085)*rim;
        ROUGHNESS=0.58;
        SPECULAR=0.14;
    } else if (surface_class<0.75) {
        float board=p.y*2.6;
        float joint=min(fract(board),1.0-fract(board));
        float aa=clamp(fwidth(board)*0.70,0.005,0.13);
        float gap=1.0-smoothstep(0.05-aa,0.075+aa,joint);
        float variation=tile_hash(vec2(2.0,floor(board)));
        float beam=1.0-smoothstep(0.15,0.31,min(abs(p.x+17.72),abs(p.x+8.28)));
        ALBEDO=(mix(vec3(0.19,0.105,0.054),vec3(0.42,0.28,0.14),variation)*0.70+vec3(0.11,0.075,0.035))*(1.0-gap*0.44)+beam*vec3(0.095,0.058,0.027)+basin*vec3(0.043,0.032,0.023);
        ROUGHNESS=0.91;
        SPECULAR=0.06;
    } else {
        float pebble=smoothstep(0.60,0.80,basin_noise(p*5.1+vec2(basin)));
        float flow=0.5+0.5*sin(p.x*0.92+p.y*4.0+basin*3.0);
        vec3 shallows=mix(vec3(0.21,0.32,0.27),vec3(0.39,0.49,0.38),basin);
        ALBEDO=mix(vec3(0.32,0.33,0.25),shallows,rim)+pebble*vec3(0.096,0.078,0.055)+flow*vec3(0.016,0.035,0.027);
        ROUGHNESS=0.95;
        SPECULAR=0.07;
    }
}

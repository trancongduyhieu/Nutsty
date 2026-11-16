#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float u_time;
    float u_zoom;
    float u_scrim;
    float u_mix;    // 0 = source, 1 = source2 (the incoming artwork)
};

layout(binding = 1) uniform sampler2D source;
layout(binding = 2) uniform sampler2D source2;

vec4 tap5(sampler2D tex, vec2 uv) {
    // Soft 5-tap dispersion kernel (Mochy-Music pre-blur equivalent)
    float d = 0.030;
    return texture(tex, uv) * 0.36
         + texture(tex, clamp(uv + vec2( d,  0.0), 0.0, 1.0)) * 0.16
         + texture(tex, clamp(uv + vec2(-d,  0.0), 0.0, 1.0)) * 0.16
         + texture(tex, clamp(uv + vec2(0.0,   d), 0.0, 1.0)) * 0.16
         + texture(tex, clamp(uv + vec2(0.0,  -d), 0.0, 1.0)) * 0.16;
}

void main() {
    // 1:1 Mochy-Music DirectWarp: center zoom + fluid 2D breathing wave (reduced speed by additional 20%)
    vec2 p = (qt_TexCoord0 - 0.5) / u_zoom + 0.5;
    float t = u_time * 0.20;
    vec2 warp = vec2(
        sin(p.y * 3.0 + t) * 0.050 + cos(p.x * 2.0 - t * 0.6) * 0.040,
        cos(p.x * 3.0 + t * 0.7) * 0.050 + sin(p.y * 2.5 + t * 0.9) * 0.040
    );
    vec2 uv = clamp(p + warp, 0.0, 1.0);

    vec4 col = tap5(source, uv);
    if (u_mix > 0.0005) {
        // Liquid hand-over: the incoming colours flood in along a slow wave field instead of a flat
        // dissolve, so the backdrop changes like the same liquid taking on new colour.
        float w = 0.5 + 0.25 * sin(qt_TexCoord0.x * 4.0 + t * 1.3) + 0.25 * cos(qt_TexCoord0.y * 3.5 - t);
        float m = smoothstep(0.0, 1.0, clamp(u_mix * 1.6 - w * 0.6, 0.0, 1.0));
        col = mix(col, tap5(source2, uv), m);
    }

    fragColor = vec4(col.rgb * (1.0 - u_scrim), col.a * qt_Opacity);
}

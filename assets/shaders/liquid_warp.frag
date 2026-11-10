#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float u_time;
    float u_zoom;
    float u_scrim;
};

layout(binding = 1) uniform sampler2D source;

void main() {
    // 1:1 Mochy-Music DirectWarp: center zoom + ultra-serene fluid 2D breathing wave
    vec2 p = (qt_TexCoord0 - 0.5) / u_zoom + 0.5;
    float t = u_time * 0.15;
    vec2 warp = vec2(
        sin(p.y * 2.8 + t) * 0.030 + cos(p.x * 1.8 - t * 0.5) * 0.022,
        cos(p.x * 2.6 + t * 0.6) * 0.030 + sin(p.y * 2.2 + t * 0.8) * 0.022
    );
    vec2 uv = clamp(p + warp, 0.0, 1.0);

    // Soft 5-tap dispersion kernel (Mochy-Music pre-blur equivalent)
    float d = 0.030;
    vec4 col = texture(source, uv) * 0.36
             + texture(source, clamp(uv + vec2( d,  0.0), 0.0, 1.0)) * 0.16
             + texture(source, clamp(uv + vec2(-d,  0.0), 0.0, 1.0)) * 0.16
             + texture(source, clamp(uv + vec2(0.0,   d), 0.0, 1.0)) * 0.16
             + texture(source, clamp(uv + vec2(0.0,  -d), 0.0, 1.0)) * 0.16;

    fragColor = vec4(col.rgb * (1.0 - u_scrim), col.a * qt_Opacity);
}

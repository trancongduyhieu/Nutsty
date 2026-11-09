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
    vec2 p = (qt_TexCoord0 - 0.5) / u_zoom + 0.5;
    float t = u_time * 0.45;
    vec2 warp = vec2(
        sin(p.y * 3.2 + t) * 0.045 + cos(p.x * 2.1 - t * 0.55) * 0.035,
        cos(p.x * 2.8 + t * 0.65) * 0.045 + sin(p.y * 2.4 + t * 0.85) * 0.035
    );
    vec4 col = texture(source, clamp(p + warp, 0.0, 1.0));
    fragColor = vec4(col.rgb * (1.0 - u_scrim), col.a * qt_Opacity);
}

#version 440
// Nutsty cover feather: alpha-fades a texture towards its edges. Each side fades from 0 at
// (edge + start) to full at (edge + end), in normalised texture space; end <= start disables it.
// Applied as an item's own layer.effect, so there is no separate mask item to go stale.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 u_left;
    vec2 u_right;
    vec2 u_top;
    vec2 u_bottom;
};

layout(binding = 1) uniform sampler2D source;

float side(vec2 r, float d) {
    return r.y > r.x + 0.0001 ? smoothstep(r.x, r.y, d) : 1.0;
}

void main() {
    vec2 p = qt_TexCoord0;
    float a = side(u_left, p.x) * side(u_right, 1.0 - p.x) * side(u_top, p.y) * side(u_bottom, 1.0 - p.y);
    fragColor = texture(source, p) * a * qt_Opacity;
}

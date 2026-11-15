#version 440
// Nutsty edge fade: alpha-fades a list texture towards its top and bottom edges so rows
// dissolve instead of being cut by the clip rect. u_top / u_bottom are fade heights in
// normalised texture space (0 disables a side, e.g. when the list is at its start).

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float u_top;
    float u_bottom;
};

layout(binding = 1) uniform sampler2D source;

void main() {
    float y = qt_TexCoord0.y;
    float top = u_top > 0.0001 ? smoothstep(0.0, u_top, y) : 1.0;
    float bottom = u_bottom > 0.0001 ? smoothstep(0.0, u_bottom, 1.0 - y) : 1.0;
    fragColor = texture(source, qt_TexCoord0) * (top * bottom) * qt_Opacity;
}

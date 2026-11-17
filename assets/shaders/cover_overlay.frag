#version 440
// Nutsty generated cover, "marble" layout: the second shape is drawn with the CSS/SVG
// "overlay" blend over the backdrop (background + first shape), as boring-avatars does
// with mix-blend-mode: overlay. Textures are premultiplied; the backdrop is opaque.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
};

layout(binding = 1) uniform sampler2D backdrop;
layout(binding = 2) uniform sampler2D source;

void main() {
    vec4 b = texture(backdrop, qt_TexCoord0);
    vec4 s = texture(source, qt_TexCoord0);
    vec3 cb = b.a > 0.0 ? b.rgb / b.a : vec3(0.0);
    vec3 cs = s.a > 0.0 ? s.rgb / s.a : vec3(0.0);
    // overlay(Cb, Cs) = hard-light with the layers swapped
    vec3 blended = mix(2.0 * cb * cs,
                       1.0 - 2.0 * (1.0 - cb) * (1.0 - cs),
                       step(0.5, cb));
    vec3 rgb = mix(cb, blended, s.a);
    fragColor = vec4(rgb * b.a, b.a) * qt_Opacity;
}

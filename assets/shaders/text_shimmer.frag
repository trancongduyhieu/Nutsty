#version 440
// Nutsty "Mixing" label: the text is drawn dim, and a soft band of light sweeps across it
// left to right (u_sweep 0..1), lighting each letter up and letting it dim again.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float u_sweep;   // 0..1 band position across the label
    float u_band;    // band half-width as a fraction of the label width
    float u_base;    // resting brightness of the text (0..1)
};
layout(binding = 1) uniform sampler2D source;

void main() {
    float a = texture(source, qt_TexCoord0).a;
    // band centre travels from fully left of the text to fully right of it
    float c = mix(-u_band, 1.0 + u_band, u_sweep);
    float d = abs(qt_TexCoord0.x - c) / max(u_band, 1e-3);
    float glow = 1.0 - smoothstep(0.0, 1.0, d);
    float lum = mix(u_base, 1.0, glow);
    float alpha = a * lum;
    fragColor = vec4(vec3(1.0) * alpha, alpha) * qt_Opacity;
}

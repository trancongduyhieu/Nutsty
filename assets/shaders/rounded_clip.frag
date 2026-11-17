#version 440

// Rounds an item's corners with a per-corner SDF (anti-aliased edge, no dark fringe).
// Used by components/RoundedClip.qml.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 u_resolution;   // item size in pixels
    vec4 u_radii;        // top-left, top-right, bottom-right, bottom-left
};

layout(binding = 1) uniform sampler2D source;

void main() {
    vec2 halfSize = u_resolution * 0.5;
    vec2 p = qt_TexCoord0 * u_resolution - halfSize;   // y grows downward
    float r = p.x > 0.0 ? (p.y > 0.0 ? u_radii.z : u_radii.y)
                        : (p.y > 0.0 ? u_radii.w : u_radii.x);
    r = clamp(r, 0.0, min(halfSize.x, halfSize.y));
    vec2 q = abs(p) - halfSize + vec2(r);
    float d = min(max(q.x, q.y), 0.0) + length(max(q, vec2(0.0))) - r;
    float mask = clamp(0.5 - d, 0.0, 1.0);
    // Premultiplied source: scaling all four channels keeps the edge free of dark halos
    fragColor = texture(source, qt_TexCoord0) * (mask * qt_Opacity);
}

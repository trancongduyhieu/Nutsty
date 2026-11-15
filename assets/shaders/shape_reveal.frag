#version 440
// Nutsty shape reveal: masks a texture with a spinning polar "petal" shape that grows
// from an origin point (the window centre) until it covers the whole window.
// r(theta) = reach * (1 - depth + depth * ((1 + cos(lobes * theta)) / 2)^sharp)
// kind == 1 switches to a superellipse (squircle). Edge AA uses the analytic
// distance estimate |r - edge| / sqrt(1 + (dEdge / (r dtheta))^2).

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 u_size;     // item size in px
    vec2 u_origin;   // shape centre in item px
    vec4 u_shape;    // (lobes, depth, sharpness, kind)
    float u_reach;   // outermost radius in px
    float u_spin;    // radians
};

layout(binding = 1) uniform sampler2D source;

float petalEdge(float t) {
    if (u_shape.w > 0.5) {
        float n = u_shape.z;
        return u_reach / pow(pow(abs(cos(t)), n) + pow(abs(sin(t)), n), 1.0 / n);
    }
    float wave = pow(0.5 + 0.5 * cos(u_shape.x * t), u_shape.z);
    return u_reach * ((1.0 - u_shape.y) + u_shape.y * wave);
}

void main() {
    vec2 p = qt_TexCoord0 * u_size - u_origin;
    float r = length(p);
    float t = atan(p.y, p.x) - u_spin;
    float h = 0.003;
    float dEdge = (petalEdge(t + h) - petalEdge(t - h)) / (2.0 * h);
    float edge = petalEdge(t);
    float dist = (r - edge) / sqrt(1.0 + (dEdge * dEdge) / max(r * r, 1.0));
    float cover = clamp(0.5 - dist, 0.0, 1.0);
    fragColor = texture(source, qt_TexCoord0) * (cover * qt_Opacity);
}

#version 440
// Nutsty ink bleed: shows the source (the next mesh) through a watercolour stain that spreads
// from u_origin. One main drop plus three satellite drops at seeded spots; every edge is pushed
// in and out by fbm noise so it creeps unevenly, drops merge with a smooth union, and the rim
// sits a touch darker where pigment pools. Coordinates are in height units (x scaled by aspect).

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float u_progress;   // 0..1
    float u_aspect;     // width / height
    float u_seed;       // new per spread
    float u_time;       // seconds, keeps the edge creeping
    float u_reach;      // farthest corner from the origin, in height units
    vec2 u_origin;      // 0..1 texture space
};

layout(binding = 1) uniform sampler2D source;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7)) + u_seed * 17.13) * 43758.5453); }
float noise(vec2 p) {
    vec2 i = floor(p), f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}
float fbm(vec2 p) {
    float v = 0.0, a = 0.5;
    for (int i = 0; i < 4; i++) { v += a * noise(p); p = p * 2.03 + vec2(1.7, 9.2); a *= 0.5; }
    return v;
}
float smin(float a, float b, float k) {
    float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}
// a drop that starts at `delay`, spreads fast and slows as the paper takes it
float drop(vec2 p, vec2 c, float maxR, float delay) {
    float t = clamp((u_progress - delay) / (1.0 - delay), 0.0, 1.0);
    float r = maxR * (1.0 - pow(1.0 - t, 2.4));
    float wobble = (fbm(p * 3.2 + vec2(u_seed * 3.1, u_time * 0.12)) - 0.5) * 0.55
                 + (fbm(p * 9.0 - vec2(u_time * 0.08, u_seed)) - 0.5) * 0.18;
    return length(p - c) - r * (1.0 + wobble);
}

void main() {
    vec2 p = vec2(qt_TexCoord0.x * u_aspect, qt_TexCoord0.y);
    vec2 o = vec2(u_origin.x * u_aspect, u_origin.y);

    // the main drop reaches past every corner by the end, wobble included
    float d = drop(p, o, u_reach * 1.5 + 0.2, 0.06);
    for (int i = 0; i < 3; i++) {
        float fi = float(i);
        float ang = 6.2832 * fract(sin((fi + 1.0) * 12.9898 + u_seed * 78.233) * 43758.5453);
        float dist = 0.34 + 0.30 * fract(sin((fi + 1.0) * 39.346 + u_seed * 11.135) * 24634.6345);
        vec2 c = o + vec2(cos(ang), sin(ang)) * dist;
        d = smin(d, drop(p, c, u_reach * (0.30 + 0.10 * fi), 0.03 + 0.07 * fi), 0.08);
    }

    float edge = 0.024;
    float a = 1.0 - smoothstep(-edge, edge, d);
    // pigment pools at the drying edge
    float rim = smoothstep(-0.07, -0.005, d) * a;
    vec4 c = texture(source, qt_TexCoord0);
    c.rgb *= 1.0 - 0.22 * rim;
    fragColor = c * a * qt_Opacity;
}

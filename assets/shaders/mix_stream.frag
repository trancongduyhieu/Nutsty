#version 440
// Nutsty AutoMix stream: two streams of glowing particles trade places between two covers,
// like data moving between them. The forward stream (u_a -> u_b) arcs over the line between
// the covers, the return stream (u_b -> u_a) arcs under it. Each particle is drawn as a short
// comet (head plus tail) and shifts colour from its source cover to its target cover.
// Everything is a pure function of u_time, so the stream costs nothing on the CPU.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 u_size;    // item size in px
    vec2 u_a;       // forward stream source, px
    vec2 u_b;       // forward stream target, px
    vec4 u_colA;    // colour of the cover at u_a
    vec4 u_colB;    // colour of the cover at u_b
    float u_time;   // seconds
    float u_flow;   // 0..1 overall intensity
    float u_bias;   // 0..1 share of the forward stream (0.5 = equal exchange)
    float u_bend;   // arc height in px
};

const int N = 54;          // particles per stream
const int GUIDE_SEGS = 10; // polyline segments for the faint guide arc
const float PI = 3.14159265;

float hash(float n) { return fract(sin(n * 127.1 + 11.7) * 43758.5453); }

vec2 bez(vec2 a, vec2 c, vec2 b, float t) {
    float u = 1.0 - t;
    return u * u * a + 2.0 * u * t * c + t * t * b;
}

float segDist(vec2 p, vec2 a, vec2 b) {
    vec2 pa = p - a, ba = b - a;
    float h = clamp(dot(pa, ba) / max(dot(ba, ba), 1e-4), 0.0, 1.0);
    return length(pa - ba * h);
}

void main() {
    vec2 p = qt_TexCoord0 * u_size;
    vec2 dir = u_b - u_a;
    float len = max(length(dir), 1.0);
    vec2 nrm = vec2(-dir.y, dir.x) / len;
    vec2 mid = 0.5 * (u_a + u_b);

    vec3 acc = vec3(0.0);
    float alpha = 0.0;

    for (int s = 0; s < 2; ++s) {
        bool fwd = (s == 0);
        vec2 a = fwd ? u_a : u_b;
        vec2 b = fwd ? u_b : u_a;
        vec2 c = mid + nrm * u_bend * (fwd ? -1.0 : 1.0);
        vec3 ca = fwd ? u_colA.rgb : u_colB.rgb;
        vec3 cb = fwd ? u_colB.rgb : u_colA.rgb;
        float w = clamp((fwd ? u_bias : 1.0 - u_bias) * 2.0, 0.0, 1.0);
        if (w <= 0.001) continue;

        // Faint guide arc the particles ride on, brightest in the middle
        float gd = 1e6;
        float gt = 0.0;
        vec2 prev = a;
        for (int k = 1; k <= GUIDE_SEGS; ++k) {
            float tk = float(k) / float(GUIDE_SEGS);
            vec2 cur = bez(a, c, b, tk);
            float dk = segDist(p, prev, cur);
            if (dk < gd) { gd = dk; gt = tk; }
            prev = cur;
        }
        float gEnv = sin(PI * gt);
        float guide = exp(-gd * gd / 18.0) * 0.10 * gEnv * w;
        acc += mix(ca, cb, gt) * guide;
        alpha += guide;

        float sOff = fwd ? 0.0 : 97.0;
        for (int i = 0; i < N; ++i) {
            float fi = float(i) + sOff;
            float h1 = hash(fi + 1.3);
            float h2 = hash(fi + 7.7);
            float h3 = hash(fi + 13.1);
            float h4 = hash(fi + 21.9);

            // Each particle loops source -> target; easing makes it leave fast and settle in
            float speed = 0.20 + 0.22 * h1;
            float ph = fract(u_time * speed + h2);
            float t = mix(ph, ph * ph * (3.0 - 2.0 * ph), 0.55);
            float env = sin(PI * t);

            // Lanes fan out in the middle and converge on the covers (a lens-shaped beam)
            float lane = (h3 - 0.5) * 2.0;
            float wob = sin(u_time * (1.3 + h4) + fi * 2.1) * 3.0;
            float spread = (u_bend * 0.50 * lane + wob) * env;
            vec2 head = bez(a, c, b, t) + nrm * spread;

            float t2 = max(t - (0.03 + 0.035 * h4), 0.0);
            float env2 = sin(PI * t2);
            vec2 tail = bez(a, c, b, t2) + nrm * (u_bend * 0.50 * lane + wob) * env2;

            float r = (1.0 + 1.8 * h4) * (0.55 + 0.65 * env);
            float d = segDist(p, head, tail);
            float dh = length(p - head);
            float core = exp(-dh * dh / (r * r)) + 0.55 * exp(-d * d / (r * r * 0.6));
            float halo = exp(-dh * dh / (r * r * 12.0)) * 0.28;
            float bright = (core + halo) * pow(env, 0.7) * w * (0.55 + 0.45 * h1);

            vec3 col = mix(ca, cb, smoothstep(0.12, 0.88, t));
            col = mix(col, vec3(1.0), clamp(core * 0.4, 0.0, 0.6));  // hot white core
            acc += col * bright;
            alpha += bright;
        }
    }

    float a = clamp(alpha, 0.0, 1.0) * u_flow;
    vec3 rgb = min(acc * u_flow, vec3(1.0));
    fragColor = vec4(rgb, a) * qt_Opacity;
}

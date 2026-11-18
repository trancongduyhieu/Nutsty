#version 440
// Nutsty desktop lyrics preset 7: an old film / CRT pass over the lyric layer.
// Grain, faint scanlines and brightness flicker live only inside the letters, so the wallpaper
// around them stays clean. A chroma fringe and a brief horizontal tear fire on cuts. A projector
// hair wiggles near an edge now and then, and thin vertical scratches flash across the frame.
// Big hits smear a streak of light sideways off the letters and swell the frame for a beat.
// All timing comes from kinetic_stage.js (film()); this shader only draws.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 u_size;        // layer size in px
    float u_frame;      // film frame counter (24 per second)
    float u_grain;      // 0..1 grain strength inside the letters
    float u_scan;       // 0..1 scanline depth
    float u_flicker;    // brightness multiplier, around 1
    float u_chroma;     // fringe offset in px
    float u_tear;       // 0..1 horizontal tear
    float u_hair;       // 0..1 hair opacity
    float u_hairX;      // hair centre, 0..1 across
    float u_hairAmp;    // hair wiggle, share of the width
    float u_hairPhase;
    float u_scratchX;   // scratch position, 0..1 across
    float u_scratchA;   // scratch opacity
    float u_smear;      // horizontal light streak length in px
    float u_smearDir;   // -1 streaks to the left, 1 to the right
    float u_bulge;      // 0..0.1 lens swell around the centre
    vec4 u_ink;         // text colour
    vec4 u_accent;      // palette highlight
};
layout(binding = 1) uniform sampler2D source;

float hash(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

void main() {
    vec2 px = 1.0 / max(u_size, vec2(1.0));
    vec2 uv = qt_TexCoord0;

    // Bulge: the frame swells from the middle for a beat as a hit lands
    if (u_bulge > 0.0005) {
        vec2 d = uv - 0.5;
        uv = 0.5 + d * (1.0 - u_bulge * (1.0 - dot(d, d) * 2.0));
    }

    // Tear: some 6 px bands slide sideways for a couple of frames
    if (u_tear > 0.001) {
        float band = floor(uv.y * u_size.y / 6.0);
        float pick = step(0.55, hash(vec2(band, u_frame)));
        uv.x += (hash(vec2(band * 1.7, u_frame + 3.0)) - 0.5) * 36.0 * px.x * u_tear * pick;
    }

    vec4 c = texture(source, uv);

    // Chroma fringe: accent spills to the left of each letter, text colour to the right
    if (u_chroma > 0.01) {
        float aL = texture(source, uv + vec2(u_chroma * px.x, 0.0)).a;
        float aR = texture(source, uv - vec2(u_chroma * px.x, 0.0)).a;
        float fa = max(aL - c.a, 0.0) * 0.6;
        float fb = max(aR - c.a, 0.0) * 0.35;
        c += vec4(u_accent.rgb * fa, fa) + vec4(u_ink.rgb * fb, fb);
    }

    // Smear: a streak of light trails off the letters, like a long exposure of a moving sign
    if (u_smear > 0.5) {
        vec4 acc = vec4(0.0);
        float wsum = 0.0;
        for (int i = 1; i <= 10; i++) {
            float fi = float(i) / 10.0;
            float wgt = (1.0 - fi) * (1.0 - fi);
            acc += texture(source, uv - vec2(u_smearDir * u_smear * fi * px.x, 0.0)) * wgt;
            wsum += wgt;
        }
        vec4 streak = acc / wsum;
        // only where the letters are not, so the words stay sharp
        float room = 1.0 - c.a;
        c += vec4(mix(u_ink.rgb, u_accent.rgb, 0.5) * streak.a, streak.a) * 0.55 * room;
    }

    // Grain, scanlines and flicker inside the letters only
    float n = hash(floor(uv * u_size / 1.5) + vec2(u_frame * 13.1, u_frame * 7.7));
    float scan = 0.5 + 0.5 * sin(uv.y * u_size.y * 3.14159 / 1.5);
    c.rgb *= (1.0 + (n - 0.5) * u_grain * 0.9) * (1.0 - u_scan * scan) * u_flicker;
    // worn specks punch small holes in the ink
    c *= 1.0 - step(1.0 - 0.02 * u_grain, n) * 0.6;
    c.rgb = min(c.rgb, vec3(c.a));

    // Projector hair: a thin wavy strand over part of the frame height
    if (u_hair > 0.001) {
        float y = qt_TexCoord0.y;
        float hx = u_hairX + u_hairAmp * sin(y * 7.0 + u_hairPhase) + 0.35 * u_hairAmp * sin(y * 19.0 - u_hairPhase * 1.6);
        float d = abs(qt_TexCoord0.x - hx) * u_size.x;
        float span = smoothstep(0.05, 0.22, y) * (1.0 - smoothstep(0.7, 0.92, y));
        float h = (1.0 - smoothstep(0.35, 1.3, d)) * span * u_hair * 0.55;
        c = c * (1.0 - h) + vec4(u_ink.rgb * h, h);
    }

    // Scratch: a one pixel vertical line, broken along its length
    if (u_scratchA > 0.001) {
        float d = abs(qt_TexCoord0.x - u_scratchX) * u_size.x;
        float broken = step(0.3, hash(vec2(floor(qt_TexCoord0.y * u_size.y / 9.0), u_frame)));
        float s = (1.0 - smoothstep(0.2, 0.9, d)) * broken * u_scratchA * 0.45;
        c = c * (1.0 - s) + vec4(u_ink.rgb * s, s);
    }

    fragColor = c * qt_Opacity;
}

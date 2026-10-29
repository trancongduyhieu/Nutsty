#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 u_resolution;    // Size of the glass item (width, height in pixels)
    float u_radius;       // Corner radius in pixels
    float u_displacement; // Refraction strength (pixel offset in source texture)
    float u_aberration;   // Chromatic dispersion factor (0.0 to 1.0)
    float u_bevelWidth;   // Width of the curved bevel edge (pixels)
    vec4 u_tint;          // Tint color and alpha
    vec2 u_sourceSize;    // Size of the background texture in pixels
    vec2 u_sourceOffset;  // Global pixel offset of this item inside source texture
    float u_time;         // Time in seconds for viscous wave flow
    float u_flowActive;   // 1.0 when music is playing, 0.0 when stopped
};

layout(binding = 1) uniform sampler2D source;

// Inigo Quilez 2D Rounded Box SDF
float sdRoundedBox(vec2 p, vec2 b, float r) {
    vec2 q = abs(p) - b + vec2(r);
    return min(max(q.x, q.y), 0.0) + length(max(q, vec2(0.0))) - r;
}

// Circle map curve from AndroidLiquidGlass / Kyant0 (SimpMusic)
float circleMap(float x) {
    return 1.0 - sqrt(max(0.0, 1.0 - x * x));
}

// Analytical Gradient of Rounded Box SDF (Zero numerical jitter, perfectly uniform at corners)
vec2 gradSdRoundedRect(vec2 coord, vec2 halfSize, float radius) {
    vec2 cornerCoord = abs(coord) - (halfSize - vec2(radius));
    if (cornerCoord.x >= 0.0 || cornerCoord.y >= 0.0) {
        return sign(coord) * normalize(max(cornerCoord, vec2(1e-5)));
    } else {
        float gradX = step(cornerCoord.y, cornerCoord.x);
        return sign(coord) * vec2(gradX, 1.0 - gradX);
    }
}

void main() {
    vec2 pixelPos = qt_TexCoord0 * u_resolution;
    vec2 center = u_resolution * 0.5;
    vec2 halfSize = u_resolution * 0.5;
    vec2 centeredCoord = pixelPos - center;
    
    // Distance from current pixel to rounded box border
    float d = sdRoundedBox(centeredCoord, halfSize, u_radius);
    
    // Anti-aliased outer silhouette mask with clamped edgeWidth
    float edgeWidth = clamp(fwidth(d), 0.75, 2.0);
    float mask = 1.0 - smoothstep(-edgeWidth, edgeWidth, d);
    if (mask <= 0.0) {
        fragColor = vec4(0.0);
        return;
    }
    
    float distInside = -d;
    
    // Bevel normal and curvature
    float gradRadius = min(u_radius * 1.5, min(halfSize.x, halfSize.y));
    vec2 grad = gradSdRoundedRect(centeredCoord, halfSize, gradRadius);
    vec2 normCentered = normalize(centeredCoord);
    grad = normalize(grad + 0.35 * normCentered);
    
    // =========================================================================
    // 1. Viscous Keo 502 Surface Tension & Whole-Surface Dome Lens Curvature
    // Tạo độ phồng vòm 3D (Spherical Dome Bulge) và sóng dẻo lượn sóng đàn hồi
    // =========================================================================
    // =========================================================================
    // 1. Viscous Keo 502 Surface Tension & Meniscus Curvature (Clean & Single-Image)
    // Khúc xạ bẻ cong mềm mại ở mép viền, loại bỏ hoàn toàn hiện tượng phân thân bóng ma
    // =========================================================================
    float refrHeight = max(8.0, min(u_bevelWidth > 0.0 ? u_bevelWidth : 10.0, halfSize.y * 0.32));
    float tEdge = clamp(1.0 - distInside / refrHeight, 0.0, 1.0);
    
    // Elastic Dome Curvature: độ phồng vòm nhẹ nhàng không làm biến dạng chữ thành nhiều bóng
    vec2 normalizedPos = centeredCoord / max(vec2(1.0), halfSize);
    float domeBulge = (1.0 - dot(normalizedPos, normalizedPos) * 0.5) * 0.12;
    
    // Độ dời khúc xạ tinh tế ở mép (10px) kết hợp sóng dẻo êm ái
    float dispAmount = -abs(u_displacement > 0.0 ? u_displacement : 9.0);
    vec2 sampleOffset = circleMap(tEdge) * dispAmount * grad;
    
    vec2 displacedPixel = pixelPos + sampleOffset;
    vec2 uv = clamp((u_sourceOffset + displacedPixel) / u_sourceSize, vec2(0.001), vec2(0.999));
    vec2 pixelStep = 1.0 / u_sourceSize;
    
    // =========================================================================
    // 2. Ultra-Deep Creamy Frosted Blur (20-Tap Multi-Ring Poisson Dispersion)
    // Tán nhuyễn hoàn toàn chữ và cạnh sắc thành một khối sương dẻo thuần nhất
    // =========================================================================
    float rDeep  = 38.0;
    float rOuter = 22.0;
    float rMid   = 11.0;
    float rInner = 5.0;
    
    vec3 bDeep = (
        texture(source, uv + vec2( rDeep,  0.0) * pixelStep).rgb +
        texture(source, uv + vec2(-rDeep,  0.0) * pixelStep).rgb +
        texture(source, uv + vec2( 0.0,  rDeep) * pixelStep).rgb +
        texture(source, uv + vec2( 0.0, -rDeep) * pixelStep).rgb
    ) * 0.25;

    vec3 bOuter = (
        texture(source, uv + vec2( rOuter * 0.707,  rOuter * 0.707) * pixelStep).rgb +
        texture(source, uv + vec2(-rOuter * 0.707, -rOuter * 0.707) * pixelStep).rgb +
        texture(source, uv + vec2( rOuter * 0.707, -rOuter * 0.707) * pixelStep).rgb +
        texture(source, uv + vec2(-rOuter * 0.707,  rOuter * 0.707) * pixelStep).rgb
    ) * 0.25;
    
    vec3 bMid = (
        texture(source, uv + vec2( rMid,  0.0) * pixelStep).rgb +
        texture(source, uv + vec2(-rMid,  0.0) * pixelStep).rgb +
        texture(source, uv + vec2( 0.0,  rMid) * pixelStep).rgb +
        texture(source, uv + vec2( 0.0, -rMid) * pixelStep).rgb
    ) * 0.25;

    vec3 bInner = (
        texture(source, uv + vec2( rInner * 0.707,  rInner * 0.707) * pixelStep).rgb +
        texture(source, uv + vec2(-rInner * 0.707, -rInner * 0.707) * pixelStep).rgb +
        texture(source, uv + vec2( rInner * 0.707, -rInner * 0.707) * pixelStep).rgb +
        texture(source, uv + vec2(-rInner * 0.707,  rInner * 0.707) * pixelStep).rgb
    ) * 0.25;
    
    vec3 bCenter = texture(source, uv).rgb;
    // Đồng nhất sương mờ: không lấy mẫu tách rời gây bóng ma, 92% mờ mịn + 8% tâm
    vec3 baseFrosted = bDeep * 0.30 + bOuter * 0.30 + bMid * 0.22 + bInner * 0.10 + bCenter * 0.08;
    
    // Tán sắc cầu vồng siêu mảnh chỉ xuất hiện tại mép bo cong (bán kính chuẩn quang học ~2.2px)
    float edgeChroma = circleMap(tEdge) * (u_aberration > 0.0 ? u_aberration : 0.025) * 45.0;
    vec2 chromaOffset = grad * edgeChroma * pixelStep;
    
    vec3 refractiveResin;
    refractiveResin.r = texture(source, uv + chromaOffset).r * 0.25 + baseFrosted.r * 0.75;
    refractiveResin.g = baseFrosted.g;
    refractiveResin.b = texture(source, uv - chromaOffset).b * 0.25 + baseFrosted.b * 0.75;
    
    // =========================================================================
    // 3. Keo 502 Glossy Meniscus Specular (Sức căng bề mặt & độ bóng trơn dẻo)
    // =========================================================================
    float rimDistance = clamp(distInside / 8.0, 0.0, 1.0);
    float rimSheen = pow(1.0 - rimDistance, 3.5) * 0.22;
    
    // Phản xạ ánh sáng mép trên (Top Light Specular Reflection)
    float topReflect = smoothstep(halfSize.y, -halfSize.y * 0.3, centeredCoord.y) * 
                       pow(clamp(1.0 - abs(distInside - 2.2) / 2.2, 0.0, 1.0), 2.0) * 0.18;
    float keo502Gloss = rimSheen + topReflect;
    
    // =========================================================================
    // 4. Dynamic Dual-Tone Color Extraction & Live Diffusion
    // =========================================================================
    // SimpMusic Vibrancy: boost saturation by 1.6x on frosted background color
    float lum = dot(baseFrosted, vec3(0.2126, 0.7152, 0.0722));
    vec3 vibrantDiffuse = clamp(mix(vec3(lum), baseFrosted, 1.60) + vec3(0.03 * lum), 0.0, 1.0);
    
    vec3 songColorA = mix(u_tint.rgb * 1.35 + vec3(0.04), vibrantDiffuse, 0.45);
    vec3 songColorB = mix(u_tint.rgb * 0.75 + vec3(0.02), vibrantDiffuse * 0.65, 0.45);
    
    // =========================================================================
    // 5. Viscous Flow Wave Diffusion (Sóng lỏng dẻo lan màu từ từ)
    // =========================================================================
    float flowTime = u_time * 0.22;
    
    // 3 lớp sóng chất lỏng dẻo giao thoa lượn sóng
    float wave1 = sin(pixelPos.x * 0.005 + flowTime * 0.8) * 0.5 + 0.5;
    float wave2 = cos(pixelPos.x * 0.003 - pixelPos.y * 0.015 + flowTime * 0.6) * 0.5 + 0.5;
    float wave3 = sin((pixelPos.x + pixelPos.y * 0.5) * 0.004 - flowTime * 0.4) * 0.5 + 0.5;
    
    float fluidPattern = smoothstep(0.20, 0.80, wave1 * 0.45 + wave2 * 0.35 + wave3 * 0.20);
    vec3 diffusingSongColor = mix(songColorA, songColorB, fluidPattern);
    
    // Lan màu nhẹ nhàng (~24%), giữ trọn vẹn độ trong veo của keo
    float tintStrength = 0.22 * clamp(u_flowActive, 0.0, 1.0);
    vec3 tintedKeo = mix(refractiveResin, diffusingSongColor, tintStrength);
    
    // =========================================================================
    // 6. Final Composite & Authentic Premultiplied Alpha (Ultra-Creamy Liquid Gem)
    // Hoàn toàn không để lọt pixel thô sắc nhọn bên dưới; tự thân khối kính là
    // một thấu kính ngọc lỏng khuếch tán mờ mịn, khúc xạ và phát quang màu sắc
    // =========================================================================
    float rimProfile = smoothstep(2.5, 0.3, distInside);
    vec3 organicRim = mix(u_tint.rgb * 1.30 + vec3(0.06), diffusingSongColor, 0.50);
    
    // Tăng cường ánh sáng nội tại (ambient jewel glow) để thanh playerbar không bị đen thui khi nền tối
    vec3 luminousResin = mix(refractiveResin, diffusingSongColor, 0.38 + 0.15 * u_flowActive);
    vec3 refractionBody = mix(luminousResin, organicRim, rimProfile * 0.40) + vec3(keo502Gloss);
    
    // Tone curve: giữ cho khối kính luôn có ánh màu trong suốt, rực rỡ và giàu sức sống
    vec3 finalColor = clamp(refractionBody + vec3(domeBulge * 0.08), 0.0, 1.0);
    
    // Strict Premultiplied Alpha: phủ kín 100% hình dạng bo tròn để xóa sổ hoàn toàn
    // các tia sáng thô sắc nhọn của chữ/hình bên dưới lọt qua, giữ trọn vẹn lớp sương dẻo
    float outAlpha = mask * qt_Opacity;
    fragColor = vec4(finalColor * outAlpha, outAlpha);
}

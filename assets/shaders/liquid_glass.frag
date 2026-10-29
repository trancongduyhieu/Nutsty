#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float u_blur;         // Độ mờ nhòe tán sương (0.0 đến 20.0 px)
    vec2 u_resolution;    // Kích thước thanh PlayerBar (width, height theo pixel)
    float u_radius;       // Bán kính bo góc (pixels)
    float u_displacement; // Độ phóng đại khúc xạ quang học theo Snell's law (scale px)
    float u_aberration;   // Hệ số tán sắc quang sai viền
    float u_bevelWidth;   // Bề rộng của dải mép kính uốn cong (bezel band px)
    float u_colorBleed;   // Mức độ lan màu và hấp thụ sắc tố động (0.0 đến 1.0)
    float u_time;         // Thời gian (giây)
    float u_flowActive;   // 1.0 khi đang phát nhạc, 0.0 khi dừng
    float _pad;           // std140 alignment padding
    vec2 u_sourceSize;    // Kích thước texture giao diện nền phía sau
    vec2 u_sourceOffset;  // Tọa độ bù của PlayerBar trên giao diện nền
    vec4 u_tint;          // Sắc thái màu động từ bài hát và độ trong suốt
};

layout(binding = 1) uniform sampler2D source;

// =============================================================================
// 1. Apple Convex Squircle Height Profile & Snell's Law Refraction
// f(u) = (1 - (1 - u)^4)^(1/4) cho u thuộc [0, 1] từ mép ngoài vào trong
// =============================================================================
float squircleHeight(float u) {
    float clampedU = clamp(u, 0.0, 1.0);
    float om = 1.0 - clampedU;
    return pow(max(0.0, 1.0 - om * om * om * om), 0.25);
}

// Tính độ dời tia sáng theo Định luật Snell-Descartes: n1 * sin(theta1) = n2 * sin(theta2)
// n1 = 1.0 (không khí), n2 = 1.5 (thủy tinh/pha lê cao cấp)
float snellDeflection(float u) {
    float eps = 0.002;
    float u1 = clamp(u - eps, 0.0, 1.0);
    float u2 = clamp(u + eps, 0.0, 1.0);
    float slope = (squircleHeight(u2) - squircleHeight(u1)) / (u2 - u1);
    
    float theta1 = atan(slope);
    float sinTheta2 = clamp((1.0 / 1.5) * sin(theta1), -0.999, 0.999);
    float theta2 = asin(sinTheta2);
    
    // Độ lệch phương ngang của tia sáng khi khúc xạ qua lớp kính
    return tan(theta1 - theta2);
}

// Inigo Quilez 2D Rounded Rectangle Signed Distance Field
float sdRoundedBox(vec2 p, vec2 b, float r) {
    vec2 q = abs(p) - b + vec2(r);
    return min(max(q.x, q.y), 0.0) + length(max(q, vec2(0.0))) - r;
}

// Đạo hàm giải tích pháp tuyến bề mặt viền bo SDF
vec2 gradSdRoundedRect(vec2 coord, vec2 halfSize, float radius) {
    vec2 cornerCoord = abs(coord) - (halfSize - vec2(radius));
    if (cornerCoord.x >= 0.0 || cornerCoord.y >= 0.0) {
        return sign(coord) * normalize(max(cornerCoord, vec2(1e-5)));
    } else {
        float gradX = step(cornerCoord.y, cornerCoord.x);
        return sign(coord) * vec2(gradX, 1.0 - gradX);
    }
}

// Bộ lọc tăng độ mọng màu (Apple Vibrancy): Tăng saturation nhưng giữ nguyên độ trong
vec3 applyVibrancy(vec3 col) {
    float luma = dot(col, vec3(0.2126, 0.7152, 0.0722));
    return clamp(mix(vec3(luma), col, 1.42), 0.0, 1.0);
}

void main() {
    vec2 pixelPos = qt_TexCoord0 * u_resolution;
    vec2 halfSize = u_resolution * 0.5;
    vec2 centeredCoord = pixelPos - halfSize;
    float radius = min(u_radius, min(halfSize.x, halfSize.y));
    
    // Khoảng cách có dấu tới mép bo ngoài
    float sd = sdRoundedBox(centeredCoord, halfSize, radius);
    
    // Khử răng cưa siêu mịn mép ngoài (Smooth Antialiasing Mask)
    float edgeWidth = clamp(fwidth(sd), 0.75, 1.75);
    float mask = 1.0 - smoothstep(-edgeWidth, edgeWidth, sd);
    if (mask <= 0.0) {
        fragColor = vec4(0.0);
        return;
    }
    
    float depthInside = -sd; // Khoảng cách đi sâu vào bên trong kính (px)
    
    // =========================================================================
    // 2. Độ cong vòm viền (Bezel Band) theo chuẩn Convex Squircle của Apple
    // =========================================================================
    float bezelWidth = max(10.0, u_bevelWidth > 0.0 ? u_bevelWidth : 20.0);
    float refrScale = abs(u_displacement > 0.0 ? u_displacement : 22.0);
    
    vec2 gradRadius = vec2(min(radius * 1.5, min(halfSize.x, halfSize.y)));
    vec2 normalOutward = gradSdRoundedRect(centeredCoord, halfSize, gradRadius.x);
    
    vec2 deflectionOffset = vec2(0.0);
    float normDepth = 1.0;
    
    if (depthInside < bezelWidth) {
        // Pixel nằm trên dải viền mép uốn cong: tính khúc xạ theo định luật Snell
        normDepth = depthInside / bezelWidth; // 0 = mép ngoài cùng, 1 = bắt đầu mặt phẳng trong
        float deflect = snellDeflection(normDepth);
        // Chuẩn hóa cực đại của hàm deflection (~0.45) về 0..1
        float normDeflect = clamp(deflect / 0.45, 0.0, 1.0);
        // Hướng pháp tuyến hướng ra ngoài -> khúc xạ kéo dãn hình ảnh phóng đại (magnifying rim)
        deflectionOffset = normalOutward * (normDeflect * refrScale);
    }
    
    // =========================================================================
    // 3. Lấy mẫu Texture nền (Adaptive Variable Blur + Vibrancy)
    // Tối ưu siêu nhẹ: 5-tap (blur nhỏ) đến 9-tap (blur lớn), an toàn tuyệt đối cho VM
    // =========================================================================
    vec2 displacedPos = pixelPos + deflectionOffset;
    vec2 uvCenter = clamp((u_sourceOffset + displacedPos) / u_sourceSize, vec2(0.001), vec2(0.999));
    vec2 pixelStep = 1.0 / u_sourceSize;
    
    float blurPx = max(0.5, u_blur);
    vec3 crystalSample = texture(source, uvCenter).rgb * 0.36;
    
    // 4 tap chữ thập theo bán kính u_blur
    crystalSample += (
        texture(source, uvCenter + vec2( blurPx, 0.0) * pixelStep).rgb +
        texture(source, uvCenter + vec2(-blurPx, 0.0) * pixelStep).rgb +
        texture(source, uvCenter + vec2(0.0,  blurPx) * pixelStep).rgb +
        texture(source, uvCenter + vec2(0.0, -blurPx) * pixelStep).rgb
    ) * 0.11;
    
    // 4 tap đường chéo bổ sung khi u_blur > 2.5px để tán sương mịn màng
    if (blurPx > 2.5) {
        float diagPx = blurPx * 0.7071;
        vec3 diagSample = (
            texture(source, uvCenter + vec2( diagPx,  diagPx) * pixelStep).rgb +
            texture(source, uvCenter + vec2(-diagPx,  diagPx) * pixelStep).rgb +
            texture(source, uvCenter + vec2( diagPx, -diagPx) * pixelStep).rgb +
            texture(source, uvCenter + vec2(-diagPx, -diagPx) * pixelStep).rgb
        ) * 0.05;
        crystalSample = crystalSample * 0.80 + diagSample;
    }
    
    // Tăng cường độ tươi tắn mọng nước (Vibrancy) cho ảnh nền khúc xạ
    vec3 vibrantBase = applyVibrancy(crystalSample);
    
    // =========================================================================
    // 4. Tán sắc lăng kính góc bo (Corner Prism Dispersion)
    // =========================================================================
    float cornerWeight = (abs(centeredCoord.x * centeredCoord.y) / max(1.0, halfSize.x * halfSize.y));
    float chromaAmt = (u_aberration > 0.0 ? u_aberration : 0.04) * cornerWeight * 40.0;
    
    vec3 refractedColor = vibrantBase;
    if (chromaAmt > 0.02 && depthInside < bezelWidth) {
        vec2 dispVec = normalOutward * chromaAmt * pixelStep;
        float rBand = texture(source, uvCenter + dispVec).r;
        float bBand = texture(source, uvCenter - dispVec).b;
        refractedColor.r = mix(vibrantBase.r, applyVibrancy(vec3(rBand)).r, 0.40);
        refractedColor.b = mix(vibrantBase.b, applyVibrancy(vec3(bBand)).b, 0.40);
    }
    
    // =========================================================================
    // 5. Dynamic Chromatic Rim & Specular Highlight
    // Tự động hấp thụ và phản chiếu màu sắc của bài hát/ảnh đang cuộn bên dưới khắp viền
    // =========================================================================
    // Lấy mẫu màu sắc nền cục bộ ngay tại mép viền bo (chính xác nơi tia sáng đi vào)
    vec2 rimSampleUv = clamp((u_sourceOffset + pixelPos - normalOutward * 2.5) / u_sourceSize, vec2(0.001), vec2(0.999));
    vec3 localBorderColor = texture(source, rimSampleUv).rgb;
    vec3 vibrantBorderColor = applyVibrancy(localBorderColor);
    
    // Viền phản xạ ánh sáng: hòa trộn linh hoạt giữa vệt sáng trắng và màu sắc nền cục bộ
    // Khi bìa đĩa đỏ/xanh/tím/vàng đi qua, viền ngay tại vị trí đó sẽ ánh lên màu sắc tương ứng
    vec3 dynamicRimColor = mix(vec3(1.0), vibrantBorderColor * 1.5, clamp(u_colorBleed * 1.1, 0.20, 0.90));
    
    // Vệt sáng phản xạ định hướng 45 độ (quét dọc theo viền của Apple)
    vec2 lightDir = vec2(0.70710678, 0.70710678);
    float dotLight = dot(normalOutward, lightDir);
    float highlightCurve = pow(max(0.0, dotLight), 1.2);
    
    // Vệt phản quang tập trung ở đỉnh mép vát ngoài (depth 0.5px đến 2.5px)
    float rimProfile = smoothstep(3.0, 0.8, depthInside);
    vec3 specularHighlight = dynamicRimColor * (highlightCurve * rimProfile * 0.75);
    
    // Viền quang học hairline 1px tự động đổi màu theo bài hát/ảnh bên dưới
    float hairline = smoothstep(1.7, 0.85, depthInside) * (1.0 - smoothstep(0.85, 0.0, depthInside));
    vec3 opticalHairline = dynamicRimColor * (hairline * 0.55);
    
    // Phản xạ đáy nhẹ (Ambient bottom bounce light)
    float bottomBounce = smoothstep(1.5, 0.2, depthInside) * 0.15;
    
    // =========================================================================
    // 6. Đổ bóng nội tại, Lan màu động & Lớp Scrim tinh thể trong suốt
    // =========================================================================
    // Inner bevel shadow: dải tối viền nhẹ sâu bên trong tạo độ dày thể tích pha lê 3D
    float innerBevelShadow = smoothstep(0.0, bezelWidth * 0.7, depthInside) * 0.08 + 0.92;
    
    // Lan màu động dọc theo dải viền mép uốn cong
    vec3 glassVolumetric = mix(refractedColor * innerBevelShadow, vibrantBase, u_colorBleed * 0.35);
    
    // Scrim nhẹ nhàng trong trẻo (darken 0.16) để chữ trắng nổi bật mà nền vẫn trong veo
    vec3 glassWithScrim = mix(glassVolumetric, vec3(0.01, 0.01, 0.02), 0.16);
    
    // Cộng hưởng vệt sáng phản xạ viền và viền hairline quang học đổi màu
    vec3 withSpec = glassWithScrim + specularHighlight + opticalHairline + vec3(bottomBounce);
    
    // Hòa quyện sắc thái màu động toàn cục từ bài hát (Dynamic Accent Tint)
    vec3 finalColor = mix(withSpec, u_tint.rgb, u_tint.a > 0.0 ? (u_tint.a * 0.24) : 0.10);
    
    // =========================================================================
    // 7. Xuất màu chuẩn Premultiplied Alpha
    // =========================================================================
    float glassAlpha = clamp(u_tint.a > 0.0 ? u_tint.a : 0.74, 0.55, 0.85);
    float outAlpha = glassAlpha * mask * qt_Opacity;
    
    fragColor = vec4(clamp(finalColor, 0.0, 1.0) * outAlpha, outAlpha);
}

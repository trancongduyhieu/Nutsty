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
    float u_time;         // Time in seconds
    float u_flowActive;   // 1.0 when active
};

layout(binding = 1) uniform sampler2D source;

// Inigo Quilez 2D Rounded Box SDF
float sdRoundedBox(vec2 p, vec2 b, float r) {
    vec2 q = abs(p) - b + vec2(r);
    return min(max(q.x, q.y), 0.0) + length(max(q, vec2(0.0))) - r;
}

// Circle map curve from Kyant Backdrop (SimpMusic)
float circleMap(float x) {
    return 1.0 - sqrt(max(0.0, 1.0 - x * x));
}

// Analytical Gradient of Rounded Box SDF from Kyant Backdrop
vec2 gradSdRoundedRect(vec2 coord, vec2 halfSize, float radius) {
    vec2 cornerCoord = abs(coord) - (halfSize - vec2(radius));
    if (cornerCoord.x >= 0.0 || cornerCoord.y >= 0.0) {
        return sign(coord) * normalize(max(cornerCoord, vec2(1e-5)));
    } else {
        float gradX = step(cornerCoord.y, cornerCoord.x);
        return sign(coord) * vec2(gradX, 1.0 - gradX);
    }
}

// Kyant Backdrop Vibrancy (Saturation = 1.5, Brightness = 0.05, Contrast = 1.0)
vec3 applyVibrancy(vec3 color) {
    float luma = dot(color, vec3(0.213, 0.715, 0.072));
    vec3 satColor = mix(vec3(luma), color, 1.5);
    return clamp(satColor + vec3(0.05), 0.0, 1.0);
}

void main() {
    vec2 pixelPos = qt_TexCoord0 * u_resolution;
    vec2 halfSize = u_resolution * 0.5;
    vec2 centeredCoord = pixelPos - halfSize;
    float radius = min(u_radius, min(halfSize.x, halfSize.y));
    
    // Signed distance to rounded rectangle boundary
    float sd = sdRoundedBox(centeredCoord, halfSize, radius);
    
    // Antialiased outer boundary mask
    float edgeWidth = clamp(fwidth(sd), 0.75, 2.0);
    float mask = 1.0 - smoothstep(-edgeWidth, edgeWidth, sd);
    if (mask <= 0.0) {
        fragColor = vec4(0.0);
        return;
    }
    
    float distInside = -sd;
    
    // -------------------------------------------------------------------------
    // 1. Kyant Lens Refraction (SDF circleMap)
    // SimpMusic: refractionHeight = minDimension / 4.0, refractionAmount = minDimension / 2.0
    // -------------------------------------------------------------------------
    float minDim = min(u_resolution.x, u_resolution.y);
    float refrHeight = max(8.0, min(u_bevelWidth > 0.0 ? u_bevelWidth : (minDim * 0.25), halfSize.y));
    float refrAmount = abs(u_displacement > 0.0 ? u_displacement : (minDim * 0.50));
    
    float gradRadius = min(radius * 1.5, min(halfSize.x, halfSize.y));
    vec2 grad = gradSdRoundedRect(centeredCoord, halfSize, gradRadius);
    
    vec2 sampleOffset = vec2(0.0);
    if (distInside < refrHeight) {
        float t = clamp(1.0 - distInside / refrHeight, 0.0, 1.0);
        sampleOffset = circleMap(t) * (-refrAmount) * grad;
    }
    
    vec2 displacedPixel = pixelPos + sampleOffset;
    vec2 uv = clamp((u_sourceOffset + displacedPixel) / u_sourceSize, vec2(0.001), vec2(0.999));
    vec2 pixelStep = 1.0 / u_sourceSize;
    
    // -------------------------------------------------------------------------
    // 2. Kyant Frosted Blur (blur(8dp) 13-tap smooth disc sampling)
    // -------------------------------------------------------------------------
    float r1 = 5.5;
    float r2 = 12.0;
    
    vec3 baseColor = texture(source, uv).rgb * 0.20;
    
    // Inner ring (r = 5.5px)
    baseColor += (
        texture(source, uv + vec2( r1,  0.0) * pixelStep).rgb +
        texture(source, uv + vec2(-r1,  0.0) * pixelStep).rgb +
        texture(source, uv + vec2( 0.0,  r1) * pixelStep).rgb +
        texture(source, uv + vec2( 0.0, -r1) * pixelStep).rgb
    ) * 0.10;
    
    // Outer ring (r = 12.0px)
    baseColor += (
        texture(source, uv + vec2( r2,  0.0) * pixelStep).rgb +
        texture(source, uv + vec2(-r2,  0.0) * pixelStep).rgb +
        texture(source, uv + vec2( 0.0,  r2) * pixelStep).rgb +
        texture(source, uv + vec2( 0.0, -r2) * pixelStep).rgb
    ) * 0.06;
    baseColor += (
        texture(source, uv + vec2( r2 * 0.707,  r2 * 0.707) * pixelStep).rgb +
        texture(source, uv + vec2(-r2 * 0.707,  r2 * 0.707) * pixelStep).rgb +
        texture(source, uv + vec2( r2 * 0.707, -r2 * 0.707) * pixelStep).rgb +
        texture(source, uv + vec2(-r2 * 0.707, -r2 * 0.707) * pixelStep).rgb
    ) * 0.04;
    
    // Apply Kyant 1.5x Vibrancy (Authentic SimpMusic tone)
    vec3 vibrantBase = applyVibrancy(baseColor);
    
    // -------------------------------------------------------------------------
    // 3. Kyant Corner Chromatic Aberration
    // dispersionIntensity = chromaticAberration * ((centeredCoord.x * centeredCoord.y) / (halfSize.x * halfSize.y))
    // -------------------------------------------------------------------------
    float chroma = u_aberration > 0.0 ? u_aberration : 0.04;
    float cornerIntensity = chroma * (abs(centeredCoord.x * centeredCoord.y) / max(1.0, halfSize.x * halfSize.y));
    float dispAmt = cornerIntensity * 50.0;
    
    vec3 glassColor = vibrantBase;
    if (dispAmt > 0.01 && distInside < refrHeight) {
        vec2 dispVec = grad * dispAmt * pixelStep;
        vec3 cRed  = applyVibrancy(texture(source, uv + dispVec).rgb);
        vec3 cBlue = applyVibrancy(texture(source, uv - dispVec).rgb);
        glassColor.r = mix(vibrantBase.r, cRed.r, 0.40);
        glassColor.b = mix(vibrantBase.b, cBlue.b, 0.40);
    }
    
    // -------------------------------------------------------------------------
    // 4. Kyant Directional Highlight (DefaultHighlightShaderString)
    // 45 degree angle light sweep, stroke width ~ 1dp (Highlight(width = 1.dp))
    // -------------------------------------------------------------------------
    vec2 lightNormal = vec2(0.70710678, 0.70710678); // cos(45°), sin(45°)
    float dHighlight = dot(grad, lightNormal);
    float highlightIntensity = pow(abs(dHighlight), 1.0);
    
    // Rim stroke profile (1dp ~ 1.5px)
    float rimProfile = smoothstep(2.5, 0.4, distInside);
    vec3 highlight = vec3(1.0) * highlightIntensity * rimProfile * 0.42;
    
    // -------------------------------------------------------------------------
    // 5. SimpMusic Scrim & Tint
    // Scrim: darken to keep contrast ("đục đen", never white wash out)
    // -------------------------------------------------------------------------
    float scrimAlpha = 0.28;
    vec3 withScrim = mix(glassColor, vec3(0.02, 0.02, 0.03), scrimAlpha);
    
    // Add directional highlight with Plus blend mode
    vec3 withHighlight = withScrim + highlight;
    
    // Accent tint: subtle absorption of song's accent color
    vec3 finalColor = mix(withHighlight, u_tint.rgb, u_tint.a > 0.0 ? (u_tint.a * 0.28) : 0.12);
    
    // -------------------------------------------------------------------------
    // 6. Output Premultiplied Alpha
    // -------------------------------------------------------------------------
    float baseAlpha = clamp(u_tint.a > 0.0 ? u_tint.a : 0.78, 0.65, 0.88);
    float outAlpha = baseAlpha * mask * qt_Opacity;
    
    fragColor = vec4(clamp(finalColor, 0.0, 1.0) * outAlpha, outAlpha);
}

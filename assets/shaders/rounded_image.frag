#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 u_resolution;    // Item size in pixels (width, height)
    vec2 u_sourceSize;    // Source image intrinsic size in pixels (width, height)
    float u_radius;       // Corner radius in pixels
    float u_scale;        // Zoom scale factor (>= 1.0)
    int u_fillMode;       // 0 = Stretch, 2 = PreserveAspectCrop
};

layout(binding = 1) uniform sampler2D source;

// Inigo Quilez 2D Rounded Box SDF
float sdRoundedBox(vec2 p, vec2 b, float r) {
    vec2 q = abs(p) - b + vec2(r);
    return min(max(q.x, q.y), 0.0) + length(max(q, vec2(0.0))) - r;
}

void main() {
    vec2 pixelPos = qt_TexCoord0 * u_resolution;
    vec2 center = u_resolution * 0.5;
    vec2 halfSize = u_resolution * 0.5;
    vec2 centeredCoord = pixelPos - center;
    
    // Clamp radius so it doesn't exceed half-dimensions
    float maxR = min(halfSize.x, halfSize.y);
    float r = clamp(u_radius, 0.0, maxR);
    
    // Distance from current pixel to rounded box border
    float d = sdRoundedBox(centeredCoord, halfSize, r);
    
    // Subpixel anti-aliased edge mask
    float edgeWidth = clamp(fwidth(d), 0.75, 1.5);
    float mask = 1.0 - smoothstep(-edgeWidth, edgeWidth, d);
    if (mask <= 0.0) {
        fragColor = vec4(0.0);
        return;
    }
    
    vec2 uv = qt_TexCoord0;
    
    // 1. Aspect Crop calculation (PreserveAspectCrop)
    if (u_fillMode == 2 && u_sourceSize.x > 0.0 && u_sourceSize.y > 0.0 && u_resolution.x > 0.0 && u_resolution.y > 0.0) {
        float itemAspect = u_resolution.x / u_resolution.y;
        float imgAspect = u_sourceSize.x / u_sourceSize.y;
        if (itemAspect > imgAspect) {
            float scaleY = imgAspect / itemAspect;
            uv.y = 0.5 + (qt_TexCoord0.y - 0.5) * scaleY;
        } else {
            float scaleX = itemAspect / imgAspect;
            uv.x = 0.5 + (qt_TexCoord0.x - 0.5) * scaleX;
        }
    }
    
    // 2. Center Zoom Scale (e.g. 1.34x for 4:3 letterboxed thumbnails)
    float s = max(0.1, u_scale);
    if (abs(s - 1.0) > 0.001) {
        uv = 0.5 + (uv - 0.5) / s;
    }
    
    // Clamp uv to avoid texture edge bleeding
    uv = clamp(uv, vec2(0.0005), vec2(0.9995));
    
    vec4 tex = texture(source, uv);
    fragColor = tex * (mask * qt_Opacity);
}

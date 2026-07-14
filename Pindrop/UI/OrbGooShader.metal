//
//  OrbGooShader.metal
//  Pindrop
//
//  Created on 2026-07-06.
//
//  Analytic "goo" shader for the Orb floating indicator. The orb and its pop-out
//  pill are modelled as two signed-distance lobes (circle + rounded rect) whose
//  Gaussian-blurred-silhouette alphas are computed in closed form and composited,
//  then thresholded into a merged liquid body with a rim highlight — the classic
//  metaball smooth-min look. Evaluating the field analytically means an animation
//  frame only updates a handful of uniforms and draws one quad; the previous
//  pipeline (rasterize silhouettes → offscreen blur → threshold layerEffect)
//  re-rasterized the whole chain on every frame of the pop-out springs.
//

#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

[[ stitchable ]] half4 orbGooField(float2 position, half4 color,
                                   float2 orbCenter, float orbRadius,
                                   float2 pillCenter, float2 pillHalfSize,
                                   float pillCornerRadius, float softness,
                                   half4 fill, half4 rim) {
    // Signed distances to the two lobes (positive outside the surface).
    float dOrb = length(position - orbCenter) - orbRadius;

    float r = min(pillCornerRadius, min(pillHalfSize.x, pillHalfSize.y));
    float2 q = abs(position - pillCenter) - pillHalfSize + r;
    float dPill = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;

    // A Gaussian-blurred binary silhouette's alpha at signed distance d is
    // Φ(-d/σ); the logistic 1/(1+e^{1.702·d/σ}) matches that to within ~1%,
    // so the field below reproduces the raster-era blur+threshold rendering.
    half aOrb = half(1.0 / (1.0 + exp(1.702 * dOrb / softness)));
    half aPill = half(1.0 / (1.0 + exp(1.702 * dPill / softness)));

    // The half-plane formula above over-reports thin slabs: blurring a slab of
    // half-thickness h caps its peak alpha at 2Φ(h/σ)−1, which is what kept the
    // collapsing pill invisible until ~σ thick in the raster pipeline. Without
    // this the 1pt-thin pill flashes as a near-opaque bar on vertical exits.
    float h = min(pillHalfSize.x, pillHalfSize.y);
    half thinness = half(max(0.0, 2.0 / (1.0 + exp(-1.702 * h / softness)) - 1.0));
    aPill *= thinness;
    // Source-over union of the two lobes; nearby fields sum past the threshold,
    // which is what bridges the surfaces into one liquid neck mid-transition.
    half alpha = aOrb + aPill - aOrb * aPill;

    // Merged liquid body: hard-ish threshold over the analytic alpha field.
    half body = smoothstep(0.34h, 0.52h, alpha);

    // Rim: a narrow band around the threshold edge, brightest just inside it.
    half edge = smoothstep(0.34h, 0.46h, alpha) * (1.0h - smoothstep(0.52h, 0.80h, alpha));

    half4 out = fill * body;
    out.rgb += rim.rgb * (edge * rim.a);
    out.a = min(out.a + edge * rim.a * 0.55h, 1.0h);
    return out;
}

/// Shader-swappable glass-study fill for the orb interior. This is deliberately
/// separate from `orbGooField`: the metaball field above remains the sole owner
/// of assembly geometry and separation physics, while this pass can evolve as a
/// purely visual fill layer.
[[ stitchable ]] half4 orbGlassFill(float2 position, half4 color,
                                    float2 size, float time,
                                    half4 primaryWave, half4 secondaryWave,
                                    float waveIntensity, float isMuted,
                                    float bandLow, float bandMid, float bandHigh) {
    float2 uv = position / max(size, float2(1.0));
    float2 p = uv - 0.5;
    float radius = length(p);

    // Near-black radial glass body: approximately oklab L34 → L23 → L15.
    half centerLight = half(clamp(1.0 - radius * 1.75, 0.0, 1.0));
    half3 glass = mix(half3(0.027h, 0.025h, 0.022h),
                      half3(0.095h, 0.088h, 0.078h), centerLight);

    // Warm and accent blooms give the glass depth without tinting the body.
    float warmBloom = exp(-dot(p - float2(-0.17, 0.18), p - float2(-0.17, 0.18)) * 18.0);
    float accentBloom = exp(-dot(p - float2(0.18, -0.12), p - float2(0.18, -0.12)) * 16.0);
    glass += half3(0.20h, 0.14h, 0.075h) * half(warmBloom * 0.16);
    glass += primaryWave.rgb * half(accentBloom * 0.18);

    // Map horizontal position onto the visible hemisphere. Sampling each sine in
    // longitude, rather than flat screen-space x, bends its motion around the
    // glass while depth-based tapering lets the traces recede toward the sides.
    float sphereX = clamp(p.x / 0.48, -1.0, 1.0);
    float sphereDepth = sqrt(max(0.0, 1.0 - sphereX * sphereX));
    float longitude = asin(sphereX);
    float edgeFade = smoothstep(0.0, 0.30, sphereDepth);
    float depthShade = (0.20 + sphereDepth * 0.80) * edgeFade;

    // Three independently driven frequency bands share nearly the same baseline.
    // Their phase and spatial frequencies distinguish them; the tiny offsets keep
    // individual cores legible without turning the display into three stacked rows.
    float low = clamp(bandLow, 0.0, 1.0);
    float mid = clamp(bandMid, 0.0, 1.0);
    float high = clamp(bandHigh, 0.0, 1.0);
    float activity = max(low, max(mid, high));
    float wrapArc = sphereDepth * (0.009 + activity * 0.021);
    float amplitudeDepth = (0.38 + sphereDepth * 0.62) * edgeFade;
    float sharedBaseline = 0.505 + wrapArc;
    float lowY = sharedBaseline - 0.004
        + sin(longitude * 2.1 + time * 0.95 + 0.15) * 0.085 * low * amplitudeDepth;
    float midY = sharedBaseline
        + sin(longitude * 3.5 - time * 1.30 + 1.10) * 0.070 * mid * amplitudeDepth;
    float highY = sharedBaseline + 0.004
        + sin(longitude * 5.2 + time * 1.65 + 2.20) * 0.055 * high * amplitudeDepth;

    // The line cores narrow and dim toward the sides, like illuminated filaments
    // receding inside the sphere. A soft lower shadow seats them below the glass.
    float pixelHeight = max(size.y, 1.0);
    float depthWidth = 0.55 + sphereDepth * 0.45;
    float coreWidth = 0.72 / pixelHeight * depthWidth;
    float glowWidth = 2.15 / pixelHeight * depthWidth;
    float shadowOffset = 1.4 / pixelHeight;
    float lowDistance = uv.y - lowY;
    float midDistance = uv.y - midY;
    float highDistance = uv.y - highY;
    float lowCore = exp(-pow(lowDistance / coreWidth, 2.0));
    float midCore = exp(-pow(midDistance / coreWidth, 2.0));
    float highCore = exp(-pow(highDistance / coreWidth, 2.0));
    float lowGlow = exp(-pow(lowDistance / glowWidth, 2.0));
    float midGlow = exp(-pow(midDistance / glowWidth, 2.0));
    float highGlow = exp(-pow(highDistance / glowWidth, 2.0));
    float lowShadow = exp(-pow((lowDistance - shadowOffset) / (glowWidth * 1.2), 2.0));
    float midShadow = exp(-pow((midDistance - shadowOffset) / (glowWidth * 1.2), 2.0));
    float highShadow = exp(-pow((highDistance - shadowOffset) / (glowWidth * 1.2), 2.0));
    float shadowField = max(lowShadow, max(midShadow, highShadow));
    glass *= half(1.0 - shadowField * depthShade * 0.12);

    half3 lowColor = primaryWave.rgb * 0.72h;
    half3 midColor = mix(primaryWave.rgb, secondaryWave.rgb, 0.28h);
    half3 highColor = secondaryWave.rgb;
    float intensity = waveIntensity * (1.0 - isMuted) * depthShade;
    glass += lowColor * half((lowCore * 0.68 + lowGlow * 0.14) * intensity);
    glass += midColor * half((midCore * 0.82 + midGlow * 0.17) * intensity);
    glass += highColor * half((highCore * 0.70 + highGlow * 0.15) * intensity);

    // Two restrained white speculars preserve the orb's glass depth.
    float specA = exp(-dot(p - float2(-0.19, -0.23), p - float2(-0.19, -0.23)) * 90.0);
    float specB = exp(-dot(p - float2(0.22, 0.24), p - float2(0.22, 0.24)) * 120.0);
    glass += half3(1.0h) * half(specA * 0.55 + specB * 0.35);

    return half4(clamp(glass, half3(0.0h), half3(1.0h)), color.a);
}

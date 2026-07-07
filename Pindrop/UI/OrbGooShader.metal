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

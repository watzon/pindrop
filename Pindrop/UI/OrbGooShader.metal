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
                                    half4 primaryRibbon, half4 secondaryRibbon,
                                    float ribbonIntensity, float isRecording,
                                    float isMuted, float bandLow,
                                    float bandMid, float bandHigh) {
    float2 uv = position / max(size, float2(1.0));
    float2 p = uv - 0.5;
    float radius = length(p);

    // Near-black radial glass body: approximately oklab L34 → L23 → L15.
    half centerLight = half(clamp(1.0 - radius * 1.75, 0.0, 1.0));
    half3 glass = mix(half3(0.027h, 0.025h, 0.022h),
                      half3(0.095h, 0.088h, 0.078h), centerLight);

    // A warm low bloom and cool accent bloom give the glass depth without
    // making the body itself theme-colored.
    float warmBloom = exp(-dot(p - float2(-0.17, 0.18), p - float2(-0.17, 0.18)) * 18.0);
    float accentBloom = exp(-dot(p - float2(0.18, -0.12), p - float2(0.18, -0.12)) * 16.0);
    glass += half3(0.20h, 0.14h, 0.075h) * half(warmBloom * 0.16);
    glass += primaryRibbon.rgb * half(accentBloom * 0.18);

    // Soft-knee live inputs keep clipped audio from producing abrupt visual spikes.
    float low = smoothstep(0.0, 1.0, clamp(bandLow, 0.0, 1.0));
    float mid = smoothstep(0.0, 1.0, clamp(bandMid, 0.0, 1.0));
    float high = smoothstep(0.0, 1.0, clamp(bandHigh, 0.0, 1.0));
    float combined = (low + mid + high) / 3.0;

    // Audio drives GEOMETRY, not glow: the ribbon's displacement is the waveform.
    // Three spatial octaves — broad low-band sway, speech-band ripple, fine
    // high-band flutter — summed into one displacement field the threads trace.
    // Every audio term is additive so zero bands preserve the approved idle image.
    float lowWave  = low  * sin(uv.x * 4.2  + time * 1.9)        * 0.085;
    float midWave  = mid  * sin(uv.x * 10.5 - time * 2.8 + 0.9)  * 0.052;
    float highWave = high * sin(uv.x * 24.0 + time * 4.6 + 2.0)  * 0.024;
    float displace = clamp(lowWave + midWave + highWave, -0.13, 0.13);

    // Layered aurora: broad back band, dominant accent thread, warm/front band.
    float waveA = 0.53 + sin(uv.x * 7.2 + time) * 0.105
                       + sin(uv.x * 14.0 - time * 0.55) * 0.025
                       + displace * 0.45;
    float waveB = 0.59 + sin(uv.x * 6.2 + time * 0.72 + 1.3) * 0.085
                       + displace;
    float waveC = 0.64 + sin(uv.x * 8.5 - time * 0.48 + 2.1) * 0.055
                       + displace * 0.70;
    float back = exp(-pow((uv.y - waveA) / 0.14, 2.0));
    float mainThread = exp(-pow((uv.y - waveB) / (0.048 * (1.0 + mid * 0.12)), 2.0));
    float frontThread = exp(-pow((uv.y - waveC) / 0.032, 2.0));
    float intensity = ribbonIntensity * (1.0 + combined * 0.06) * (1.0 - isMuted);
    glass += primaryRibbon.rgb * half((back * 0.23 + mainThread * (0.82 + mid * 0.10)) * intensity);
    glass += secondaryRibbon.rgb * half(frontThread * 0.68 * intensity);

    // Wax red is a product-state signal, not a theme color. It only exists
    // while the microphone is hot. Slightly stronger displacement + a phase lead
    // so it visibly chases the accent thread instead of moving in lockstep.
    float redWave = 0.57 + sin(uv.x * 9.0 + time * 0.9 + 0.7) * 0.052
                         + displace * 0.9
                         + low * sin(uv.x * 5.1 + time * 2.2 + 1.6) * 0.028;
    float redThread = exp(-pow((uv.y - redWave) / (0.022 * (1.0 + mid * 0.12)), 2.0));
    glass += half3(0.824h, 0.357h, 0.298h) * half(redThread * (0.80 + mid * 0.10) * isRecording);

    // Two restrained white speculars from the artboard study.
    float specA = exp(-dot(p - float2(-0.19, -0.23), p - float2(-0.19, -0.23)) * 90.0);
    float specB = exp(-dot(p - float2(0.22, 0.24), p - float2(0.22, 0.24)) * 120.0);
    glass += half3(1.0h) * half(specA * 0.55 + specB * 0.35);
    float sparkle = pow(max(0.0, sin(uv.x * 43.0 + uv.y * 37.0 - time * 4.2)), 18.0);
    glass += half3(1.0h) * half(sparkle * high * 0.10);

    return half4(clamp(glass, half3(0.0h), half3(1.0h)), color.a);
}

//
//  OrbGooShader.metal
//  Pindrop
//
//  Created on 2026-07-06.
//
//  Alpha-threshold "goo" shader for the Orb floating indicator. The orb and its
//  pop-out pill are drawn as solid silhouettes, blurred, and run through this
//  layer effect: thresholding the blurred alpha field produces a single merged
//  liquid surface (the classic SDF/metaball smooth-min look), and the band just
//  outside the threshold is re-lit as a rim highlight so the surface reads as
//  glass instead of flat ink.
//

#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

[[ stitchable ]] half4 orbGoo(float2 position, SwiftUI::Layer layer,
                              half4 fill, half4 rim) {
    half alpha = layer.sample(position).a;

    // Merged liquid body: hard-ish threshold over the blurred alpha field.
    half body = smoothstep(0.34h, 0.52h, alpha);

    // Rim: a narrow band around the threshold edge, brightest just inside it.
    half edge = smoothstep(0.34h, 0.46h, alpha) * (1.0h - smoothstep(0.52h, 0.80h, alpha));

    half4 color = fill * body;
    color.rgb += rim.rgb * (edge * rim.a);
    color.a = min(color.a + edge * rim.a * 0.55h, 1.0h);
    return color;
}

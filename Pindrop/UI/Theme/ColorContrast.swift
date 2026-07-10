//
//  ColorContrast.swift
//  Pindrop
//
//  Created on 2026-07-09.
//

import AppKit
import Foundation

/// Pure WCAG contrast utilities for palette resolution.
enum ColorContrast {
    /// WCAG AA normal text minimum contrast ratio.
    static let minimumNormalTextRatio: Double = 4.5
    /// WCAG AA large text (≥18pt regular / ≥14pt bold; we use ≥17pt as the design threshold).
    static let minimumLargeTextRatio: Double = 3.0
    /// Point size at which large-text contrast rules apply for design roles.
    static let largeTextPointSize: CGFloat = 17

    struct RGB: Equatable, Hashable {
        var r: Double
        var g: Double
        var b: Double

        init(r: Double, g: Double, b: Double) {
            self.r = min(max(r, 0), 1)
            self.g = min(max(g, 0), 1)
            self.b = min(max(b, 0), 1)
        }

        init(nsColor: NSColor) {
            let rgb = nsColor.usingColorSpace(.deviceRGB) ?? nsColor
            self.init(
                r: Double(rgb.redComponent),
                g: Double(rgb.greenComponent),
                b: Double(rgb.blueComponent)
            )
        }

        var nsColor: NSColor {
            NSColor(red: r, green: g, blue: b, alpha: 1)
        }

        var hex: String {
            let ri = Int((r * 255).rounded())
            let gi = Int((g * 255).rounded())
            let bi = Int((b * 255).rounded())
            return String(format: "#%02X%02X%02X", ri, gi, bi)
        }
    }

    struct ClampResult: Equatable {
        let color: RGB
        let didClamp: Bool
        let ratioBefore: Double
        let ratioAfter: Double
    }

    /// Relative luminance per WCAG 2.x (sRGB).
    static func relativeLuminance(of color: RGB) -> Double {
        func channel(_ c: Double) -> Double {
            c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        let r = channel(color.r)
        let g = channel(color.g)
        let b = channel(color.b)
        return 0.2126 * r + 0.7152 * g + 0.0722 * b
    }

    /// Contrast ratio of two colors, ≥ 1.
    static func contrastRatio(_ a: RGB, _ b: RGB) -> Double {
        let l1 = relativeLuminance(of: a)
        let l2 = relativeLuminance(of: b)
        let lighter = max(l1, l2)
        let darker = min(l1, l2)
        return (lighter + 0.05) / (darker + 0.05)
    }

    static func minimumRatio(forPointSize pointSize: CGFloat) -> Double {
        pointSize >= largeTextPointSize ? minimumLargeTextRatio : minimumNormalTextRatio
    }

    /// Clamp `text` toward black or white until contrast against every background is ≥ `minimumRatio`.
    /// Chooses the polarity (darken vs lighten) that needs the least movement from the original.
    static func clampTextColor(
        _ text: RGB,
        against backgrounds: [RGB],
        minimumRatio: Double = minimumNormalTextRatio
    ) -> ClampResult {
        guard !backgrounds.isEmpty else {
            return ClampResult(color: text, didClamp: false, ratioBefore: 1, ratioAfter: 1)
        }

        let ratioBefore = backgrounds.map { contrastRatio(text, $0) }.min() ?? 1
        if ratioBefore + 0.001 >= minimumRatio {
            return ClampResult(color: text, didClamp: false, ratioBefore: ratioBefore, ratioAfter: ratioBefore)
        }

        let black = RGB(r: 0, g: 0, b: 0)
        let white = RGB(r: 1, g: 1, b: 1)

        let towardBlack = binarySearchClamp(text: text, target: black, backgrounds: backgrounds, minimumRatio: minimumRatio)
        let towardWhite = binarySearchClamp(text: text, target: white, backgrounds: backgrounds, minimumRatio: minimumRatio)

        let candidates = [towardBlack, towardWhite].compactMap { $0 }
        guard let best = candidates.min(by: { distance($0, text) < distance($1, text) }) else {
            // Fall back to pure black/white with better contrast.
            let blackMin = backgrounds.map { contrastRatio(black, $0) }.min() ?? 0
            let whiteMin = backgrounds.map { contrastRatio(white, $0) }.min() ?? 0
            let fallback = blackMin >= whiteMin ? black : white
            let ratioAfter = backgrounds.map { contrastRatio(fallback, $0) }.min() ?? 1
            return ClampResult(color: fallback, didClamp: true, ratioBefore: ratioBefore, ratioAfter: ratioAfter)
        }

        let ratioAfter = backgrounds.map { contrastRatio(best, $0) }.min() ?? 1
        return ClampResult(color: best, didClamp: true, ratioBefore: ratioBefore, ratioAfter: ratioAfter)
    }

    /// Clamp against the lowest-contrast background among the set.
    static func clampTextColor(
        _ text: NSColor,
        against backgrounds: [NSColor],
        minimumRatio: Double = minimumNormalTextRatio
    ) -> (color: NSColor, didClamp: Bool) {
        let result = clampTextColor(
            RGB(nsColor: text),
            against: backgrounds.map(RGB.init(nsColor:)),
            minimumRatio: minimumRatio
        )
        return (result.color.nsColor, result.didClamp)
    }

    // MARK: - Private

    private static func distance(_ a: RGB, _ b: RGB) -> Double {
        let dr = a.r - b.r
        let dg = a.g - b.g
        let db = a.b - b.b
        return dr * dr + dg * dg + db * db
    }

    private static func lerp(_ a: RGB, _ b: RGB, t: Double) -> RGB {
        RGB(
            r: a.r + (b.r - a.r) * t,
            g: a.g + (b.g - a.g) * t,
            b: a.b + (b.b - a.b) * t
        )
    }

    private static func binarySearchClamp(
        text: RGB,
        target: RGB,
        backgrounds: [RGB],
        minimumRatio: Double
    ) -> RGB? {
        let targetMin = backgrounds.map { contrastRatio(target, $0) }.min() ?? 0
        guard targetMin + 0.001 >= minimumRatio else { return nil }

        var low = 0.0
        var high = 1.0
        var best = target
        for _ in 0..<24 {
            let mid = (low + high) / 2
            let candidate = lerp(text, target, t: mid)
            let minRatio = backgrounds.map { contrastRatio(candidate, $0) }.min() ?? 0
            if minRatio + 0.001 >= minimumRatio {
                best = candidate
                high = mid
            } else {
                low = mid
            }
        }
        return best
    }
}

//
//  FontLoader.swift
//  Pindrop
//
//  Created on 2026-07-09.
//

import AppKit
import SwiftUI

/// Bundled Scorched Earth typefaces with system-font fallbacks.
///
/// Faces are registered via `ATSApplicationFontsPath` (`Fonts/` in the app bundle).
/// If a PostScript name is missing at runtime, we fall back once (logged via `Log.ui`)
/// to New York (serif via `.fontDesign(.serif)`), SF Pro, or SF Mono.
enum FontLoader {
    enum Family {
        case newsreader
        case inter
        case jetbrainsMono
    }

    enum Weight {
        case regular
        case medium
        case semibold

        var fontWeight: Font.Weight {
            switch self {
            case .regular: return .regular
            case .medium: return .medium
            case .semibold: return .semibold
            }
        }

        var nsWeight: NSFont.Weight {
            switch self {
            case .regular: return .regular
            case .medium: return .medium
            case .semibold: return .semibold
            }
        }
    }

    private static let lock = NSLock()
    private static var didBootstrap = false
    private static var missingFacesLogged = Set<String>()
    private static var availabilityCache: [String: Bool] = [:]

    /// PostScript names for bundled static faces.
    static func postScriptName(family: Family, weight: Weight, italic: Bool = false) -> String {
        switch family {
        case .newsreader:
            switch (weight, italic) {
            case (.regular, false): return "Newsreader-Regular"
            case (.medium, false): return "Newsreader-Medium"
            case (.semibold, false): return "Newsreader-SemiBold"
            case (.regular, true): return "Newsreader-Italic"
            case (.medium, true): return "Newsreader-MediumItalic"
            case (.semibold, true): return "Newsreader-SemiBoldItalic"
            }
        case .inter:
            // Inter statics ship each weight as its own family/PS name.
            switch weight {
            case .regular: return "Inter-Regular"
            case .medium: return "Inter-Medium"
            case .semibold: return "Inter-SemiBold"
            }
        case .jetbrainsMono:
            switch weight {
            case .regular: return "JetBrainsMono-Regular"
            case .medium, .semibold: return "JetBrainsMono-Medium"
            }
        }
    }

    /// Call once at launch (and from typography access) to warm availability checks.
    static func bootstrap() {
        lock.lock()
        defer { lock.unlock() }
        guard !didBootstrap else { return }
        didBootstrap = true

        let faces: [(Family, Weight, Bool)] = [
            (.newsreader, .regular, false),
            (.newsreader, .medium, false),
            (.newsreader, .semibold, false),
            (.newsreader, .regular, true),
            (.newsreader, .medium, true),
            (.newsreader, .semibold, true),
            (.inter, .regular, false),
            (.inter, .medium, false),
            (.inter, .semibold, false),
            (.jetbrainsMono, .regular, false),
            (.jetbrainsMono, .medium, false),
        ]

        for (family, weight, italic) in faces {
            let name = postScriptName(family: family, weight: weight, italic: italic)
            let available = NSFont(name: name, size: 12) != nil
            availabilityCache[name] = available
            if !available {
                logMissingFaceOnce(name)
            }
        }
    }

    static func isAvailable(family: Family, weight: Weight, italic: Bool = false) -> Bool {
        bootstrap()
        let name = postScriptName(family: family, weight: weight, italic: italic)
        lock.lock()
        defer { lock.unlock() }
        if let cached = availabilityCache[name] {
            return cached
        }
        let available = NSFont(name: name, size: 12) != nil
        availabilityCache[name] = available
        if !available {
            logMissingFaceOnce(name)
        }
        return available
    }

    static func font(
        family: Family,
        size: CGFloat,
        weight: Weight = .regular,
        italic: Bool = false
    ) -> Font {
        if isAvailable(family: family, weight: weight, italic: italic),
           let nsFont = NSFont(name: postScriptName(family: family, weight: weight, italic: italic), size: size) {
            return Font(nsFont)
        }
        return fallbackFont(family: family, size: size, weight: weight, italic: italic)
    }

    static func nsFont(
        family: Family,
        size: CGFloat,
        weight: Weight = .regular,
        italic: Bool = false
    ) -> NSFont {
        if isAvailable(family: family, weight: weight, italic: italic),
           let nsFont = NSFont(name: postScriptName(family: family, weight: weight, italic: italic), size: size) {
            return nsFont
        }
        return fallbackNSFont(family: family, size: size, weight: weight, italic: italic)
    }

    // MARK: - Fallbacks

    private static func fallbackFont(
        family: Family,
        size: CGFloat,
        weight: Weight,
        italic: Bool
    ) -> Font {
        switch family {
        case .newsreader:
            // New York via serif design.
            let base = Font.system(size: size, weight: weight.fontWeight, design: .serif)
            return italic ? base.italic() : base
        case .inter:
            let base = Font.system(size: size, weight: weight.fontWeight, design: .default)
            return italic ? base.italic() : base
        case .jetbrainsMono:
            return Font.system(size: size, weight: weight.fontWeight, design: .monospaced)
        }
    }

    private static func fallbackNSFont(
        family: Family,
        size: CGFloat,
        weight: Weight,
        italic: Bool
    ) -> NSFont {
        let base: NSFont
        switch family {
        case .newsreader:
            base = NSFont.systemFont(ofSize: size, weight: weight.nsWeight)
            // Prefer serif if available (New York).
            if let descriptor = base.fontDescriptor.withDesign(.serif) {
                let serif = NSFont(descriptor: descriptor, size: size) ?? base
                return italic ? italicized(serif, size: size) : serif
            }
            return italic ? italicized(base, size: size) : base
        case .inter:
            base = NSFont.systemFont(ofSize: size, weight: weight.nsWeight)
            return italic ? italicized(base, size: size) : base
        case .jetbrainsMono:
            return NSFont.monospacedSystemFont(ofSize: size, weight: weight.nsWeight)
        }
    }

    private static func italicized(_ font: NSFont, size: CGFloat) -> NSFont {
        let traits = font.fontDescriptor.symbolicTraits.union(.italic)
        let descriptor = font.fontDescriptor.withSymbolicTraits(traits)
        return NSFont(descriptor: descriptor, size: size) ?? font
    }

    private static func logMissingFaceOnce(_ postScriptName: String) {
        // Caller may already hold `lock`; only mutate logged set under lock from bootstrap/isAvailable.
        if missingFacesLogged.contains(postScriptName) { return }
        missingFacesLogged.insert(postScriptName)
        Log.ui.warning("Bundled font face unavailable; using system fallback: \(postScriptName)")
    }
}

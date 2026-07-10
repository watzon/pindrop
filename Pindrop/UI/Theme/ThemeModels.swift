//
//  ThemeModels.swift
//  Pindrop
//
//  Created on 2026-03-20.
//

import AppKit
import Foundation

enum PindropThemeStorageKeys {
    static let themeMode = "themeMode"
    static let lightThemePresetID = "lightThemePresetID"
    static let darkThemePresetID = "darkThemePresetID"
}

enum PindropThemeVariant: String, CaseIterable, Identifiable {
    case light
    case dark

    var id: String { rawValue }
}

enum PindropThemeMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        title(locale: .autoupdatingCurrent)
    }

    func title(locale: Locale) -> String {
        switch self {
        case .system:
            return localized("System", locale: locale)
        case .light:
            return localized("Light", locale: locale)
        case .dark:
            return localized("Dark", locale: locale)
        }
    }

    var symbolName: String {
        switch self {
        case .system:
            return "desktopcomputer"
        case .light:
            return "sun.max"
        case .dark:
            return "moon.stars"
        }
    }

    var appKitAppearanceName: NSAppearance.Name? {
        switch self {
        case .system:
            return nil
        case .light:
            return .aqua
        case .dark:
            return .darkAqua
        }
    }
}

/// Scorched Earth profile: a preset remaps accent + the two grounds.
/// Ink / line / record come from the shared light/dark token tables and WCAG clamp.
struct PindropThemeProfile: Hashable {
    let groundHex: String
    let pageHex: String
    let accentHex: String
    /// Explicit accent-soft when the design specifies it; otherwise derived from accent over ground.
    let accentSoftHex: String?
    /// Explicit record when overridden; otherwise shared light/dark record tokens.
    let recordHex: String?
    let recordSoftHex: String?

    /// Compatibility alias for swatches / older call sites.
    var backgroundHex: String { groundHex }
    /// Ink is not preset-owned; swatches use a neutral placeholder. Prefer ground/page/accent.
    var foregroundHex: String { groundHex }

    init(
        groundHex: String,
        pageHex: String,
        accentHex: String,
        accentSoftHex: String? = nil,
        recordHex: String? = nil,
        recordSoftHex: String? = nil
    ) {
        self.groundHex = groundHex
        self.pageHex = pageHex
        self.accentHex = accentHex
        self.accentSoftHex = accentSoftHex
        self.recordHex = recordHex
        self.recordSoftHex = recordSoftHex
    }
}

struct PindropThemePreset: Hashable, Identifiable {
    let id: String
    let title: String
    let summary: String
    let badgeText: String
    let badgeBackgroundHex: String
    let badgeForegroundHex: String
    let lightTheme: PindropThemeProfile
    let darkTheme: PindropThemeProfile
    /// Hidden from the picker but still resolvable by ID (e.g. graphite legacy).
    let isLegacy: Bool

    init(
        id: String,
        title: String,
        summary: String,
        badgeText: String,
        badgeBackgroundHex: String,
        badgeForegroundHex: String,
        lightTheme: PindropThemeProfile,
        darkTheme: PindropThemeProfile,
        isLegacy: Bool = false
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.badgeText = badgeText
        self.badgeBackgroundHex = badgeBackgroundHex
        self.badgeForegroundHex = badgeForegroundHex
        self.lightTheme = lightTheme
        self.darkTheme = darkTheme
        self.isLegacy = isLegacy
    }

    func profile(for variant: PindropThemeVariant) -> PindropThemeProfile {
        switch variant {
        case .light:
            return lightTheme
        case .dark:
            return darkTheme
        }
    }
}

/// Shared Scorched Earth ink/line/record tables (Library artboard).
enum ScorchedEarthBaseTokens {
    // Light
    static let lightInk = "#201D18"
    static let lightInk2 = "#6E6759"
    static let lightInk3 = "#9B937F"
    static let lightLine = "#E3DFD3"
    static let lightRecord = "#B03A2E"
    static let lightRecordSoft = "#F6E7E3"
    static let lightAccentSoftLibrary = "#E7EFE7"

    // Dark ("Candlelit")
    static let darkInk = "#EFEBE2"
    static let darkInk2 = "#A59D8C"
    static let darkInk3 = "#6E675B"
    static let darkLine = "#37332B"
    static let darkRecord = "#D25B4C"
    static let darkAccentSoftLibrary = "#263A30"
}

enum PindropThemePresetCatalog {
    /// New installs default to Library.
    static let defaultPresetID = "library"

    /// Visible in the Appearance picker (excludes legacy/hidden presets).
    static let presets: [PindropThemePreset] = [
        library,
        pindrop,
        paper,
        harbor,
        evergreen,
        signal,
    ]

    /// Resolvable by ID for existing users but not shown in the picker.
    static let legacyPresets: [PindropThemePreset] = [
        graphite,
    ]

    static var allPresets: [PindropThemePreset] {
        presets + legacyPresets
    }

    // MARK: - Presets

    /// Library — design default (spec §1).
    static let library = PindropThemePreset(
        id: "library",
        title: "Library",
        summary: "Warm paper ground with a library-green accent.",
        badgeText: "Lb",
        badgeBackgroundHex: "#F6F4EE",
        badgeForegroundHex: "#1F6D53",
        lightTheme: PindropThemeProfile(
            groundHex: "#F6F4EE",
            pageHex: "#FCFBF7",
            accentHex: "#1F6D53",
            accentSoftHex: ScorchedEarthBaseTokens.lightAccentSoftLibrary,
            recordHex: ScorchedEarthBaseTokens.lightRecord,
            recordSoftHex: ScorchedEarthBaseTokens.lightRecordSoft
        ),
        darkTheme: PindropThemeProfile(
            groundHex: "#1B1916",
            pageHex: "#242119",
            accentHex: "#4CA582",
            accentSoftHex: ScorchedEarthBaseTokens.darkAccentSoftLibrary,
            recordHex: ScorchedEarthBaseTokens.darkRecord
        )
    )

    /// Pindrop — amber signal on near-black grounds.
    static let pindrop = PindropThemePreset(
        id: "pindrop",
        title: "Pindrop",
        summary: "Dark precision surfaces with an amber signal accent.",
        badgeText: "Pd",
        badgeBackgroundHex: "#141417",
        badgeForegroundHex: "#F2B54A",
        lightTheme: PindropThemeProfile(
            groundHex: "#F5F1E8",
            pageHex: "#FBF8F1",
            accentHex: "#C48A1E"
        ),
        darkTheme: PindropThemeProfile(
            groundHex: "#0A0A0F",
            pageHex: "#12121A",
            accentHex: "#F2B54A"
        )
    )

    /// Paper — cream grounds with ink-blue accent.
    static let paper = PindropThemePreset(
        id: "paper",
        title: "Paper",
        summary: "Quiet parchment tones with ink-forward contrast.",
        badgeText: "Aa",
        badgeBackgroundHex: "#FBF7EF",
        badgeForegroundHex: "#2E4E73",
        lightTheme: PindropThemeProfile(
            groundHex: "#F7F1E6",
            pageHex: "#FBF7EF",
            accentHex: "#2E4E73"
        ),
        darkTheme: PindropThemeProfile(
            groundHex: "#1A1816",
            pageHex: "#242119",
            accentHex: "#89A9D4"
        )
    )

    /// Harbor — fog-cool grounds with marine accent.
    static let harbor = PindropThemePreset(
        id: "harbor",
        title: "Harbor",
        summary: "Cool fog chrome with a crisp marine accent.",
        badgeText: "Hb",
        badgeBackgroundHex: "#EFF5F7",
        badgeForegroundHex: "#14708A",
        lightTheme: PindropThemeProfile(
            groundHex: "#EEF3F4",
            pageHex: "#F6F9FA",
            accentHex: "#14708A"
        ),
        darkTheme: PindropThemeProfile(
            groundHex: "#12181B",
            pageHex: "#1A2226",
            accentHex: "#5AB4D4"
        )
    )

    /// Evergreen — forest utility palette.
    static let evergreen = PindropThemePreset(
        id: "evergreen",
        title: "Evergreen",
        summary: "Forest-tinted utility palette with a calm studio feel.",
        badgeText: "Eg",
        badgeBackgroundHex: "#F3F5EE",
        badgeForegroundHex: "#4D7A4A",
        lightTheme: PindropThemeProfile(
            groundHex: "#F1F3EB",
            pageHex: "#F7F8F2",
            accentHex: "#4D7A4A"
        ),
        darkTheme: PindropThemeProfile(
            groundHex: "#121612",
            pageHex: "#1A1F19",
            accentHex: "#87B57D"
        )
    )

    /// Signal — red-orange pulse on dark warm grounds.
    static let signal = PindropThemePreset(
        id: "signal",
        title: "Signal",
        summary: "Dark broadcast palette with a vivid red-orange pulse.",
        badgeText: "Sg",
        badgeBackgroundHex: "#181211",
        badgeForegroundHex: "#F06D4F",
        lightTheme: PindropThemeProfile(
            groundHex: "#F7F0EC",
            pageHex: "#FCF7F4",
            accentHex: "#D95E45"
        ),
        darkTheme: PindropThemeProfile(
            groundHex: "#181211",
            pageHex: "#221A18",
            accentHex: "#F06D4F"
        )
    )

    /// Graphite — legacy monochrome; resolvable, hidden from picker.
    static let graphite = PindropThemePreset(
        id: "graphite",
        title: "Graphite",
        summary: "Neutral monochrome with a high-signal cobalt edge.",
        badgeText: "Gr",
        badgeBackgroundHex: "#F4F5F7",
        badgeForegroundHex: "#4B65D6",
        lightTheme: PindropThemeProfile(
            groundHex: "#F2F3F5",
            pageHex: "#F8F9FA",
            accentHex: "#4B65D6"
        ),
        darkTheme: PindropThemeProfile(
            groundHex: "#101114",
            pageHex: "#181A1E",
            accentHex: "#7D93FF"
        ),
        isLegacy: true
    )

    static func preset(withID id: String?) -> PindropThemePreset {
        guard let id, let preset = allPresets.first(where: { $0.id == id }) else {
            return allPresets.first(where: { $0.id == defaultPresetID }) ?? library
        }
        return preset
    }

    static func profile(for id: String?, variant: PindropThemeVariant) -> PindropThemeProfile {
        preset(withID: id).profile(for: variant)
    }
}

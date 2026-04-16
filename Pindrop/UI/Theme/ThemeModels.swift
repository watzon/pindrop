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

struct PindropThemeProfile: Hashable {
    let accentHex: String
    let backgroundHex: String
    let foregroundHex: String
    let contrast: Double
    let successHex: String
    let warningHex: String
    let dangerHex: String
    let processingHex: String
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

    func profile(for variant: PindropThemeVariant) -> PindropThemeProfile {
        switch variant {
        case .light:
            return lightTheme
        case .dark:
            return darkTheme
        }
    }
}

enum PindropThemePresetCatalog {
    static let defaultPresetID = "pindrop"

    static let presets: [PindropThemePreset] = [
        PindropThemePreset(
            id: "pindrop",
            title: "Pindrop",
            summary: "Dark precision surfaces with an amber signal accent.",
            badgeText: "Pd",
            badgeBackgroundHex: "#141417",
            badgeForegroundHex: "#F2B54A",
            lightTheme: PindropThemeProfile(
                accentHex: "#D4952E",
                backgroundHex: "#F7F5F0",
                foregroundHex: "#111111",
                contrast: 50,
                successHex: "#2E8B67",
                warningHex: "#A9692D",
                dangerHex: "#C95452",
                processingHex: "#3B82F6"
            ),
            darkTheme: PindropThemeProfile(
                accentHex: "#F2B54A",
                backgroundHex: "#0A0A0F",
                foregroundHex: "#F7F5F0",
                contrast: 66,
                successHex: "#53B48A",
                warningHex: "#F59E0B",
                dangerHex: "#EF4444",
                processingHex: "#3B82F6"
            )
        ),
        PindropThemePreset(
            id: "paper",
            title: "Paper",
            summary: "Quiet parchment tones with ink-forward contrast.",
            badgeText: "Aa",
            badgeBackgroundHex: "#FBF7EF",
            badgeForegroundHex: "#2E4E73",
            lightTheme: PindropThemeProfile(
                accentHex: "#2E4E73",
                backgroundHex: "#FBF7EF",
                foregroundHex: "#1A1712",
                contrast: 46,
                successHex: "#2D7D5A",
                warningHex: "#9C6B24",
                dangerHex: "#BD514A",
                processingHex: "#3A67C3"
            ),
            darkTheme: PindropThemeProfile(
                accentHex: "#89A9D4",
                backgroundHex: "#1A1816",
                foregroundHex: "#F4EEE5",
                contrast: 62,
                successHex: "#58B48B",
                warningHex: "#D09B53",
                dangerHex: "#E87C74",
                processingHex: "#7FA7FF"
            )
        ),
        PindropThemePreset(
            id: "harbor",
            title: "Harbor",
            summary: "Cool blue-gray chrome with a crisp marine accent.",
            badgeText: "Hb",
            badgeBackgroundHex: "#EFF5F7",
            badgeForegroundHex: "#14708A",
            lightTheme: PindropThemeProfile(
                accentHex: "#14708A",
                backgroundHex: "#EFF5F7",
                foregroundHex: "#14232B",
                contrast: 48,
                successHex: "#2F8663",
                warningHex: "#B0702D",
                dangerHex: "#C85652",
                processingHex: "#2F78D0"
            ),
            darkTheme: PindropThemeProfile(
                accentHex: "#5AB4D4",
                backgroundHex: "#0F171C",
                foregroundHex: "#E3F0F5",
                contrast: 67,
                successHex: "#5FB98C",
                warningHex: "#D59A4F",
                dangerHex: "#E3716D",
                processingHex: "#69A8FF"
            )
        ),
        PindropThemePreset(
            id: "evergreen",
            title: "Evergreen",
            summary: "Forest-tinted utility palette with a calm studio feel.",
            badgeText: "Eg",
            badgeBackgroundHex: "#F3F5EE",
            badgeForegroundHex: "#4D7A4A",
            lightTheme: PindropThemeProfile(
                accentHex: "#4D7A4A",
                backgroundHex: "#F3F5EE",
                foregroundHex: "#1C2019",
                contrast: 47,
                successHex: "#3A8B5B",
                warningHex: "#AA6D26",
                dangerHex: "#B84F49",
                processingHex: "#4A74C9"
            ),
            darkTheme: PindropThemeProfile(
                accentHex: "#87B57D",
                backgroundHex: "#101411",
                foregroundHex: "#E6EEE1",
                contrast: 65,
                successHex: "#64BC85",
                warningHex: "#D29648",
                dangerHex: "#DF6F68",
                processingHex: "#7EA7FF"
            )
        ),
        PindropThemePreset(
            id: "graphite",
            title: "Graphite",
            summary: "Neutral monochrome with a high-signal cobalt edge.",
            badgeText: "Gr",
            badgeBackgroundHex: "#F4F5F7",
            badgeForegroundHex: "#4B65D6",
            lightTheme: PindropThemeProfile(
                accentHex: "#4B65D6",
                backgroundHex: "#F4F5F7",
                foregroundHex: "#16181D",
                contrast: 49,
                successHex: "#2C8A67",
                warningHex: "#A66821",
                dangerHex: "#C34C50",
                processingHex: "#507BFF"
            ),
            darkTheme: PindropThemeProfile(
                accentHex: "#7D93FF",
                backgroundHex: "#101114",
                foregroundHex: "#ECEFF4",
                contrast: 70,
                successHex: "#5DBD93",
                warningHex: "#D69D55",
                dangerHex: "#E77A80",
                processingHex: "#87A7FF"
            )
        ),
        PindropThemePreset(
            id: "signal",
            title: "Signal",
            summary: "Dark broadcast palette with a vivid red-orange pulse.",
            badgeText: "Sg",
            badgeBackgroundHex: "#181211",
            badgeForegroundHex: "#F06D4F",
            lightTheme: PindropThemeProfile(
                accentHex: "#D95E45",
                backgroundHex: "#FBF4F1",
                foregroundHex: "#251816",
                contrast: 51,
                successHex: "#2C8863",
                warningHex: "#AF6A21",
                dangerHex: "#C94E4B",
                processingHex: "#466AD4"
            ),
            darkTheme: PindropThemeProfile(
                accentHex: "#F06D4F",
                backgroundHex: "#181211",
                foregroundHex: "#F5E7E2",
                contrast: 72,
                successHex: "#53B98A",
                warningHex: "#DD9745",
                dangerHex: "#F5847A",
                processingHex: "#7EA4FF"
            )
        ),
    ]

    static func preset(withID id: String?) -> PindropThemePreset {
        guard let id, let preset = presets.first(where: { $0.id == id }) else {
            return presets.first(where: { $0.id == defaultPresetID }) ?? presets[0]
        }

        return preset
    }

    static func profile(for id: String?, variant: PindropThemeVariant) -> PindropThemeProfile {
        preset(withID: id).profile(for: variant)
    }
}

//
//  ThemeModels.swift
//  Pindrop
//
//  Created on 2026-03-20.
//

import AppKit
import Foundation

import PindropSharedUITheme

enum PindropThemeStorageKeys {
    static let themeMode = "themeMode"
    static let lightThemePresetID = "lightThemePresetID"
    static let darkThemePresetID = "darkThemePresetID"
}

enum PindropThemeVariant: String, CaseIterable, Identifiable {
    case light
    case dark

    var id: String { rawValue }

    var coreValue: ThemeVariant {
        switch self {
        case .light: .light
        case .dark: .dark
        }
    }

    init(coreValue: ThemeVariant) {
        switch coreValue {
        case .light:
            self = .light
        default:
            self = .dark
        }
    }
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

    var coreValue: ThemeMode {
        switch self {
        case .system: .system
        case .light: .light
        case .dark: .dark
        }
    }

    init(coreValue: ThemeMode) {
        switch coreValue {
        case .system:
            self = .system
        case .light:
            self = .light
        default:
            self = .dark
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

    init(coreProfile: ThemeProfile) {
        accentHex = coreProfile.accentHex
        backgroundHex = coreProfile.backgroundHex
        foregroundHex = coreProfile.foregroundHex
        contrast = coreProfile.contrast
        successHex = coreProfile.successHex
        warningHex = coreProfile.warningHex
        dangerHex = coreProfile.dangerHex
        processingHex = coreProfile.processingHex
    }
}

struct PindropThemePreset: Hashable, Identifiable {
    let id: String
    let title: String
    let summary: String
    let badgeText: String
    let badgeBackgroundHex: String
    let badgeForegroundHex: String

    private let lightTheme: PindropThemeProfile
    private let darkTheme: PindropThemeProfile

    func profile(for variant: PindropThemeVariant) -> PindropThemeProfile {
        switch variant {
        case .light:
            lightTheme
        case .dark:
            darkTheme
        }
    }

    init(corePreset: ThemePreset) {
        id = corePreset.id
        title = corePreset.title
        summary = corePreset.summary
        badgeText = corePreset.badgeText
        badgeBackgroundHex = corePreset.badgeBackgroundHex
        badgeForegroundHex = corePreset.badgeForegroundHex
        lightTheme = PindropThemeProfile(coreProfile: corePreset.lightTheme)
        darkTheme = PindropThemeProfile(coreProfile: corePreset.darkTheme)
    }
}

enum PindropThemePresetCatalog {
    static var defaultPresetID: String {
        ThemeCatalog.shared.defaultPresetId
    }

    static var presets: [PindropThemePreset] {
        ThemeCatalog.shared.presets().map(PindropThemePreset.init(corePreset:))
    }

    static func preset(withID id: String?) -> PindropThemePreset {
        PindropThemePreset(corePreset: ThemeCatalog.shared.preset(id: id))
    }

    static func profile(for id: String?, variant: PindropThemeVariant) -> PindropThemeProfile {
        preset(withID: id).profile(for: variant)
    }
}

enum PindropThemeBridge {
    static let capabilities = ThemeCapabilities(
        supportsTranslucentSidebar: true,
        supportsWindowMaterial: true,
        supportsOverlayBlur: true,
        supportsNativeVibrancy: true,
        supportsUnifiedTitlebar: true
    )

    private struct CacheKey: Equatable {
        let mode: String
        let lightPresetID: String
        let darkPresetID: String
        let variant: PindropThemeVariant
    }

    private static var cachedKey: CacheKey?
    private static var cachedTheme: ResolvedTheme?

    static func resolveTheme(systemVariant: PindropThemeVariant) -> ResolvedTheme {
        let selection = ThemeSelection(
            mode: currentMode().coreValue,
            lightPresetId: currentLightPresetID(),
            darkPresetId: currentDarkPresetID()
        )
        let key = CacheKey(
            mode: currentMode().rawValue,
            lightPresetID: selection.lightPresetId,
            darkPresetID: selection.darkPresetId,
            variant: systemVariant
        )

        if let cachedTheme, cachedKey == key {
            return cachedTheme
        }

        let resolved = ThemeEngine.shared.resolveTheme(
            selection: selection,
            systemVariant: systemVariant.coreValue,
            capabilities: capabilities
        )
        cachedKey = key
        cachedTheme = resolved
        return resolved
    }

    static func invalidateCache() {
        cachedKey = nil
        cachedTheme = nil
    }

    static var spacingScale: SpacingScale {
        ThemeEngine.shared.resolveTheme(
            selection: ThemeSelection(
                mode: .system,
                lightPresetId: ThemeCatalog.shared.defaultPresetId,
                darkPresetId: ThemeCatalog.shared.defaultPresetId
            ),
            systemVariant: .light,
            capabilities: capabilities
        ).tokens.spacing
    }

    static var radiusScale: RadiusScale {
        ThemeEngine.shared.resolveTheme(
            selection: ThemeSelection(
                mode: .system,
                lightPresetId: ThemeCatalog.shared.defaultPresetId,
                darkPresetId: ThemeCatalog.shared.defaultPresetId
            ),
            systemVariant: .light,
            capabilities: capabilities
        ).tokens.radius
    }

    static var typographyScale: TypographyScale {
        ThemeEngine.shared.resolveTheme(
            selection: ThemeSelection(
                mode: .system,
                lightPresetId: ThemeCatalog.shared.defaultPresetId,
                darkPresetId: ThemeCatalog.shared.defaultPresetId
            ),
            systemVariant: .light,
            capabilities: capabilities
        ).tokens.typography
    }

    static var shadowScale: ShadowScale {
        ThemeEngine.shared.resolveTheme(
            selection: ThemeSelection(
                mode: .system,
                lightPresetId: ThemeCatalog.shared.defaultPresetId,
                darkPresetId: ThemeCatalog.shared.defaultPresetId
            ),
            systemVariant: .light,
            capabilities: capabilities
        ).tokens.shadowScale
    }

    private static func currentMode() -> PindropThemeMode {
        let rawValue = UserDefaults.standard.string(forKey: PindropThemeStorageKeys.themeMode) ?? ""
        return PindropThemeMode(rawValue: rawValue) ?? .system
    }

    private static func currentLightPresetID() -> String {
        UserDefaults.standard.string(forKey: PindropThemeStorageKeys.lightThemePresetID)
            ?? ThemeCatalog.shared.defaultPresetId
    }

    private static func currentDarkPresetID() -> String {
        UserDefaults.standard.string(forKey: PindropThemeStorageKeys.darkThemePresetID)
            ?? ThemeCatalog.shared.defaultPresetId
    }
}

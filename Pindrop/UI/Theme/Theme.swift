//
//  Theme.swift
//  Pindrop
//
//  Created on 2026-03-20.
//

import AppKit
import SwiftUI

@MainActor
final class PindropThemeController: ObservableObject {
    static let shared = PindropThemeController()

    @Published private(set) var revision = 0

    private init() {
        applyAppAppearance()
    }

    func refresh() {
        applyAppAppearance()
        revision &+= 1
    }

    func apply(to window: NSWindow?) {
        window?.appearance = currentMode.appKitAppearanceName.flatMap(NSAppearance.init(named:))
        window?.backgroundColor = NSColor(AppColors.windowBackground)
    }

    private func applyAppAppearance() {
        NSApp.appearance = currentMode.appKitAppearanceName.flatMap(NSAppearance.init(named:))
    }

    private var currentMode: PindropThemeMode {
        let rawValue = UserDefaults.standard.string(forKey: PindropThemeStorageKeys.themeMode)
        return PindropThemeMode(rawValue: rawValue ?? "") ?? .system
    }
}

private struct ThemeRefreshModifier: ViewModifier {
    @ObservedObject private var theme = PindropThemeController.shared

    func body(content: Content) -> some View {
        let _ = theme.revision
        content
    }
}

enum AppTheme {
    enum Spacing {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 6
        static let sm: CGFloat = 10
        static let md: CGFloat = 14
        static let lg: CGFloat = 18
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
        static let xxxl: CGFloat = 40
        static let huge: CGFloat = 56
    }

    enum Radius {
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 18
        static let xl: CGFloat = 24
        static let full: CGFloat = 9999
    }

    enum Shadow {
        static let sm = ShadowStyle(color: AppColors.shadowColor.opacity(0.08), radius: 6, x: 0, y: 2)
        static let md = ShadowStyle(color: AppColors.shadowColor.opacity(0.14), radius: 16, x: 0, y: 8)
        static let lg = ShadowStyle(color: AppColors.shadowColor.opacity(0.2), radius: 30, x: 0, y: 18)
    }

    enum Window {
        /// Scorched Earth §3 / Decision 8 — min ~980×640, default canvas 1160×760.
        static let mainMinWidth: CGFloat = 980
        static let mainMinHeight: CGFloat = 640
        static let mainDefaultWidth: CGFloat = 1160
        static let mainDefaultHeight: CGFloat = 760

        /// Kept for page layouts that still pad under the content header.
        static let mainContentTopInset: CGFloat = 0

        /// Expanded sidebar width (spec §3); collapsed is a derived 64 pt icon rail.
        static let sidebarWidth: CGFloat = 236
        static let sidebarCollapsedWidth: CGFloat = 64
    }

    enum Animation {
        static let fast: SwiftUI.Animation = .easeOut(duration: 0.16)
        static let normal: SwiftUI.Animation = .easeInOut(duration: 0.24)
        static let smooth: SwiftUI.Animation = .spring(response: 0.38, dampingFraction: 0.84)
        static let bouncy: SwiftUI.Animation = .spring(response: 0.45, dampingFraction: 0.74)
    }
}

struct ShadowStyle {
    let color: Color
    let radius: CGFloat
    let x: CGFloat
    let y: CGFloat
}

enum AppColors {
    static var windowBackground: Color { dynamicColor(\.windowBackground) }
    static var sidebarBackground: Color { dynamicColor(\.sidebarBackground) }
    static var contentBackground: Color { dynamicColor(\.contentBackground) }
    static var surfaceBackground: Color { dynamicColor(\.surfaceBackground) }
    static var elevatedSurface: Color { dynamicColor(\.elevatedSurface) }
    static var mutedSurface: Color { dynamicColor(\.mutedSurface) }
    static var inputBackground: Color { dynamicColor(\.inputBackground) }
    static var inputBorder: Color { dynamicColor(\.inputBorder) }
    static var inputBorderFocused: Color { dynamicColor(\.inputBorderFocused) }
    static var accent: Color { dynamicColor(\.accent) }
    static var accentSecondary: Color { dynamicColor(\.accentSecondary) }
    static var accentBackground: Color { dynamicColor(\.accentBackground) }
    static var textPrimary: Color { dynamicColor(\.textPrimary) }
    static var textSecondary: Color { dynamicColor(\.textSecondary) }
    static var textTertiary: Color { dynamicColor(\.textTertiary) }
    static var border: Color { dynamicColor(\.border) }
    static var divider: Color { dynamicColor(\.divider) }
    static var success: Color { dynamicColor(\.success) }
    static var successBackground: Color { dynamicColor(\.successBackground) }
    static var warning: Color { dynamicColor(\.warning) }
    static var warningBackground: Color { dynamicColor(\.warningBackground) }
    static var error: Color { dynamicColor(\.error) }
    static var errorBackground: Color { dynamicColor(\.errorBackground) }
    static var recording: Color { dynamicColor(\.recording) }
    static var processing: Color { dynamicColor(\.processing) }
    static var sidebarItemHover: Color { dynamicColor(\.sidebarItemHover) }
    static var sidebarItemActive: Color { dynamicColor(\.sidebarItemActive) }
    static var overlaySurface: Color { dynamicColor(\.overlaySurface) }
    static var overlaySurfaceStrong: Color { dynamicColor(\.overlaySurfaceStrong) }
    static var overlayLine: Color { dynamicColor(\.overlayLine) }
    static var overlayTextPrimary: Color { dynamicColor(\.overlayTextPrimary) }
    static var overlayTextSecondary: Color { dynamicColor(\.overlayTextSecondary) }
    static var overlayWaveform: Color { dynamicColor(\.overlayWaveform) }
    static var overlayRecording: Color { dynamicColor(\.overlayRecording) }
    static var overlayWarning: Color { dynamicColor(\.overlayWarning) }
    static var overlayTooltipAccent: Color { dynamicColor(\.overlayTooltipAccent) }
    static var shadowColor: Color { dynamicColor(\.shadow) }

    static var windowBackgroundColor: NSColor { dynamicNSColor(\.windowBackground) }
    static var overlaySurfaceColor: NSColor { dynamicNSColor(\.overlaySurface) }

    private static func dynamicColor(_ keyPath: KeyPath<ResolvedPalette, NSColor>) -> Color {
        Color(nsColor: dynamicNSColor(keyPath))
    }

    private static func dynamicNSColor(_ keyPath: KeyPath<ResolvedPalette, NSColor>) -> NSColor {
        NSColor(name: nil) { appearance in
            resolvedPalette(for: isDark(appearance))[keyPath: keyPath]
        }
    }

    private static func resolvedPalette(for isDark: Bool) -> ResolvedPalette {
        let variant: PindropThemeVariant = isDark ? .dark : .light
        let storageKey = isDark ? PindropThemeStorageKeys.darkThemePresetID : PindropThemeStorageKeys.lightThemePresetID
        let presetID = UserDefaults.standard.string(forKey: storageKey)
        let profile = PindropThemePresetCatalog.profile(for: presetID, variant: variant)
        return ResolvedPalette(profile: profile, isDark: isDark)
    }

    private static func isDark(_ appearance: NSAppearance) -> Bool {
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
}

/// Concrete size/weight/line-height for a typography role (spec §2).
/// Prefer these metrics in tests; use the paired `Font` / `lineSpacing` at call sites.
struct TypographyRoleMetrics: Equatable, Sendable {
    let family: FontLoader.Family
    let size: CGFloat
    let weight: FontLoader.Weight
    /// Design line box (pt). `lineSpacing` = max(0, lineHeight − size).
    let lineHeight: CGFloat
    var italic: Bool = false

    var lineSpacing: CGFloat { max(0, lineHeight - size) }

    var font: Font {
        FontLoader.font(family: family, size: size, weight: weight, italic: italic)
    }
}

/// Scorched Earth typography ramp (spec §2).
/// New role names are preferred; legacy members map onto the ramp so existing views compile.
enum AppTypography {
    // MARK: Role metrics (authoritative sizes / weights / line boxes)

    static let wordmarkMetrics = TypographyRoleMetrics(
        family: .newsreader, size: 22, weight: .semibold, lineHeight: 28
    )
    static let pageTitleMetrics = TypographyRoleMetrics(
        family: .newsreader, size: 34, weight: .medium, lineHeight: 38
    )
    static let transcriptBodyMetrics = TypographyRoleMetrics(
        family: .newsreader, size: 17, weight: .regular, lineHeight: 26
    )
    /// Newsreader 17/22 · 500 — pinned note card titles (spec §10).
    /// Custom Font cannot be restyled via `.fontWeight` — bake medium in.
    static let pinnedCardTitleMetrics = TypographyRoleMetrics(
        family: .newsreader, size: 17, weight: .medium, lineHeight: 22
    )
    static let bodyMetrics = TypographyRoleMetrics(
        family: .inter, size: 13, weight: .regular, lineHeight: 16
    )
    static let bodyMetaMetrics = TypographyRoleMetrics(
        family: .inter, size: 13, weight: .regular, lineHeight: 22
    )
    static let labelMetrics = TypographyRoleMetrics(
        family: .inter, size: 12, weight: .medium, lineHeight: 16
    )
    /// Inter 12/16 · 600 — status card titles (custom Font cannot be restyled via `.fontWeight`)
    static let labelSemiboldMetrics = TypographyRoleMetrics(
        family: .inter, size: 12, weight: .semibold, lineHeight: 16
    )
    static let labelStrongMetrics = TypographyRoleMetrics(
        family: .inter, size: 13, weight: .medium, lineHeight: 16
    )
    static let labelStrongSelectedMetrics = TypographyRoleMetrics(
        family: .inter, size: 13, weight: .semibold, lineHeight: 16
    )
    static let badgeMetrics = TypographyRoleMetrics(
        family: .inter, size: 11, weight: .semibold, lineHeight: 14
    )
    static let captionMetrics = TypographyRoleMetrics(
        family: .inter, size: 11, weight: .regular, lineHeight: 14
    )
    /// Inter 11/14 · 500 — unselected settings tab labels (spec §13; custom Font
    /// cannot be restyled via `.fontWeight` — bake medium in).
    static let captionMediumMetrics = TypographyRoleMetrics(
        family: .inter, size: 11, weight: .medium, lineHeight: 14
    )
    /// Inter 12/16 · 400 — settings row subtitles (spec §13 "subtitle Inter 12 ink-2").
    static let captionLargeMetrics = TypographyRoleMetrics(
        family: .inter, size: 12, weight: .regular, lineHeight: 16
    )
    static let monoTimeMetrics = TypographyRoleMetrics(
        family: .jetbrainsMono, size: 12, weight: .medium, lineHeight: 16
    )
    static let monoSmallMetrics = TypographyRoleMetrics(
        family: .jetbrainsMono, size: 11, weight: .medium, lineHeight: 14
    )
    static let sectionHeaderMetrics = TypographyRoleMetrics(
        family: .inter, size: 11, weight: .semibold, lineHeight: 14
    )
    static let statLargeMetrics = TypographyRoleMetrics(
        family: .newsreader, size: 34, weight: .medium, lineHeight: 38
    )
    static let statMediumMetrics = TypographyRoleMetrics(
        family: .newsreader, size: 24, weight: .semibold, lineHeight: 28
    )

    /// All primary roles for exhaustive metric tests.
    static var allRoleMetrics: [TypographyRoleMetrics] {
        [
            wordmarkMetrics, pageTitleMetrics, transcriptBodyMetrics, pinnedCardTitleMetrics,
            bodyMetrics, bodyMetaMetrics, labelMetrics, labelSemiboldMetrics,
            labelStrongMetrics, labelStrongSelectedMetrics, badgeMetrics,
            captionMetrics, captionMediumMetrics, captionLargeMetrics,
            monoTimeMetrics, monoSmallMetrics, sectionHeaderMetrics,
            statLargeMetrics, statMediumMetrics,
        ]
    }

    // MARK: New roles (spec §2) — Fonts

    /// Newsreader 22/28 · 600 · -0.01em — sidebar wordmark
    static let wordmark = wordmarkMetrics.font
    /// Newsreader 34/38 · 500 · -0.015em — page titles
    static let pageTitle = pageTitleMetrics.font
    /// Newsreader 17/26 · 400 — expanded-card transcript
    static let transcriptBody = transcriptBodyMetrics.font
    /// Newsreader 17/22 · 500 — pinned note card titles (spec §10)
    static let pinnedCardTitle = pinnedCardTitleMetrics.font
    /// Inter 13/16 · 400 — row preview / body
    static let body = bodyMetrics.font
    /// Inter 13/22 · 400 — header meta line
    static let bodyMeta = bodyMetaMetrics.font
    /// Inter 12/16 · 500 — buttons, chips, nav secondary
    static let label = labelMetrics.font
    /// Inter 12/16 · 600 — status titles, strong chip labels
    static let labelSemibold = labelSemiboldMetrics.font
    /// Inter 13/16 · 500–600 — nav items
    static let labelStrong = labelStrongMetrics.font
    static let labelStrongSelected = labelStrongSelectedMetrics.font
    /// Inter 11/14 · 600 — kind badges
    static let badge = badgeMetrics.font
    /// Inter 11/14 · 400 — captions
    static let caption = captionMetrics.font
    /// Inter 11/14 · 500 — unselected settings tab labels
    static let captionMedium = captionMediumMetrics.font
    /// Inter 12/16 · 400 — settings row subtitles
    static let captionLarge = captionLargeMetrics.font
    /// JetBrains Mono 12/16 · 500 — row times
    static let monoTime = monoTimeMetrics.font
    /// JetBrains Mono 11/14 · 400–500 — counts, kbd hints
    static let monoSmall = monoSmallMetrics.font
    /// Inter 11–12/14 · 500 · uppercase section headers
    static let sectionHeader = sectionHeaderMetrics.font

    // MARK: Line spacing (lineHeight − size) for multi-line Text sites

    static let wordmarkLineSpacing = wordmarkMetrics.lineSpacing
    static let pageTitleLineSpacing = pageTitleMetrics.lineSpacing
    static let transcriptBodyLineSpacing = transcriptBodyMetrics.lineSpacing
    static let pinnedCardTitleLineSpacing = pinnedCardTitleMetrics.lineSpacing
    static let bodyLineSpacing = bodyMetrics.lineSpacing
    static let bodyMetaLineSpacing = bodyMetaMetrics.lineSpacing
    static let labelLineSpacing = labelMetrics.lineSpacing
    static let captionLineSpacing = captionMetrics.lineSpacing

    // MARK: Legacy members (mapped onto the new ramp — migrate call sites over time)

    /// Mapped → pageTitle
    static let largeTitle = pageTitle
    /// Mapped → wordmark
    static let title = wordmark
    /// Mapped → labelStrongSelected
    static let headline = labelStrongSelected
    /// Mapped → labelStrong
    static let subheadline = labelStrong
    /// Mapped → body (was 14pt rounded; now Inter 13)
    static let bodySmall = body
    /// Mapped → badge
    static let tiny = badge
    /// Mapped → monoTime
    static let mono = monoTime
    /// Mapped → pageTitle scale for hero stats
    static let statLarge = statLargeMetrics.font
    /// Mapped → wordmark scale for medium stats
    static let statMedium = statMediumMetrics.font

    // MARK: Tracking helpers (em → SwiftUI relative tracking)

    static let wordmarkTracking: CGFloat = -0.01 * wordmarkMetrics.size
    static let pageTitleTracking: CGFloat = -0.015 * pageTitleMetrics.size
}

/// Builds the ~37 semantic roles from Scorched Earth tokens (spec §1).
struct ResolvedPalette {
    let windowBackground: NSColor
    let sidebarBackground: NSColor
    let contentBackground: NSColor
    let surfaceBackground: NSColor
    let elevatedSurface: NSColor
    let mutedSurface: NSColor
    let inputBackground: NSColor
    let inputBorder: NSColor
    let inputBorderFocused: NSColor
    let accent: NSColor
    let accentSecondary: NSColor
    let accentBackground: NSColor
    let textPrimary: NSColor
    let textSecondary: NSColor
    let textTertiary: NSColor
    let border: NSColor
    let divider: NSColor
    let success: NSColor
    let successBackground: NSColor
    let warning: NSColor
    let warningBackground: NSColor
    let error: NSColor
    let errorBackground: NSColor
    let recording: NSColor
    let processing: NSColor
    let sidebarItemHover: NSColor
    let sidebarItemActive: NSColor
    let overlaySurface: NSColor
    let overlaySurfaceStrong: NSColor
    let overlayLine: NSColor
    let overlayTextPrimary: NSColor
    let overlayTextSecondary: NSColor
    let overlayWaveform: NSColor
    let overlayRecording: NSColor
    let overlayWarning: NSColor
    let overlayTooltipAccent: NSColor
    let shadow: NSColor

    /// Whether WCAG clamping adjusted ink-2 / ink-3 for this palette.
    let didClampTextColors: Bool

    init(profile: PindropThemeProfile, isDark: Bool) {
        let resolved = Self.resolve(profile: profile, isDark: isDark)
        self = resolved.palette
    }

    /// Pure resolution entry used by tests — returns palette + clamp flag + optional log message.
    static func resolve(
        profile: PindropThemeProfile,
        isDark: Bool
    ) -> (palette: ResolvedPalette, didClamp: Bool) {
        let ground = NSColor(pindropHex: profile.groundHex)
            ?? (isDark
                ? NSColor(pindropHex: "#1B1916")!
                : NSColor(pindropHex: "#F6F4EE")!)
        let page = NSColor(pindropHex: profile.pageHex)
            ?? (isDark
                ? NSColor(pindropHex: "#242119")!
                : NSColor(pindropHex: "#FCFBF7")!)
        let accentBase = NSColor(pindropHex: profile.accentHex) ?? .systemGreen

        let inkHex = isDark ? ScorchedEarthBaseTokens.darkInk : ScorchedEarthBaseTokens.lightInk
        let ink2Hex = isDark ? ScorchedEarthBaseTokens.darkInk2 : ScorchedEarthBaseTokens.lightInk2
        let ink3Hex = isDark ? ScorchedEarthBaseTokens.darkInk3 : ScorchedEarthBaseTokens.lightInk3
        let lineHex = isDark ? ScorchedEarthBaseTokens.darkLine : ScorchedEarthBaseTokens.lightLine
        let defaultRecordHex = isDark ? ScorchedEarthBaseTokens.darkRecord : ScorchedEarthBaseTokens.lightRecord

        let ink = NSColor(pindropHex: inkHex) ?? (isDark ? .white : .black)
        var ink2 = NSColor(pindropHex: ink2Hex) ?? ink.withAlphaComponent(0.72)
        var ink3 = NSColor(pindropHex: ink3Hex) ?? ink.withAlphaComponent(0.48)
        let line = NSColor(pindropHex: lineHex) ?? ink.withAlphaComponent(0.12)

        // WCAG clamp ink-2 / ink-3 against ground + page (≥4.5:1 for normal text roles).
        let grounds = [ground, page]
        let ink2Clamp = ColorContrast.clampTextColor(
            ink2,
            against: grounds,
            minimumRatio: ColorContrast.minimumNormalTextRatio
        )
        let ink3Clamp = ColorContrast.clampTextColor(
            ink3,
            against: grounds,
            minimumRatio: ColorContrast.minimumNormalTextRatio
        )
        ink2 = ink2Clamp.color
        ink3 = ink3Clamp.color
        let didClamp = ink2Clamp.didClamp || ink3Clamp.didClamp
        if didClamp {
            Log.ui.info(
                "Theme palette WCAG clamp applied (isDark=\(isDark) ink2=\(ink2Clamp.didClamp) ink3=\(ink3Clamp.didClamp))"
            )
        }

        let accentSoft: NSColor
        if let softHex = profile.accentSoftHex, let soft = NSColor(pindropHex: softHex) {
            accentSoft = soft
        } else {
            // Soft wash of accent over ground.
            accentSoft = accentBase.mixed(with: ground, ratio: isDark ? 0.82 : 0.90)
        }

        let recordBase = NSColor(pindropHex: profile.recordHex ?? defaultRecordHex) ?? .systemRed
        let recordSoft: NSColor
        if let softHex = profile.recordSoftHex, let soft = NSColor(pindropHex: softHex) {
            recordSoft = soft
        } else if !isDark, let soft = NSColor(pindropHex: ScorchedEarthBaseTokens.lightRecordSoft) {
            recordSoft = soft
        } else {
            recordSoft = recordBase.mixed(with: ground, ratio: isDark ? 0.82 : 0.90)
        }

        let warningBase = isDark
            ? (NSColor(pindropHex: "#D09B53") ?? .systemOrange)
            : (NSColor(pindropHex: "#A9692D") ?? .systemOrange)
        let warningSoft = warningBase.mixed(with: ground, ratio: isDark ? 0.86 : 0.92)

        // Mapping guidance (task U1):
        // window/sidebar → ground · content/elevated → page · surface → ground
        // text* → ink* · borders → line · success/processing → accent · error/recording → record
        let palette = ResolvedPalette(
            windowBackground: ground,
            sidebarBackground: ground,
            contentBackground: page,
            surfaceBackground: ground,
            elevatedSurface: page,
            mutedSurface: line.withAlphaComponent(isDark ? 0.45 : 0.55),
            inputBackground: ground,
            inputBorder: line,
            inputBorderFocused: accentBase,
            accent: accentBase,
            accentSecondary: accentBase.mixed(with: ink, ratio: 0.18),
            accentBackground: accentSoft,
            textPrimary: ink,
            textSecondary: ink2,
            textTertiary: ink3,
            border: line,
            divider: line,
            success: accentBase,
            successBackground: accentSoft,
            warning: warningBase,
            warningBackground: warningSoft,
            error: recordBase,
            errorBackground: recordSoft,
            recording: recordBase,
            processing: accentBase,
            sidebarItemHover: ink.withAlphaComponent(isDark ? 0.06 : 0.04),
            sidebarItemActive: page,
            overlaySurface: isDark ? ground.darker(by: 0.12) : ground.darker(by: 0.82),
            overlaySurfaceStrong: isDark ? ground.darker(by: 0.22) : ground.darker(by: 0.9),
            overlayLine: isDark ? line : NSColor.white.withAlphaComponent(0.14),
            overlayTextPrimary: NSColor.white.withAlphaComponent(0.96),
            overlayTextSecondary: NSColor.white.withAlphaComponent(0.74),
            overlayWaveform: accentBase.mixed(with: NSColor.white, ratio: isDark ? 0.24 : 0.42),
            overlayRecording: recordBase.mixed(with: NSColor.white, ratio: isDark ? 0.12 : 0.18),
            overlayWarning: isDark ? warningBase : warningBase.mixed(with: NSColor.white, ratio: 0.18),
            overlayTooltipAccent: accentBase.mixed(with: NSColor.white, ratio: isDark ? 0.3 : 0.42),
            shadow: isDark ? NSColor.black : ink,
            didClampTextColors: didClamp
        )
        return (palette, didClamp)
    }

    private init(
        windowBackground: NSColor,
        sidebarBackground: NSColor,
        contentBackground: NSColor,
        surfaceBackground: NSColor,
        elevatedSurface: NSColor,
        mutedSurface: NSColor,
        inputBackground: NSColor,
        inputBorder: NSColor,
        inputBorderFocused: NSColor,
        accent: NSColor,
        accentSecondary: NSColor,
        accentBackground: NSColor,
        textPrimary: NSColor,
        textSecondary: NSColor,
        textTertiary: NSColor,
        border: NSColor,
        divider: NSColor,
        success: NSColor,
        successBackground: NSColor,
        warning: NSColor,
        warningBackground: NSColor,
        error: NSColor,
        errorBackground: NSColor,
        recording: NSColor,
        processing: NSColor,
        sidebarItemHover: NSColor,
        sidebarItemActive: NSColor,
        overlaySurface: NSColor,
        overlaySurfaceStrong: NSColor,
        overlayLine: NSColor,
        overlayTextPrimary: NSColor,
        overlayTextSecondary: NSColor,
        overlayWaveform: NSColor,
        overlayRecording: NSColor,
        overlayWarning: NSColor,
        overlayTooltipAccent: NSColor,
        shadow: NSColor,
        didClampTextColors: Bool
    ) {
        self.windowBackground = windowBackground
        self.sidebarBackground = sidebarBackground
        self.contentBackground = contentBackground
        self.surfaceBackground = surfaceBackground
        self.elevatedSurface = elevatedSurface
        self.mutedSurface = mutedSurface
        self.inputBackground = inputBackground
        self.inputBorder = inputBorder
        self.inputBorderFocused = inputBorderFocused
        self.accent = accent
        self.accentSecondary = accentSecondary
        self.accentBackground = accentBackground
        self.textPrimary = textPrimary
        self.textSecondary = textSecondary
        self.textTertiary = textTertiary
        self.border = border
        self.divider = divider
        self.success = success
        self.successBackground = successBackground
        self.warning = warning
        self.warningBackground = warningBackground
        self.error = error
        self.errorBackground = errorBackground
        self.recording = recording
        self.processing = processing
        self.sidebarItemHover = sidebarItemHover
        self.sidebarItemActive = sidebarItemActive
        self.overlaySurface = overlaySurface
        self.overlaySurfaceStrong = overlaySurfaceStrong
        self.overlayLine = overlayLine
        self.overlayTextPrimary = overlayTextPrimary
        self.overlayTextSecondary = overlayTextSecondary
        self.overlayWaveform = overlayWaveform
        self.overlayRecording = overlayRecording
        self.overlayWarning = overlayWarning
        self.overlayTooltipAccent = overlayTooltipAccent
        self.shadow = shadow
        self.didClampTextColors = didClampTextColors
    }
}

private struct HairlineBorderModifier<BorderShape: InsettableShape, BorderStyle: ShapeStyle>: ViewModifier {
    @Environment(\.displayScale) private var displayScale

    let shape: BorderShape
    let style: BorderStyle

    private var hairlineWidth: CGFloat {
        1 / max(displayScale, 1)
    }

    func body(content: Content) -> some View {
        content.overlay(
            shape.strokeBorder(style, lineWidth: hairlineWidth)
        )
    }
}

private struct HairlineDashedBorderModifier<BorderShape: InsettableShape, BorderStyle: ShapeStyle>: ViewModifier {
    @Environment(\.displayScale) private var displayScale

    let shape: BorderShape
    let style: BorderStyle
    let dash: [CGFloat]

    private var hairlineWidth: CGFloat {
        1 / max(displayScale, 1)
    }

    func body(content: Content) -> some View {
        content.overlay(
            shape.strokeBorder(style, style: StrokeStyle(lineWidth: hairlineWidth, dash: dash))
        )
    }
}

private struct HairlineStrokeModifier<BorderShape: Shape, BorderStyle: ShapeStyle>: ViewModifier {
    @Environment(\.displayScale) private var displayScale

    let shape: BorderShape
    let style: BorderStyle

    private var hairlineWidth: CGFloat {
        1 / max(displayScale, 1)
    }

    func body(content: Content) -> some View {
        content.overlay(
            shape.stroke(style, lineWidth: hairlineWidth)
        )
    }
}

extension View {
    func hairlineBorder<BorderShape: InsettableShape, BorderStyle: ShapeStyle>(
        _ shape: BorderShape,
        style: BorderStyle
    ) -> some View {
        modifier(HairlineBorderModifier(shape: shape, style: style))
    }

    func hairlineBorder<BorderShape: InsettableShape, BorderStyle: ShapeStyle>(
        _ shape: BorderShape,
        style: BorderStyle,
        dash: [CGFloat]
    ) -> some View {
        modifier(HairlineDashedBorderModifier(shape: shape, style: style, dash: dash))
    }

    func hairlineStroke<BorderShape: Shape, BorderStyle: ShapeStyle>(
        _ shape: BorderShape,
        style: BorderStyle
    ) -> some View {
        modifier(HairlineStrokeModifier(shape: shape, style: style))
    }

    func cardStyle(elevated: Bool = false) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
                    .fill(elevated ? AppColors.elevatedSurface : AppColors.surfaceBackground)
            )
            .hairlineStroke(
                RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous),
                style: AppColors.border
            )
    }

    func shadow(_ style: ShadowStyle) -> some View {
        shadow(color: style.color, radius: style.radius, x: style.x, y: style.y)
    }

    func sidebarItemStyle(isSelected: Bool, isHovered: Bool) -> some View {
        self
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.vertical, AppTheme.Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                    .fill(isSelected ? AppColors.sidebarItemActive : (isHovered ? AppColors.sidebarItemHover : Color.clear))
            )
    }

    func highlightedCardStyle() -> some View {
        self
            .background(AppColors.accentBackground)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous))
    }

    func themeRefresh() -> some View {
        modifier(ThemeRefreshModifier())
    }
}

extension NSColor {
    convenience init?(pindropHex: String) {
        let cleaned = pindropHex
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")

        guard cleaned.count == 6, let hexValue = Int(cleaned, radix: 16) else {
            return nil
        }

        let red = CGFloat((hexValue >> 16) & 0xFF) / 255
        let green = CGFloat((hexValue >> 8) & 0xFF) / 255
        let blue = CGFloat(hexValue & 0xFF) / 255
        self.init(red: red, green: green, blue: blue, alpha: 1)
    }

    func mixed(with color: NSColor, ratio: CGFloat) -> NSColor {
        let resolvedSelf = usingColorSpace(.deviceRGB) ?? self
        let resolvedOther = color.usingColorSpace(.deviceRGB) ?? color
        let clampedRatio = min(max(ratio, 0), 1)
        let inverse = 1 - clampedRatio

        return NSColor(
            red: (resolvedSelf.redComponent * inverse) + (resolvedOther.redComponent * clampedRatio),
            green: (resolvedSelf.greenComponent * inverse) + (resolvedOther.greenComponent * clampedRatio),
            blue: (resolvedSelf.blueComponent * inverse) + (resolvedOther.blueComponent * clampedRatio),
            alpha: (resolvedSelf.alphaComponent * inverse) + (resolvedOther.alphaComponent * clampedRatio)
        )
    }

    func lighter(by amount: CGFloat) -> NSColor {
        mixed(with: .white, ratio: amount)
    }

    func darker(by amount: CGFloat) -> NSColor {
        mixed(with: .black, ratio: amount)
    }
}

#Preview("Theme Colors - Light") {
    ThemePreviewView()
        .preferredColorScheme(.light)
}

#Preview("Theme Colors - Dark") {
    ThemePreviewView()
        .preferredColorScheme(.dark)
}

private struct ThemePreviewView: View {
    var body: some View {
        VStack(spacing: AppTheme.Spacing.xl) {
            Text("Pindrop Theme")
                .font(AppTypography.largeTitle)
                .foregroundStyle(AppColors.textPrimary)

            HStack(spacing: AppTheme.Spacing.md) {
                colorSwatch("Window", AppColors.windowBackground)
                colorSwatch("Sidebar", AppColors.sidebarBackground)
                colorSwatch("Surface", AppColors.surfaceBackground)
                colorSwatch("Elevated", AppColors.elevatedSurface)
            }

            HStack(spacing: AppTheme.Spacing.md) {
                colorSwatch("Accent", AppColors.accent)
                colorSwatch("Success", AppColors.success)
                colorSwatch("Warning", AppColors.warning)
                colorSwatch("Error", AppColors.error)
            }

            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                Text("Primary Text")
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textPrimary)
                Text("Secondary Text")
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textSecondary)
                Text("Tertiary Text")
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textTertiary)
            }
            .padding()
            .cardStyle()
        }
        .padding(AppTheme.Spacing.xxl)
        .background(AppColors.windowBackground)
        .themeRefresh()
    }

    private func colorSwatch(_ name: String, _ color: Color) -> some View {
        VStack(spacing: AppTheme.Spacing.xs) {
            RoundedRectangle(cornerRadius: AppTheme.Radius.sm)
                .fill(color)
                .frame(width: 60, height: 40)
                .hairlineBorder(
                    RoundedRectangle(cornerRadius: AppTheme.Radius.sm),
                    style: AppColors.border
                )

            Text(name)
                .font(AppTypography.tiny)
                .foregroundStyle(AppColors.textSecondary)
        }
    }
}

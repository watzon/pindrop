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
        static let mainMinWidth: CGFloat = 1215
        static let mainMinHeight: CGFloat = 600
        static let mainDefaultWidth: CGFloat = 1186
        static let mainDefaultHeight: CGFloat = 753

        static let sidebarTopInset: CGFloat = 32
        static let sidebarContentGap: CGFloat = 14
        static let mainContentTopInset: CGFloat = 32
        static let panelCornerRadius: CGFloat = 28

        static let sidebarWidth: CGFloat = 272
        static let sidebarCollapsedWidth: CGFloat = 64

        static let settingsMinWidth: CGFloat = 1024
        static let settingsMinHeight: CGFloat = 600
        static let settingsDefaultWidth: CGFloat = 850
        static let settingsDefaultHeight: CGFloat = 753
        static let settingsSidebarWidth: CGFloat = 220
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

enum AppTypography {
    static let largeTitle = Font.system(size: 30, weight: .semibold, design: .rounded)
    static let title = Font.system(size: 21, weight: .semibold, design: .rounded)
    static let headline = Font.system(size: 16, weight: .semibold, design: .rounded)
    static let subheadline = Font.system(size: 14, weight: .semibold, design: .rounded)
    static let body = Font.system(size: 14, weight: .regular, design: .rounded)
    static let bodySmall = Font.system(size: 13, weight: .regular, design: .rounded)
    static let caption = Font.system(size: 12, weight: .medium, design: .rounded)
    static let tiny = Font.system(size: 11, weight: .medium, design: .rounded)
    static let mono = Font.system(size: 13, weight: .medium, design: .monospaced)
    static let monoSmall = Font.system(size: 11, weight: .medium, design: .monospaced)
    static let statLarge = Font.system(size: 32, weight: .bold, design: .rounded)
    static let statMedium = Font.system(size: 24, weight: .semibold, design: .rounded)
}

private struct ResolvedPalette {
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

    init(profile: PindropThemeProfile, isDark: Bool) {
        let background = NSColor(pindropHex: profile.backgroundHex)
            ?? (isDark ? NSColor(red: 0.08, green: 0.08, blue: 0.09, alpha: 1) : NSColor(red: 0.97, green: 0.96, blue: 0.94, alpha: 1))
        let foreground = NSColor(pindropHex: profile.foregroundHex)
            ?? (isDark ? NSColor.white : NSColor.black)
        let accentBase = NSColor(pindropHex: profile.accentHex) ?? .systemOrange
        let successBase = NSColor(pindropHex: profile.successHex) ?? .systemGreen
        let warningBase = NSColor(pindropHex: profile.warningHex) ?? .systemOrange
        let dangerBase = NSColor(pindropHex: profile.dangerHex) ?? .systemRed
        let processingBase = NSColor(pindropHex: profile.processingHex) ?? .systemBlue
        let contrast = min(max(profile.contrast, 20), 80) / 100

        if isDark {
            windowBackground = background
            sidebarBackground = background.lighter(by: 0.035)
            contentBackground = background.lighter(by: 0.015)
            surfaceBackground = background.lighter(by: 0.055 + contrast * 0.035)
            elevatedSurface = background.lighter(by: 0.09 + contrast * 0.045)
            mutedSurface = foreground.withAlphaComponent(0.06 + contrast * 0.02)
            inputBackground = background.lighter(by: 0.075 + contrast * 0.03)
            inputBorder = foreground.withAlphaComponent(0.14 + contrast * 0.06)
            inputBorderFocused = accentBase.withAlphaComponent(0.78)
            accent = accentBase
            accentSecondary = accentBase.mixed(with: foreground, ratio: 0.22)
            accentBackground = accentBase.mixed(with: background, ratio: 0.86)
            textPrimary = foreground
            textSecondary = foreground.withAlphaComponent(0.72)
            textTertiary = foreground.withAlphaComponent(0.48)
            border = foreground.withAlphaComponent(0.11 + contrast * 0.05)
            divider = foreground.withAlphaComponent(0.08 + contrast * 0.04)
            success = successBase
            successBackground = successBase.mixed(with: background, ratio: 0.88)
            warning = warningBase
            warningBackground = warningBase.mixed(with: background, ratio: 0.88)
            error = dangerBase
            errorBackground = dangerBase.mixed(with: background, ratio: 0.89)
            recording = dangerBase
            processing = processingBase
            sidebarItemHover = foreground.withAlphaComponent(0.065)
            sidebarItemActive = accentBase.mixed(with: background, ratio: 0.82)
            overlaySurface = background.darker(by: 0.24)
            overlaySurfaceStrong = background.darker(by: 0.32)
            overlayLine = foreground.withAlphaComponent(0.18)
            overlayTextPrimary = NSColor.white.withAlphaComponent(0.96)
            overlayTextSecondary = NSColor.white.withAlphaComponent(0.74)
            overlayWaveform = accentBase.mixed(with: NSColor.white, ratio: 0.24)
            overlayRecording = dangerBase.mixed(with: NSColor.white, ratio: 0.12)
            overlayWarning = warningBase
            overlayTooltipAccent = accentBase.mixed(with: NSColor.white, ratio: 0.3)
            shadow = NSColor.black
        } else {
            windowBackground = background
            sidebarBackground = background.darker(by: 0.018)
            contentBackground = background.lighter(by: 0.005)
            surfaceBackground = background.lighter(by: 0.025)
            elevatedSurface = background.darker(by: 0.02 + contrast * 0.01)
            mutedSurface = foreground.withAlphaComponent(0.045 + contrast * 0.02)
            inputBackground = background.lighter(by: 0.015)
            inputBorder = foreground.withAlphaComponent(0.14 + contrast * 0.04)
            inputBorderFocused = accentBase.withAlphaComponent(0.72)
            accent = accentBase
            accentSecondary = accentBase.mixed(with: foreground, ratio: 0.18)
            accentBackground = accentBase.mixed(with: background, ratio: 0.92)
            textPrimary = foreground
            textSecondary = foreground.withAlphaComponent(0.7)
            textTertiary = foreground.withAlphaComponent(0.48)
            border = foreground.withAlphaComponent(0.1 + contrast * 0.04)
            divider = foreground.withAlphaComponent(0.07 + contrast * 0.03)
            success = successBase
            successBackground = successBase.mixed(with: background, ratio: 0.93)
            warning = warningBase
            warningBackground = warningBase.mixed(with: background, ratio: 0.93)
            error = dangerBase
            errorBackground = dangerBase.mixed(with: background, ratio: 0.94)
            recording = dangerBase
            processing = processingBase
            sidebarItemHover = foreground.withAlphaComponent(0.05)
            sidebarItemActive = accentBase.mixed(with: background, ratio: 0.87)
            overlaySurface = background.darker(by: 0.82)
            overlaySurfaceStrong = background.darker(by: 0.9)
            overlayLine = NSColor.white.withAlphaComponent(0.14)
            overlayTextPrimary = NSColor.white.withAlphaComponent(0.96)
            overlayTextSecondary = NSColor.white.withAlphaComponent(0.74)
            overlayWaveform = accentBase.mixed(with: NSColor.white, ratio: 0.42)
            overlayRecording = dangerBase.mixed(with: NSColor.white, ratio: 0.18)
            overlayWarning = warningBase.mixed(with: NSColor.white, ratio: 0.18)
            overlayTooltipAccent = accentBase.mixed(with: NSColor.white, ratio: 0.42)
            shadow = foreground
        }
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

//
//  Theme.swift
//  Pindrop
//
//  Created on 2026-03-20.
//

import AppKit
import SwiftUI

import PindropSharedUITheme

@MainActor
final class PindropThemeController: ObservableObject {
    static let shared = PindropThemeController()

    @Published private(set) var revision = 0

    private init() {
        applyAppAppearance()
    }

    func refresh() {
        PindropThemeBridge.invalidateCache()
        applyAppAppearance()
        revision &+= 1
    }

    func apply(to window: NSWindow?) {
        window?.appearance = currentMode.appKitAppearanceName.flatMap(NSAppearance.init(named:))
        window?.backgroundColor = AppColors.windowBackgroundColor
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
        static var xxs: CGFloat { CGFloat(themeSpacing.xxs) }
        static var xs: CGFloat { CGFloat(themeSpacing.xs) }
        static var sm: CGFloat { CGFloat(themeSpacing.sm) }
        static var md: CGFloat { CGFloat(themeSpacing.md) }
        static var lg: CGFloat { CGFloat(themeSpacing.lg) }
        static var xl: CGFloat { CGFloat(themeSpacing.xl) }
        static var xxl: CGFloat { CGFloat(themeSpacing.xxl) }
        static var xxxl: CGFloat { CGFloat(themeSpacing.xxxl) }
        static var huge: CGFloat { CGFloat(themeSpacing.huge) }

        private static var themeSpacing: SpacingScale { PindropThemeBridge.spacingScale }
    }

    enum Radius {
        static var sm: CGFloat { CGFloat(themeRadius.sm) }
        static var md: CGFloat { CGFloat(themeRadius.md) }
        static var lg: CGFloat { CGFloat(themeRadius.lg) }
        static var xl: CGFloat { CGFloat(themeRadius.xl) }
        static var full: CGFloat { CGFloat(themeRadius.full) }

        private static var themeRadius: RadiusScale { PindropThemeBridge.radiusScale }
    }

    enum Shadow {
        static var sm: ShadowStyle { shadowStyle(from: themeShadow.sm) }
        static var md: ShadowStyle { shadowStyle(from: themeShadow.md) }
        static var lg: ShadowStyle { shadowStyle(from: themeShadow.lg) }

        private static var themeShadow: ShadowScale { PindropThemeBridge.shadowScale }

        private static func shadowStyle(from token: ShadowTokenValue) -> ShadowStyle {
            ShadowStyle(
                color: Color(nsColor: NSColor(token.color)),
                radius: CGFloat(token.radius),
                x: CGFloat(token.x),
                y: CGFloat(token.y)
            )
        }
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
            resolvedPalette(for: appearance)[keyPath: keyPath]
        }
    }

    private static func resolvedPalette(for appearance: NSAppearance) -> ResolvedPalette {
        let variant: PindropThemeVariant = isDark(appearance) ? .dark : .light
        return ResolvedPalette(theme: PindropThemeBridge.resolveTheme(systemVariant: variant))
    }

    private static func isDark(_ appearance: NSAppearance) -> Bool {
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
}

enum AppTypography {
    static var largeTitle: Font { font(from: scale.largeTitle) }
    static var title: Font { font(from: scale.title) }
    static var headline: Font { font(from: scale.headline) }
    static var subheadline: Font { font(from: scale.subheadline) }
    static var body: Font { font(from: scale.body) }
    static var bodySmall: Font { font(from: scale.bodySmall) }
    static var caption: Font { font(from: scale.caption) }
    static var tiny: Font { font(from: scale.tiny) }
    static var mono: Font { font(from: scale.mono) }
    static var monoSmall: Font { font(from: scale.monoSmall) }
    static var statLarge: Font { font(from: scale.statLarge) }
    static var statMedium: Font { font(from: scale.statMedium) }

    private static var scale: TypographyScale { PindropThemeBridge.typographyScale }

    private static func font(from token: TypographyTokenValue) -> Font {
        Font.system(
            size: token.size,
            weight: weight(from: Int(token.weight)),
            design: design(from: token.design)
        )
    }

    private static func weight(from value: Int) -> Font.Weight {
        switch value {
        case 700...:
            .bold
        case 600...:
            .semibold
        case 500...:
            .medium
        default:
            .regular
        }
    }

    private static func design(from design: TypographyDesign) -> Font.Design {
        switch design {
        case .monospaced:
            .monospaced
        default:
            .rounded
        }
    }
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

    init(theme: ResolvedTheme) {
        let tokens = theme.tokens
        windowBackground = NSColor(tokens.windowBackground)
        sidebarBackground = NSColor(tokens.sidebarBackground)
        contentBackground = NSColor(tokens.contentBackground)
        surfaceBackground = NSColor(tokens.surfaceBackground)
        elevatedSurface = NSColor(tokens.elevatedSurface)
        mutedSurface = NSColor(tokens.mutedSurface)
        inputBackground = NSColor(tokens.inputBackground)
        inputBorder = NSColor(tokens.inputBorder)
        inputBorderFocused = NSColor(tokens.inputBorderFocused)
        accent = NSColor(tokens.accent)
        accentSecondary = NSColor(tokens.accentSecondary)
        accentBackground = NSColor(tokens.accentBackground)
        textPrimary = NSColor(tokens.textPrimary)
        textSecondary = NSColor(tokens.textSecondary)
        textTertiary = NSColor(tokens.textTertiary)
        border = NSColor(tokens.border)
        divider = NSColor(tokens.divider)
        success = NSColor(tokens.success)
        successBackground = NSColor(tokens.successBackground)
        warning = NSColor(tokens.warning)
        warningBackground = NSColor(tokens.warningBackground)
        error = NSColor(tokens.error)
        errorBackground = NSColor(tokens.errorBackground)
        recording = NSColor(tokens.recording)
        processing = NSColor(tokens.processing)
        sidebarItemHover = NSColor(tokens.sidebarItemHover)
        sidebarItemActive = NSColor(tokens.sidebarItemActive)
        overlaySurface = NSColor(tokens.overlaySurface)
        overlaySurfaceStrong = NSColor(tokens.overlaySurfaceStrong)
        overlayLine = NSColor(tokens.overlayLine)
        overlayTextPrimary = NSColor(tokens.overlayTextPrimary)
        overlayTextSecondary = NSColor(tokens.overlayTextSecondary)
        overlayWaveform = NSColor(tokens.overlayWaveform)
        overlayRecording = NSColor(tokens.overlayRecording)
        overlayWarning = NSColor(tokens.overlayWarning)
        overlayTooltipAccent = NSColor(tokens.overlayTooltipAccent)
        shadow = NSColor(tokens.shadow)
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

    convenience init(_ token: ColorTokenValue) {
        self.init(
            red: CGFloat(token.red) / 255,
            green: CGFloat(token.green) / 255,
            blue: CGFloat(token.blue) / 255,
            alpha: CGFloat(token.alpha) / 255
        )
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
    }

    private func colorSwatch(_ title: String, _ color: Color) -> some View {
        VStack(spacing: AppTheme.Spacing.xs) {
            RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                .fill(color)
                .frame(height: 72)
            Text(title)
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }
}

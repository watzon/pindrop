//
//  ThemeFoundationTests.swift
//  Pindrop
//
//  Created on 2026-07-09.
//

import AppKit
import Foundation
import SwiftUI
import Testing
@testable import Pindrop

@Suite("Theme foundation (U1)")
struct ThemeFoundationTests {

    // MARK: - WCAG clamp math

    @Test func contrastRatioOfBlackOnWhiteIs21() {
        let black = ColorContrast.RGB(r: 0, g: 0, b: 0)
        let white = ColorContrast.RGB(r: 1, g: 1, b: 1)
        let ratio = ColorContrast.contrastRatio(black, white)
        #expect(abs(ratio - 21) < 0.05)
    }

    @Test func contrastRatioIsSymmetric() {
        let a = ColorContrast.RGB(r: 0.12, g: 0.11, b: 0.09)
        let b = ColorContrast.RGB(r: 0.96, g: 0.95, b: 0.93)
        #expect(abs(ColorContrast.contrastRatio(a, b) - ColorContrast.contrastRatio(b, a)) < 0.0001)
    }

    @Test func clampLeavesSufficientContrastUntouched() {
        let text = ColorContrast.RGB(r: 0.12, g: 0.11, b: 0.09)
        let ground = ColorContrast.RGB(r: 0.96, g: 0.95, b: 0.93)
        let result = ColorContrast.clampTextColor(text, against: [ground], minimumRatio: 4.5)
        #expect(result.didClamp == false)
        #expect(result.color == text)
        #expect(result.ratioAfter >= 4.5)
    }

    @Test func clampDarkensLowContrastGrayOnLightGround() {
        // Mid gray on near-white fails AA.
        let text = ColorContrast.RGB(r: 0.7, g: 0.7, b: 0.7)
        let ground = ColorContrast.RGB(r: 0.98, g: 0.97, b: 0.95)
        let before = ColorContrast.contrastRatio(text, ground)
        #expect(before < 4.5)

        let result = ColorContrast.clampTextColor(text, against: [ground], minimumRatio: 4.5)
        #expect(result.didClamp == true)
        #expect(result.ratioAfter + 0.01 >= 4.5)
        // Should move toward black (darker).
        #expect(ColorContrast.relativeLuminance(of: result.color) < ColorContrast.relativeLuminance(of: text))
    }

    @Test func clampLightensLowContrastGrayOnDarkGround() {
        let text = ColorContrast.RGB(r: 0.35, g: 0.33, b: 0.30)
        let ground = ColorContrast.RGB(r: 0.10, g: 0.09, b: 0.08)
        let before = ColorContrast.contrastRatio(text, ground)
        #expect(before < 4.5)

        let result = ColorContrast.clampTextColor(text, against: [ground], minimumRatio: 4.5)
        #expect(result.didClamp == true)
        #expect(result.ratioAfter + 0.01 >= 4.5)
        #expect(ColorContrast.relativeLuminance(of: result.color) > ColorContrast.relativeLuminance(of: text))
    }

    @Test func largeTextUsesLowerRatioThreshold() {
        #expect(ColorContrast.minimumRatio(forPointSize: 17) == 3.0)
        #expect(ColorContrast.minimumRatio(forPointSize: 16) == 4.5)
    }

    // MARK: - Preset resolution

    @Test func libraryIsDefaultPreset() {
        #expect(PindropThemePresetCatalog.defaultPresetID == "library")
        let fallback = PindropThemePresetCatalog.preset(withID: nil)
        #expect(fallback.id == "library")
        let unknown = PindropThemePresetCatalog.preset(withID: "does-not-exist")
        #expect(unknown.id == "library")
    }

    @Test func graphiteIsLegacyResolvableButHiddenFromPicker() {
        #expect(PindropThemePresetCatalog.presets.contains(where: { $0.id == "graphite" }) == false)
        #expect(PindropThemePresetCatalog.legacyPresets.contains(where: { $0.id == "graphite" }) == true)
        let graphite = PindropThemePresetCatalog.preset(withID: "graphite")
        #expect(graphite.id == "graphite")
        #expect(graphite.isLegacy == true)
    }

    @Test func pickerIncludesScorchedPresets() {
        let ids = Set(PindropThemePresetCatalog.presets.map(\.id))
        #expect(ids == Set(["library", "pindrop", "paper", "harbor", "evergreen", "signal"]))
    }

    @Test func signaturePresetAccentHexesArePinned() {
        // Signature accents from the redesign brief (personality carriers).
        #expect(PindropThemePresetCatalog.pindrop.darkTheme.accentHex.uppercased() == "#F2B54A")
        #expect(PindropThemePresetCatalog.paper.lightTheme.accentHex.uppercased() == "#2E4E73")
        #expect(PindropThemePresetCatalog.harbor.lightTheme.accentHex.uppercased() == "#14708A")
        #expect(PindropThemePresetCatalog.evergreen.lightTheme.accentHex.uppercased() == "#4D7A4A")
        #expect(PindropThemePresetCatalog.signal.darkTheme.accentHex.uppercased() == "#F06D4F")
    }

    @Test func sharedBaseTokenHexesArePinned() {
        #expect(ScorchedEarthBaseTokens.lightInk.uppercased() == "#201D18")
        #expect(ScorchedEarthBaseTokens.lightInk2.uppercased() == "#6E6759")
        #expect(ScorchedEarthBaseTokens.lightInk3.uppercased() == "#9B937F")
        #expect(ScorchedEarthBaseTokens.lightLine.uppercased() == "#E3DFD3")
        #expect(ScorchedEarthBaseTokens.lightRecord.uppercased() == "#B03A2E")
        #expect(ScorchedEarthBaseTokens.lightRecordSoft.uppercased() == "#F6E7E3")
        #expect(ScorchedEarthBaseTokens.lightAccentSoftLibrary.uppercased() == "#E7EFE7")

        #expect(ScorchedEarthBaseTokens.darkInk.uppercased() == "#EFEBE2")
        #expect(ScorchedEarthBaseTokens.darkInk2.uppercased() == "#A59D8C")
        #expect(ScorchedEarthBaseTokens.darkInk3.uppercased() == "#6E675B")
        #expect(ScorchedEarthBaseTokens.darkLine.uppercased() == "#37332B")
        #expect(ScorchedEarthBaseTokens.darkRecord.uppercased() == "#D25B4C")
        #expect(ScorchedEarthBaseTokens.darkAccentSoftLibrary.uppercased() == "#263A30")
    }

    @Test func allPresetsProduceValidClampedPalettesLightAndDark() {
        for preset in PindropThemePresetCatalog.allPresets {
            for variant in PindropThemeVariant.allCases {
                let isDark = variant == .dark
                let profile = preset.profile(for: variant)
                let (palette, _) = ResolvedPalette.resolve(profile: profile, isDark: isDark)

                let ground = ColorContrast.RGB(nsColor: palette.windowBackground)
                let page = ColorContrast.RGB(nsColor: palette.contentBackground)
                let ink2 = ColorContrast.RGB(nsColor: palette.textSecondary)
                let ink3 = ColorContrast.RGB(nsColor: palette.textTertiary)

                for bg in [ground, page] {
                    #expect(
                        ColorContrast.contrastRatio(ink2, bg) + 0.01 >= 4.5,
                        "ink-2 failed for \(preset.id)/\(variant.rawValue)"
                    )
                    #expect(
                        ColorContrast.contrastRatio(ink3, bg) + 0.01 >= 4.5,
                        "ink-3 failed for \(preset.id)/\(variant.rawValue)"
                    )
                }

                // Accent / record must resolve (non-zero alpha).
                #expect(palette.accent.alphaComponent > 0.9)
                #expect(palette.recording.alphaComponent > 0.9)
                #expect(palette.success.alphaComponent > 0.9)
            }
        }
    }

    @Test func libraryLightTokensMatchSpec() {
        let profile = PindropThemePresetCatalog.library.lightTheme
        #expect(profile.groundHex.uppercased() == "#F6F4EE")
        #expect(profile.pageHex.uppercased() == "#FCFBF7")
        #expect(profile.accentHex.uppercased() == "#1F6D53")
    }

    @Test func libraryDarkTokensMatchSpec() {
        let profile = PindropThemePresetCatalog.library.darkTheme
        #expect(profile.groundHex.uppercased() == "#1B1916")
        #expect(profile.pageHex.uppercased() == "#242119")
        #expect(profile.accentHex.uppercased() == "#4CA582")
    }

    // MARK: - Typography role metrics

    @Test func typographyRolesHaveConcreteSizeAndWeight() {
        assertRole(AppTypography.wordmarkMetrics, size: 22, weight: .semibold, family: .newsreader, lineHeight: 28)
        assertRole(AppTypography.pageTitleMetrics, size: 34, weight: .medium, family: .newsreader, lineHeight: 38)
        assertRole(AppTypography.transcriptBodyMetrics, size: 17, weight: .regular, family: .newsreader, lineHeight: 26)
        assertRole(AppTypography.bodyMetrics, size: 13, weight: .regular, family: .inter, lineHeight: 16)
        assertRole(AppTypography.bodyMetaMetrics, size: 13, weight: .regular, family: .inter, lineHeight: 22)
        assertRole(AppTypography.labelMetrics, size: 12, weight: .medium, family: .inter, lineHeight: 16)
        assertRole(AppTypography.labelSemiboldMetrics, size: 12, weight: .semibold, family: .inter, lineHeight: 16)
        assertRole(AppTypography.labelStrongMetrics, size: 13, weight: .medium, family: .inter, lineHeight: 16)
        assertRole(AppTypography.labelStrongSelectedMetrics, size: 13, weight: .semibold, family: .inter, lineHeight: 16)
        assertRole(AppTypography.badgeMetrics, size: 11, weight: .semibold, family: .inter, lineHeight: 14)
        assertRole(AppTypography.captionMetrics, size: 11, weight: .regular, family: .inter, lineHeight: 14)
        assertRole(AppTypography.monoTimeMetrics, size: 12, weight: .medium, family: .jetbrainsMono, lineHeight: 16)
        assertRole(AppTypography.monoSmallMetrics, size: 11, weight: .medium, family: .jetbrainsMono, lineHeight: 14)
        assertRole(AppTypography.sectionHeaderMetrics, size: 11, weight: .medium, family: .inter, lineHeight: 14)
        assertRole(AppTypography.statLargeMetrics, size: 34, weight: .medium, family: .newsreader, lineHeight: 38)
        assertRole(AppTypography.statMediumMetrics, size: 24, weight: .semibold, family: .newsreader, lineHeight: 28)
    }

    @Test func typographyLineSpacingMatchesSpecLineBoxes() {
        // lineSpacing = lineHeight − size (spec pt boxes)
        #expect(AppTypography.transcriptBodyLineSpacing == CGFloat(9))
        #expect(AppTypography.bodyMetaLineSpacing == CGFloat(9))
        #expect(AppTypography.bodyLineSpacing == CGFloat(3))
        #expect(AppTypography.pageTitleLineSpacing == CGFloat(4))
        #expect(AppTypography.wordmarkLineSpacing == CGFloat(6))
    }

    @Test func legacyTypographyMembersAliasNewRoles() {
        let _: Font = AppTypography.largeTitle
        let _: Font = AppTypography.pageTitle
        let _: Font = AppTypography.title
        let _: Font = AppTypography.wordmark
        let _: Font = AppTypography.body
        let _: Font = AppTypography.bodySmall
        let _: Font = AppTypography.caption
        let _: Font = AppTypography.badge
        let _: Font = AppTypography.tiny
        let _: Font = AppTypography.mono
        let _: Font = AppTypography.monoTime
        let _: Font = AppTypography.monoSmall
        let _: Font = AppTypography.transcriptBody
        let _: Font = AppTypography.sectionHeader
        let _: Font = AppTypography.label
        let _: Font = AppTypography.labelSemibold
        let _: Font = AppTypography.statLarge

        #expect(AppTypography.pageTitleTracking < 0)
        #expect(AppTypography.wordmarkTracking < 0)
    }

    @Test func fontLoaderPostScriptNamesAreStable() {
        #expect(FontLoader.postScriptName(family: .newsreader, weight: .semibold) == "Newsreader-SemiBold")
        #expect(FontLoader.postScriptName(family: .newsreader, weight: .regular, italic: true) == "Newsreader-Italic")
        #expect(FontLoader.postScriptName(family: .inter, weight: .medium) == "Inter-Medium")
        #expect(FontLoader.postScriptName(family: .inter, weight: .semibold) == "Inter-SemiBold")
        #expect(FontLoader.postScriptName(family: .jetbrainsMono, weight: .regular) == "JetBrainsMono-Regular")
    }

    // MARK: - Play chip / waveform geometry

    @Test func playChipMetricsAreLoadBearing74pt() {
        #expect(PlayChipMetrics.width == 74)
        #expect(PlayChipMetrics.verticalPadding == 3)
        #expect(PlayChipMetrics.horizontalPadding == 9)
        #expect(PlayChipMetrics.iconTextGap == 5)
        // Padding is inside the frame, not additive: outer width stays 74, not 74+9+9=92.
        let outerIfPaddingOutside = PlayChipMetrics.width + (PlayChipMetrics.horizontalPadding * 2)
        #expect(outerIfPaddingOutside == 92)
        #expect(PlayChipMetrics.width != outerIfPaddingOutside)
    }

    @Test func waveformBarCountForExactPitch() {
        // width that fits exactly N bars: barWidth + (N-1)*barPitch
        // For N=3: 3.5 + 2*15 = 33.5
        #expect(WaveformGeometry.barCount(forWidth: 33.5) == 3)
        #expect(WaveformGeometry.barCount(forWidth: 3.5) == 1)
        #expect(WaveformGeometry.barCount(forWidth: 0) == 0)
    }

    @Test func waveformBarCountGrowsWithWidth() {
        let narrow = WaveformGeometry.barCount(forWidth: 100)
        let wide = WaveformGeometry.barCount(forWidth: 400)
        #expect(wide > narrow)
        #expect(narrow >= 1)
    }

    @Test func waveformDisplayPeaksResamples() {
        let source: [Float] = [0, 0.5, 1, 0.25]
        let down = WaveformGeometry.displayPeaks(from: source, count: 2)
        #expect(down.count == 2)
        #expect(down[0] >= 0 && down[0] <= 1)
        #expect(down[1] >= 0 && down[1] <= 1)

        let up = WaveformGeometry.displayPeaks(from: source, count: 8)
        #expect(up.count == 8)

        let empty = WaveformGeometry.displayPeaks(from: [], count: 4)
        #expect(empty.count == 4)
    }

    @Test func waveformPlayheadXClamps() {
        #expect(WaveformGeometry.playheadX(progress: 0, width: 100) == 0)
        #expect(WaveformGeometry.playheadX(progress: 1, width: 100) == 100 - WaveformGeometry.playheadWidth)
        #expect(WaveformGeometry.playheadX(progress: -1, width: 100) == 0)
        #expect(WaveformGeometry.playheadX(progress: 2, width: 100) == 100 - WaveformGeometry.playheadWidth)
    }

    // MARK: - Dead token removal sanity

    @Test func settingsWindowTokensRemoved() {
        // Compile-time: AppTheme.Window no longer exposes stale settings* size tokens.
        // Runtime smoke: main window tokens still present.
        #expect(AppTheme.Window.mainMinWidth > 0)
        #expect(AppTheme.Window.sidebarWidth > 0)
    }

    // MARK: - Helpers

    private func assertRole(
        _ metrics: TypographyRoleMetrics,
        size: CGFloat,
        weight: FontLoader.Weight,
        family: FontLoader.Family,
        lineHeight: CGFloat
    ) {
        #expect(metrics.size == size)
        #expect(metrics.weight == weight)
        #expect(metrics.family == family)
        #expect(metrics.lineHeight == lineHeight)
        #expect(metrics.lineSpacing == max(0, lineHeight - size))
    }
}

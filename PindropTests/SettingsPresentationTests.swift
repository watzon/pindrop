//
//  SettingsPresentationTests.swift
//  PindropTests
//
//  Created on 2026-07-10.
//

import Foundation
import Testing
@testable import Pindrop

@Suite
struct SettingsPresentationTests {

    // MARK: - Retention picker labels

    @Test func retentionPickerOrderIsOff7_30Forever() {
        #expect(
            DictationRetentionPresentation.pickerOrder
                == [.off, .days7, .days30, .forever]
        )
    }

    @Test func retentionLabelsAreLocalizedEnglish() {
        let locale = Locale(identifier: "en")
        #expect(DictationRetentionPresentation.label(.off, locale: locale) == "Off")
        #expect(DictationRetentionPresentation.label(.days7, locale: locale) == "7 days")
        #expect(DictationRetentionPresentation.label(.days30, locale: locale) == "30 days")
        #expect(DictationRetentionPresentation.label(.forever, locale: locale) == "Forever")
    }

    // MARK: - Disk usage formatting

    @Test func diskUsageFormatsZeroAndSmallBytes() {
        #expect(DictationAudioDiskUsageFormatting.formattedByteCount(0) == "0 MB")
        #expect(DictationAudioDiskUsageFormatting.formattedByteCount(512) == "0 MB")
        // Non-zero sub-MB rounds up to 1 MB so the row never hides tiny files as 0.
        #expect(DictationAudioDiskUsageFormatting.formattedByteCount(2048) == "1 MB")
    }

    @Test func diskUsageFormatsMegabytesAndGigabytes() {
        let mb142 = Int64(142) * 1024 * 1024
        #expect(DictationAudioDiskUsageFormatting.formattedByteCount(mb142) == "142 MB")

        let gb1 = Int64(1000) * 1024 * 1024
        #expect(DictationAudioDiskUsageFormatting.formattedByteCount(gb1) == "1 GB")

        let gb32 = Int64(3200) * 1024 * 1024
        #expect(DictationAudioDiskUsageFormatting.formattedByteCount(gb32) == "3.2 GB")
    }

    @Test func snippetCountLabels() {
        let locale = Locale(identifier: "en")
        #expect(DictationAudioDiskUsageFormatting.snippetCountLabel(1, locale: locale) == "1 snippet")
        #expect(DictationAudioDiskUsageFormatting.snippetCountLabel(64, locale: locale) == "64 snippets")
    }

    @Test func diskUsageSummaryLine() {
        let locale = Locale(identifier: "en")
        let usage = DictationAudioDiskUsage(
            totalBytes: Int64(142) * 1024 * 1024,
            snippetCount: 64
        )
        #expect(
            DictationAudioDiskUsageFormatting.summaryLine(usage: usage, locale: locale)
                == "Audio on disk: 142 MB · 64 snippets"
        )
    }

    // MARK: - Theme preset chip ordering (legacy graphite)

    @Test func presetsForPickerIncludesSixCatalogPresets() {
        let list = SettingsThemePresetPresentation.presetsForPicker(selectedID: "library")
        #expect(list.count == PindropThemePresetCatalog.presets.count)
        #expect(list.map(\.id) == PindropThemePresetCatalog.presets.map(\.id))
        #expect(!list.contains(where: { $0.id == "graphite" }))
    }

    @Test func presetsForPickerAppendsLegacyGraphiteOnlyWhenSelected() {
        let without = SettingsThemePresetPresentation.presetsForPicker(selectedID: "library")
        #expect(!without.contains(where: { $0.id == "graphite" }))

        let withLegacy = SettingsThemePresetPresentation.presetsForPicker(selectedID: "graphite")
        #expect(withLegacy.contains(where: { $0.id == "graphite" }))
        #expect(withLegacy.count == PindropThemePresetCatalog.presets.count + 1)
        #expect(withLegacy.last?.id == "graphite")
    }

    @Test func shouldShowLegacyPresetOnlyWhileActive() {
        #expect(
            SettingsThemePresetPresentation.shouldShowLegacyPreset(
                legacyID: "graphite",
                selectedID: "graphite"
            )
        )
        #expect(
            !SettingsThemePresetPresentation.shouldShowLegacyPreset(
                legacyID: "graphite",
                selectedID: "library"
            )
        )
    }

    // MARK: - Speaker / MCP / hotkey helpers

    @Test func trainedCountFiltersZeroEvidence() {
        let count = SpeakerProfileSummaryPresentation.trainedCount(
            evidenceCounts: [3, 0, 1]
        )
        #expect(count == 2)
    }

    @Test func mcpEndpointUsesLoopbackAndPort() {
        #expect(MCPEndpointPresentation.endpointURL(port: 46337) == "http://127.0.0.1:46337/mcp")
    }

    @Test func hotkeyAggregateNoConflictLine() {
        let locale = Locale(identifier: "en")
        #expect(
            SettingsHotkeyConflictPresentation.aggregateStatus(
                statuses: [.noConflict, .noConflict],
                locale: locale
            ) == "No conflicts with system or app shortcuts."
        )
    }

    @Test func aboutVersionLineIncludesChannel() {
        #expect(
            SettingsAboutPresentation.versionLine(
                version: "0.10.0",
                build: "42",
                channel: "Release"
            ) == "0.10.0 (42) · Release"
        )
    }

    // MARK: - Log level filtering (Advanced pane → file sink)

    @Test func logLevelSeverityIsOrdered() {
        #expect(AppLogLevel.debug.severity < AppLogLevel.info.severity)
        #expect(AppLogLevel.info.severity < AppLogLevel.warning.severity)
        #expect(AppLogLevel.warning.severity < AppLogLevel.error.severity)
    }

    @Test func logLevelMinimumMapsSettingsNamesAndDefaultsToInfo() {
        #expect(AppLogLevel.minimum(fromSettingsName: "debug") == .debug)
        #expect(AppLogLevel.minimum(fromSettingsName: "info") == .info)
        #expect(AppLogLevel.minimum(fromSettingsName: "warning") == .warning)
        #expect(AppLogLevel.minimum(fromSettingsName: "error") == .error)
        #expect(AppLogLevel.minimum(fromSettingsName: nil) == .info)
        #expect(AppLogLevel.minimum(fromSettingsName: "bogus") == .info)
    }

    @Test func settingsLogLevelRoundTripsWithAppLogLevel() {
        for level in SettingsLogLevel.allCases {
            #expect(SettingsLogLevel.from(appLogLevel: level.appLogLevel) == level)
            #expect(AppLogLevel.minimum(fromSettingsName: level.rawValue) == level.appLogLevel)
        }
        #expect(SettingsLogLevel.userDefaultsKey == AppLogLevel.minimumPersistedLevelDefaultsKey)
    }

    @Test func logExportListsRegularFilesOnly() throws {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("pindrop-log-export-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }

        let fileA = temp.appendingPathComponent("a.log")
        let fileB = temp.appendingPathComponent("b.log")
        try "a".write(to: fileA, atomically: true, encoding: .utf8)
        try "b".write(to: fileB, atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(
            at: temp.appendingPathComponent("subdir", isDirectory: true),
            withIntermediateDirectories: true
        )

        let urls = SettingsLogExport.logFileURLs(in: temp)
        #expect(urls.map(\.lastPathComponent).sorted() == ["a.log", "b.log"])
    }

    // MARK: - Floating surface presentation

    @Test func orbRibbonPaletteUsesExactArtboardRemaps() {
        let library = OrbRibbonPalette.forPresetID("library")
        #expect(library.primaryHex == "#6FDCAF")
        #expect(library.secondaryHex == "#EFD9A8")
        #expect(library.glowHex == "#1F6D53")

        let pindrop = OrbRibbonPalette.forPresetID("pindrop")
        #expect(pindrop.primaryHex == "#F2B54A")
        #expect(pindrop.secondaryHex == "#F7E3BC")

        let harbor = OrbRibbonPalette.forPresetID("harbor")
        #expect(harbor.primaryHex == "#4FB3D1")
        #expect(harbor.secondaryHex == "#CFE9F0")
    }

    @Test func orbRibbonPaletteDerivesUnspecifiedPresetFromAccent() {
        // Derived presets follow the catalog's (contrast-tuned) accent, not the raw
        // artboard table, so the ribbon matches the rest of the themed UI.
        let signal = OrbRibbonPalette.forPresetID("signal")
        let catalogAccent = PindropThemePresetCatalog
            .profile(for: "signal", variant: .light)
            .accentHex
        #expect(signal.primaryHex == catalogAccent)
        #expect(signal.secondaryHex != signal.primaryHex)
        #expect(signal.glowHex == signal.primaryHex)
    }

    @Test func orbRibbonPaletteTracksVariantAccentForDerivedPresets() {
        for presetID in ["paper", "evergreen", "signal"] {
            for variant in [PindropThemeVariant.light, .dark] {
                let palette = OrbRibbonPalette.forPresetID(presetID, variant: variant)
                let catalogAccent = PindropThemePresetCatalog
                    .profile(for: presetID, variant: variant)
                    .accentHex
                #expect(palette.primaryHex == catalogAccent)
                #expect(palette.glowHex == catalogAccent)
            }
        }
    }

    @Test func toastVariantPresentationStringsAndSymbols() {
        let locale = Locale(identifier: "en")
        #expect(
            ToastVariantPresentation.trailingText(
                for: .inserted(wordCount: 32),
                locale: locale
            ) == "32 words"
        )
        #expect(ToastVariantPresentation.trailingText(for: .copied, locale: locale) == nil)
        #expect(
            ToastVariantPresentation.systemImage(for: .microphoneUnavailable, style: .error)
                == "exclamationmark.triangle"
        )
    }

    @Test func floatingIndicatorTimerFormatting() {
        #expect(FloatingIndicatorTimeFormatting.elapsed(-1) == "0:00")
        #expect(FloatingIndicatorTimeFormatting.elapsed(7.9) == "0:07")
        #expect(FloatingIndicatorTimeFormatting.elapsed(125) == "2:05")
    }
}

@Suite
struct OnboardingPresentationTests {
    @Test func progressHasOneDotPerStepIncludingDownload() {
        #expect(OnboardingProgressPresentation.dotCount == 7)
        #expect(OnboardingStep.allCases.count == 7)
    }

    @Test func progressActiveIndexMapsEveryStepInOrder() {
        let indices = OnboardingStep.allCases.map(OnboardingProgressPresentation.activeIndex)
        #expect(indices == [0, 1, 2, 3, 4, 5, 6])
        #expect(OnboardingProgressPresentation.activeIndex(for: .modelSelection) == 1)
        #expect(OnboardingProgressPresentation.activeIndex(for: .modelDownload) == 2)
    }
}

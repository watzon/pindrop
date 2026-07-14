//
//  SettingsStoreTests.swift
//  PindropTests
//
//  Created on 2026-01-25.
//

import AppKit
import Carbon
import Testing
@testable import Pindrop

@MainActor
@Suite
struct SettingsStoreTests {
    private func makeSettingsStore() -> SettingsStore {
        let settingsStore = SettingsStore()
        cleanup(settingsStore)
        return settingsStore
    }

    private func cleanup(_ settingsStore: SettingsStore) {
        settingsStore.resetAllSettings()
        try? settingsStore.deleteAPIEndpoint()
        try? settingsStore.deleteAPIKey()
        settingsStore.mentionTemplateOverridesJSON = SettingsStore.Defaults.mentionTemplateOverridesJSON
    }

    @Test func testSaveAndLoadSettings() {
        let settingsStore = makeSettingsStore()
        defer { cleanup(settingsStore) }

        settingsStore.selectedModel = "large-v3"
        #expect(settingsStore.selectedModel == "large-v3")

        settingsStore.selectedThemeMode = .dark
        settingsStore.lightThemePresetID = "paper"
        settingsStore.darkThemePresetID = "signal"
        #expect(settingsStore.selectedThemeMode == .dark)
        #expect(settingsStore.lightThemePresetID == "paper")
        #expect(settingsStore.darkThemePresetID == "signal")

        settingsStore.toggleHotkey = "⌘⇧A"
        #expect(settingsStore.toggleHotkey == "⌘⇧A")

        settingsStore.pushToTalkHotkey = "⌘⇧B"
        #expect(settingsStore.pushToTalkHotkey == "⌘⇧B")

        settingsStore.outputMode = "directInsert"
        #expect(settingsStore.outputMode == "directInsert")

        settingsStore.selectedAppLanguage = .simplifiedChinese
        #expect(settingsStore.selectedAppLanguage == .simplifiedChinese)

        settingsStore.aiEnhancementEnabled = true
        #expect(settingsStore.aiEnhancementEnabled)

        let newStore = SettingsStore()
        #expect(newStore.selectedModel == "large-v3")
        #expect(newStore.selectedThemeMode == .dark)
        #expect(newStore.lightThemePresetID == "paper")
        #expect(newStore.darkThemePresetID == "signal")
        #expect(newStore.toggleHotkey == "⌘⇧A")
        #expect(newStore.pushToTalkHotkey == "⌘⇧B")
        #expect(newStore.outputMode == "directInsert")
        #expect(newStore.selectedAppLanguage == .simplifiedChinese)
        #expect(newStore.aiEnhancementEnabled)

        settingsStore.selectedModel = "base"
        settingsStore.selectedThemeMode = .system
        settingsStore.lightThemePresetID = SettingsStore.Defaults.lightThemePresetID
        settingsStore.darkThemePresetID = SettingsStore.Defaults.darkThemePresetID
        settingsStore.toggleHotkey = "⌘⇧R"
        settingsStore.pushToTalkHotkey = "⌘⇧T"
        settingsStore.outputMode = "clipboard"
        settingsStore.aiEnhancementEnabled = false
    }

    @Test func testKeychainStorage() throws {
        let settingsStore = makeSettingsStore()
        defer { cleanup(settingsStore) }

        let testEndpoint = "https://api.openai.com/v1/chat/completions"
        let testKey = "sk-test-key-12345"

        try settingsStore.saveAPIEndpoint(testEndpoint)
        #expect(settingsStore.apiEndpoint == testEndpoint)

        try settingsStore.saveAPIKey(testKey)
        #expect(settingsStore.apiKey == testKey)

        let newStore = SettingsStore()
        #expect(newStore.apiEndpoint == testEndpoint)
        #expect(newStore.apiKey == testKey)

        try settingsStore.deleteAPIEndpoint()
        #expect(settingsStore.apiEndpoint == nil)

        try settingsStore.deleteAPIKey()
        #expect(settingsStore.apiKey == nil)

        let emptyStore = SettingsStore()
        #expect(emptyStore.apiEndpoint == nil)
        #expect(emptyStore.apiKey == nil)
    }

    @Test func testKeychainPersistence() throws {
        let settingsStore = makeSettingsStore()
        defer { cleanup(settingsStore) }

        try settingsStore.saveAPIEndpoint("https://api.example.com/v1")
        try settingsStore.saveAPIKey("key-12345")
        try settingsStore.saveAPIEndpoint("https://api.different.com/v2")
        try settingsStore.saveAPIKey("key-67890")

        #expect(settingsStore.apiEndpoint == "https://api.different.com/v2")
        #expect(settingsStore.apiKey == "key-67890")

        let newStore = SettingsStore()
        #expect(newStore.apiEndpoint == "https://api.different.com/v2")
        #expect(newStore.apiKey == "key-67890")
    }

    @Test func testCustomLocalProviderIsInferredFromOllamaEndpoint() throws {
        let settingsStore = makeSettingsStore()
        defer { cleanup(settingsStore) }

        try settingsStore.saveAPIEndpoint("http://localhost:11434/v1/chat/completions")

        #expect(settingsStore.currentAIProvider == .custom)
        #expect(settingsStore.currentCustomLocalProvider == .ollama)
        #expect(!settingsStore.requiresAPIKey(for: .custom))
    }

    @Test func testCustomProviderAPIKeysAreScopedBySubtype() throws {
        let settingsStore = makeSettingsStore()
        defer { cleanup(settingsStore) }

        try settingsStore.saveAPIKey("custom-key", for: .custom, customLocalProvider: .custom)
        try settingsStore.saveAPIKey("lmstudio-key", for: .custom, customLocalProvider: .lmStudio)

        #expect(settingsStore.loadAPIKey(for: .custom, customLocalProvider: .custom) == "custom-key")
        #expect(settingsStore.loadAPIKey(for: .custom, customLocalProvider: .lmStudio) == "lmstudio-key")
        #expect(settingsStore.loadAPIKey(for: .custom, customLocalProvider: .ollama) == nil)
    }

    @Test func testCustomProviderEndpointsAreScopedBySubtype() throws {
        let settingsStore = makeSettingsStore()
        defer { cleanup(settingsStore) }

        let groqLike = "https://api.groq.com/openai/v1/chat/completions"
        let ollamaLocal = "http://localhost:11434/v1/chat/completions"

        try settingsStore.saveAPIEndpoint(groqLike, for: .custom, customLocalProvider: .custom)
        try settingsStore.saveAPIEndpoint(ollamaLocal, for: .custom, customLocalProvider: .ollama)

        #expect(settingsStore.storedAPIEndpoint(forCustomLocalProvider: .custom) == groqLike)
        #expect(settingsStore.storedAPIEndpoint(forCustomLocalProvider: .ollama) == ollamaLocal)
        #expect(settingsStore.storedAPIEndpoint(forCustomLocalProvider: .lmStudio) == nil)
    }

    @Test func testSavingBlankAPIKeyDeletesStoredValue() throws {
        let settingsStore = makeSettingsStore()
        defer { cleanup(settingsStore) }

        try settingsStore.saveAPIKey("temporary-key", for: .openai)
        try settingsStore.saveAPIKey("   ", for: .openai)

        #expect(settingsStore.loadAPIKey(for: .openai) == nil)
    }

    @Test func testDefaultValues() {
        let store = makeSettingsStore()
        defer { cleanup(store) }

        #expect(store.selectedModel == SettingsStore.Defaults.selectedModel)
        #expect(store.selectedThemeMode == .system)
        #expect(store.lightThemePresetID == SettingsStore.Defaults.lightThemePresetID)
        #expect(store.darkThemePresetID == SettingsStore.Defaults.darkThemePresetID)
        #expect(store.toggleHotkey == SettingsStore.Defaults.Hotkeys.toggleHotkey)
        #expect(store.pushToTalkHotkey == SettingsStore.Defaults.Hotkeys.pushToTalkHotkey)
        #expect(store.outputMode == "clipboard")
        #expect(store.selectedAppLanguage == .automatic)
        #expect(!store.aiEnhancementEnabled)
        #expect(store.floatingIndicatorType == FloatingIndicatorType.orb.rawValue)
        #expect(store.apiEndpoint == nil)
        #expect(store.apiKey == nil)
        #expect(!store.launchWithoutShowingWindow)
        #expect(!store.telemetryEnabled)
        #expect(store.telemetryConsentPromptVersion == 0)
    }

    @Test func testLaunchWithoutShowingWindowDefaultsOffAndPersists() {
        let settingsStore = makeSettingsStore()
        defer { cleanup(settingsStore) }

        #expect(!settingsStore.launchWithoutShowingWindow)

        settingsStore.launchWithoutShowingWindow = true
        #expect(settingsStore.launchWithoutShowingWindow)

        let reloaded = SettingsStore()
        #expect(reloaded.launchWithoutShowingWindow)

        settingsStore.resetAllSettings()
        #expect(!settingsStore.launchWithoutShowingWindow)
    }

    @Test func testCancelOperationHotkeyPersistsAndAppearsInAssignments() {
        let settingsStore = makeSettingsStore()
        defer { cleanup(settingsStore) }

        #expect(settingsStore.cancelOperationHotkey == "")
        #expect(settingsStore.cancelOperationHotkeyCode == 0)
        #expect(settingsStore.cancelOperationHotkeyModifiers == 0)
        #expect(settingsStore.configuredHotkeyAssignments().allSatisfy { $0.slot != .cancelOperation })

        settingsStore.updateCancelOperationHotkey("⌘.", keyCode: Int(kVK_ANSI_Period), modifiers: Int(cmdKey))

        #expect(settingsStore.cancelOperationHotkey == "⌘.")
        #expect(settingsStore.cancelOperationHotkeyCode == Int(kVK_ANSI_Period))
        #expect(settingsStore.cancelOperationHotkeyModifiers == Int(cmdKey))

        let assignment = settingsStore.configuredHotkeyAssignments().first { $0.slot == .cancelOperation }
        #expect(assignment?.keyCode == UInt32(kVK_ANSI_Period))
        #expect(assignment?.modifiers == UInt32(cmdKey))

        settingsStore.updateCancelOperationHotkey("", keyCode: 0, modifiers: 0)
        #expect(settingsStore.configuredHotkeyAssignments().allSatisfy { $0.slot != .cancelOperation })

        settingsStore.updateCancelOperationHotkey("⌘.", keyCode: Int(kVK_ANSI_Period), modifiers: Int(cmdKey))
        settingsStore.resetAllSettings()
        #expect(settingsStore.cancelOperationHotkey == SettingsStore.Defaults.Hotkeys.cancelOperationHotkey)
        #expect(settingsStore.cancelOperationHotkeyCode == SettingsStore.Defaults.Hotkeys.cancelOperationHotkeyCode)
        #expect(settingsStore.cancelOperationHotkeyModifiers == SettingsStore.Defaults.Hotkeys.cancelOperationHotkeyModifiers)
    }

    @Test func testThemeModeBridgesStoredValue() {
        let settingsStore = makeSettingsStore()
        defer { cleanup(settingsStore) }

        settingsStore.selectedThemeMode = .light

        #expect(settingsStore.themeMode == PindropThemeMode.light.rawValue)
        #expect(settingsStore.selectedThemeMode == .light)
    }

    @Test func testSelectedAppLanguageBridgesStoredValue() {
        let settingsStore = makeSettingsStore()
        defer { cleanup(settingsStore) }

        settingsStore.selectedAppLanguage = .german

        #expect(settingsStore.selectedLanguage == AppLanguage.german.rawValue)
        #expect(settingsStore.selectedAppLanguage == .german)
    }

    @Test func testHindiAndMalayalamAreSelectableDictationLanguages() {
        #expect(AppLanguage.hindi.rawValue == "hi")
        #expect(AppLanguage.malayalam.rawValue == "ml")
        #expect(AppLanguage.hindi.whisperLanguageCode == "hi")
        #expect(AppLanguage.malayalam.whisperLanguageCode == "ml")
        #expect(AppLanguage.hindi.isSelectable)
        #expect(AppLanguage.malayalam.isSelectable)
        #expect(AppLanguage.allCases.contains(.hindi))
        #expect(AppLanguage.allCases.contains(.malayalam))

        // Interface locale already ships Hindi; dictation language remains a separate enum.
        #expect(AppLocale.allCases.contains(.hindi))
        #expect(!AppLocale.allCases.map(\.rawValue).contains(AppLanguage.malayalam.rawValue))
    }

    @Test func testSelectedAppLanguagePersistsHindiAndMalayalam() {
        let settingsStore = makeSettingsStore()
        defer { cleanup(settingsStore) }

        settingsStore.selectedAppLanguage = .hindi
        #expect(settingsStore.selectedLanguage == "hi")
        #expect(settingsStore.selectedAppLanguage == .hindi)

        settingsStore.selectedAppLanguage = .malayalam
        #expect(settingsStore.selectedLanguage == "ml")
        #expect(settingsStore.selectedAppLanguage == .malayalam)

        let reloaded = SettingsStore()
        #expect(reloaded.selectedAppLanguage == .malayalam)
    }

    @Test func testSelectedAppLocaleBridgesStoredValue() {
        let settingsStore = makeSettingsStore()
        defer { cleanup(settingsStore) }

        settingsStore.selectedAppLocale = .arabic

        #expect(settingsStore.selectedAppLocaleRawValue == AppLocale.arabic.rawValue)
        #expect(settingsStore.selectedAppLocale == .arabic)
    }

    @Test func testAppLocaleIncludesShippedLocalesBeyondDictationList() {
        #expect(AppLocale.allCases.contains(.arabic))
        #expect(AppLocale.allCases.contains(.traditionalChinese))
        #expect(!AppLanguage.allCases.map(\.rawValue).contains(AppLocale.arabic.rawValue))
    }

    @Test func testAppLocaleMapsRTLLayoutDirections() {
        #expect(AppLocale.arabic.layoutDirection == .rightToLeft)
        #expect(AppLocale.hebrew.layoutDirection == .rightToLeft)
    }

    @Test func testAppLocaleMapsLTRLayoutDirections() {
        #expect(AppLocale.english.layoutDirection == .leftToRight)
        #expect(AppLocale.german.layoutDirection == .leftToRight)
    }

    @Test func testLocalizedResolvesSelectedLocaleStrings() {
        #expect(localized("Settings", locale: Locale(identifier: "de")) == "Einstellungen")
        #expect(localized("Settings", locale: Locale(identifier: "tr")) == "Ayarlar")
        #expect(localized("Settings", locale: Locale(identifier: "pl")) == "Ustawienia")
    }

    @Test func testPolishIsShippedAsInterfaceLocaleAndDictationLanguage() {
        #expect(AppLocale.allCases.contains(.polish))
        #expect(AppLanguage.allCases.contains(.polish))
        #expect(AppLanguage.polish.rawValue == "pl")
        #expect(AppLanguage.polish.whisperLanguageCode == "pl")
        #expect(AppLanguage.polish.isSelectable)
        #expect(AppLocale.polish.layoutDirection == .leftToRight)
        #expect(AppLocale.polish.rawValue == AppLanguage.polish.rawValue)
    }

    @Test func testSelectedAppLanguageSupportsPolish() {
        let settingsStore = makeSettingsStore()
        defer { cleanup(settingsStore) }

        settingsStore.selectedAppLanguage = .polish
        settingsStore.selectedAppLocale = .polish

        #expect(settingsStore.selectedLanguage == AppLanguage.polish.rawValue)
        #expect(settingsStore.selectedAppLanguage == .polish)
        #expect(settingsStore.selectedAppLocale == .polish)
        #expect(settingsStore.selectedAppLocaleRawValue == AppLocale.polish.rawValue)
    }

    @Test func testThemeModeFallsBackToSystemForUnknownValue() {
        let settingsStore = makeSettingsStore()
        defer { cleanup(settingsStore) }

        settingsStore.themeMode = "mystery"

        #expect(settingsStore.selectedThemeMode == .system)
    }

    @Test func testSelectedThemePresetsResolveCatalogEntries() {
        let settingsStore = makeSettingsStore()
        defer { cleanup(settingsStore) }

        settingsStore.lightThemePresetID = "paper"
        settingsStore.darkThemePresetID = "signal"

        #expect(settingsStore.selectedLightThemePreset.id == "paper")
        #expect(settingsStore.selectedDarkThemePreset.id == "signal")
    }

    @Test func testThemePresetFallsBackToDefaultForUnknownPresetID() {
        let settingsStore = makeSettingsStore()
        defer { cleanup(settingsStore) }

        settingsStore.lightThemePresetID = "unknown"
        settingsStore.darkThemePresetID = "unknown"

        #expect(settingsStore.selectedLightThemePreset.id == PindropThemePresetCatalog.defaultPresetID)
        #expect(settingsStore.selectedDarkThemePreset.id == PindropThemePresetCatalog.defaultPresetID)
    }

    @Test func testThemeModeMapsToAppKitAppearance() {
        #expect(PindropThemeMode.system.appKitAppearanceName == nil)
        #expect(PindropThemeMode.light.appKitAppearanceName == .aqua)
        #expect(PindropThemeMode.dark.appKitAppearanceName == .darkAqua)
    }

    @Test func testResetAllSettingsResetsThemeSettings() {
        let settingsStore = makeSettingsStore()
        defer { cleanup(settingsStore) }

        settingsStore.selectedThemeMode = .dark
        settingsStore.lightThemePresetID = "paper"
        settingsStore.darkThemePresetID = "signal"

        settingsStore.resetAllSettings()

        #expect(settingsStore.selectedThemeMode == .system)
        #expect(settingsStore.lightThemePresetID == SettingsStore.Defaults.lightThemePresetID)
        #expect(settingsStore.darkThemePresetID == SettingsStore.Defaults.darkThemePresetID)
    }

    @Test func testSelectedFloatingIndicatorTypeBridgesStoredValue() {
        let settingsStore = makeSettingsStore()
        defer { cleanup(settingsStore) }

        settingsStore.selectedFloatingIndicatorType = .pill

        #expect(settingsStore.floatingIndicatorType == FloatingIndicatorType.pill.rawValue)
        #expect(settingsStore.selectedFloatingIndicatorType == .pill)
    }

    @Test func testSelectedFloatingIndicatorTypeFallsBackToOrbForUnknownValue() {
        let settingsStore = makeSettingsStore()
        defer { cleanup(settingsStore) }

        settingsStore.floatingIndicatorType = "unknown"

        #expect(settingsStore.selectedFloatingIndicatorType == .orb)
    }

    @Test func testSelectedFloatingIndicatorTypeMigratesRetiredDotToOrb() {
        let settingsStore = makeSettingsStore()
        defer { cleanup(settingsStore) }

        settingsStore.floatingIndicatorType = "dot"

        #expect(settingsStore.selectedFloatingIndicatorType == .orb)
    }

    @Test func testSelectedFloatingIndicatorTypePreservesNotchAndBubble() {
        let settingsStore = makeSettingsStore()
        defer { cleanup(settingsStore) }

        settingsStore.selectedFloatingIndicatorType = .notch
        #expect(settingsStore.floatingIndicatorType == FloatingIndicatorType.notch.rawValue)
        #expect(settingsStore.selectedFloatingIndicatorType == .notch)
        #expect(!settingsStore.selectedFloatingIndicatorType.isAlwaysOn)

        settingsStore.selectedFloatingIndicatorType = .bubble
        #expect(settingsStore.floatingIndicatorType == FloatingIndicatorType.bubble.rawValue)
        #expect(settingsStore.selectedFloatingIndicatorType == .bubble)
        #expect(!settingsStore.selectedFloatingIndicatorType.isAlwaysOn)
    }

    @Test func testPillFloatingIndicatorOffsetBridgesStoredValue() {
        let settingsStore = makeSettingsStore()
        defer { cleanup(settingsStore) }

        settingsStore.pillFloatingIndicatorOffset = CGSize(width: 42, height: -18)

        #expect(settingsStore.pillFloatingIndicatorOffsetX == 42)
        #expect(settingsStore.pillFloatingIndicatorOffsetY == -18)
        #expect(settingsStore.pillFloatingIndicatorOffset.width == 42)
        #expect(settingsStore.pillFloatingIndicatorOffset.height == -18)
    }

    @Test func testSwitchingAwayFromPillResetsStoredPillOffset() {
        let settingsStore = makeSettingsStore()
        defer { cleanup(settingsStore) }

        settingsStore.selectedFloatingIndicatorType = .pill
        settingsStore.pillFloatingIndicatorOffset = CGSize(width: 36, height: 12)

        settingsStore.selectedFloatingIndicatorType = .orb

        #expect(settingsStore.pillFloatingIndicatorOffset.width == 0)
        #expect(settingsStore.pillFloatingIndicatorOffset.height == 0)
    }

    @Test func testVibeDefaultsAndRuntimeState() {
        let store = makeSettingsStore()
        defer { cleanup(store) }

        #expect(store.vibeLiveSessionEnabled)
        #expect(store.vibeRuntimeState == .degraded)
        #expect(store.vibeRuntimeDetail == "Vibe mode is disabled.")
    }

    @Test func testUpdateVibeRuntimeState() {
        let settingsStore = makeSettingsStore()
        defer { cleanup(settingsStore) }

        settingsStore.updateVibeRuntimeState(.ready, detail: "Live session context active in Cursor.")

        #expect(settingsStore.vibeRuntimeState == .ready)
        #expect(settingsStore.vibeRuntimeDetail == "Live session context active in Cursor.")
    }

    @Test func testResetAllSettingsResetsVibeRuntimeState() {
        let settingsStore = makeSettingsStore()
        defer { cleanup(settingsStore) }

        settingsStore.vibeLiveSessionEnabled = false
        settingsStore.updateVibeRuntimeState(.ready, detail: "Live session context active in Cursor.")

        settingsStore.resetAllSettings()

        #expect(settingsStore.vibeLiveSessionEnabled)
        #expect(settingsStore.vibeRuntimeState == .degraded)
        #expect(settingsStore.vibeRuntimeDetail == "Vibe mode is disabled.")
    }

    @Test func testResolveMentionFormattingUsesTerminalProviderDefaultTemplate() {
        let settingsStore = makeSettingsStore()
        defer { cleanup(settingsStore) }

        let resolved = settingsStore.resolveMentionFormatting(
            editorBundleIdentifier: "com.microsoft.VSCode",
            terminalProviderIdentifier: "codex",
            adapterDefaultTemplate: "@{path}",
            adapterDefaultPrefix: "@"
        )

        #expect(resolved.mentionTemplate == "[@{path}]({path})")
        #expect(resolved.mentionPrefix == "@")
    }

    @Test func testResolveMentionFormattingPrefersProviderOverrideOverEditorOverride() {
        let settingsStore = makeSettingsStore()
        defer { cleanup(settingsStore) }

        settingsStore.setMentionTemplateOverride("/{path}", for: "provider:codex")
        settingsStore.setMentionTemplateOverride("@{path}", for: "editor:com.microsoft.vscode")

        let resolved = settingsStore.resolveMentionFormatting(
            editorBundleIdentifier: "com.microsoft.VSCode",
            terminalProviderIdentifier: "codex",
            adapterDefaultTemplate: "#{path}",
            adapterDefaultPrefix: "#"
        )

        #expect(resolved.mentionTemplate == "/{path}")
        #expect(resolved.mentionPrefix == "/")
    }

    @Test func testSetMentionTemplateOverrideRejectsInvalidTemplate() {
        let settingsStore = makeSettingsStore()
        defer { cleanup(settingsStore) }

        settingsStore.setMentionTemplateOverride("not-a-template", for: "provider:codex")
        #expect(settingsStore.mentionTemplateOverride(for: "provider:codex") == nil)
    }

    @Test func testKeychainErrorHandling() {
        let settingsStore = makeSettingsStore()
        defer { cleanup(settingsStore) }

        do {
            try settingsStore.deleteAPIEndpoint()
            try settingsStore.deleteAPIKey()
            try settingsStore.deleteAPIEndpoint()
            try settingsStore.deleteAPIKey()
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func testObservableUpdates() async throws {
        let settingsStore = makeSettingsStore()
        defer { cleanup(settingsStore) }

        let task = Task { @MainActor in
            settingsStore.selectedModel = "tiny"
            #expect(settingsStore.selectedModel == "tiny")

            try settingsStore.saveAPIEndpoint("https://test.com")
            #expect(settingsStore.apiEndpoint == "https://test.com")
        }

        try await task.value
    }
}

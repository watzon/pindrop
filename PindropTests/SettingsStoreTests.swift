//
//  SettingsStoreTests.swift
//  PindropTests
//
//  Created on 2026-01-25.
//

import AppKit
import Testing
@testable import Pindrop
#if canImport(PindropSharedSchema)
import PindropSharedSchema
#endif
#if canImport(PindropSharedUITheme)
import PindropSharedUITheme
#endif
#if canImport(PindropSharedNavigation)
import PindropSharedNavigation
#endif
#if canImport(PindropSharedAISettings)
import PindropSharedAISettings
#endif
#if canImport(PindropSharedUIWorkspace)
import PindropSharedUIWorkspace
#endif

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
        settingsStore.mentionTemplateOverridesJSON = SettingsDefaults.shared.mentionTemplateOverridesJSON
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
        settingsStore.lightThemePresetID = SettingsDefaults.shared.lightThemePresetID
        settingsStore.darkThemePresetID = SettingsDefaults.shared.darkThemePresetID
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

        #expect(store.selectedModel == SettingsDefaults.shared.selectedModel)
        #expect(store.selectedThemeMode == .system)
        #expect(store.lightThemePresetID == SettingsDefaults.shared.lightThemePresetID)
        #expect(store.darkThemePresetID == SettingsDefaults.shared.darkThemePresetID)
        #expect(store.toggleHotkey == SettingsDefaults.Hotkeys.shared.toggleHotkey)
        #expect(store.pushToTalkHotkey == SettingsDefaults.Hotkeys.shared.pushToTalkHotkey)
        #expect(store.outputMode == "clipboard")
        #expect(store.selectedAppLanguage == .automatic)
        #expect(!store.aiEnhancementEnabled)
        #expect(store.floatingIndicatorEnabled)
        #expect(store.floatingIndicatorType == Pindrop.FloatingIndicatorType.pill.rawValue)
        #expect(store.apiEndpoint == nil)
        #expect(store.apiKey == nil)
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

        settingsStore.selectedAppLanguage = Pindrop.AppLanguage.german

        #expect(settingsStore.selectedLanguage == Pindrop.AppLanguage.german.rawValue)
        #expect(settingsStore.selectedAppLanguage == .german)
    }

    @Test func testLocalizedResolvesSelectedLocaleStrings() {
        #expect(localized("Settings", locale: Locale(identifier: "de")) == "Einstellungen")
        #expect(localized("Settings", locale: Locale(identifier: "tr")) == "Ayarlar")
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

    @Test func testThemeCatalogBridgesSharedPresetDefinitions() {
        let presetIDs = Set(PindropThemePresetCatalog.presets.map(\.id))

        #expect(presetIDs.contains(PindropThemePresetCatalog.defaultPresetID))
        #expect(presetIDs.contains("paper"))
        #expect(presetIDs.contains("signal"))
    }

    @Test func testThemeBridgeResolvesSharedThemeAndCapabilities() {
        let settingsStore = makeSettingsStore()
        defer { cleanup(settingsStore) }

        UserDefaults.standard.set(PindropThemeMode.system.rawValue, forKey: PindropThemeStorageKeys.themeMode)
        UserDefaults.standard.set("paper", forKey: PindropThemeStorageKeys.lightThemePresetID)
        UserDefaults.standard.set("signal", forKey: PindropThemeStorageKeys.darkThemePresetID)

        #if canImport(PindropSharedUITheme)
        PindropThemeBridge.invalidateCache()
        let lightTheme = PindropThemeBridge.resolveTheme(systemVariant: .light)
        let darkTheme = PindropThemeBridge.resolveTheme(systemVariant: .dark)

        #expect(lightTheme.selectedPreset.id == "paper")
        #expect(darkTheme.selectedPreset.id == "signal")
        #expect(lightTheme.adaptedSidebarTreatment == .translucent)
        #expect(darkTheme.adaptedOverlayTreatment == .blurred)
        #endif
    }

    @Test func testSettingsTabSearchUsesSharedShellDefinitions() {
        #expect(SettingsTab.theme.matches("palette"))
        #expect(!SettingsTab.about.matches("palette"))
    }

    @Test func testAISettingsPresenterSharesValidationAndPresetRules() {
        #if canImport(PindropSharedAISettings)
        let state = AIEnhancementPresenter.shared.present(
            draft: AIEnhancementDraft(
                selectedProvider: .custom,
                selectedCustomProvider: .ollama,
                apiKey: "",
                selectedModel: "",
                customModel: "",
                enhancementPrompt: "Prompt",
                noteEnhancementPrompt: "Notes",
                selectedPromptType: .transcription,
                selectedPresetId: "builtin",
                customEndpointText: "http://localhost:11434/v1/chat/completions",
                availableModels: [],
                modelErrorMessage: nil,
                isLoadingModels: false,
                aiEnhancementEnabled: true
            ),
            presets: [
                PromptPresetSnapshot(
                    id: "builtin",
                    name: "Built In",
                    prompt: "Prompt",
                    isBuiltIn: true,
                    sortOrder: 0
                )
            ]
        )

        #expect(state.isApiKeyOptional)
        #expect(!state.canSave)
        #expect(state.selectedPresetId == "builtin")
        #expect(state.isBuiltInPresetSelected)
        #expect(state.isSelectedPromptReadOnly)
        #endif
    }

    @Test func testPromptPresetPresenterSharesGroupingAndValidation() {
        #if canImport(PindropSharedAISettings)
        let state = PromptPresetPresenter.shared.present(
            presets: [
                PromptPresetSnapshot(id: "builtin", name: "Built In", prompt: "One", isBuiltIn: true, sortOrder: 0),
                PromptPresetSnapshot(id: "custom", name: "Custom", prompt: "Two", isBuiltIn: false, sortOrder: 1),
            ],
            newName: "New",
            newPrompt: "Prompt",
            editingPresetId: "custom",
            editName: "Edited",
            editPrompt: "Updated"
        )

        #expect(state.builtInPresetIds == ["builtin"])
        #expect(state.customPresetIds == ["custom"])
        #expect(state.canCreatePreset)
        #expect(state.canSaveEditingPreset)
        #endif
    }

    @Test func testSharedShellBrowseSelectsFirstVisibleTab() {
        #if canImport(PindropSharedNavigation)
        let browseState = SettingsShell.shared.browse(
            query: "palette",
            selectedSection: SettingsSection.general,
            initialSection: SettingsSection.general
        )

        #expect(browseState.selectedSection == .theme)
        #expect(browseState.matchCount == 1)
        #endif
    }

    @Test func testMainWorkspaceNavigatorRoutesSettingsSelection() {
        #if canImport(PindropSharedNavigation)
        let state = MainWorkspaceNavigator.shared.navigateToSettings(
            currentState: MainWorkspaceNavigator.shared.initialState(),
            section: .hotkeys
        )

        #expect(state.selectedNavigationItem == .settings)
        #expect(state.selectedSettingsSection == .hotkeys)
        #endif
    }

    @Test func testDashboardPresenterSharesGreetingAndStats() {
        #if canImport(PindropSharedUIWorkspace)
        let state = DashboardPresenter.shared.present(
            records: [
                DashboardRecordSnapshot(text: "one two three", durationSeconds: 30),
                DashboardRecordSnapshot(text: "four five", durationSeconds: 30),
            ],
            currentHour: 9,
            hasDismissedHotkeyReminder: false
        )

        #expect(state.greetingKey == "Good morning")
        #expect(state.totalSessions == 2)
        #expect(state.totalWords == 5)
        #expect(state.shouldShowHotkeyReminder)
        #endif
    }

    @Test func testMediaLibraryPresenterFiltersAndSortsRecords() {
        #if canImport(PindropSharedUIWorkspace)
        let state = MediaLibraryPresenter.shared.browse(
            folders: [
                MediaFolderSnapshot(id: "folder-a", name: "Calls", itemCount: 1),
                MediaFolderSnapshot(id: "folder-b", name: "Meetings", itemCount: 1),
            ],
            records: [
                MediaRecordSnapshot(
                    id: "record-older",
                    folderId: nil,
                    timestampEpochMillis: 1,
                    searchText: "planning session",
                    sortName: "Planning Session"
                ),
                MediaRecordSnapshot(
                    id: "record-newer",
                    folderId: nil,
                    timestampEpochMillis: 2,
                    searchText: "planning follow up",
                    sortName: "Planning Follow Up"
                ),
            ],
            selectedFolderId: nil,
            searchText: "planning",
            sortMode: .newest
        )

        #expect(state.visibleRecordIds == ["record-newer", "record-older"])
        #expect(state.emptyStateKind == .none)
        #endif
    }

    @Test func testHistoryPresenterBuildsSectionsAndLoadingState() {
        #if canImport(PindropSharedUIWorkspace)
        let now: Int64 = 1_700_000_000_000
        let state = HistoryPresenter.shared.present(
            records: [
                HistoryRecordSnapshot(id: "today", timestampEpochMillis: now),
                HistoryRecordSnapshot(id: "yesterday", timestampEpochMillis: now - 86_400_000),
                HistoryRecordSnapshot(id: "older", timestampEpochMillis: now - 172_800_000),
            ],
            totalTranscriptionsCount: 3,
            searchText: "",
            selectedRecordId: "yesterday",
            hasLoadedInitialPage: true,
            isLoadingPage: false,
            errorMessage: nil,
            nowEpochMillis: now,
            timeZoneOffsetMinutes: 0
        )

        #expect(state.contentStateKind == .populated)
        #expect(state.selectedRecordId == "yesterday")
        #expect(state.sections.count == 3)
        #expect(state.sections[0].kind == .today)
        #expect(state.sections[1].kind == .yesterday)
        #expect(state.sections[2].kind == .date)
        #endif
    }

    @Test func testDictionaryPresenterSharesOrderingAndFormValidation() {
        #if canImport(PindropSharedUIWorkspace)
        let state = DictionaryPresenter.shared.present(
            selectedSection: .replacements,
            replacements: [
                ReplacementEntrySnapshot(id: "second", originals: ["beta"], replacement: "B", sortOrder: 2),
                ReplacementEntrySnapshot(id: "first", originals: ["alpha"], replacement: "A", sortOrder: 1),
            ],
            vocabularyWords: [
                VocabularyWordSnapshot(id: "vocabulary", word: "Zebra"),
            ],
            primaryInput: "source",
            secondaryInput: "target",
            errorMessage: nil
        )

        #expect(state.totalItemCount == 3)
        #expect(state.visibleReplacementIds == ["first", "second"])
        #expect(state.canAdd)
        #expect(state.contentStateKind == .populated)
        #endif
    }

    @Test func testNotesPresenterSharesFilteringAndEmptyState() {
        #if canImport(PindropSharedUIWorkspace)
        let state = NotesPresenter.shared.present(
            notes: [
                NoteSnapshot(
                    id: "note-1",
                    title: "Meeting Notes",
                    content: "Quarterly planning session",
                    tags: ["planning"],
                    updatedAtEpochMillis: 20
                ),
                NoteSnapshot(
                    id: "note-2",
                    title: "Ideas",
                    content: "Ship desktop rewrite",
                    tags: ["product"],
                    updatedAtEpochMillis: 10
                ),
            ],
            searchText: "quarterly",
            sortOrder: .descending,
            selectedNoteId: "note-2",
            errorMessage: nil
        )

        #expect(state.visibleNoteIds == ["note-1"])
        #expect(state.selectedNoteId == nil)
        #expect(state.contentStateKind == .populated)

        let emptyState = NotesPresenter.shared.present(
            notes: [],
            searchText: "missing",
            sortOrder: .ascending,
            selectedNoteId: nil,
            errorMessage: nil
        )

        #expect(emptyState.contentStateKind == .emptySearch)
        #endif
    }

    @Test func testModelsPresenterSharesBrowseState() {
        #if canImport(PindropSharedUIWorkspace)
        let state = ModelsPresenter.shared.browse(
            models: [
                ModelCatalogEntrySnapshot(
                    id: "recommended",
                    name: "recommended",
                    displayName: "Recommended Local",
                    description: "fast local model",
                    providerName: "WhisperKit",
                    isLocal: true,
                    isRecommended: true,
                    availability: "available"
                ),
                ModelCatalogEntrySnapshot(
                    id: "cloud",
                    name: "cloud",
                    displayName: "Cloud Model",
                    description: "remote model",
                    providerName: "OpenAI",
                    isLocal: false,
                    isRecommended: false,
                    availability: "available"
                ),
            ],
            selectedFilter: .recommended,
            searchText: ""
        )

        #expect(state.effectiveFilter == .recommended)
        #expect(state.visibleModelIds == ["recommended"])
        #expect(state.contentStateKind == .populated)
        #endif
    }

    @Test func testTranscribeLibraryPresenterSharesEmptyStateAndActions() {
        #if canImport(PindropSharedUIWorkspace)
        let browseState = MediaLibraryBrowseState(
            trimmedSearchText: "",
            selectedFolderId: "folder-1",
            visibleFolderIds: [],
            visibleRecordIds: [],
            filteredFolderCount: 0,
            filteredRecordCount: 0,
            totalRecordCountForSelectedFolder: 0,
            emptyStateKind: .folderEmpty
        )
        let state = TranscribeLibraryPresenter.shared.present(
            selectedFolderId: "folder-1",
            selectedFolderName: "Calls",
            draftLink: " https://example.com/video ",
            librarySearchText: "",
            browseState: browseState
        )

        #expect(state.shouldShowBackButton)
        #expect(state.canSubmitDraftLink)
        #expect(state.shouldShowLibraryEmptyState)
        #expect(state.emptyStateTitleKey == "No items in %@")
        #expect(state.emptyStateMessageKey == "Import or transcribe media while this folder is selected to save items here.")
        #endif
    }

    @Test func testResetAllSettingsResetsThemeSettings() {
        let settingsStore = makeSettingsStore()
        defer { cleanup(settingsStore) }

        settingsStore.selectedThemeMode = .dark
        settingsStore.lightThemePresetID = "paper"
        settingsStore.darkThemePresetID = "signal"

        settingsStore.resetAllSettings()

        #expect(settingsStore.selectedThemeMode == .system)
        #expect(settingsStore.lightThemePresetID == SettingsDefaults.shared.lightThemePresetID)
        #expect(settingsStore.darkThemePresetID == SettingsDefaults.shared.darkThemePresetID)
    }

    @Test func testSelectedFloatingIndicatorTypeBridgesStoredValue() {
        let settingsStore = makeSettingsStore()
        defer { cleanup(settingsStore) }

        settingsStore.selectedFloatingIndicatorType = .notch

        #expect(settingsStore.floatingIndicatorType == Pindrop.FloatingIndicatorType.notch.rawValue)
        #expect(settingsStore.selectedFloatingIndicatorType == .notch)
    }

    @Test func testSelectedFloatingIndicatorTypeFallsBackToPillForUnknownValue() {
        let settingsStore = makeSettingsStore()
        defer { cleanup(settingsStore) }

        settingsStore.floatingIndicatorType = "unknown"

        #expect(settingsStore.selectedFloatingIndicatorType == .pill)
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

        settingsStore.selectedFloatingIndicatorType = .bubble

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

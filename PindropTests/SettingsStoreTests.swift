//
//  SettingsStoreTests.swift
//  PindropTests
//
//  Created on 2026-01-25.
//

import XCTest
@testable import Pindrop

@MainActor
final class SettingsStoreTests: XCTestCase {
    
    var settingsStore: SettingsStore!
    
    override func setUp() async throws {
        try await super.setUp()
        settingsStore = SettingsStore()
        settingsStore.resetAllSettings()
        
        try? settingsStore.deleteAPIEndpoint()
        try? settingsStore.deleteAPIKey()
        settingsStore.mentionTemplateOverridesJSON = SettingsStore.Defaults.mentionTemplateOverridesJSON
    }
    
    override func tearDown() async throws {
        try? settingsStore.deleteAPIEndpoint()
        settingsStore.resetAllSettings()
        try? settingsStore.deleteAPIKey()
        settingsStore.mentionTemplateOverridesJSON = SettingsStore.Defaults.mentionTemplateOverridesJSON
        settingsStore = nil
        try await super.tearDown()
    }
    
    func testSaveAndLoadSettings() throws {
        settingsStore.selectedModel = "large-v3"
        XCTAssertEqual(settingsStore.selectedModel, "large-v3")
        
        settingsStore.toggleHotkey = "⌘⇧A"
        XCTAssertEqual(settingsStore.toggleHotkey, "⌘⇧A")
        
        settingsStore.pushToTalkHotkey = "⌘⇧B"
        XCTAssertEqual(settingsStore.pushToTalkHotkey, "⌘⇧B")
        
        settingsStore.outputMode = "directInsert"
        XCTAssertEqual(settingsStore.outputMode, "directInsert")
        
        settingsStore.aiEnhancementEnabled = true
        XCTAssertTrue(settingsStore.aiEnhancementEnabled)
        
        let newStore = SettingsStore()
        XCTAssertEqual(newStore.selectedModel, "large-v3")
        XCTAssertEqual(newStore.toggleHotkey, "⌘⇧A")
        XCTAssertEqual(newStore.pushToTalkHotkey, "⌘⇧B")
        XCTAssertEqual(newStore.outputMode, "directInsert")
        XCTAssertTrue(newStore.aiEnhancementEnabled)
        
        settingsStore.selectedModel = "base"
        settingsStore.toggleHotkey = "⌘⇧R"
        settingsStore.pushToTalkHotkey = "⌘⇧T"
        settingsStore.outputMode = "clipboard"
        settingsStore.aiEnhancementEnabled = false
    }
    
    func testKeychainStorage() throws {
        let testEndpoint = "https://api.openai.com/v1/chat/completions"
        let testKey = "sk-test-key-12345"
        
        try settingsStore.saveAPIEndpoint(testEndpoint)
        XCTAssertEqual(settingsStore.apiEndpoint, testEndpoint)
        
        try settingsStore.saveAPIKey(testKey)
        XCTAssertEqual(settingsStore.apiKey, testKey)
        
        let newStore = SettingsStore()
        XCTAssertEqual(newStore.apiEndpoint, testEndpoint)
        XCTAssertEqual(newStore.apiKey, testKey)
        
        try settingsStore.deleteAPIEndpoint()
        XCTAssertNil(settingsStore.apiEndpoint)
        
        try settingsStore.deleteAPIKey()
        XCTAssertNil(settingsStore.apiKey)
        
        let emptyStore = SettingsStore()
        XCTAssertNil(emptyStore.apiEndpoint)
        XCTAssertNil(emptyStore.apiKey)
    }
    
    func testKeychainPersistence() throws {
        let endpoint1 = "https://api.example.com/v1"
        let key1 = "key-12345"
        
        try settingsStore.saveAPIEndpoint(endpoint1)
        try settingsStore.saveAPIKey(key1)
        
        let endpoint2 = "https://api.different.com/v2"
        let key2 = "key-67890"
        
        try settingsStore.saveAPIEndpoint(endpoint2)
        try settingsStore.saveAPIKey(key2)
        
        XCTAssertEqual(settingsStore.apiEndpoint, endpoint2)
        XCTAssertEqual(settingsStore.apiKey, key2)
        
        let newStore = SettingsStore()
        XCTAssertEqual(newStore.apiEndpoint, endpoint2)
        XCTAssertEqual(newStore.apiKey, key2)
    }
    
    func testDefaultValues() {
        let store = SettingsStore()
        
        XCTAssertEqual(store.selectedModel, SettingsStore.Defaults.selectedModel)
        XCTAssertEqual(store.toggleHotkey, SettingsStore.Defaults.Hotkeys.toggleHotkey)
        XCTAssertEqual(store.pushToTalkHotkey, SettingsStore.Defaults.Hotkeys.pushToTalkHotkey)
        XCTAssertEqual(store.outputMode, "clipboard")
        XCTAssertFalse(store.aiEnhancementEnabled)
        XCTAssertTrue(store.floatingIndicatorEnabled)
        XCTAssertEqual(store.floatingIndicatorType, FloatingIndicatorType.pill.rawValue)
        XCTAssertNil(store.apiEndpoint)
        XCTAssertNil(store.apiKey)
    }

    func testVibeDefaultsAndRuntimeState() {
        let store = SettingsStore()

        XCTAssertTrue(store.vibeLiveSessionEnabled)
        XCTAssertEqual(store.vibeRuntimeState, .degraded)
        XCTAssertEqual(store.vibeRuntimeDetail, "Vibe mode is disabled.")
    }

    func testUpdateVibeRuntimeState() {
        settingsStore.updateVibeRuntimeState(.ready, detail: "Live session context active in Cursor.")

        XCTAssertEqual(settingsStore.vibeRuntimeState, .ready)
        XCTAssertEqual(settingsStore.vibeRuntimeDetail, "Live session context active in Cursor.")
    }

    func testResetAllSettingsResetsVibeRuntimeState() {
        settingsStore.vibeLiveSessionEnabled = false
        settingsStore.updateVibeRuntimeState(.ready, detail: "Live session context active in Cursor.")

        settingsStore.resetAllSettings()

        XCTAssertTrue(settingsStore.vibeLiveSessionEnabled)
        XCTAssertEqual(settingsStore.vibeRuntimeState, .degraded)
        XCTAssertEqual(settingsStore.vibeRuntimeDetail, "Vibe mode is disabled.")
    }

    func testResolveMentionFormattingUsesTerminalProviderDefaultTemplate() {
        let resolved = settingsStore.resolveMentionFormatting(
            editorBundleIdentifier: "com.microsoft.VSCode",
            terminalProviderIdentifier: "codex",
            adapterDefaultTemplate: "@{path}",
            adapterDefaultPrefix: "@"
        )

        XCTAssertEqual(resolved.mentionTemplate, "[@{path}]({path})")
        XCTAssertEqual(resolved.mentionPrefix, "@")
    }

    func testResolveMentionFormattingPrefersProviderOverrideOverEditorOverride() {
        settingsStore.setMentionTemplateOverride("/{path}", for: "provider:codex")
        settingsStore.setMentionTemplateOverride("@{path}", for: "editor:com.microsoft.vscode")

        let resolved = settingsStore.resolveMentionFormatting(
            editorBundleIdentifier: "com.microsoft.VSCode",
            terminalProviderIdentifier: "codex",
            adapterDefaultTemplate: "#{path}",
            adapterDefaultPrefix: "#"
        )

        XCTAssertEqual(resolved.mentionTemplate, "/{path}")
        XCTAssertEqual(resolved.mentionPrefix, "/")
    }

    func testSetMentionTemplateOverrideRejectsInvalidTemplate() {
        settingsStore.setMentionTemplateOverride("not-a-template", for: "provider:codex")
        XCTAssertNil(settingsStore.mentionTemplateOverride(for: "provider:codex"))
    }


    
    func testKeychainErrorHandling() throws {
        XCTAssertNoThrow(try settingsStore.deleteAPIEndpoint())
        XCTAssertNoThrow(try settingsStore.deleteAPIKey())
        
        XCTAssertNoThrow(try settingsStore.deleteAPIEndpoint())
        XCTAssertNoThrow(try settingsStore.deleteAPIKey())
    }
    
    func testObservableUpdates() throws {
        let expectation = XCTestExpectation(description: "Settings update")
        
        Task {
            settingsStore.selectedModel = "tiny"
            XCTAssertEqual(settingsStore.selectedModel, "tiny")
            
            try settingsStore.saveAPIEndpoint("https://test.com")
            XCTAssertEqual(settingsStore.apiEndpoint, "https://test.com")
            
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
    }
}

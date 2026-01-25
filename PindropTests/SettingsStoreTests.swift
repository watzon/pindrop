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
        
        try? settingsStore.deleteAPIEndpoint()
        try? settingsStore.deleteAPIKey()
    }
    
    override func tearDown() async throws {
        try? settingsStore.deleteAPIEndpoint()
        try? settingsStore.deleteAPIKey()
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
        
        XCTAssertEqual(store.selectedModel, "base")
        XCTAssertEqual(store.toggleHotkey, "⌘⇧R")
        XCTAssertEqual(store.pushToTalkHotkey, "⌘⇧T")
        XCTAssertEqual(store.outputMode, "clipboard")
        XCTAssertFalse(store.aiEnhancementEnabled)
        XCTAssertNil(store.apiEndpoint)
        XCTAssertNil(store.apiKey)
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

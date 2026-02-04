//
//  SettingsStore.swift
//  Pindrop
//
//  Created on 2026-01-25.
//

import Foundation
import SwiftUI
import Security
import Combine

@MainActor
final class SettingsStore: ObservableObject {
    
    // MARK: - Errors
    
    enum SettingsError: Error, LocalizedError {
        case keychainError(String)
        
        var errorDescription: String? {
            switch self {
            case .keychainError(let message):
                return "Keychain error: \(message)"
            }
        }
    }
    
    // MARK: - Default Values (Single Source of Truth)
    
    enum Defaults {
        static let selectedModel = "openai_whisper-base"
        static let outputMode = "clipboard"
        static let aiModel = "openai/gpt-4o-mini"
        static let aiEnhancementPrompt = "You are a text enhancement assistant. Improve the grammar, punctuation, and formatting of the provided text while preserving its original meaning and tone. Return only the enhanced text without any additional commentary."
        static let noteEnhancementPrompt = """
You are a note formatting assistant. Transform the transcribed text into a well-structured note.

Rules:
- Fix grammar, punctuation, and spelling errors
- For longer content (3+ paragraphs), add markdown formatting:
  - Use headers (## or ###) to organize sections
  - Use bullet points or numbered lists where appropriate
  - Use **bold** for emphasis on key terms
- For shorter content, keep it simple with minimal formatting
- Preserve the original meaning and tone
- Do not add content that wasn't in the original
- Return only the formatted note without any commentary
"""
        
        enum Hotkeys {
            static let toggleHotkey = "⌥Space"
            static let toggleHotkeyCode = 49
            static let toggleHotkeyModifiers = 0x800
            
            static let pushToTalkHotkey = "⌘/"
            static let pushToTalkHotkeyCode = 44
            static let pushToTalkHotkeyModifiers = 0x100
            
            static let copyLastTranscriptHotkey = "⇧⌘C"
            static let copyLastTranscriptHotkeyCode = 8
            static let copyLastTranscriptHotkeyModifiers = 0x300
            
            static let quickCapturePTTHotkey = "⇧⌥Space"
            static let quickCapturePTTHotkeyCode = 49
            static let quickCapturePTTHotkeyModifiers = 0xA00  // Shift + Option
            
            static let quickCaptureToggleHotkey = ""
            static let quickCaptureToggleHotkeyCode = 0
            static let quickCaptureToggleHotkeyModifiers = 0
        }
    }
    
    // MARK: - AppStorage Properties
    
    @AppStorage("selectedModel") var selectedModel: String = Defaults.selectedModel
    @AppStorage("toggleHotkey") var toggleHotkey: String = Defaults.Hotkeys.toggleHotkey
    @AppStorage("toggleHotkeyCode") var toggleHotkeyCode: Int = Defaults.Hotkeys.toggleHotkeyCode
    @AppStorage("toggleHotkeyModifiers") var toggleHotkeyModifiers: Int = Defaults.Hotkeys.toggleHotkeyModifiers
    @AppStorage("pushToTalkHotkey") var pushToTalkHotkey: String = Defaults.Hotkeys.pushToTalkHotkey
    @AppStorage("pushToTalkHotkeyCode") var pushToTalkHotkeyCode: Int = Defaults.Hotkeys.pushToTalkHotkeyCode
    @AppStorage("pushToTalkHotkeyModifiers") var pushToTalkHotkeyModifiers: Int = Defaults.Hotkeys.pushToTalkHotkeyModifiers
    @AppStorage("copyLastTranscriptHotkey") var copyLastTranscriptHotkey: String = Defaults.Hotkeys.copyLastTranscriptHotkey
    @AppStorage("copyLastTranscriptHotkeyCode") var copyLastTranscriptHotkeyCode: Int = Defaults.Hotkeys.copyLastTranscriptHotkeyCode
    @AppStorage("copyLastTranscriptHotkeyModifiers") var copyLastTranscriptHotkeyModifiers: Int = Defaults.Hotkeys.copyLastTranscriptHotkeyModifiers
    @AppStorage("quickCapturePTTHotkey") var quickCapturePTTHotkey: String = Defaults.Hotkeys.quickCapturePTTHotkey
    @AppStorage("quickCapturePTTHotkeyCode") var quickCapturePTTHotkeyCode: Int = Defaults.Hotkeys.quickCapturePTTHotkeyCode
    @AppStorage("quickCapturePTTHotkeyModifiers") var quickCapturePTTHotkeyModifiers: Int = Defaults.Hotkeys.quickCapturePTTHotkeyModifiers
    @AppStorage("quickCaptureToggleHotkey") var quickCaptureToggleHotkey: String = Defaults.Hotkeys.quickCaptureToggleHotkey
    @AppStorage("quickCaptureToggleHotkeyCode") var quickCaptureToggleHotkeyCode: Int = Defaults.Hotkeys.quickCaptureToggleHotkeyCode
    @AppStorage("quickCaptureToggleHotkeyModifiers") var quickCaptureToggleHotkeyModifiers: Int = Defaults.Hotkeys.quickCaptureToggleHotkeyModifiers
    @AppStorage("outputMode") var outputMode: String = Defaults.outputMode
    @AppStorage("aiEnhancementEnabled") var aiEnhancementEnabled: Bool = false
    @AppStorage("aiModel") var aiModel: String = Defaults.aiModel
    @AppStorage("aiEnhancementPrompt") var aiEnhancementPrompt: String = Defaults.aiEnhancementPrompt
    @AppStorage("noteEnhancementPrompt") var noteEnhancementPrompt: String = Defaults.noteEnhancementPrompt
    @AppStorage("floatingIndicatorEnabled") var floatingIndicatorEnabled: Bool = false
    @AppStorage("floatingIndicatorType") var floatingIndicatorType: String = FloatingIndicatorType.pill.rawValue
    @AppStorage("showInDock") var showInDock: Bool = false
    @AppStorage("addTrailingSpace") var addTrailingSpace: Bool = true
    @AppStorage("launchAtLogin") var launchAtLogin: Bool = false
    @AppStorage("selectedPresetId") var selectedPresetId: String?

    @AppStorage("enableClipboardContext") var enableClipboardContext: Bool = false
    @AppStorage("enableImageContext") var enableImageContext: Bool = false
    @AppStorage("enableScreenshotContext") var enableScreenshotContext: Bool = false
    @AppStorage("screenshotMode") var screenshotMode: String = "activeWindow"

    @AppStorage("vadFeatureEnabled") var vadFeatureEnabled: Bool = false
    @AppStorage("diarizationFeatureEnabled") var diarizationFeatureEnabled: Bool = false
    @AppStorage("streamingFeatureEnabled") var streamingFeatureEnabled: Bool = false
    
    // MARK: - Onboarding State
    
    @AppStorage("hasCompletedOnboarding") var hasCompletedOnboarding: Bool = false
    @AppStorage("currentOnboardingStep") var currentOnboardingStep: Int = 0
    @AppStorage("hasSeededPresets") var hasSeededPresets: Bool = false
    
    // MARK: - Keychain Properties
    
    private let keychainService = "com.pindrop.settings"
    private let apiEndpointAccount = "api-endpoint"
    private let apiKeyAccount = "api-key"
    
    // MARK: - Cached Keychain Values
    
    private(set) var apiEndpoint: String?
    private(set) var apiKey: String?
    
    private static var isPreview: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }
    
    init() {
        guard !Self.isPreview else { return }
        apiEndpoint = try? loadFromKeychain(account: apiEndpointAccount)
        apiKey = try? loadFromKeychain(account: apiKeyAccount)
    }
    
    // MARK: - Keychain Methods
    
    func saveAPIEndpoint(_ endpoint: String) throws {
        try saveToKeychain(value: endpoint, account: apiEndpointAccount)
        apiEndpoint = endpoint
    }
    
    func saveAPIKey(_ key: String) throws {
        try saveToKeychain(value: key, account: apiKeyAccount)
        apiKey = key
    }
    
    func deleteAPIEndpoint() throws {
        try deleteFromKeychain(account: apiEndpointAccount)
        apiEndpoint = nil
    }
    
    func deleteAPIKey() throws {
        try deleteFromKeychain(account: apiKeyAccount)
        apiKey = nil
    }
    
    func resetAllSettings() {
        selectedModel = Defaults.selectedModel
        toggleHotkey = Defaults.Hotkeys.toggleHotkey
        toggleHotkeyCode = Defaults.Hotkeys.toggleHotkeyCode
        toggleHotkeyModifiers = Defaults.Hotkeys.toggleHotkeyModifiers
        pushToTalkHotkey = Defaults.Hotkeys.pushToTalkHotkey
        pushToTalkHotkeyCode = Defaults.Hotkeys.pushToTalkHotkeyCode
        pushToTalkHotkeyModifiers = Defaults.Hotkeys.pushToTalkHotkeyModifiers
        copyLastTranscriptHotkey = Defaults.Hotkeys.copyLastTranscriptHotkey
        copyLastTranscriptHotkeyCode = Defaults.Hotkeys.copyLastTranscriptHotkeyCode
        copyLastTranscriptHotkeyModifiers = Defaults.Hotkeys.copyLastTranscriptHotkeyModifiers
        quickCapturePTTHotkey = Defaults.Hotkeys.quickCapturePTTHotkey
        quickCapturePTTHotkeyCode = Defaults.Hotkeys.quickCapturePTTHotkeyCode
        quickCapturePTTHotkeyModifiers = Defaults.Hotkeys.quickCapturePTTHotkeyModifiers
        quickCaptureToggleHotkey = Defaults.Hotkeys.quickCaptureToggleHotkey
        quickCaptureToggleHotkeyCode = Defaults.Hotkeys.quickCaptureToggleHotkeyCode
        quickCaptureToggleHotkeyModifiers = Defaults.Hotkeys.quickCaptureToggleHotkeyModifiers
        outputMode = Defaults.outputMode
        aiEnhancementEnabled = false
        floatingIndicatorEnabled = false
        floatingIndicatorType = FloatingIndicatorType.pill.rawValue
        launchAtLogin = false
        hasCompletedOnboarding = false
        currentOnboardingStep = 0
        
        try? deleteAPIEndpoint()
        try? deleteAPIKey()
        
        objectWillChange.send()
    }
    
    // MARK: - Private Keychain Helpers
    
    private func saveToKeychain(value: String, account: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw SettingsError.keychainError("Failed to encode value")
        }
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
            kSecValueData as String: data
        ]
        
        SecItemDelete(query as CFDictionary)
        
        let status = SecItemAdd(query as CFDictionary, nil)
        
        guard status == errSecSuccess else {
            throw SettingsError.keychainError("Failed to save to keychain: \(status)")
        }
    }
    
    private func loadFromKeychain(account: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess else {
            if status == errSecItemNotFound {
                return nil
            }
            throw SettingsError.keychainError("Failed to load from keychain: \(status)")
        }
        
        guard let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            throw SettingsError.keychainError("Failed to decode value")
        }
        
        return value
    }
    
    private func deleteFromKeychain(account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SettingsError.keychainError("Failed to delete from keychain: \(status)")
        }
    }
    
    func isFeatureEnabled(_ type: FeatureModelType) -> Bool {
        switch type {
        case .vad: return vadFeatureEnabled
        case .diarization: return diarizationFeatureEnabled
        case .streaming: return streamingFeatureEnabled
        }
    }
    
    func setFeatureEnabled(_ type: FeatureModelType, enabled: Bool) {
        switch type {
        case .vad: vadFeatureEnabled = enabled
        case .diarization: diarizationFeatureEnabled = enabled
        case .streaming: streamingFeatureEnabled = enabled
        }
        objectWillChange.send()
    }
}

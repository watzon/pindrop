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
        static let selectedInputDeviceUID = ""
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
        static let mentionTemplateOverridesJSON = "{}"
        
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
    @AppStorage("selectedInputDeviceUID") var selectedInputDeviceUID: String = Defaults.selectedInputDeviceUID
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
    @AppStorage("mentionTemplateOverridesJSON") var mentionTemplateOverridesJSON: String = Defaults.mentionTemplateOverridesJSON

    @AppStorage("enableClipboardContext") var enableClipboardContext: Bool = false
    @AppStorage("enableUIContext") var enableUIContext: Bool = false
    @AppStorage("contextCaptureTimeoutSeconds") var contextCaptureTimeoutSeconds: Double = 2.0
    @AppStorage("vibeLiveSessionEnabled") var vibeLiveSessionEnabled: Bool = true

    @AppStorage("vadFeatureEnabled") var vadFeatureEnabled: Bool = false
    @AppStorage("diarizationFeatureEnabled") var diarizationFeatureEnabled: Bool = false
    @AppStorage("streamingFeatureEnabled") var streamingFeatureEnabled: Bool = false

    @Published private(set) var vibeRuntimeState: VibeRuntimeState = .degraded
    @Published private(set) var vibeRuntimeDetail: String = "Vibe mode is disabled."
    
    // MARK: - Onboarding State
    
    @AppStorage("hasCompletedOnboarding") var hasCompletedOnboarding: Bool = false
    @AppStorage("currentOnboardingStep") var currentOnboardingStep: Int = 0

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
        selectedInputDeviceUID = Defaults.selectedInputDeviceUID
        aiEnhancementEnabled = false
        floatingIndicatorEnabled = false
        floatingIndicatorType = FloatingIndicatorType.pill.rawValue
        launchAtLogin = false
        mentionTemplateOverridesJSON = Defaults.mentionTemplateOverridesJSON
        enableUIContext = false
        contextCaptureTimeoutSeconds = 2.0
        vibeLiveSessionEnabled = true
        vibeRuntimeState = .degraded
        vibeRuntimeDetail = "Vibe mode is disabled."
        hasCompletedOnboarding = false
        currentOnboardingStep = 0
        
        try? deleteAPIEndpoint()
        try? deleteAPIKey()
        
        objectWillChange.send()
    }

    func updateVibeRuntimeState(_ state: VibeRuntimeState, detail: String) {
        guard vibeRuntimeState != state || vibeRuntimeDetail != detail else { return }
        vibeRuntimeState = state
        vibeRuntimeDetail = detail
    }

    private static let mentionTemplateOverrideEditorPrefix = "editor:"
    private static let mentionTemplateOverrideProviderPrefix = "provider:"

    func mentionTemplateOverride(for key: String) -> String? {
        let normalizedKey = key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedKey.isEmpty else { return nil }
        return normalizedMentionTemplate(decodedMentionTemplateOverrides()[normalizedKey])
    }

    func setMentionTemplateOverride(_ template: String?, for key: String) {
        let normalizedKey = key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedKey.isEmpty else { return }

        var overrides = decodedMentionTemplateOverrides()
        if let normalizedTemplate = normalizedMentionTemplate(template) {
            overrides[normalizedKey] = normalizedTemplate
        } else {
            overrides.removeValue(forKey: normalizedKey)
        }

        persistMentionTemplateOverrides(overrides)
    }

    func resolveMentionFormatting(
        editorBundleIdentifier: String?,
        terminalProviderIdentifier: String?,
        adapterDefaultTemplate: String,
        adapterDefaultPrefix: String
    ) -> (mentionPrefix: String, mentionTemplate: String) {
        let resolvedTemplate = resolveMentionTemplate(
            editorBundleIdentifier: editorBundleIdentifier,
            terminalProviderIdentifier: terminalProviderIdentifier,
            adapterDefaultTemplate: adapterDefaultTemplate
        )

        let resolvedPrefix = Self.deriveMentionPrefix(
            from: resolvedTemplate,
            fallback: adapterDefaultPrefix
        )

        return (mentionPrefix: resolvedPrefix, mentionTemplate: resolvedTemplate)
    }

    static func deriveMentionPrefix(from template: String, fallback: String) -> String {
        guard let tokenRange = template.range(of: MentionTemplateCatalog.pathToken) else {
            return fallback
        }

        let prefixSlice = template[..<tokenRange.lowerBound]
        if let prefixCharacter = prefixSlice.last(where: { $0 == "@" || $0 == "#" || $0 == "/" }) {
            return String(prefixCharacter)
        }

        return fallback
    }

    private func resolveMentionTemplate(
        editorBundleIdentifier: String?,
        terminalProviderIdentifier: String?,
        adapterDefaultTemplate: String
    ) -> String {
        let overrides = decodedMentionTemplateOverrides()

        if let providerKey = providerOverrideKey(terminalProviderIdentifier),
           let template = normalizedMentionTemplate(overrides[providerKey]) {
            return template
        }

        if let editorKey = editorOverrideKey(editorBundleIdentifier),
           let template = normalizedMentionTemplate(overrides[editorKey]) {
            return template
        }

        if let providerDefault = TerminalProviderRegistry.defaultMentionTemplate(for: terminalProviderIdentifier),
           let template = normalizedMentionTemplate(providerDefault) {
            return template
        }

        return normalizedMentionTemplate(adapterDefaultTemplate) ?? AppAdapterCapabilities.none.mentionTemplate
    }

    private func decodedMentionTemplateOverrides() -> [String: String] {
        guard let data = mentionTemplateOverridesJSON.data(using: .utf8),
              !data.isEmpty,
              let decoded = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }

        return decoded
    }

    private func persistMentionTemplateOverrides(_ overrides: [String: String]) {
        guard let data = try? JSONEncoder().encode(overrides),
              let encoded = String(data: data, encoding: .utf8) else {
            return
        }

        mentionTemplateOverridesJSON = encoded
    }

    private func normalizedMentionTemplate(_ template: String?) -> String? {
        guard let template = template?.trimmingCharacters(in: .whitespacesAndNewlines),
              !template.isEmpty,
              template.contains(MentionTemplateCatalog.pathToken) else {
            return nil
        }

        return template
    }

    private func editorOverrideKey(_ editorBundleIdentifier: String?) -> String? {
        guard let editorBundleIdentifier = editorBundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines),
              !editorBundleIdentifier.isEmpty else {
            return nil
        }

        return Self.mentionTemplateOverrideEditorPrefix + editorBundleIdentifier.lowercased()
    }

    private func providerOverrideKey(_ terminalProviderIdentifier: String?) -> String? {
        guard let terminalProviderIdentifier = terminalProviderIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines),
              !terminalProviderIdentifier.isEmpty else {
            return nil
        }

        return Self.mentionTemplateOverrideProviderPrefix + terminalProviderIdentifier.lowercased()
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

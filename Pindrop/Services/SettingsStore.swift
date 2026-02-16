//
//  SettingsStore.swift
//  Pindrop
//
//  Created on 2026-01-25.
//

import Combine
import Foundation
import Security
import SwiftUI

private enum SettingsStoreRuntime {
   static let isPreview = ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"

   static let isRunningTests: Bool = {
      ProcessInfo.processInfo.environment["PINDROP_TEST_MODE"] == "1"
         || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
   }()

   static let appStorageStore: UserDefaults? = {
      guard isRunningTests else { return nil }

      let suiteName =
         ProcessInfo.processInfo.environment["PINDROP_TEST_USER_DEFAULTS_SUITE"]
         ?? "com.pindrop.settings.tests.\(ProcessInfo.processInfo.processIdentifier)"
      return UserDefaults(suiteName: suiteName)
   }()
}

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
      static let aiEnhancementPrompt =
         "You are a text enhancement assistant. Improve the grammar, punctuation, and formatting of the provided text while preserving its original meaning and tone. Return only the enhanced text without any additional commentary."
      static let floatingIndicatorEnabled = true
      static let floatingIndicatorType = FloatingIndicatorType.pill.rawValue
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

   @AppStorage("selectedModel", store: SettingsStoreRuntime.appStorageStore) var selectedModel:
      String = Defaults.selectedModel
   @AppStorage("toggleHotkey", store: SettingsStoreRuntime.appStorageStore) var toggleHotkey:
      String = Defaults.Hotkeys.toggleHotkey
   @AppStorage("toggleHotkeyCode", store: SettingsStoreRuntime.appStorageStore)
   var toggleHotkeyCode: Int = Defaults.Hotkeys.toggleHotkeyCode
   @AppStorage("toggleHotkeyModifiers", store: SettingsStoreRuntime.appStorageStore)
   var toggleHotkeyModifiers: Int = Defaults.Hotkeys.toggleHotkeyModifiers
   @AppStorage("pushToTalkHotkey", store: SettingsStoreRuntime.appStorageStore)
   var pushToTalkHotkey: String = Defaults.Hotkeys.pushToTalkHotkey
   @AppStorage("pushToTalkHotkeyCode", store: SettingsStoreRuntime.appStorageStore)
   var pushToTalkHotkeyCode: Int = Defaults.Hotkeys.pushToTalkHotkeyCode
   @AppStorage("pushToTalkHotkeyModifiers", store: SettingsStoreRuntime.appStorageStore)
   var pushToTalkHotkeyModifiers: Int = Defaults.Hotkeys.pushToTalkHotkeyModifiers
   @AppStorage("copyLastTranscriptHotkey", store: SettingsStoreRuntime.appStorageStore)
   var copyLastTranscriptHotkey: String = Defaults.Hotkeys.copyLastTranscriptHotkey
   @AppStorage("copyLastTranscriptHotkeyCode", store: SettingsStoreRuntime.appStorageStore)
   var copyLastTranscriptHotkeyCode: Int = Defaults.Hotkeys.copyLastTranscriptHotkeyCode
   @AppStorage("copyLastTranscriptHotkeyModifiers", store: SettingsStoreRuntime.appStorageStore)
   var copyLastTranscriptHotkeyModifiers: Int = Defaults.Hotkeys.copyLastTranscriptHotkeyModifiers
   @AppStorage("quickCapturePTTHotkey", store: SettingsStoreRuntime.appStorageStore)
   var quickCapturePTTHotkey: String = Defaults.Hotkeys.quickCapturePTTHotkey
   @AppStorage("quickCapturePTTHotkeyCode", store: SettingsStoreRuntime.appStorageStore)
   var quickCapturePTTHotkeyCode: Int = Defaults.Hotkeys.quickCapturePTTHotkeyCode
   @AppStorage("quickCapturePTTHotkeyModifiers", store: SettingsStoreRuntime.appStorageStore)
   var quickCapturePTTHotkeyModifiers: Int = Defaults.Hotkeys.quickCapturePTTHotkeyModifiers
   @AppStorage("quickCaptureToggleHotkey", store: SettingsStoreRuntime.appStorageStore)
   var quickCaptureToggleHotkey: String = Defaults.Hotkeys.quickCaptureToggleHotkey
   @AppStorage("quickCaptureToggleHotkeyCode", store: SettingsStoreRuntime.appStorageStore)
   var quickCaptureToggleHotkeyCode: Int = Defaults.Hotkeys.quickCaptureToggleHotkeyCode
   @AppStorage("quickCaptureToggleHotkeyModifiers", store: SettingsStoreRuntime.appStorageStore)
   var quickCaptureToggleHotkeyModifiers: Int = Defaults.Hotkeys.quickCaptureToggleHotkeyModifiers
   @AppStorage("outputMode", store: SettingsStoreRuntime.appStorageStore) var outputMode: String =
      Defaults.outputMode
   @AppStorage("selectedInputDeviceUID", store: SettingsStoreRuntime.appStorageStore)
   var selectedInputDeviceUID: String = Defaults.selectedInputDeviceUID
   @AppStorage("aiEnhancementEnabled", store: SettingsStoreRuntime.appStorageStore)
   var aiEnhancementEnabled: Bool = false
   @AppStorage("aiProvider", store: SettingsStoreRuntime.appStorageStore)
   var aiProvider: String = AIProvider.openai.rawValue
   @AppStorage("aiModel", store: SettingsStoreRuntime.appStorageStore) var aiModel: String =
      Defaults.aiModel
   @AppStorage("openRouterModelsCacheTimestamp", store: SettingsStoreRuntime.appStorageStore)
   var openRouterModelsCacheTimestamp: TimeInterval = 0
   @AppStorage("openAIModelsCacheTimestamp", store: SettingsStoreRuntime.appStorageStore)
   var openAIModelsCacheTimestamp: TimeInterval = 0
   @AppStorage("aiEnhancementPrompt", store: SettingsStoreRuntime.appStorageStore)
   var aiEnhancementPrompt: String = Defaults.aiEnhancementPrompt
   @AppStorage("noteEnhancementPrompt", store: SettingsStoreRuntime.appStorageStore)
   var noteEnhancementPrompt: String = Defaults.noteEnhancementPrompt
   @AppStorage("floatingIndicatorEnabled", store: SettingsStoreRuntime.appStorageStore)
   var floatingIndicatorEnabled: Bool = Defaults.floatingIndicatorEnabled
   @AppStorage("floatingIndicatorType", store: SettingsStoreRuntime.appStorageStore)
   var floatingIndicatorType: String = Defaults.floatingIndicatorType
   @AppStorage("showInDock", store: SettingsStoreRuntime.appStorageStore) var showInDock: Bool =
      false
   @AppStorage("addTrailingSpace", store: SettingsStoreRuntime.appStorageStore)
   var addTrailingSpace: Bool = true
   @AppStorage("pauseMediaOnRecording", store: SettingsStoreRuntime.appStorageStore)
   var pauseMediaOnRecording: Bool = false
   @AppStorage("muteAudioDuringRecording", store: SettingsStoreRuntime.appStorageStore)
   var muteAudioDuringRecording: Bool = false
   @AppStorage("launchAtLogin", store: SettingsStoreRuntime.appStorageStore) var launchAtLogin:
      Bool = false
   @AppStorage("selectedPresetId", store: SettingsStoreRuntime.appStorageStore)
   var selectedPresetId: String?
   @AppStorage("mentionTemplateOverridesJSON", store: SettingsStoreRuntime.appStorageStore)
   var mentionTemplateOverridesJSON: String = Defaults.mentionTemplateOverridesJSON

   @AppStorage("enableClipboardContext", store: SettingsStoreRuntime.appStorageStore)
   var enableClipboardContext: Bool = false
   @AppStorage("enableUIContext", store: SettingsStoreRuntime.appStorageStore) var enableUIContext:
      Bool = false
   @AppStorage("contextCaptureTimeoutSeconds", store: SettingsStoreRuntime.appStorageStore)
   var contextCaptureTimeoutSeconds: Double = 2.0
   @AppStorage("vibeLiveSessionEnabled", store: SettingsStoreRuntime.appStorageStore)
   var vibeLiveSessionEnabled: Bool = true

   @AppStorage("vadFeatureEnabled", store: SettingsStoreRuntime.appStorageStore)
   var vadFeatureEnabled: Bool = false
   @AppStorage("diarizationFeatureEnabled", store: SettingsStoreRuntime.appStorageStore)
   var diarizationFeatureEnabled: Bool = false
   @AppStorage("streamingFeatureEnabled", store: SettingsStoreRuntime.appStorageStore)
   var streamingFeatureEnabled: Bool = false

   @Published private(set) var vibeRuntimeState: VibeRuntimeState = .degraded
   @Published private(set) var vibeRuntimeDetail: String = "Vibe mode is disabled."
   @Published private(set) var isApplyingHotkeyUpdate = false

   // MARK: - Onboarding State

   @AppStorage("hasCompletedOnboarding", store: SettingsStoreRuntime.appStorageStore)
   var hasCompletedOnboarding: Bool = false
   @AppStorage("currentOnboardingStep", store: SettingsStoreRuntime.appStorageStore)
   var currentOnboardingStep: Int = 0

   // MARK: - Keychain Properties

   private let keychainService = "com.pindrop.settings"
   private let apiEndpointAccount = "api-endpoint"
   private let legacyAPIKeyAccount = "api-key"

   private static var inMemoryKeychainStorage: [String: String] = [:]

   private static var shouldUseInMemoryKeychain: Bool {
      SettingsStoreRuntime.isRunningTests
   }

   // MARK: - Cached Keychain Values

   private(set) var apiEndpoint: String?
   private var apiKeys: [AIProvider: String] = [:]

   @available(*, deprecated, message: "Use loadAPIKey(for:)")
   var apiKey: String? {
      loadAPIKey(for: currentAIProvider)
   }

   var currentAIProvider: AIProvider {
      if let provider = AIProvider(rawValue: aiProvider) {
         return provider
      }
      if let provider = provider(for: apiEndpoint) {
         return provider
      }
      return .openai
   }

   private func provider(for endpoint: String?) -> AIProvider? {
      guard
         let endpoint = endpoint?.trimmingCharacters(in: .whitespacesAndNewlines),
         !endpoint.isEmpty
      else {
         return nil
      }

      let normalizedEndpoint = endpoint.lowercased()

      if normalizedEndpoint.contains("openai.com") {
         return .openai
      }
      if normalizedEndpoint.contains("anthropic.com") {
         return .anthropic
      }
      if normalizedEndpoint.contains("googleapis.com") {
         return .google
      }
      if normalizedEndpoint.contains("openrouter.ai") {
         return .openrouter
      }

      return .custom
   }

   init() {
      guard !SettingsStoreRuntime.isPreview else { return }
      apiEndpoint = try? loadFromKeychain(account: apiEndpointAccount)
      if let provider = provider(for: apiEndpoint) {
         aiProvider = provider.rawValue
      }
   }

   // MARK: - Keychain Methods
   private func apiKeyAccount(for provider: AIProvider) -> String {
      "api-key-\(provider.rawValue)"
   }

   func saveAPIEndpoint(_ endpoint: String) throws {
      try saveToKeychain(value: endpoint, account: apiEndpointAccount)
      apiEndpoint = endpoint
      if let provider = provider(for: endpoint) {
         aiProvider = provider.rawValue
      }
   }

   func saveAPIKey(_ key: String, for provider: AIProvider) throws {
      try saveToKeychain(value: key, account: apiKeyAccount(for: provider))
      apiKeys[provider] = key
   }

   @available(*, deprecated, message: "Use saveAPIKey(_:for:)")
   func saveAPIKey(_ key: String) throws {
      try saveAPIKey(key, for: currentAIProvider)
   }

   func loadAPIKey(for provider: AIProvider) -> String? {
      if let cachedKey = apiKeys[provider] {
         return cachedKey
      }

      let storedKey = (try? loadFromKeychain(account: apiKeyAccount(for: provider))) ?? nil
      if let key = storedKey {
         apiKeys[provider] = key
         return key
      }

      guard provider == currentAIProvider else { return nil }

      let legacyKey = (try? loadFromKeychain(account: legacyAPIKeyAccount)) ?? nil
      guard let key = legacyKey else { return nil }

      try? saveToKeychain(value: key, account: apiKeyAccount(for: provider))
      apiKeys[provider] = key
      try? deleteFromKeychain(account: legacyAPIKeyAccount)

      return key
   }

   func deleteAPIEndpoint() throws {
      try deleteFromKeychain(account: apiEndpointAccount)
      apiEndpoint = nil
   }

   func deleteAPIKey(for provider: AIProvider) throws {
      try deleteFromKeychain(account: apiKeyAccount(for: provider))
      apiKeys.removeValue(forKey: provider)
   }

   @available(*, deprecated, message: "Use deleteAPIKey(for:)")
   func deleteAPIKey() throws {
      try deleteAPIKey(for: currentAIProvider)
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
      aiProvider = AIProvider.openai.rawValue
      floatingIndicatorEnabled = Defaults.floatingIndicatorEnabled
      floatingIndicatorType = Defaults.floatingIndicatorType
      pauseMediaOnRecording = false
      muteAudioDuringRecording = false
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
      for provider in AIProvider.allCases {
         try? deleteAPIKey(for: provider)
      }
      try? deleteFromKeychain(account: legacyAPIKeyAccount)
      apiKeys.removeAll()

      objectWillChange.send()
   }

   func isModelCacheStale(for provider: AIProvider) -> Bool {
      let cacheTimestamp: TimeInterval
      switch provider {
      case .openrouter:
         cacheTimestamp = openRouterModelsCacheTimestamp
      case .openai:
         cacheTimestamp = openAIModelsCacheTimestamp
      default:
         return true
      }

      guard cacheTimestamp > 0 else { return true }
      return Date().timeIntervalSince1970 - cacheTimestamp > 60 * 60 * 24 * 7
   }

   func updateVibeRuntimeState(_ state: VibeRuntimeState, detail: String) {
      guard vibeRuntimeState != state || vibeRuntimeDetail != detail else { return }
      vibeRuntimeState = state
      vibeRuntimeDetail = detail
   }

   func updateToggleHotkey(_ hotkey: String, keyCode: Int, modifiers: Int) {
      performHotkeyUpdate {
         toggleHotkey = hotkey
         toggleHotkeyCode = keyCode
         toggleHotkeyModifiers = modifiers
      }
   }

   func updatePushToTalkHotkey(_ hotkey: String, keyCode: Int, modifiers: Int) {
      performHotkeyUpdate {
         pushToTalkHotkey = hotkey
         pushToTalkHotkeyCode = keyCode
         pushToTalkHotkeyModifiers = modifiers
      }
   }

   func updateCopyLastTranscriptHotkey(_ hotkey: String, keyCode: Int, modifiers: Int) {
      performHotkeyUpdate {
         copyLastTranscriptHotkey = hotkey
         copyLastTranscriptHotkeyCode = keyCode
         copyLastTranscriptHotkeyModifiers = modifiers
      }
   }

   func updateQuickCapturePTTHotkey(_ hotkey: String, keyCode: Int, modifiers: Int) {
      performHotkeyUpdate {
         quickCapturePTTHotkey = hotkey
         quickCapturePTTHotkeyCode = keyCode
         quickCapturePTTHotkeyModifiers = modifiers
      }
   }

   func updateQuickCaptureToggleHotkey(_ hotkey: String, keyCode: Int, modifiers: Int) {
      performHotkeyUpdate {
         quickCaptureToggleHotkey = hotkey
         quickCaptureToggleHotkeyCode = keyCode
         quickCaptureToggleHotkeyModifiers = modifiers
      }
   }

   private func performHotkeyUpdate(_ update: () -> Void) {
      isApplyingHotkeyUpdate = true
      defer { isApplyingHotkeyUpdate = false }
      update()
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
         let template = normalizedMentionTemplate(overrides[providerKey])
      {
         return template
      }

      if let editorKey = editorOverrideKey(editorBundleIdentifier),
         let template = normalizedMentionTemplate(overrides[editorKey])
      {
         return template
      }

      if let providerDefault = TerminalProviderRegistry.defaultMentionTemplate(
         for: terminalProviderIdentifier),
         let template = normalizedMentionTemplate(providerDefault)
      {
         return template
      }

      return normalizedMentionTemplate(adapterDefaultTemplate)
         ?? AppAdapterCapabilities.none.mentionTemplate
   }

   private func decodedMentionTemplateOverrides() -> [String: String] {
      guard let data = mentionTemplateOverridesJSON.data(using: .utf8),
         !data.isEmpty,
         let decoded = try? JSONDecoder().decode([String: String].self, from: data)
      else {
         return [:]
      }

      return decoded
   }

   private func persistMentionTemplateOverrides(_ overrides: [String: String]) {
      guard let data = try? JSONEncoder().encode(overrides),
         let encoded = String(data: data, encoding: .utf8)
      else {
         return
      }

      mentionTemplateOverridesJSON = encoded
   }

   private func normalizedMentionTemplate(_ template: String?) -> String? {
      guard let template = template?.trimmingCharacters(in: .whitespacesAndNewlines),
         !template.isEmpty,
         template.contains(MentionTemplateCatalog.pathToken)
      else {
         return nil
      }

      return template
   }

   private func editorOverrideKey(_ editorBundleIdentifier: String?) -> String? {
      guard
         let editorBundleIdentifier = editorBundleIdentifier?.trimmingCharacters(
            in: .whitespacesAndNewlines),
         !editorBundleIdentifier.isEmpty
      else {
         return nil
      }

      return Self.mentionTemplateOverrideEditorPrefix + editorBundleIdentifier.lowercased()
   }

   private func providerOverrideKey(_ terminalProviderIdentifier: String?) -> String? {
      guard
         let terminalProviderIdentifier = terminalProviderIdentifier?.trimmingCharacters(
            in: .whitespacesAndNewlines),
         !terminalProviderIdentifier.isEmpty
      else {
         return nil
      }

      return Self.mentionTemplateOverrideProviderPrefix + terminalProviderIdentifier.lowercased()
   }

   // MARK: - Private Keychain Helpers

   private func saveToKeychain(value: String, account: String) throws {
      if Self.shouldUseInMemoryKeychain {
         Self.inMemoryKeychainStorage[account] = value
         return
      }

      guard let data = value.data(using: .utf8) else {
         throw SettingsError.keychainError("Failed to encode value")
      }

      let query: [String: Any] = [
         kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: keychainService,
         kSecAttrAccount as String: account,
         kSecValueData as String: data,
      ]

      SecItemDelete(query as CFDictionary)

      let status = SecItemAdd(query as CFDictionary, nil)

      guard status == errSecSuccess else {
         throw SettingsError.keychainError("Failed to save to keychain: \(status)")
      }
   }

   private func loadFromKeychain(account: String) throws -> String? {
      if Self.shouldUseInMemoryKeychain {
         return Self.inMemoryKeychainStorage[account]
      }

      let query: [String: Any] = [
         kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: keychainService,
         kSecAttrAccount as String: account,
         kSecReturnData as String: true,
         kSecMatchLimit as String: kSecMatchLimitOne,
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
         let value = String(data: data, encoding: .utf8)
      else {
         throw SettingsError.keychainError("Failed to decode value")
      }

      return value
   }

   private func deleteFromKeychain(account: String) throws {
      if Self.shouldUseInMemoryKeychain {
         Self.inMemoryKeychainStorage.removeValue(forKey: account)
         return
      }

      let query: [String: Any] = [
         kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: keychainService,
         kSecAttrAccount as String: account,
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

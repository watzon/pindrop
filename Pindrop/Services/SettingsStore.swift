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
      AppTestMode.isRunningAnyTests
   }()

   static let appStorageStore: UserDefaults? = {
      guard isRunningTests else { return nil }

      let suiteName =
         ProcessInfo.processInfo.environment[AppTestMode.testUserDefaultsSuiteKey]
         ?? "tech.watzon.pindrop.settings.tests.\(ProcessInfo.processInfo.processIdentifier)"
      return UserDefaults(suiteName: suiteName)
   }()
}

public enum AppLanguage: String, CaseIterable, Sendable, Identifiable {
   case automatic = "auto"
   case english = "en"
   case simplifiedChinese = "zh-Hans"
   case spanish = "es"
   case french = "fr"
   case german = "de"
   case japanese = "ja"
   case portugueseBrazil = "pt-BR"
   case italian = "it"
   case dutch = "nl"
   case korean = "ko"

   public var id: String { rawValue }

    var displayName: String {
       displayName(locale: .autoupdatingCurrent)
    }

    var pickerLabel: String {
       pickerLabel(locale: .autoupdatingCurrent)
    }

    func displayName(locale: Locale) -> String {
       switch self {
       case .automatic:
          return localized("Automatic (Follow System)", locale: locale)
       case .english:
          return localized("English", locale: locale)
       case .simplifiedChinese:
          return localized("Simplified Chinese", locale: locale)
       case .spanish:
          return localized("Spanish", locale: locale)
       case .french:
          return localized("French", locale: locale)
       case .german:
          return localized("German", locale: locale)
       case .japanese:
          return localized("Japanese", locale: locale)
       case .portugueseBrazil:
          return localized("Portuguese (Brazil)", locale: locale)
       case .italian:
          return localized("Italian", locale: locale)
       case .dutch:
          return localized("Dutch", locale: locale)
       case .korean:
          return localized("Korean", locale: locale)
       }
    }

    func pickerLabel(locale: Locale) -> String {
       let displayName = displayName(locale: locale)
       guard !isSelectable else { return displayName }
       return String(format: localized("%@ (Coming Soon)", locale: locale), displayName)
    }

   var isSelectable: Bool {
      switch self {
      case .automatic, .english, .simplifiedChinese, .spanish, .french, .german:
         return true
      case .japanese, .portugueseBrazil, .italian, .dutch, .korean:
         return false
      }
   }

   var isEnglish: Bool {
      self == .english
   }

   var locale: Locale {
      switch self {
      case .automatic:
         return .autoupdatingCurrent
      case .english:
         return Locale(identifier: "en")
      case .simplifiedChinese:
         return Locale(identifier: "zh-Hans")
      case .spanish:
         return Locale(identifier: "es")
      case .french:
         return Locale(identifier: "fr")
      case .german:
         return Locale(identifier: "de")
      case .japanese:
         return Locale(identifier: "ja")
      case .portugueseBrazil:
         return Locale(identifier: "pt-BR")
      case .italian:
         return Locale(identifier: "it")
      case .dutch:
         return Locale(identifier: "nl")
      case .korean:
         return Locale(identifier: "ko")
      }
   }

   var whisperLanguageCode: String? {
      switch self {
      case .automatic:
         return nil
      case .english:
         return "en"
      case .simplifiedChinese:
         return "zh"
      case .spanish:
         return "es"
      case .french:
         return "fr"
      case .german:
         return "de"
      case .japanese:
         return "ja"
      case .portugueseBrazil:
         return "pt"
      case .italian:
         return "it"
      case .dutch:
         return "nl"
      case .korean:
         return "ko"
      }
   }

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
       static let selectedLanguage = AppLanguage.automatic.rawValue
       static let themeMode = PindropThemeMode.system.rawValue
      static let lightThemePresetID = PindropThemePresetCatalog.defaultPresetID
      static let darkThemePresetID = PindropThemePresetCatalog.defaultPresetID
      static let automaticDictionaryLearningEnabled = true
      static let selectedInputDeviceUID = ""
      static let aiModel = "openai/gpt-4o-mini"
      static let aiEnhancementPrompt =
         "You are a text enhancement assistant. Improve the grammar, punctuation, and formatting of the provided text while preserving its original meaning and tone. Return only the enhanced text without any additional commentary."
      static let floatingIndicatorEnabled = true
      static let floatingIndicatorType = FloatingIndicatorType.pill.rawValue
      static let pillFloatingIndicatorOffsetX = 0.0
      static let pillFloatingIndicatorOffsetY = 0.0
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
    @AppStorage("selectedLanguage", store: SettingsStoreRuntime.appStorageStore)
    var selectedLanguage: String = Defaults.selectedLanguage
    @AppStorage(PindropThemeStorageKeys.themeMode, store: SettingsStoreRuntime.appStorageStore)
    var themeMode: String = Defaults.themeMode {
      didSet { notifyThemeDidChange() }
   }
   @AppStorage(PindropThemeStorageKeys.lightThemePresetID, store: SettingsStoreRuntime.appStorageStore)
   var lightThemePresetID: String = Defaults.lightThemePresetID {
      didSet { notifyThemeDidChange() }
   }
   @AppStorage(PindropThemeStorageKeys.darkThemePresetID, store: SettingsStoreRuntime.appStorageStore)
   var darkThemePresetID: String = Defaults.darkThemePresetID {
      didSet { notifyThemeDidChange() }
   }
   @AppStorage("automaticDictionaryLearningEnabled", store: SettingsStoreRuntime.appStorageStore)
   var automaticDictionaryLearningEnabled: Bool = Defaults.automaticDictionaryLearningEnabled
   @AppStorage("selectedInputDeviceUID", store: SettingsStoreRuntime.appStorageStore)
   var selectedInputDeviceUID: String = Defaults.selectedInputDeviceUID
   @AppStorage("aiEnhancementEnabled", store: SettingsStoreRuntime.appStorageStore)
   var aiEnhancementEnabled: Bool = false
   @AppStorage("aiProvider", store: SettingsStoreRuntime.appStorageStore)
   var aiProvider: String = AIProvider.openai.rawValue
   @AppStorage("customLocalProviderType", store: SettingsStoreRuntime.appStorageStore)
   var customLocalProviderType: String = CustomProviderType.custom.rawValue
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
   @AppStorage("pillFloatingIndicatorOffsetX", store: SettingsStoreRuntime.appStorageStore)
   var pillFloatingIndicatorOffsetX: Double = Defaults.pillFloatingIndicatorOffsetX
   @AppStorage("pillFloatingIndicatorOffsetY", store: SettingsStoreRuntime.appStorageStore)
   var pillFloatingIndicatorOffsetY: Double = Defaults.pillFloatingIndicatorOffsetY
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
   private var apiKeys: [String: String] = [:]

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

   var currentCustomLocalProvider: CustomProviderType {
      if let storedProvider = CustomProviderType(rawValue: customLocalProviderType),
         storedProvider != .custom
      {
         return storedProvider
      }

      return inferredCustomLocalProvider(for: apiEndpoint) ?? .custom
   }

   var selectedFloatingIndicatorType: FloatingIndicatorType {
      get { FloatingIndicatorType(rawValue: floatingIndicatorType) ?? .pill }
      set {
         let previousValue = selectedFloatingIndicatorType
         floatingIndicatorType = newValue.rawValue

         if previousValue == .pill, newValue != .pill {
            resetPillFloatingIndicatorOffset()
         }
      }
   }

    var selectedThemeMode: PindropThemeMode {
       get { PindropThemeMode(rawValue: themeMode) ?? .system }
       set { themeMode = newValue.rawValue }
    }

    var selectedAppLanguage: AppLanguage {
       get { AppLanguage(rawValue: selectedLanguage) ?? .automatic }
       set { selectedLanguage = newValue.rawValue }
    }

   var selectedLightThemePreset: PindropThemePreset {
      PindropThemePresetCatalog.preset(withID: lightThemePresetID)
   }

   var selectedDarkThemePreset: PindropThemePreset {
      PindropThemePresetCatalog.preset(withID: darkThemePresetID)
   }

   var pillFloatingIndicatorOffset: CGSize {
      get {
         CGSize(
            width: pillFloatingIndicatorOffsetX,
            height: pillFloatingIndicatorOffsetY
         )
      }
      set {
         pillFloatingIndicatorOffsetX = newValue.width
         pillFloatingIndicatorOffsetY = newValue.height
      }
   }

   func resetPillFloatingIndicatorOffset() {
      pillFloatingIndicatorOffset = CGSize(
         width: Defaults.pillFloatingIndicatorOffsetX,
         height: Defaults.pillFloatingIndicatorOffsetY
      )
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

   func inferredCustomLocalProvider(for endpoint: String?) -> CustomProviderType? {
      guard
         let endpoint = endpoint?.trimmingCharacters(in: .whitespacesAndNewlines),
         !endpoint.isEmpty
      else {
         return nil
      }

      let normalizedEndpoint = endpoint.lowercased()
      if normalizedEndpoint.contains("localhost:11434") || normalizedEndpoint.contains("127.0.0.1:11434") {
         return .ollama
      }
      if normalizedEndpoint.contains("localhost:1234") || normalizedEndpoint.contains("127.0.0.1:1234") {
         return .lmStudio
      }

      return .custom
   }

   init() {
      guard !SettingsStoreRuntime.isPreview else { return }
      apiEndpoint = try? loadFromKeychain(account: apiEndpointAccount)
      if let provider = provider(for: apiEndpoint) {
         aiProvider = provider.rawValue
      }
      if let customProvider = inferredCustomLocalProvider(for: apiEndpoint), currentAIProvider == .custom {
         customLocalProviderType = customProvider.rawValue
      }
      PindropThemeController.shared.refresh()
   }

   // MARK: - Keychain Methods
   private func resolvedCustomLocalProvider(_ customLocalProvider: CustomProviderType?) ->
      CustomProviderType
   {
      customLocalProvider ?? currentCustomLocalProvider
   }

   private func normalizedAPIKey(_ key: String?) -> String? {
      guard let key = key?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty else {
         return nil
      }
      return key
   }

   private func apiKeyAccount(
      for provider: AIProvider,
      customLocalProvider: CustomProviderType? = nil
   ) -> String {
      guard provider == .custom else {
         return "api-key-\(provider.rawValue)"
      }

      let resolvedProvider = resolvedCustomLocalProvider(customLocalProvider)
      return "api-key-\(provider.rawValue)-\(resolvedProvider.storageKey)"
   }

   private func apiKeyAccounts(for provider: AIProvider) -> [String] {
      guard provider == .custom else {
         return [apiKeyAccount(for: provider)]
      }

      return CustomProviderType.allCases.map {
         apiKeyAccount(for: provider, customLocalProvider: $0)
      } + ["api-key-\(provider.rawValue)"]
   }

   func saveAPIEndpoint(_ endpoint: String) throws {
      try saveToKeychain(value: endpoint, account: apiEndpointAccount)
      apiEndpoint = endpoint
      if let provider = provider(for: endpoint) {
         aiProvider = provider.rawValue
      }
      if let customProvider = inferredCustomLocalProvider(for: endpoint), currentAIProvider == .custom {
         customLocalProviderType = customProvider.rawValue
      }
   }

   func saveAPIKey(
      _ key: String,
      for provider: AIProvider,
      customLocalProvider: CustomProviderType? = nil
   ) throws {
      let account = apiKeyAccount(for: provider, customLocalProvider: customLocalProvider)

      guard let normalizedKey = normalizedAPIKey(key) else {
         try deleteFromKeychain(account: account)
         apiKeys.removeValue(forKey: account)
         return
      }

      try saveToKeychain(value: normalizedKey, account: account)
      apiKeys[account] = normalizedKey
   }

   @available(*, deprecated, message: "Use saveAPIKey(_:for:)")
   func saveAPIKey(_ key: String) throws {
      try saveAPIKey(key, for: currentAIProvider)
   }

   func loadAPIKey(
      for provider: AIProvider,
      customLocalProvider: CustomProviderType? = nil
   ) -> String? {
      let resolvedCustomProvider = resolvedCustomLocalProvider(customLocalProvider)
      let account = apiKeyAccount(for: provider, customLocalProvider: resolvedCustomProvider)

      if let cachedKey = apiKeys[account] {
         return cachedKey
      }

      if let storedKey = normalizedAPIKey((try? loadFromKeychain(account: account)) ?? nil) {
         apiKeys[account] = storedKey
         return storedKey
      }

      if provider == .custom,
         resolvedCustomProvider == .custom,
         let legacyCustomKey = normalizedAPIKey((try? loadFromKeychain(account: "api-key-\(provider.rawValue)")) ?? nil)
      {
         try? saveToKeychain(value: legacyCustomKey, account: account)
         apiKeys[account] = legacyCustomKey
         try? deleteFromKeychain(account: "api-key-\(provider.rawValue)")
         return legacyCustomKey
      }

      guard provider == currentAIProvider else { return nil }

      guard let legacyKey = normalizedAPIKey((try? loadFromKeychain(account: legacyAPIKeyAccount)) ?? nil)
      else { return nil }

      try? saveToKeychain(value: legacyKey, account: account)
      apiKeys[account] = legacyKey
      try? deleteFromKeychain(account: legacyAPIKeyAccount)

      return legacyKey
   }

   func configuredAPIKey(
      for provider: AIProvider,
      customLocalProvider: CustomProviderType? = nil
   ) -> String? {
      normalizedAPIKey(loadAPIKey(for: provider, customLocalProvider: customLocalProvider))
   }

   func requiresAPIKey(
      for provider: AIProvider,
      customLocalProvider: CustomProviderType? = nil
   ) -> Bool {
      switch provider {
      case .custom:
         return resolvedCustomLocalProvider(customLocalProvider).requiresAPIKey
      default:
         return true
      }
   }

   func hasRequiredAPIKey(
      for provider: AIProvider,
      customLocalProvider: CustomProviderType? = nil
   ) -> Bool {
      !requiresAPIKey(for: provider, customLocalProvider: customLocalProvider)
         || configuredAPIKey(for: provider, customLocalProvider: customLocalProvider) != nil
   }

   func configuredAPIKeyForCurrentAIProvider() -> String? {
      configuredAPIKey(for: currentAIProvider)
   }

   func currentAIProviderHasRequiredAPIKey() -> Bool {
      hasRequiredAPIKey(for: currentAIProvider)
   }

   func deleteAPIEndpoint() throws {
      try deleteFromKeychain(account: apiEndpointAccount)
      apiEndpoint = nil
   }

   func deleteAPIKey(
      for provider: AIProvider,
      customLocalProvider: CustomProviderType? = nil
   ) throws {
      let account = apiKeyAccount(for: provider, customLocalProvider: customLocalProvider)
      try deleteFromKeychain(account: account)
      apiKeys.removeValue(forKey: account)
   }

   @available(*, deprecated, message: "Use deleteAPIKey(for:)")
   func deleteAPIKey() throws {
      try deleteAPIKey(for: currentAIProvider)
   }

   func resetAllSettings() {
      selectedModel = Defaults.selectedModel
      themeMode = Defaults.themeMode
      lightThemePresetID = Defaults.lightThemePresetID
      darkThemePresetID = Defaults.darkThemePresetID
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
      selectedLanguage = Defaults.selectedLanguage
      selectedInputDeviceUID = Defaults.selectedInputDeviceUID
      aiEnhancementEnabled = false
      aiProvider = AIProvider.openai.rawValue
      customLocalProviderType = CustomProviderType.custom.rawValue
      floatingIndicatorEnabled = Defaults.floatingIndicatorEnabled
      floatingIndicatorType = Defaults.floatingIndicatorType
      resetPillFloatingIndicatorOffset()
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
         for account in apiKeyAccounts(for: provider) {
            try? deleteFromKeychain(account: account)
         }
      }
      try? deleteFromKeychain(account: legacyAPIKeyAccount)
      apiKeys.removeAll()

      objectWillChange.send()
   }

   private func notifyThemeDidChange() {
      guard !SettingsStoreRuntime.isPreview else { return }
      PindropThemeController.shared.refresh()
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

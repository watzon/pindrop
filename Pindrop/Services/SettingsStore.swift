//
//  SettingsStore.swift
//  Pindrop
//
//  Created on 2026-01-25.
//

import Combine
import Foundation
import Security
import Speech
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

public enum SidebarPosition: String, CaseIterable, Identifiable {
   case leading
   case trailing

   public var id: String { rawValue }

   var icon: String {
      switch self {
      case .leading: return "sidebar.left"
      case .trailing: return "sidebar.right"
      }
   }
}

/// Which streaming transcription engine the user prefers. Availability at runtime may
/// force the service to substitute a different backend — see
/// `SettingsStore.resolvedTranscriptionBackend` for the effective value.
public enum TranscriptionBackend: String, CaseIterable, Sendable, Identifiable {
   /// Parakeet Realtime EOU via FluidAudio. Available on all supported macOS versions;
   /// requires a ~150 MB model download.
   case parakeet = "parakeet"

   /// Apple's on-device `Speech.SpeechTranscriber` (macOS 26+). Ships with the OS,
   /// zero download, but locale coverage follows Apple's supported-locales list.
   case appleSpeechTranscriber = "apple"

   public var id: String { rawValue }

   var displayNameKey: String {
      switch self {
      case .parakeet: return "Parakeet (default)"
      case .appleSpeechTranscriber: return "Apple SpeechTranscriber (macOS 26+)"
      }
   }
}

public enum AppLanguage: String, CaseIterable, Sendable, Identifiable {
   case automatic = "auto"
   case english = "en"
   case simplifiedChinese = "zh-Hans"
   case spanish = "es"
   case french = "fr"
   case german = "de"
   case turkish = "tr"
   case japanese = "ja"
   case portugueseBrazil = "pt-BR"
   case italian = "it"
   case dutch = "nl"
   case korean = "ko"

   public var id: String { rawValue }

   private struct Metadata {
      let displayKey: String
      let whisperCode: String?
      let localeIdentifier: String?
      let selectable: Bool
   }

   private var metadata: Metadata {
      switch self {
      case .automatic:        return Metadata(displayKey: "Automatic (Follow System)", whisperCode: nil, localeIdentifier: nil, selectable: true)
      case .english:          return Metadata(displayKey: "English", whisperCode: "en", localeIdentifier: "en", selectable: true)
      case .simplifiedChinese: return Metadata(displayKey: "Simplified Chinese", whisperCode: "zh", localeIdentifier: "zh-Hans", selectable: true)
      case .spanish:          return Metadata(displayKey: "Spanish", whisperCode: "es", localeIdentifier: "es", selectable: true)
      case .french:           return Metadata(displayKey: "French", whisperCode: "fr", localeIdentifier: "fr", selectable: true)
      case .german:           return Metadata(displayKey: "German", whisperCode: "de", localeIdentifier: "de", selectable: true)
      case .turkish:          return Metadata(displayKey: "Turkish", whisperCode: "tr", localeIdentifier: "tr", selectable: true)
      case .japanese:         return Metadata(displayKey: "Japanese", whisperCode: "ja", localeIdentifier: "ja", selectable: true)
      case .portugueseBrazil: return Metadata(displayKey: "Portuguese (Brazil)", whisperCode: "pt", localeIdentifier: "pt-BR", selectable: true)
      case .italian:          return Metadata(displayKey: "Italian", whisperCode: "it", localeIdentifier: "it", selectable: true)
      case .dutch:            return Metadata(displayKey: "Dutch", whisperCode: "nl", localeIdentifier: "nl", selectable: true)
      case .korean:           return Metadata(displayKey: "Korean", whisperCode: "ko", localeIdentifier: "ko", selectable: true)
      }
   }

   var displayName: String {
      displayName(locale: .autoupdatingCurrent)
   }

   var pickerLabel: String {
      pickerLabel(locale: .autoupdatingCurrent)
   }

   func displayName(locale: Locale) -> String {
      localized(metadata.displayKey, locale: locale)
   }

   func pickerLabel(locale: Locale) -> String {
      let name = displayName(locale: locale)
      guard !isSelectable else { return name }
      return String(format: localized("%@ (Coming Soon)", locale: locale), name)
   }

   var isSelectable: Bool { metadata.selectable }

   var isEnglish: Bool { self == .english }

   var locale: Locale {
      guard let id = metadata.localeIdentifier else { return .autoupdatingCurrent }
      return Locale(identifier: id)
   }

   var whisperLanguageCode: String? { metadata.whisperCode }

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
      static let sidebarPosition = SidebarPosition.trailing.rawValue
      static let automaticDictionaryLearningEnabled = true
      static let selectedInputDeviceUID = ""
      static let aiModel = "openai/gpt-4o-mini"
      static let aiEnhancementPrompt =
         "You are a text enhancement assistant. Improve the grammar, punctuation, and formatting of the provided text while preserving its original meaning and tone. Return only the enhanced text without any additional commentary."
      static let floatingIndicatorEnabled = true
      static let floatingIndicatorType = FloatingIndicatorType.dot.rawValue
      static let pillFloatingIndicatorOffsetX = 0.0
      static let pillFloatingIndicatorOffsetY = 0.0
      static let dotFloatingIndicatorOffsetX = 0.0
      static let dotFloatingIndicatorOffsetY = 0.0
      static let dotFloatingIndicatorSize = "large"
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
   @AppStorage("didMigrateToCleanTranscriptDefault", store: SettingsStoreRuntime.appStorageStore)
   var didMigrateToCleanTranscriptDefault: Bool = false
   @AppStorage("floatingIndicatorEnabled", store: SettingsStoreRuntime.appStorageStore)
   var floatingIndicatorEnabled: Bool = Defaults.floatingIndicatorEnabled
   @AppStorage("floatingIndicatorType", store: SettingsStoreRuntime.appStorageStore)
   var floatingIndicatorType: String = Defaults.floatingIndicatorType
   @AppStorage("pillFloatingIndicatorOffsetX", store: SettingsStoreRuntime.appStorageStore)
   var pillFloatingIndicatorOffsetX: Double = Defaults.pillFloatingIndicatorOffsetX
   @AppStorage("pillFloatingIndicatorOffsetY", store: SettingsStoreRuntime.appStorageStore)
   var pillFloatingIndicatorOffsetY: Double = Defaults.pillFloatingIndicatorOffsetY
   @AppStorage("dotFloatingIndicatorOffsetX", store: SettingsStoreRuntime.appStorageStore)
   var dotFloatingIndicatorOffsetX: Double = Defaults.dotFloatingIndicatorOffsetX
   @AppStorage("dotFloatingIndicatorOffsetY", store: SettingsStoreRuntime.appStorageStore)
   var dotFloatingIndicatorOffsetY: Double = Defaults.dotFloatingIndicatorOffsetY
   @AppStorage("dotFloatingIndicatorSize", store: SettingsStoreRuntime.appStorageStore)
   var dotFloatingIndicatorSize: String = Defaults.dotFloatingIndicatorSize
   @AppStorage("sidebarPosition", store: SettingsStoreRuntime.appStorageStore)
   var sidebarPosition: String = Defaults.sidebarPosition
   @AppStorage("sidebarExpanded", store: SettingsStoreRuntime.appStorageStore)
   var sidebarExpanded: Bool = true
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

   // MARK: V2 AI Configuration (providers + per-purpose assignments)
   //
   // These AppStorage blobs store non-secret v2 config. Secrets (API keys, endpoint
   // overrides) live in Keychain keyed by each ProviderConfig's UUID. Legacy
   // `aiProvider` / `aiModel` / `aiEnhancementEnabled` / `aiEnhancementPrompt` /
   // `noteEnhancementPrompt` / `customLocalProviderType` remain readable for one release
   // behind the `aiConfigV2Migrated` flag; after migration they are no longer consulted.
   @AppStorage("aiConfigProvidersJSON", store: SettingsStoreRuntime.appStorageStore)
   var aiConfigProvidersJSON: String = "[]"
   @AppStorage("aiConfigAssignmentsJSON", store: SettingsStoreRuntime.appStorageStore)
   var aiConfigAssignmentsJSON: String = "{}"
   @AppStorage("aiConfigV2Migrated", store: SettingsStoreRuntime.appStorageStore)
   var aiConfigV2Migrated: Bool = false

   @AppStorage("vadFeatureEnabled", store: SettingsStoreRuntime.appStorageStore)
   var vadFeatureEnabled: Bool = false
   @AppStorage("diarizationFeatureEnabled", store: SettingsStoreRuntime.appStorageStore)
   var diarizationFeatureEnabled: Bool = false
   @AppStorage("streamingFeatureEnabled", store: SettingsStoreRuntime.appStorageStore)
   var streamingFeatureEnabled: Bool = false
   /// Picks the Parakeet EOU chunk variant used by the streaming backend. OFF (default)
   /// maps to the 320ms variant — lower WER, ~160ms extra latency on partials. ON maps
   /// to the 160ms variant — snappier partials, noisier text.
   @AppStorage("streamingLowLatencyMode", store: SettingsStoreRuntime.appStorageStore)
   var streamingLowLatencyMode: Bool = false

   /// Which streaming transcription backend to use. Default is Parakeet (cross-platform,
   /// 150MB model download). `.apple` uses Apple's SpeechTranscriber (macOS 26+, zero
   /// download) but falls back to Parakeet when unavailable on the host.
   @AppStorage("transcriptionBackend", store: SettingsStoreRuntime.appStorageStore)
   var transcriptionBackend: String = TranscriptionBackend.parakeet.rawValue

   /// Whether to run the post-stop LLM cleanup pass on streaming transcripts. OFF by
   /// default (Phase 3 update): the deterministic cleaner handles filler removal,
   /// capitalization, spoken punctuation, word-number normalization, and split-word
   /// merges on its own. Users can opt back in if they've configured a
   /// `transcriptionEnhancement` assignment and want the LLM to polish the final text.
   @AppStorage("streamingPostStopEnhancementEnabled", store: SettingsStoreRuntime.appStorageStore)
   var streamingPostStopEnhancementEnabled: Bool = false

   @Published private(set) var vibeRuntimeState: VibeRuntimeState = .degraded
   @Published private(set) var vibeRuntimeDetail: String = "Vibe mode is disabled."
   @Published private(set) var isApplyingHotkeyUpdate = false

   // MARK: - Onboarding State

   @AppStorage("hasCompletedOnboarding", store: SettingsStoreRuntime.appStorageStore)
   var hasCompletedOnboarding: Bool = false
   @AppStorage("currentOnboardingStep", store: SettingsStoreRuntime.appStorageStore)
   var currentOnboardingStep: Int = 0

   // MARK: - MCP Server

   @AppStorage("mcpServerEnabled", store: SettingsStoreRuntime.appStorageStore)
   var mcpServerEnabled: Bool = false
   @AppStorage("mcpServerPort", store: SettingsStoreRuntime.appStorageStore)
   var mcpServerPort: Int = 46337

   // MARK: - Keychain Properties

   private let keychainService = "com.pindrop.settings"
   private let apiEndpointAccount = "api-endpoint"
   /// Per Custom / Ollama / LM Studio endpoint storage (OpenAI-compatible URLs).
   private func apiEndpointCustomAccount(for type: CustomProviderType) -> String {
      "api-endpoint-custom-\(type.storageKey)"
   }

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

      let genericEndpoint =
         (try? loadFromKeychain(account: apiEndpointCustomAccount(for: .custom)))
         ?? ""
      let trimmed = genericEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
      return inferredCustomLocalProvider(for: trimmed.isEmpty ? nil : trimmed) ?? .custom
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

    /// Streaming chunk profile derived from `streamingLowLatencyMode`. OFF (the default)
    /// resolves to `.standard` (320ms); ON resolves to `.lowLatency` (160ms).
    var streamingChunkProfile: StreamingChunkProfile {
       streamingLowLatencyMode ? .lowLatency : .standard
    }

    /// User-selected transcription backend. Reads the raw storage string. Use
    /// `resolvedTranscriptionBackend` when you need the backend actually in use after
    /// availability checks.
    var selectedTranscriptionBackend: TranscriptionBackend {
       get { TranscriptionBackend(rawValue: transcriptionBackend) ?? .parakeet }
       set { transcriptionBackend = newValue.rawValue }
    }

    /// Backend actually usable on this host. Mirrors `selectedTranscriptionBackend` unless
    /// Apple SpeechTranscriber was chosen but is unavailable (e.g., < macOS 26), in which
    /// case we fall back to Parakeet.
    var resolvedTranscriptionBackend: TranscriptionBackend {
       switch selectedTranscriptionBackend {
       case .parakeet:
          return .parakeet
       case .appleSpeechTranscriber:
          return Self.appleSpeechTranscriberAvailable ? .appleSpeechTranscriber : .parakeet
       }
    }

    /// True when the current host can run Apple SpeechTranscriber. Checked synchronously;
    /// deeper locale/asset checks happen at engine load time.
    static var appleSpeechTranscriberAvailable: Bool {
       if #available(macOS 26, *) {
          return Speech.SpeechTranscriber.isAvailable
       }
       return false
    }

    var selectedSidebarPosition: SidebarPosition {
       get { SidebarPosition(rawValue: sidebarPosition) ?? .trailing }
       set { sidebarPosition = newValue.rawValue }
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

   var dotFloatingIndicatorOffset: CGSize {
      get {
         CGSize(
            width: dotFloatingIndicatorOffsetX,
            height: dotFloatingIndicatorOffsetY
         )
      }
      set {
         dotFloatingIndicatorOffsetX = newValue.width
         dotFloatingIndicatorOffsetY = newValue.height
      }
   }

   func resetDotFloatingIndicatorOffset() {
      dotFloatingIndicatorOffset = CGSize(
         width: Defaults.dotFloatingIndicatorOffsetX,
         height: Defaults.dotFloatingIndicatorOffsetY
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
       migrateLegacyCustomEndpointIfNeeded()
       refreshCachedAPIEndpoint()
       // Only infer provider from the stored endpoint URL if the user hasn't explicitly
       // chosen a provider that doesn't use an endpoint (e.g. Apple Intelligence).
       // Without this guard, a stale OpenRouter/OpenAI URL in the keychain would
       // overwrite the saved "Apple" provider choice on every launch.
       if AIProvider(rawValue: aiProvider) != .apple,
          let inferredProvider = provider(for: apiEndpoint) {
          aiProvider = inferredProvider.rawValue
       }
       if let customProvider = inferredCustomLocalProvider(for: apiEndpoint), currentAIProvider == .custom {
          customLocalProviderType = customProvider.rawValue
       }
       // v2 AI configuration migration (providers + per-purpose assignments). Idempotent;
       // gated on `aiConfigV2Migrated`. Legacy properties are left readable behind the flag
       // for one release as a rollback path.
       migrateToAIConfigV2IfNeeded()
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

   /// Saved OpenAI-compatible URL for a custom provider subtype (Custom, Ollama, LM Studio, …).
   func storedAPIEndpoint(forCustomLocalProvider type: CustomProviderType) -> String? {
      guard let value = try? loadFromKeychain(account: apiEndpointCustomAccount(for: type)) else {
         return nil
      }
      let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
      return trimmed.isEmpty ? nil : trimmed
   }

   /// Persists the API endpoint for the given provider. Custom OpenAI-compatible endpoints are stored per subtype.
   func saveAPIEndpoint(
      _ endpoint: String,
      for targetProvider: AIProvider,
      customLocalProvider: CustomProviderType? = nil
   ) throws {
      let trimmed = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)

      if targetProvider == .custom {
         let resolved = customLocalProvider ?? currentCustomLocalProvider
         let account = apiEndpointCustomAccount(for: resolved)
         if trimmed.isEmpty {
            try deleteFromKeychain(account: account)
         } else {
            try saveToKeychain(value: trimmed, account: account)
         }
         if let p = provider(for: trimmed.isEmpty ? nil : trimmed) {
            aiProvider = p.rawValue
         }
         refreshCachedAPIEndpoint()
         objectWillChange.send()
         return
      }

      if trimmed.isEmpty {
         try deleteFromKeychain(account: apiEndpointAccount)
         apiEndpoint = nil
      } else {
         try saveToKeychain(value: trimmed, account: apiEndpointAccount)
         apiEndpoint = trimmed
         if let p = provider(for: trimmed) {
            aiProvider = p.rawValue
         }
      }
      objectWillChange.send()
   }

   /// Legacy helper: infers built-in vs custom from the URL and which custom subtype to use.
   func saveAPIEndpoint(_ endpoint: String) throws {
      let trimmed = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty else {
         try deleteFromKeychain(account: apiEndpointAccount)
         for type in CustomProviderType.allCases {
            try? deleteFromKeychain(account: apiEndpointCustomAccount(for: type))
         }
         refreshCachedAPIEndpoint()
         objectWillChange.send()
         return
      }
      guard let p = provider(for: trimmed) else {
         try saveAPIEndpoint(trimmed, for: .openai, customLocalProvider: nil)
         return
      }
      switch p {
      case .custom:
         let customType = inferredCustomLocalProvider(for: trimmed) ?? .custom
         try saveAPIEndpoint(trimmed, for: .custom, customLocalProvider: customType)
         customLocalProviderType = customType.rawValue
      default:
         try saveAPIEndpoint(trimmed, for: p, customLocalProvider: nil)
      }
   }

   private func migrateLegacyCustomEndpointIfNeeded() {
      guard let legacy = try? loadFromKeychain(account: apiEndpointAccount) else { return }
      let trimmed = legacy.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty, provider(for: trimmed) == .custom else { return }

      let targetType: CustomProviderType =
         if let stored = CustomProviderType(rawValue: customLocalProviderType), stored != .custom {
            stored
         } else {
            inferredCustomLocalProvider(for: trimmed) ?? .custom
         }

      let account = apiEndpointCustomAccount(for: targetType)
      if ((try? loadFromKeychain(account: account)) ?? nil) == nil {
         try? saveToKeychain(value: trimmed, account: account)
      }
      try? deleteFromKeychain(account: apiEndpointAccount)
   }

   private func refreshCachedAPIEndpoint() {
      if currentAIProvider == .custom {
         let account = apiEndpointCustomAccount(for: currentCustomLocalProvider)
         apiEndpoint = try? loadFromKeychain(account: account)
      } else {
         apiEndpoint = try? loadFromKeychain(account: apiEndpointAccount)
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
      case .apple:
         return false
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
      for type in CustomProviderType.allCases {
         try? deleteFromKeychain(account: apiEndpointCustomAccount(for: type))
      }
      refreshCachedAPIEndpoint()
      objectWillChange.send()
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
      aiEnhancementPrompt = Defaults.aiEnhancementPrompt
      noteEnhancementPrompt = Defaults.noteEnhancementPrompt
      selectedPresetId = nil
      didMigrateToCleanTranscriptDefault = false
      aiProvider = AIProvider.openai.rawValue
      customLocalProviderType = CustomProviderType.custom.rawValue
      // v2 AI config: clear persisted blobs so tests (and user-initiated resets) start with
      // a clean slate and re-run the migrator on next init.
      let previousProviders = providers
      aiConfigProvidersJSON = "[]"
      aiConfigAssignmentsJSON = "{}"
      aiConfigV2Migrated = false
      for config in previousProviders {
         try? deleteProviderAPIKey(forProviderID: config.id)
         try? deleteProviderEndpoint(forProviderID: config.id)
      }
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

   // MARK: - Keychain Helpers (module-internal so SettingsStore+AIConfigV2 can reuse them)

   func saveToKeychain(value: String, account: String) throws {
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

   func loadFromKeychain(account: String) throws -> String? {
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

   func deleteFromKeychain(account: String) throws {
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

   // MARK: - MCP Token

   private let mcpServerTokenAccount = "mcp-server-token"

   func loadMCPToken() -> String? {
      try? loadFromKeychain(account: mcpServerTokenAccount)
   }

   func saveMCPToken(_ token: String) throws {
      try saveToKeychain(value: token, account: mcpServerTokenAccount)
   }

   func deleteMCPToken() throws {
      try deleteFromKeychain(account: mcpServerTokenAccount)
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

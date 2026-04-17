//
//  AIEnhancementStepView.swift
//  Pindrop
//
//  Created on 2026-01-25.
//

import Foundation
import SwiftUI

enum AIProvider: String, CaseIterable, Identifiable {
   case openai = "OpenAI"
   case google = "Google"
   case anthropic = "Anthropic"
   case openrouter = "OpenRouter"
   case apple = "Apple"
   case custom = "Custom"

   var id: String { rawValue }

   var displayName: String {
      switch self {
      case .apple:
         return "Apple Intelligence"
      case .custom:
         return "Custom/Local"
      default:
         return rawValue
      }
   }

   var icon: Icon {
      switch self {
      case .openai: return .openai
      case .google: return .google
      case .anthropic: return .anthropic
      case .openrouter: return .openrouter
      case .apple: return .sparkles
      case .custom: return .server
      }
   }

   var defaultEndpoint: String {
      switch self {
      case .openai: return "https://api.openai.com/v1/chat/completions"
      case .google: return "https://generativelanguage.googleapis.com/v1beta"
      case .anthropic: return "https://api.anthropic.com/v1/messages"
      case .openrouter: return "https://openrouter.ai/api/v1/chat/completions"
      case .apple: return ""
      case .custom: return ""
      }
   }

   var apiKeyPlaceholder: String {
      switch self {
      case .openai: return "sk-..."
      case .google: return "AIza..."
      case .anthropic: return "sk-ant-..."
      case .openrouter: return "sk-or-..."
      case .apple: return "Not required"
      case .custom: return "Enter API key"
      }
   }

   /// Whether this provider requires API credentials (key + endpoint) to operate.
   var requiresAPICredentials: Bool {
      switch self {
      case .apple: return false
      default: return true
      }
   }

   var isImplemented: Bool {
      switch self {
      case .openai, .openrouter, .custom, .anthropic, .apple: return true
      default: return false
      }
   }
}

enum CustomProviderType: String, CaseIterable, Identifiable {
   case custom = "Custom"
   case ollama = "Ollama"
   case lmStudio = "LM Studio"

   var id: String { rawValue }

   var icon: Icon {
      switch self {
      case .custom:
         return .server
      case .ollama, .lmStudio:
         return .hardDrive
      }
   }

   var storageKey: String {
      switch self {
      case .custom:
         return "custom"
      case .ollama:
         return "ollama"
      case .lmStudio:
         return "lm-studio"
      }
   }

   var requiresAPIKey: Bool {
      self == .custom
   }

   var supportsModelListing: Bool {
      self != .custom
   }

   var defaultEndpoint: String {
      switch self {
      case .custom:
         return ""
      case .ollama:
         return "http://localhost:11434/v1/chat/completions"
      case .lmStudio:
         return "http://localhost:1234/v1/chat/completions"
      }
   }

   var defaultModelsEndpoint: String? {
      switch self {
      case .custom:
         return nil
      case .ollama:
         return "http://localhost:11434/v1/models"
      case .lmStudio:
         return "http://localhost:1234/v1/models"
      }
   }

   var apiKeyPlaceholder: String {
      switch self {
      case .custom:
         return "Enter API key"
      case .ollama:
         return "Optional (usually not needed)"
      case .lmStudio:
         return "Optional unless auth is enabled"
      }
   }

   var endpointPlaceholder: String {
      switch self {
      case .custom:
         return "https://your-api.com/v1/chat/completions"
      case .ollama:
         return defaultEndpoint
      case .lmStudio:
         return defaultEndpoint
      }
   }

   var modelPlaceholder: String {
      switch self {
      case .custom:
         return "e.g., gpt-4o"
      case .ollama:
         return "e.g., llama3.2"
      case .lmStudio:
         return "e.g., local-model"
      }
   }
}

struct AIEnhancementStepView: View {
    @ObservedObject var settings: SettingsStore
    let onContinue: () -> Void
    let onSkip: () -> Void
    let onPreferredContentSizeChange: (CGSize) -> Void

    @Environment(\.locale) private var locale
    @State private var selectedProvider: AIProvider = .openai
    @State private var selectedCustomProvider: CustomProviderType = .custom
    @State private var apiKey = ""
    @State private var customEndpointDrafts: [CustomProviderType: String] = [:]
    @State private var selectedModel = "gpt-4o-mini"
    @State private var customModel = ""
    @State private var showingAPIKey = false
    @State private var availableModels: [AIModelService.AIModel] = []
    @State private var isLoadingModels = false
    @State private var modelError: String?
    @State private var modelService = AIModelService()
    @State private var endpointRefreshTask: Task<Void, Never>?

    private static func preferredContentSize(for provider: AIProvider) -> CGSize {
        switch provider {
        case .openrouter, .openai:
           return CGSize(width: 800, height: 820)
        case .custom:
           return CGSize(width: 800, height: 900)
        default:
           return CGSize(width: 800, height: 720)
        }
    }
    private var preferredContentSize: CGSize {
       Self.preferredContentSize(for: selectedProvider)
    }

    var body: some View {
       VStack(spacing: 20) {
          headerSection

          providerTabs

          providerConfigSection
             .frame(maxHeight: .infinity)

          actionButtons
       }
       .padding(.horizontal, 40)
        .padding(.top, 16)
        .padding(.bottom, 24)
        .onAppear {
           loadSavedConfiguration()
           onPreferredContentSizeChange(preferredContentSize)
        }
        .onChange(of: selectedProvider) { oldValue, newValue in
           if newValue == .custom {
              applyCustomEndpointDefault(forceReset: oldValue != .custom)
           }

           apiKey = loadKeyForCurrentSelection()
           onPreferredContentSizeChange(preferredContentSize)
           Task {
              await loadModelsIfNeeded(
                 for: newValue,
                 customLocalProvider: selectedCustomProvider,
                 forceRefresh: newValue == .custom
              )
           }
        }
        .onChange(of: apiKey) { _, newValue in
           guard selectedProvider == .openai else { return }
           guard !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
           Task { await loadModelsIfNeeded(for: .openai, forceRefresh: true) }
        }
        .onChange(of: selectedCustomProvider) { _, newValue in
           apiKey = loadKeyForCurrentSelection()

           if newValue == .custom {
              if customModel.isEmpty {
                 customModel = selectedModel
              }
              availableModels = []
              modelError = nil
           }

           Task {
              await loadModelsIfNeeded(
                 for: .custom,
                 customLocalProvider: newValue,
                 forceRefresh: true
              )
           }
        }
    }

    private var headerSection: some View {
       VStack(spacing: 6) {
          IconView(icon: .sparkles, size: 36)
             .foregroundStyle(AppColors.accent)

          Text(localized("AI Enhancement", locale: locale))
             .font(.system(size: 24, weight: .bold, design: .rounded))

          Text(localized("Optionally clean up transcriptions with AI", locale: locale))
             .font(.subheadline)
             .foregroundStyle(.secondary)
       }
    }

    private var providerTabs: some View {
       HStack(spacing: 0) {
          ForEach(AIProvider.allCases) { provider in
             providerTab(provider)
          }
       }
       .frame(height: 56)
       .background(.ultraThinMaterial, in: .rect(cornerRadius: 12))
    }

    private func providerTab(_ provider: AIProvider) -> some View {
       Button {
          withAnimation(.spring(duration: 0.3)) {
             selectedProvider = provider
          }
       } label: {
          VStack(spacing: 4) {
             IconView(icon: provider.icon, size: 18)
             Text(provider.displayName)
                .font(.caption)
                .fontWeight(.medium)
          }
          .frame(maxWidth: .infinity)
          .padding(.vertical, 12)
          .contentShape(Rectangle())
          .background(
             selectedProvider == provider
                ? AppColors.accent.opacity(0.2)
                : Color.clear
          )
          .foregroundStyle(selectedProvider == provider ? AppColors.accent : .secondary)
       }
       .buttonStyle(.plain)
    }

    @ViewBuilder
    private var providerConfigSection: some View {
       VStack(spacing: 16) {
          if !selectedProvider.isImplemented {
             comingSoonView
          } else if selectedProvider == .apple {
             appleIntelligenceConfig
          } else {
             if selectedProvider == .custom {
                customProviderPicker
             }

             apiKeyField

             if selectedProvider == .openrouter || selectedProvider == .openai || selectedProvider == .anthropic {
                modelPicker
             }

             if selectedProvider == .custom {
                if selectedCustomProvider.supportsModelListing {
                   modelPicker
                 } else {
                   customModelField
                 }
                 customEndpointField
             }

             Spacer()

             featureList
          }
       }
       .padding(20)
       .frame(maxWidth: .infinity, maxHeight: .infinity)
       .background(.ultraThinMaterial, in: .rect(cornerRadius: 16))
    }

    @ViewBuilder
    private var appleIntelligenceConfig: some View {
       VStack(spacing: 16) {
          if #available(macOS 26, *) {
             VStack(spacing: 12) {
                HStack(spacing: 10) {
                   IconView(icon: .sparkles, size: 20)
                      .foregroundStyle(.green)
                   Text(localized("Available on This Mac", locale: locale))
                      .font(.headline)
                      .foregroundStyle(.primary)
                   Spacer()
                }
                .padding(14)
                .background(.green.opacity(0.1), in: .rect(cornerRadius: 10))

                appleIntelligenceFeatureList
             }
          } else {
             VStack(spacing: 12) {
                HStack(spacing: 10) {
                   IconView(icon: .warning, size: 20)
                      .foregroundStyle(.orange)
                   Text(localized("Requires macOS 26 or Later", locale: locale))
                      .font(.headline)
                      .foregroundStyle(.primary)
                   Spacer()
                }
                Text(localized("Apple Intelligence and on-device AI enhancement require macOS 26 with Apple Intelligence enabled. Upgrade your Mac to use this feature.", locale: locale))
                   .font(.subheadline)
                   .foregroundStyle(.secondary)
                   .multilineTextAlignment(.leading)
             }
             .padding(14)
             .background(.orange.opacity(0.1), in: .rect(cornerRadius: 10))

             appleIntelligenceFeatureList
          }

          Spacer()
       }
    }

    private var appleIntelligenceFeatureList: some View {
       VStack(alignment: .leading, spacing: 8) {
          Text(localized("Apple Intelligence Enhancement:", locale: locale))
             .font(.subheadline)
             .fontWeight(.medium)

          appleFeatureItem(localized("Completely on-device — no data sent anywhere", locale: locale), icon: .shield)
          appleFeatureItem(localized("No API key or subscription required", locale: locale), icon: .circleCheck)
          appleFeatureItem(localized("Works offline, no internet needed", locale: locale), icon: .circleCheck)
          appleFeatureItem(localized("Uses Apple's 3B parameter language model", locale: locale), icon: .circleCheck)
       }
       .frame(maxWidth: .infinity, alignment: .leading)
       .padding(16)
       .background(AppColors.accent.opacity(0.05))
       .background(.ultraThinMaterial, in: .rect(cornerRadius: 12))
    }

    private func appleFeatureItem(_ text: String, icon: Icon) -> some View {
       HStack(spacing: 8) {
          IconView(icon: icon, size: 14)
             .foregroundStyle(.green)
          Text(text)
             .font(.caption)
             .foregroundStyle(.secondary)
       }
    }

    private var comingSoonView: some View {
       VStack(spacing: 12) {
          Spacer()

          IconView(icon: .construction, size: 40)
             .foregroundStyle(.secondary)

          Text(localized("%@ Support Coming Soon", locale: locale).replacingOccurrences(of: "%@", with: selectedProvider.displayName))
             .font(.headline)

          Text(
             localized("This provider will be available in a future update.\nFor now, try OpenAI or use a Custom endpoint.", locale: locale)
          )
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)

          Spacer()
       }
    }

     private var apiKeyField: some View {
        VStack(alignment: .leading, spacing: 8) {
           HStack(spacing: 8) {
              Text(localized("API Key", locale: locale))
                 .font(.subheadline)
                 .fontWeight(.medium)

              if isAPIKeyOptional {
                 Text(localized("Optional", locale: locale))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.ultraThinMaterial, in: Capsule())
              }
           }

           HStack {
              Group {
                 if showingAPIKey {
                   TextField(currentAPIKeyPlaceholder, text: $apiKey)
                 } else {
                   SecureField(currentAPIKeyPlaceholder, text: $apiKey)
                 }
              }
              .textFieldStyle(.plain)

             Button {
                showingAPIKey.toggle()
             } label: {
                IconView(icon: showingAPIKey ? .eyeOff : .eye, size: 16)
                   .foregroundStyle(.secondary)
             }
             .buttonStyle(.plain)
           }
           .aiSettingsInputChrome()

           if let apiKeyHelpText {
              Text(apiKeyHelpText)
                 .font(.caption)
                .foregroundStyle(.secondary)
          }
        }
     }

     private var customProviderPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
           Text(localized("Provider Type", locale: locale))
              .font(.subheadline)
              .fontWeight(.medium)

           SelectField(
              options: customProviderOptions,
              selection: customProviderSelection,
              placeholder: localized("Select a provider type", locale: locale)
           )
           .frame(maxWidth: 220, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }

     private var customEndpointField: some View {
        VStack(alignment: .leading, spacing: 8) {
          HStack {
             Text(localized("API Endpoint", locale: locale))
                .font(.subheadline)
                .fontWeight(.medium)

             Spacer()

              Text(selectedCustomProvider == .custom
                 ? localized("Must be OpenAI-compatible", locale: locale)
                 : localized("OpenAI-compatible local server", locale: locale))
                 .font(.caption)
                 .foregroundStyle(.secondary)
          }

           TextField(selectedCustomProvider.endpointPlaceholder, text: customEndpointTextBinding())
              .textFieldStyle(.plain)
              .aiSettingsInputChrome()
        }
     }

    private var customModelField: some View {
       VStack(alignment: .leading, spacing: 8) {
           Text(localized("AI Model", locale: locale))
              .font(.subheadline)
              .fontWeight(.medium)

            TextField(selectedCustomProvider.modelPlaceholder, text: $customModel)
               .textFieldStyle(.plain)
               .aiSettingsInputChrome()
        }
      }

     private var modelPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
          HStack {
             Text(localized("AI Model", locale: locale))
                .font(.subheadline)
                .fontWeight(.medium)
             Spacer()

             if isLoadingModels {
                ProgressView()
                   .controlSize(.small)
             }

             Button(localized("Refresh", locale: locale)) {
                 Task {
                    await loadModelsIfNeeded(
                       for: selectedProvider,
                       customLocalProvider: selectedCustomProvider,
                       forceRefresh: true
                    )
                 }
              }
             .buttonStyle(.bordered)
             .controlSize(.small)
             .disabled(
                isLoadingModels
                   || (selectedProvider == .openai
                      && apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
             )
          }

           if availableModels.isEmpty {
              Text(emptyModelsMessage)
                 .font(.caption)
                 .foregroundStyle(.secondary)
                 .frame(maxWidth: .infinity, alignment: .leading)
                 .aiSettingsInputChrome()
           } else {
              SearchableDropdown(
                 items: availableModels,
                 selection: Binding(
                  get: { selectedModel.isEmpty ? nil : selectedModel },
                  set: { selectedModel = $0 ?? "" }
               ),
                placeholder: localized("Select a model", locale: locale),
                emptyMessage: localized("No models found.", locale: locale),
                searchPlaceholder: localized("Search models...", locale: locale)
             )
             .frame(maxWidth: .infinity)
           }

           if let modelError {
              HStack(spacing: 6) {
                 IconView(icon: .warning, size: 12)
                    .foregroundStyle(.red)
                 Text(modelError)
                    .font(.caption)
                    .foregroundStyle(.red)
              }
           }
        }
        .zIndex(10)
    }


   private var emptyModelsMessage: String {
      if isLoadingModels {
         return localized("Loading models...", locale: locale)
      }
       if selectedProvider == .openai,
          apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
       {
          return localized("Enter an OpenAI API key to load models.", locale: locale)
       }
       if modelError != nil {
          return localized("Unable to load models. Try refresh.", locale: locale)
       }
       if selectedProvider == .custom && selectedCustomProvider.supportsModelListing {
          return localized("No models available. Try Refresh or enter a model ID manually.", locale: locale)
       }
       return localized("No models available.", locale: locale)
    }

    private var isAPIKeyOptional: Bool {
       selectedProvider == .custom && !selectedCustomProvider.requiresAPIKey
    }

    private var currentAPIKeyPlaceholder: String {
       selectedProvider == .custom ? selectedCustomProvider.apiKeyPlaceholder : selectedProvider.apiKeyPlaceholder
    }

    private var apiKeyHelpText: String? {
       guard selectedProvider == .custom else { return nil }

       switch selectedCustomProvider {
       case .custom:
          return nil
       case .ollama:
          return localized("Ollama usually does not require authentication for local requests.", locale: locale)
       case .lmStudio:
          return localized("LM Studio only needs a token if local server authentication is enabled.", locale: locale)
       }
    }

    private func applyCustomEndpointDefault(forceReset: Bool = false) {
       guard selectedProvider == .custom else { return }

       if forceReset {
          let defaultEndpoint = selectedCustomProvider.defaultEndpoint
          if !defaultEndpoint.isEmpty {
             customEndpointDrafts[selectedCustomProvider] = defaultEndpoint
          }
       }
    }

    private func customEndpointTextBinding() -> Binding<String> {
       Binding(
          get: { customEndpointDrafts[selectedCustomProvider] ?? "" },
          set: { newValue in
             customEndpointDrafts[selectedCustomProvider] = newValue
             if selectedProvider == .custom, selectedCustomProvider.supportsModelListing {
                scheduleEndpointRefresh(for: newValue)
             }
          }
       )
    }

    private func loadCustomEndpointDrafts() {
       for type in CustomProviderType.allCases {
          if let provider = settings.providers.first(where: { $0.kind == .custom && $0.customKind == type }),
             let stored = settings.loadProviderEndpoint(forProviderID: provider.id),
             !stored.isEmpty
          {
             customEndpointDrafts[type] = stored
          } else if !type.defaultEndpoint.isEmpty {
             customEndpointDrafts[type] = type.defaultEndpoint
          } else {
             customEndpointDrafts[type] = ""
          }
       }
    }

    /// Looks up a stored API key for the currently-selected provider (by kind/customKind).
    /// Returns empty string if no matching provider exists or no key is stored.
    private func loadKeyForCurrentSelection() -> String {
       let matching = settings.providers.first { candidate in
          guard candidate.kind == selectedProvider else { return false }
          if selectedProvider == .custom {
             return candidate.customKind == selectedCustomProvider
          }
          return true
       }
       guard let provider = matching else { return "" }
       return settings.loadProviderAPIKey(forProviderID: provider.id) ?? ""
    }

    private var currentCustomEndpointText: String {
       (customEndpointDrafts[selectedCustomProvider] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func scheduleEndpointRefresh(for endpoint: String) {
       endpointRefreshTask?.cancel()

       let trimmedEndpoint = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
       guard !trimmedEndpoint.isEmpty else {
          availableModels = []
          modelError = nil
          return
       }

       endpointRefreshTask = Task {
          try? await Task.sleep(for: .milliseconds(300))
          guard !Task.isCancelled else { return }
          await loadModelsIfNeeded(
             for: .custom,
             customLocalProvider: selectedCustomProvider,
             forceRefresh: true
          )
       }
    }

    private func loadSavedConfiguration() {
       loadCustomEndpointDrafts()

       // Prefer the currently-assigned transcription-enhancement provider; fall back to the
       // first configured provider; otherwise defaults.
       let sourceProvider: ProviderConfig? = {
          if let assignment = settings.assignment(for: .transcriptionEnhancement),
             let provider = settings.provider(withID: assignment.providerID)
          {
             return provider
          }
          return settings.providers.first
       }()

       if let provider = sourceProvider {
          selectedProvider = provider.kind
          if provider.kind == .custom {
             selectedCustomProvider = provider.customKind ?? .custom
          }
          if let assignment = settings.assignment(for: .transcriptionEnhancement),
             assignment.providerID == provider.id
          {
             selectedModel = assignment.modelID
             customModel = assignment.modelID
          }
          // Seed the draft endpoint from stored per-provider endpoint (custom only).
          if provider.kind == .custom,
             let storedEndpoint = settings.loadProviderEndpoint(forProviderID: provider.id),
             !storedEndpoint.isEmpty
          {
             customEndpointDrafts[provider.customKind ?? .custom] = storedEndpoint
          }
          if provider.kind != .apple {
             apiKey = settings.loadProviderAPIKey(forProviderID: provider.id) ?? ""
          }
       }

       guard selectedProvider != .apple else { return }

       Task {
          await loadModelsIfNeeded(
             for: selectedProvider,
             customLocalProvider: selectedCustomProvider
          )
       }
    }

    @MainActor
    private func loadModelsIfNeeded(
       for provider: AIProvider,
       customLocalProvider: CustomProviderType? = nil,
       forceRefresh: Bool = false
    ) async {
       let resolvedCustomProvider = customLocalProvider ?? selectedCustomProvider
       let shouldUseCachedModels = !(provider == .custom && resolvedCustomProvider.supportsModelListing)
       if provider == .anthropic {
          availableModels = Self.anthropicModels
          updateSelectedModelIfNeeded(for: provider, models: availableModels)
          return
       }
       let supportsModelListing = provider == .openrouter || provider == .openai
          || (provider == .custom && resolvedCustomProvider.supportsModelListing)
       guard supportsModelListing else {
          availableModels = []
          modelError = nil
          return
       }
       modelError = nil

       switch provider {
       case .openai where selectedModel.contains("/"):
          selectedModel = defaultModelIdentifier(for: provider)
       case .openrouter where !selectedModel.contains("/"):
          selectedModel = defaultModelIdentifier(for: provider)
       default:
          break
       }

        if shouldUseCachedModels,
           let cachedModels = modelService.getCachedModels(
              for: provider,
              customLocalProvider: resolvedCustomProvider
           )
        {
           availableModels = cachedModels
           updateSelectedModelIfNeeded(for: provider, models: cachedModels)
        } else {
           availableModels = []
        }

        let shouldRefresh =
           forceRefresh || !shouldUseCachedModels || modelService.isCacheStale(
              for: provider,
              customLocalProvider: resolvedCustomProvider
           ) || availableModels.isEmpty
        guard shouldRefresh else { return }

       if provider == .openai {
          let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
          guard !trimmedKey.isEmpty else {
             return
          }
       }

       await refreshModels(for: provider, customLocalProvider: resolvedCustomProvider)
    }

    @MainActor
    private func refreshModels(
       for provider: AIProvider,
       customLocalProvider: CustomProviderType? = nil
    ) async {
       guard !isLoadingModels else { return }
       isLoadingModels = true
       defer { isLoadingModels = false }

        let resolvedCustomProvider = customLocalProvider ?? selectedCustomProvider

        if provider == .custom && resolvedCustomProvider.supportsModelListing {
           availableModels = []
        }

        do {
           let models = try await modelService.refreshModels(
             for: provider,
             apiKey: apiKey,
             endpointOverride: provider == .custom ? (customEndpointDrafts[selectedCustomProvider] ?? "") : nil,
             customLocalProvider: resolvedCustomProvider
          )
          availableModels = models
          updateSelectedModelIfNeeded(for: provider, models: models)
       } catch {
          if provider == .custom && resolvedCustomProvider.supportsModelListing {
             availableModels = []
          }
          Log.aiEnhancement.error("Failed to fetch \(provider.rawValue) models: \(error)")
          modelError = error.localizedDescription
       }
    }

    private func updateSelectedModelIfNeeded(
       for provider: AIProvider,
       models: [AIModelService.AIModel]
    ) {
       guard !models.isEmpty else { return }
       guard !models.contains(where: { $0.id == selectedModel }) else { return }

       let preferredModel = defaultModelIdentifier(for: provider)
       if let matching = models.first(where: { $0.id == preferredModel }) {
          selectedModel = matching.id
       } else if let firstModel = models.first {
          selectedModel = firstModel.id
       }
    }

    private func defaultModelIdentifier(for provider: AIProvider) -> String {
       switch provider {
       case .openrouter:
          return "openai/gpt-4o-mini"
       case .openai:
          return "gpt-4o-mini"
       case .anthropic:
          return "claude-haiku-4-5"
       default:
          return selectedModel
       }
    }

    private static let anthropicModels: [AIModelService.AIModel] = [
       AIModelService.AIModel(id: "claude-haiku-4-5", name: "Claude Haiku 4.5", provider: .anthropic,
                              description: "Fast and affordable", contextLength: 200_000),
       AIModelService.AIModel(id: "claude-sonnet-4-6", name: "Claude Sonnet 4.6", provider: .anthropic,
                              description: "Balanced performance", contextLength: 1_000_000),
       AIModelService.AIModel(id: "claude-opus-4-6", name: "Claude Opus 4.6", provider: .anthropic,
                              description: "Most capable", contextLength: 1_000_000),
    ]

   private var featureList: some View {
      VStack(alignment: .leading, spacing: 8) {
         Text(localized("AI Enhancement will:", locale: locale))
            .font(.subheadline)
            .fontWeight(.medium)

         featureItem(localized("Fix punctuation and capitalization", locale: locale))
         featureItem(localized("Correct grammar mistakes", locale: locale))
         featureItem(localized("Clean up filler words", locale: locale))
         featureItem(localized("Format text appropriately", locale: locale))
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(16)
      .background(AppColors.accent.opacity(0.05))
      .background(.ultraThinMaterial, in: .rect(cornerRadius: 12))
   }

   private func featureItem(_ text: String) -> some View {
      HStack(spacing: 8) {
         IconView(icon: .circleCheck, size: 14)
            .foregroundStyle(.green)
         Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
      }
   }

   private var actionButtons: some View {
      HStack(spacing: 16) {
         Button(localized("Skip for Now", locale: locale), action: onSkip)
            .buttonStyle(.bordered)

         Button(action: saveAndContinue) {
            Text(localized("Save & Continue", locale: locale))
               .font(.headline)
               .frame(maxWidth: 180)
               .padding(.vertical, 12)
         }
         .buttonStyle(.borderedProminent)
         .disabled(!canContinue)
      }
   }

    private var canContinue: Bool {
       guard selectedProvider.isImplemented else { return false }
       // Apple Intelligence needs no API key, endpoint, or model selection.
       if selectedProvider == .apple { return true }
       if settings.requiresAPIKey(for: selectedProvider, customLocalProvider: selectedCustomProvider)
          && apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
       {
          return false
       }
       if selectedProvider == .custom, currentCustomEndpointText.isEmpty {
          return false
       }
       let configuredModel = selectedProvider == .custom && !selectedCustomProvider.supportsModelListing
          ? customModel
          : selectedModel
       if configuredModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          return false
       }
       return true
    }

    private func saveAndContinue() {
       // Resolve/create the ProviderConfig corresponding to the current selection.
       let customKind: CustomProviderType? =
          selectedProvider == .custom ? selectedCustomProvider : nil
       let providerConfig: ProviderConfig = {
          if let existing = settings.providers.first(where: {
             $0.kind == selectedProvider && $0.customKind == customKind
          }) {
             return existing
          }
          let displayName: String = {
             switch selectedProvider {
             case .openai: return "OpenAI"
             case .anthropic: return "Anthropic"
             case .google: return "Google"
             case .openrouter: return "OpenRouter"
             case .apple: return "Apple Intelligence"
             case .custom:
                switch customKind ?? .custom {
                case .ollama: return "Ollama"
                case .lmStudio: return "LM Studio"
                case .custom: return "Custom"
                }
             }
          }()
          return ProviderConfig(
             kind: selectedProvider,
             customKind: customKind,
             displayName: displayName
          )
       }()
       settings.upsertProvider(providerConfig)

       // Persist credentials into UUID-keyed Keychain slots.
       if selectedProvider != .apple {
          try? settings.saveProviderAPIKey(apiKey, forProviderID: providerConfig.id)
       }
       if selectedProvider == .custom {
          let endpoint = (customEndpointDrafts[selectedCustomProvider] ?? "")
             .trimmingCharacters(in: .whitespacesAndNewlines)
          try? settings.saveProviderEndpoint(endpoint, forProviderID: providerConfig.id)
       }

       // Resolve the model ID to assign.
       let resolvedModelID: String = {
          if selectedProvider == .apple { return "apple_intelligence" }
          if selectedProvider == .custom && !selectedCustomProvider.supportsModelListing {
             return customModel
          }
          return selectedModel
       }()

       // Write the transcription + note enhancement assignments.
       settings.setAssignment(
          ModelAssignment(
             providerID: providerConfig.id,
             modelID: resolvedModelID,
             promptPresetID: BuiltInPresetID.cleanTranscript
          ),
          for: .transcriptionEnhancement
       )
       settings.setAssignment(
          ModelAssignment(
             providerID: providerConfig.id,
             modelID: resolvedModelID
          ),
          for: .noteEnhancement
       )

       onContinue()
    }
}

private extension AIEnhancementStepView {
   var customProviderOptions: [SelectFieldOption] {
      CustomProviderType.allCases.map {
         SelectFieldOption(
            id: $0.id,
            displayName: $0.rawValue
         )
      }
   }

   var customProviderSelection: Binding<String> {
      Binding(
         get: { selectedCustomProvider.id },
         set: { newValue in
            guard let provider = CustomProviderType(rawValue: newValue)
            else {
               return
            }

            selectedCustomProvider = provider
         }
      )
   }
}

#if DEBUG
   struct AIEnhancementStepView_Previews: PreviewProvider {
      static var previews: some View {
         AIEnhancementStepView(
            settings: SettingsStore(),
            onContinue: {},
            onSkip: {},
            onPreferredContentSizeChange: { _ in }
         )
         .frame(width: 800, height: 600)
      }
   }
#endif

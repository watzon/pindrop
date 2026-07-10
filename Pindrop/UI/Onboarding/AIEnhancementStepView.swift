//
//  AIEnhancementStepView.swift
//  Pindrop
//
//  Created on 2026-01-25.
//

#if canImport(FoundationModels)
import FoundationModels
#endif
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
    @State private var selectedProvider: AIProvider = .apple
    @State private var selectedCustomProvider: CustomProviderType = .custom
    @State private var apiKey = ""
    @State private var customEndpointDrafts: [CustomProviderType: String] = [:]
    @State private var selectedModel = "gpt-4o-mini"
    @State private var customModel = ""
    @State private var availableModels: [AIModelService.AIModel] = []
    @State private var isLoadingModels = false
    @State private var modelError: String?
    @State private var modelService = AIModelService()

    var body: some View {
       VStack(spacing: 0) {
          headerSection

          VStack(spacing: 10) {
             enhancementExampleCard(
                label: localized("You say", locale: locale),
                text: localized("um so the meeting is at three thirty period can you confirm question mark", locale: locale),
                highlighted: false
             )
             enhancementExampleCard(
                label: localized("Pindrop writes", locale: locale),
                text: localized("So the meeting is at 3:30. Can you confirm?", locale: locale),
                highlighted: true
             )
          }
          .frame(width: 480)
          .padding(.top, 26)

          actionButtons.padding(.top, 28)
       }
        .onAppear {
           loadSavedConfiguration()
           onPreferredContentSizeChange(CGSize(width: 760, height: 560))
        }
    }

    private var headerSection: some View {
       VStack(spacing: 0) {
          Text(localized("AI Enhancement", locale: locale))
             .font(OnboardingType.stepHeading)
             .tracking(-0.42)
             .foregroundStyle(AppColors.textPrimary)

          Text(localized("Optionally clean up transcriptions with AI", locale: locale))
             .font(OnboardingType.stepSubtitle)
             .foregroundStyle(AppColors.textSecondary)
             .padding(.top, 8)
       }
    }

    private func enhancementExampleCard(label: String, text: String, highlighted: Bool) -> some View {
       VStack(alignment: .leading, spacing: 8) {
          Text(label.uppercased(with: locale))
             .font(AppTypography.badge)
             .tracking(0.77)
             .foregroundStyle(highlighted ? AppColors.accent : AppColors.textTertiary)

          Text(text)
             .font(highlighted
                ? FontLoader.font(family: .newsreader, size: 16, weight: .regular)
                : AppTypography.body)
             .lineSpacing(highlighted ? 4 : 3)
             .foregroundStyle(highlighted ? AppColors.textPrimary : AppColors.textSecondary)
       }
       .padding(.vertical, 16)
       .padding(.horizontal, 18)
       .frame(maxWidth: .infinity, alignment: .leading)
       .background(highlighted ? AppColors.accentBackground : AppColors.contentBackground, in: .rect(cornerRadius: 12))
       .overlay {
          if !highlighted {
             RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(AppColors.border, lineWidth: 1)
          }
       }
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

   private var actionButtons: some View {
      HStack(spacing: 14) {
         OnboardingPrimaryButton(
            title: localized("Enable enhancement", locale: locale),
            icon: .sparkles,
            action: enableAndContinue
         )

         OnboardingGhostButton(title: localized("Skip for Now", locale: locale), action: onSkip)
      }
   }

    private func enableAndContinue() {
       // Preserve a complete saved configuration when one exists. Fresh onboarding has no
       // credentials UI in the U9 artboard, so use the credential-free on-device provider.
       if !canContinue {
          // Don't persist assignments to a provider that can't run on this system;
          // Settings → AI handles setup later.
          guard Self.isAppleIntelligenceAvailable else {
             onContinue()
             return
          }
          selectedProvider = .apple
          selectedModel = "apple_intelligence"
       }
       saveAndContinue()
    }

    private static var isAppleIntelligenceAvailable: Bool {
       #if canImport(FoundationModels)
       if #available(macOS 26, *) {
          return SystemLanguageModel.default.availability == .available
       }
       return false
       #else
       return false
       #endif
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

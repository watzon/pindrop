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
   case custom = "Custom"

   var id: String { rawValue }

   var icon: Icon {
      switch self {
      case .openai: return .openai
      case .google: return .google
      case .anthropic: return .anthropic
      case .openrouter: return .openrouter
      case .custom: return .server
      }
   }

   var defaultEndpoint: String {
      switch self {
      case .openai: return "https://api.openai.com/v1/chat/completions"
      case .google: return "https://generativelanguage.googleapis.com/v1beta"
      case .anthropic: return "https://api.anthropic.com/v1"
      case .openrouter: return "https://openrouter.ai/api/v1/chat/completions"
      case .custom: return ""
      }
   }

   var apiKeyPlaceholder: String {
      switch self {
      case .openai: return "sk-..."
      case .google: return "AIza..."
      case .anthropic: return "sk-ant-..."
      case .openrouter: return "sk-or-..."
      case .custom: return "Enter API key"
      }
   }

   var isImplemented: Bool {
      switch self {
      case .openai, .openrouter, .custom: return true
      default: return false
      }
   }
}

private struct AIModelOption: Identifiable, Hashable, Codable {
   let id: String
   let name: String?

   var displayName: String {
      let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines)
      return trimmedName?.isEmpty == false ? trimmedName! : id
   }
}

private enum ModelFetchError: LocalizedError {
   case invalidResponse
   case apiError(String)

   var errorDescription: String? {
      switch self {
      case .invalidResponse:
         return "Invalid response from model API"
      case .apiError(let message):
         return message
      }
   }
}

struct AIEnhancementStepView: View {
   @ObservedObject var settings: SettingsStore
   let onContinue: () -> Void
   let onSkip: () -> Void
   let onPreferredContentSizeChange: (CGSize) -> Void

   @State private var selectedProvider: AIProvider = .openai
   @State private var apiKey = ""
   @State private var customEndpoint = ""
   @State private var selectedModel = "gpt-4o-mini"
   @State private var customModel = ""
   @State private var showingAPIKey = false
   @State private var availableModels: [AIModelOption] = []
   @State private var isLoadingModels = false
   @State private var modelError: String?

   private static func preferredContentSize(for provider: AIProvider) -> CGSize {
      switch provider {
      case .openrouter, .openai:
         return CGSize(width: 800, height: 820)
      case .custom:
         return CGSize(width: 800, height: 820)
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
         apiKey = settings.loadAPIKey(for: selectedProvider) ?? ""
         onPreferredContentSizeChange(preferredContentSize)
         Task { await loadModelsIfNeeded(for: selectedProvider) }
      }
      .onChange(of: selectedProvider) { _, newValue in
         apiKey = settings.loadAPIKey(for: newValue) ?? ""
         onPreferredContentSizeChange(preferredContentSize)
         Task { await loadModelsIfNeeded(for: newValue) }
      }
      .onChange(of: apiKey) { _, newValue in
         guard selectedProvider == .openai else { return }
         guard !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
         Task { await loadModelsIfNeeded(for: .openai, forceRefresh: true) }
      }

   }

   private var headerSection: some View {
      VStack(spacing: 6) {
         IconView(icon: .sparkles, size: 36)
            .foregroundStyle(AppColors.accent)

         Text("AI Enhancement")
            .font(.system(size: 24, weight: .bold, design: .rounded))

         Text("Optionally clean up transcriptions with AI")
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
            Text(provider.rawValue)
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
         } else {
            apiKeyField

            if selectedProvider == .openrouter || selectedProvider == .openai {
               modelPicker
            }

            if selectedProvider == .custom {
               customModelField
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

   private var comingSoonView: some View {
      VStack(spacing: 12) {
         Spacer()

         IconView(icon: .construction, size: 40)
            .foregroundStyle(.secondary)

         Text("\(selectedProvider.rawValue) Support Coming Soon")
            .font(.headline)

         Text(
            "This provider will be available in a future update.\nFor now, try OpenAI or use a Custom endpoint."
         )
         .font(.subheadline)
         .foregroundStyle(.secondary)
         .multilineTextAlignment(.center)

         Spacer()
      }
   }

   private var apiKeyField: some View {
      VStack(alignment: .leading, spacing: 8) {
         Text("API Key")
            .font(.subheadline)
            .fontWeight(.medium)

         HStack {
            Group {
               if showingAPIKey {
                  TextField(selectedProvider.apiKeyPlaceholder, text: $apiKey)
               } else {
                  SecureField(selectedProvider.apiKeyPlaceholder, text: $apiKey)
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
         .padding(12)
         .background(.ultraThinMaterial, in: .rect(cornerRadius: 8))
      }
   }

   private var customEndpointField: some View {
      VStack(alignment: .leading, spacing: 8) {
         HStack {
            Text("API Endpoint")
               .font(.subheadline)
               .fontWeight(.medium)

            Spacer()

            Text("Must be OpenAI-compatible")
               .font(.caption)
               .foregroundStyle(.secondary)
         }

         TextField("https://your-api.com/v1", text: $customEndpoint)
            .textFieldStyle(.plain)
            .padding(12)
            .background(.ultraThinMaterial, in: .rect(cornerRadius: 8))
      }
   }

   private var customModelField: some View {
      VStack(alignment: .leading, spacing: 8) {
         Text("AI Model")
            .font(.subheadline)
            .fontWeight(.medium)

         TextField("e.g., gpt-4o", text: $customModel)
            .textFieldStyle(.plain)
            .padding(12)
            .background(.ultraThinMaterial, in: .rect(cornerRadius: 8))
      }
   }

   private var modelPicker: some View {
      VStack(alignment: .leading, spacing: 8) {
         HStack {
            Text("AI Model")
               .font(.subheadline)
               .fontWeight(.medium)
            Spacer()

            if isLoadingModels {
               ProgressView()
                  .controlSize(.small)
            }

            Button("Refresh") {
               Task { await loadModelsIfNeeded(for: selectedProvider, forceRefresh: true) }
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
               .padding(10)
               .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
         } else {
            SearchableDropdown(
               items: availableModels,
               selection: Binding(
                  get: { selectedModel.isEmpty ? nil : selectedModel },
                  set: { selectedModel = $0 ?? "" }
               ),
               placeholder: "Select a model",
               emptyMessage: "No models found.",
               searchPlaceholder: "Search models..."
            )
            .padding(10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
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
   }


   private var emptyModelsMessage: String {
      if isLoadingModels {
         return "Loading models..."
      }
      if selectedProvider == .openai,
         apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      {
         return "Enter an OpenAI API key to load models."
      }
      if modelError != nil {
         return "Unable to load models. Try refresh."
      }
      return "No models available."
   }

   @MainActor
   private func loadModelsIfNeeded(for provider: AIProvider, forceRefresh: Bool = false) async {
      guard provider == .openrouter || provider == .openai else { return }
      modelError = nil

      switch provider {
      case .openai where selectedModel.contains("/"):
         selectedModel = defaultModelIdentifier(for: provider)
      case .openrouter where !selectedModel.contains("/"):
         selectedModel = defaultModelIdentifier(for: provider)
      default:
         break
      }

      let cachedModels = loadCachedModels(for: provider)
      if !cachedModels.isEmpty {
         availableModels = cachedModels
         updateSelectedModelIfNeeded(for: provider, models: cachedModels)
      } else {
         availableModels = []
      }

      let shouldRefresh =
         forceRefresh || settings.isModelCacheStale(for: provider) || cachedModels.isEmpty
      guard shouldRefresh else { return }

      if provider == .openai {
         let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
         guard !trimmedKey.isEmpty else {
            return
         }
      }

      await refreshModels(for: provider)
   }

   @MainActor
   private func refreshModels(for provider: AIProvider) async {
      guard !isLoadingModels else { return }
      isLoadingModels = true
      defer { isLoadingModels = false }

      do {
         let models = try await fetchModels(for: provider)
         availableModels = models
         saveCachedModels(models, for: provider)
         updateSelectedModelIfNeeded(for: provider, models: models)
      } catch {
         Log.aiEnhancement.error("Failed to fetch \(provider.rawValue) models: \(error)")
         modelError = error.localizedDescription
      }
   }

   private func fetchModels(for provider: AIProvider) async throws -> [AIModelOption] {
      let urlString: String
      switch provider {
      case .openrouter:
         urlString = "https://openrouter.ai/api/v1/models"
      case .openai:
         urlString = "https://api.openai.com/v1/models"
      default:
         throw ModelFetchError.invalidResponse
      }

      guard let url = URL(string: urlString) else {
         throw ModelFetchError.invalidResponse
      }

      var request = URLRequest(url: url)
      request.httpMethod = "GET"

      if provider == .openai {
         request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
      }

      let (data, response) = try await URLSession.shared.data(for: request)

      guard let httpResponse = response as? HTTPURLResponse else {
         throw ModelFetchError.invalidResponse
      }

      guard httpResponse.statusCode == 200 else {
         let message = modelErrorMessage(from: data, statusCode: httpResponse.statusCode)
         throw ModelFetchError.apiError(message)
      }

      guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
         let dataArray = json["data"] as? [[String: Any]]
      else {
         throw ModelFetchError.invalidResponse
      }

      let models = dataArray.compactMap { entry -> AIModelOption? in
         guard let id = entry["id"] as? String else { return nil }
         let name = entry["name"] as? String
         return AIModelOption(id: id, name: name)
      }

      return sortedModels(models)
   }

   private func modelErrorMessage(from data: Data, statusCode: Int) -> String {
      if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
         let error = json["error"] as? [String: Any],
         let message = error["message"] as? String
      {
         return message
      }
      return "HTTP \(statusCode)"
   }

   private func updateSelectedModelIfNeeded(for provider: AIProvider, models: [AIModelOption]) {
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
      default:
         return "gpt-4o-mini"
      }
   }

   private func sortedModels(_ models: [AIModelOption]) -> [AIModelOption] {
      models.sorted {
         $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
      }
   }

   private var modelCacheDirectory: URL? {
      FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
         .appendingPathComponent("Pindrop", isDirectory: true)
         .appendingPathComponent("AIModels", isDirectory: true)
   }

   private func cacheURL(for provider: AIProvider) -> URL? {
      guard let directory = modelCacheDirectory else { return nil }
      switch provider {
      case .openrouter:
         return directory.appendingPathComponent("openrouter-models.json")
      case .openai:
         return directory.appendingPathComponent("openai-models.json")
      default:
         return nil
      }
   }

   private func loadCachedModels(for provider: AIProvider) -> [AIModelOption] {
      guard let cacheURL = cacheURL(for: provider) else { return [] }
      do {
         let data = try Data(contentsOf: cacheURL)
         let models = try JSONDecoder().decode([AIModelOption].self, from: data)
         return sortedModels(models)
      } catch {
         Log.aiEnhancement.warning("Failed to load cached \(provider.rawValue) models: \(error)")
         return []
      }
   }

   private func saveCachedModels(_ models: [AIModelOption], for provider: AIProvider) {
      guard let cacheURL = cacheURL(for: provider) else { return }
      do {
         try FileManager.default.createDirectory(
            at: cacheURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
         )
         let data = try JSONEncoder().encode(models)
         try data.write(to: cacheURL, options: .atomic)
         switch provider {
         case .openrouter:
            settings.openRouterModelsCacheTimestamp = Date().timeIntervalSince1970
         case .openai:
            settings.openAIModelsCacheTimestamp = Date().timeIntervalSince1970
         default:
            break
         }
      } catch {
         Log.aiEnhancement.error("Failed to save cached \(provider.rawValue) models: \(error)")
      }
   }

   private var featureList: some View {
      VStack(alignment: .leading, spacing: 8) {
         Text("AI Enhancement will:")
            .font(.subheadline)
            .fontWeight(.medium)

         featureItem("Fix punctuation and capitalization")
         featureItem("Correct grammar mistakes")
         featureItem("Clean up filler words")
         featureItem("Format text appropriately")
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
         Button("Skip for Now", action: onSkip)
            .buttonStyle(.bordered)

         Button(action: saveAndContinue) {
            Text("Save & Continue")
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
      if apiKey.isEmpty { return false }
      if selectedProvider == .custom && customEndpoint.isEmpty { return false }
      if selectedProvider == .custom && customModel.isEmpty { return false }
      if (selectedProvider == .openrouter || selectedProvider == .openai) && selectedModel.isEmpty {
         return false
      }
      return true
   }

   private func saveAndContinue() {
      settings.aiEnhancementEnabled = true

      let endpoint = selectedProvider == .custom ? customEndpoint : selectedProvider.defaultEndpoint
      try? settings.saveAPIEndpoint(endpoint)
      try? settings.saveAPIKey(apiKey, for: selectedProvider)
      if selectedProvider == .custom {
         settings.aiModel = customModel
      } else {
         settings.aiModel = selectedModel
      }

      onContinue()
   }
}

extension AIModelOption: SearchableDropdownItem {}

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

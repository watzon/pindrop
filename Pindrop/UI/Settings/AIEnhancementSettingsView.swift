//
//  AIEnhancementSettingsView.swift
//  Pindrop
//
//  Created on 2026-01-25.
//

import SwiftData
import SwiftUI

struct AIEnhancementSettingsView: View {
   @ObservedObject var settings: SettingsStore
   @Environment(\.modelContext) private var modelContext

   @State private var selectedProvider: AIProvider = .openai
   @State private var apiKey = ""
   @State private var customEndpoint = ""
   @State private var selectedModel = "gpt-4o-mini"
   @State private var customModel = ""
   @State private var useCustomModel = false
   @State private var enhancementPrompt = ""
   @State private var noteEnhancementPrompt = ""
   @State private var selectedPromptType: PromptType = .transcription
   @State private var showingAPIKey = false
   @State private var showingSaveSuccess = false
   @State private var showingPromptSaveSuccess = false
   @State private var errorMessage: String?
   @State private var showAccessibilityAlert = false
   @State private var accessibilityPermissionGranted = false
   @State private var accessibilityPermissionRequestInFlight = false

   @State private var presets: [PromptPreset] = []
   @State private var showPresetManagement = false

   // MARK: - Model Fetching State
   @State private var availableModels: [AIModelService.AIModel] = []
   @State private var isLoadingModels = false
   @State private var modelError: String?
   @State private var modelService = AIModelService()

   private var promptPresetStore: PromptPresetStore {
      PromptPresetStore(modelContext: modelContext)
   }

   enum PromptType: String, CaseIterable, Identifiable {
      case transcription = "Transcription"
      case notes = "Notes"

      var id: String { rawValue }

      var icon: Icon {
         switch self {
         case .transcription: return .mic
         case .notes: return .stickyNote
         }
      }

      var description: String {
         switch self {
         case .transcription:
            return "Sent to the AI model when processing dictation for direct text insertion."
         case .notes:
            return
               "Used when capturing notes via hotkey. Can add markdown formatting for longer content."
         }
      }
   }

   var body: some View {
      VStack(spacing: 20) {
         enableToggleCard
         providerCard
         promptsCard
         contextCard
      }
      .task {
         loadPresets()
         loadCredentialsAndPrompt()
         refreshPermissionStates()
      }
      .onChange(of: settings.selectedPresetId) { _, newValue in
         handlePresetChange(newValue)
      }
      .onChange(of: enhancementPrompt) { _, newValue in
         handlePromptChange(newValue)
      }
      .onChange(of: selectedProvider) { _, newValue in
         apiKey = settings.loadAPIKey(for: newValue) ?? ""
         Task { await loadModelsIfNeeded(for: newValue) }
      }
      .onChange(of: apiKey) { _, newValue in
         guard selectedProvider == .openai else { return }
         guard !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
         Task { await loadModelsIfNeeded(for: .openai, forceRefresh: true) }
      }
      .sheet(isPresented: $showPresetManagement) {
         PresetManagementSheet()
            .onDisappear {
               loadPresets()
            }
      }
      .alert("Accessibility Permission Recommended", isPresented: $showAccessibilityAlert) {
         Button("Open System Settings") {
            PermissionManager().openAccessibilityPreferences()
         }
         Button("Continue Without", role: .cancel) {}
      } message: {
         Text(
            "Vibe mode works best with Accessibility permission. Without it, Pindrop falls back to limited app metadata and transcription still works normally."
         )
      }
   }

   // MARK: - Enable Toggle Card

   private var enableToggleCard: some View {
      SettingsCard(title: "Status", icon: "sparkles") {
         Toggle(isOn: $settings.aiEnhancementEnabled) {
            VStack(alignment: .leading, spacing: 2) {
               Text("Enable AI Enhancement")
                  .font(.body)
               Text("Improve transcription quality using AI")
                  .font(.caption)
                  .foregroundStyle(.secondary)
            }
         }
         .toggleStyle(.switch)
      }
   }

   // MARK: - Provider Card

   private var providerCard: some View {
      SettingsCard(title: "Provider", icon: "server.rack") {
         VStack(spacing: 16) {
            providerTabs
               .opacity(settings.aiEnhancementEnabled ? 1 : 0.5)

            providerConfigContent
               .opacity(settings.aiEnhancementEnabled ? 1 : 0.5)
         }
         .disabled(!settings.aiEnhancementEnabled)
      }
   }

   // MARK: - Prompts Card

   private var promptsCard: some View {
      SettingsCard(title: "Enhancement Prompts", icon: "text.bubble") {
         VStack(spacing: 16) {
            if selectedPromptType == .transcription {
               presetPicker
               Divider()
                  .overlay(AppColors.divider)
            }

            promptTypeTabs
            promptContent
         }
         .opacity(settings.aiEnhancementEnabled ? 1 : 0.5)
         .disabled(!settings.aiEnhancementEnabled)
      }
   }

   private var validatedPresetSelection: Binding<String?> {
      Binding(
         get: {
            guard let presetId = settings.selectedPresetId,
               presets.contains(where: { $0.id.uuidString == presetId })
            else {
               return nil
            }
            return presetId
         },
         set: { settings.selectedPresetId = $0 }
      )
   }

   private var presetPicker: some View {
      VStack(alignment: .leading, spacing: 6) {
         Text("Prompt Preset")
            .font(.subheadline)
            .fontWeight(.medium)

         HStack(spacing: 8) {
            Picker("Preset", selection: validatedPresetSelection) {
               Text("Custom").tag(nil as String?)
               ForEach(presets) { preset in
                  Text(preset.name).tag(preset.id.uuidString as String?)
               }
            }
            .pickerStyle(.menu)
            .labelsHidden()

            Button("Manage Presets...") {
               showPresetManagement = true
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Spacer()

            if let presetId = settings.selectedPresetId,
               let preset = presets.first(where: { $0.id.uuidString == presetId })
            {
               Text(preset.isBuiltIn ? "Built-in (read-only)" : "Custom")
                  .font(.caption)
                  .foregroundStyle(.secondary)
                  .padding(.horizontal, 8)
                  .padding(.vertical, 4)
                  .background(.ultraThinMaterial, in: Capsule())
            }
         }
      }
   }

   // MARK: - Context Card

   private var contextCard: some View {
      SettingsCard(title: "Vibe Mode", icon: "wand.and.stars") {
         VStack(alignment: .leading, spacing: 16) {
            Text(
               "Vibe mode captures structured UI context when recording starts so AI enhancement can use your active app state as reference."
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            Toggle(
               "Enable vibe mode (UI context)",
               isOn: Binding(
                  get: { settings.enableUIContext },
                  set: { newValue in
                     settings.enableUIContext = newValue
                     if newValue {
                        requestAccessibilityPermissionIfNeeded()
                     }
                  }
               )
            )
            .toggleStyle(.switch)
            .frame(maxWidth: .infinity, alignment: .leading)

            Toggle(
               "Enable live session updates during recording",
               isOn: $settings.vibeLiveSessionEnabled
            )
            .toggleStyle(.switch)
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 6) {
               IconView(icon: accessibilityPermissionGranted ? .check : .info, size: 12)
                  .foregroundStyle(accessibilityPermissionGranted ? .green : .secondary)
               Text(
                  accessibilityPermissionGranted
                     ? "Accessibility permission is enabled. Full UI context is available."
                     : "Accessibility permission is not granted. Vibe mode remains non-blocking with limited context."
               )
               .font(.caption)
               .foregroundStyle(.secondary)

               if !accessibilityPermissionGranted {
                  Spacer(minLength: 8)
                  Button("Open Settings") {
                     PermissionManager().openAccessibilityPreferences()
                  }
                  .buttonStyle(.borderless)
                  .font(.caption)
               }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 6) {
               HStack(spacing: 6) {
                  Circle()
                     .fill(vibeRuntimeColor)
                     .frame(width: 8, height: 8)
                  Text("Runtime: \(vibeRuntimeLabel)")
                     .font(.caption.weight(.semibold))
                     .foregroundStyle(vibeRuntimeColor)
               }

               Text(settings.vibeRuntimeDetail)
                  .font(.caption)
                  .foregroundStyle(.secondary)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))

            VStack(spacing: 12) {
               Toggle("Include clipboard text", isOn: $settings.enableClipboardContext)
                  .toggleStyle(.switch)
                  .frame(maxWidth: .infinity, alignment: .leading)
            }
         }
         .opacity(settings.aiEnhancementEnabled ? 1 : 0.5)
         .disabled(!settings.aiEnhancementEnabled)
      }
   }

   private var vibeRuntimeLabel: String {
      switch settings.vibeRuntimeState {
      case .ready:
         return "Ready"
      case .limited:
         return "Limited"
      case .degraded:
         return "Degraded"
      }
   }

   private var vibeRuntimeColor: Color {
      switch settings.vibeRuntimeState {
      case .ready:
         return .green
      case .limited:
         return .yellow
      case .degraded:
         return .orange
      }
   }

   private var promptTypeTabs: some View {
      HStack(spacing: 0) {
         ForEach(PromptType.allCases) { type in
            promptTypeTab(type)
         }
      }
      .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
   }

   private func promptTypeTab(_ type: PromptType) -> some View {
      Button {
         withAnimation(.spring(duration: 0.3)) {
            selectedPromptType = type
         }
      } label: {
         VStack(spacing: 3) {
            IconView(icon: type.icon, size: 14)
            Text(type.rawValue)
               .font(.caption2)
               .fontWeight(.medium)
         }
         .frame(maxWidth: .infinity, maxHeight: .infinity)
         .padding(.vertical, 10)
         .contentShape(Rectangle())
         .background(
            selectedPromptType == type
               ? AppColors.accent.opacity(0.2)
               : Color.clear,
            in: RoundedRectangle(cornerRadius: 8)
         )
         .foregroundStyle(selectedPromptType == type ? AppColors.accent : .secondary)
      }
      .buttonStyle(.plain)
   }

   @ViewBuilder
   private var promptContent: some View {
      let currentPrompt =
         selectedPromptType == .transcription ? $enhancementPrompt : $noteEnhancementPrompt
      let charCount =
         selectedPromptType == .transcription
         ? enhancementPrompt.count : noteEnhancementPrompt.count

      let isReadOnly = selectedPromptType == .transcription && isBuiltInPresetSelected

      VStack(alignment: .leading, spacing: 12) {
         TextEditor(text: currentPrompt)
            .font(.body)
            .frame(minHeight: 120, maxHeight: 220)
            .padding(8)
            .scrollContentBackground(.hidden)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            .disabled(isReadOnly)
            .opacity(isReadOnly ? 0.7 : 1)

         HStack {
            Button("Reset to Default") {
               resetCurrentPrompt()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Spacer()

            Text("\(charCount) characters")
               .font(.caption)
               .foregroundStyle(.secondary)
         }

         Text(selectedPromptType.description)
            .font(.caption)
            .foregroundStyle(.secondary)

         HStack {
            Button("Save Prompt") {
               saveCurrentPrompt()
            }
            .buttonStyle(.borderedProminent)
            .disabled(charCount == 0 || isReadOnly)

            Spacer()

            if showingPromptSaveSuccess {
               HStack(spacing: 6) {
                  IconView(icon: .check, size: 12)
                     .foregroundStyle(.green)
                  Text("Saved")
                     .font(.caption)
                     .foregroundStyle(.green)
               }
            }
         }
      }
   }

   private var isBuiltInPresetSelected: Bool {
      guard let id = settings.selectedPresetId,
         let preset = presets.first(where: { $0.id.uuidString == id })
      else { return false }
      return preset.isBuiltIn
   }

   private func resetCurrentPrompt() {
      switch selectedPromptType {
      case .transcription:
         settings.selectedPresetId = nil  // Reset preset to Custom
         enhancementPrompt = AIEnhancementService.defaultSystemPrompt
      case .notes:
         noteEnhancementPrompt = SettingsStore.Defaults.noteEnhancementPrompt
      }
   }

   private func saveCurrentPrompt() {
      switch selectedPromptType {
      case .transcription:
         savePrompt()
      case .notes:
         saveNotePrompt()
      }
   }

   private var providerTabs: some View {
      HStack(spacing: 0) {
         ForEach(AIProvider.allCases) { provider in
            providerTab(provider)
         }
      }
      .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
   }

   private func providerTab(_ provider: AIProvider) -> some View {
      Button {
         withAnimation(.spring(duration: 0.3)) {
            selectedProvider = provider
         }
      } label: {
         VStack(spacing: 3) {
            IconView(icon: provider.icon, size: 14)
            Text(provider.rawValue)
               .font(.caption2)
               .fontWeight(.medium)
         }
         .frame(maxWidth: .infinity, maxHeight: .infinity)
         .padding(.vertical, 10)
         .contentShape(Rectangle())
         .background(
            selectedProvider == provider
               ? AppColors.accent.opacity(0.2)
               : Color.clear,
            in: RoundedRectangle(cornerRadius: 8)
         )
         .foregroundStyle(selectedProvider == provider ? AppColors.accent : .secondary)
      }
      .buttonStyle(.plain)
   }

   @ViewBuilder
   private var providerConfigContent: some View {
      if !selectedProvider.isImplemented {
         comingSoonView
      } else {
         VStack(spacing: 16) {
            apiKeyField

            if selectedProvider == .openrouter || selectedProvider == .openai {
               modelPicker
            }

            if selectedProvider == .custom {
               customModelField
               customEndpointField
            }

            saveButton

            if showingSaveSuccess {
               successMessage
            }

            if let errorMessage {
               errorMessageView(errorMessage)
            }

            keychainNote
         }
      }
   }

   private var comingSoonView: some View {
      VStack(spacing: 10) {
         IconView(icon: .construction, size: 28)
            .foregroundStyle(.secondary)

         Text("\(selectedProvider.rawValue) Coming Soon")
            .font(.headline)

         Text(
            "This provider will be available in a future update.\nTry OpenAI or use a Custom endpoint."
         )
         .font(.caption)
         .foregroundStyle(.secondary)
         .multilineTextAlignment(.center)
      }
      .padding(.vertical, 24)
      .frame(maxWidth: .infinity)
   }

   private var apiKeyField: some View {
      VStack(alignment: .leading, spacing: 6) {
         Text("API Key")
            .font(.subheadline)
            .fontWeight(.medium)

         HStack(spacing: 8) {
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
         .padding(10)
         .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
      }
   }

   private var customEndpointField: some View {
      VStack(alignment: .leading, spacing: 6) {
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
            .padding(10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
      }
   }

   private var customModelField: some View {
      VStack(alignment: .leading, spacing: 6) {
         Text("AI Model")
            .font(.subheadline)
            .fontWeight(.medium)

         TextField("e.g., gpt-4o", text: $customModel)
            .textFieldStyle(.plain)
            .padding(10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
      }
   }

   private var modelPicker: some View {
      VStack(alignment: .leading, spacing: 6) {
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
               Task { await refreshModels(for: selectedProvider) }
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

   private var saveButton: some View {
      HStack {
         Spacer()

         Button("Save Credentials") {
            saveCredentials()
         }
         .buttonStyle(.borderedProminent)
         .disabled(!canSave)
      }
   }

   private var successMessage: some View {
      HStack(spacing: 6) {
         IconView(icon: .check, size: 14)
            .foregroundStyle(.green)
         Text("Credentials saved successfully")
            .font(.caption)
            .foregroundStyle(.green)
      }
      .frame(maxWidth: .infinity)
      .padding(10)
      .background(Color.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
   }

   private func errorMessageView(_ message: String) -> some View {
      HStack(spacing: 6) {
         IconView(icon: .warning, size: 14)
            .foregroundStyle(.red)
         Text(message)
            .font(.caption)
            .foregroundStyle(.red)
      }
      .frame(maxWidth: .infinity)
      .padding(10)
      .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
   }

   private var keychainNote: some View {
      HStack(spacing: 6) {
         IconView(icon: .shield, size: 12)
            .foregroundStyle(.secondary)
         Text("Credentials are stored securely in Keychain")
            .font(.caption)
            .foregroundStyle(.secondary)
      }
   }

   // MARK: - Model Fetching

   @MainActor
   private func loadModelsIfNeeded(for provider: AIProvider, forceRefresh: Bool = false) async {
      guard provider == .openrouter || provider == .openai else { return }
      modelError = nil

      // Reset selected model if switching between providers with different formats
      switch provider {
      case .openai where selectedModel.contains("/"):
         selectedModel = defaultModelIdentifier(for: provider)
      case .openrouter where !selectedModel.contains("/"):
         selectedModel = defaultModelIdentifier(for: provider)
      default:
         break
      }

      // Try to load cached models first
      if let cachedModels = modelService.getCachedModels(for: provider) {
         availableModels = cachedModels
         updateSelectedModelIfNeeded(for: provider, models: cachedModels)
      } else {
         availableModels = []
      }

      // Check if we should refresh
      let shouldRefresh =
         forceRefresh || settings.isModelCacheStale(for: provider) || availableModels.isEmpty
      guard shouldRefresh else { return }

      // For OpenAI, need API key
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
         let models = try await modelService.refreshModels(
            for: provider,
            apiKey: provider == .openai ? apiKey : nil
         )
         availableModels = models
         updateSelectedModelIfNeeded(for: provider, models: models)

         // Update cache timestamp in settings
         switch provider {
         case .openrouter:
            settings.openRouterModelsCacheTimestamp = Date().timeIntervalSince1970
         case .openai:
            settings.openAIModelsCacheTimestamp = Date().timeIntervalSince1970
         default:
            break
         }
      } catch {
         Log.aiEnhancement.error("Failed to fetch \(provider.rawValue) models: \(error)")
         modelError = error.localizedDescription
      }
   }

   private func updateSelectedModelIfNeeded(
      for provider: AIProvider, models: [AIModelService.AIModel]
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
      default:
         return "gpt-4o-mini"
      }
   }

   // MARK: - Logic

   private var canSave: Bool {
      guard selectedProvider.isImplemented else { return false }
      if apiKey.isEmpty { return false }
      if selectedProvider == .custom {
         if customEndpoint.isEmpty { return false }
         if customModel.isEmpty { return false }
      }
      if (selectedProvider == .openrouter || selectedProvider == .openai) && selectedModel.isEmpty {
         return false
      }
      return true
   }

   private func loadCredentialsAndPrompt() {
      let loadedModel = settings.aiModel
      selectedModel = loadedModel

      if let endpoint = settings.apiEndpoint {
         customEndpoint = endpoint
         if endpoint.contains("openai.com") {
            selectedProvider = .openai
         } else if endpoint.contains("anthropic.com") {
            selectedProvider = .anthropic
         } else if endpoint.contains("googleapis.com") {
            selectedProvider = .google
         } else if endpoint.contains("openrouter.ai") {
            selectedProvider = .openrouter
         } else if !endpoint.isEmpty {
            selectedProvider = .custom
            customModel = loadedModel
         }
      }
      apiKey = settings.loadAPIKey(for: selectedProvider) ?? ""

      noteEnhancementPrompt = settings.noteEnhancementPrompt

      // Load models for the current provider
      Task {
         await loadModelsIfNeeded(for: selectedProvider)
      }
   }

   private func savePrompt() {
      settings.aiEnhancementPrompt = enhancementPrompt

      showingPromptSaveSuccess = true

      Task {
         try? await Task.sleep(for: .seconds(3))
         showingPromptSaveSuccess = false
      }
   }

   private func saveNotePrompt() {
      settings.noteEnhancementPrompt = noteEnhancementPrompt

      showingPromptSaveSuccess = true

      Task {
         try? await Task.sleep(for: .seconds(3))
         showingPromptSaveSuccess = false
      }
   }

   private func saveCredentials() {
      errorMessage = nil
      showingSaveSuccess = false

      do {
         let endpoint =
            selectedProvider == .custom ? customEndpoint : selectedProvider.defaultEndpoint
         try settings.saveAPIEndpoint(endpoint)
         try settings.saveAPIKey(apiKey, for: selectedProvider)

         if selectedProvider == .custom {
            settings.aiModel = customModel
         } else {
            settings.aiModel = selectedModel
         }

         settings.aiEnhancementPrompt = enhancementPrompt

         showingSaveSuccess = true

         Task {
            try? await Task.sleep(for: .seconds(3))
            showingSaveSuccess = false
         }
      } catch {
         errorMessage = "Failed to save: \(error.localizedDescription)"
      }
   }

   private func loadPresets() {
      do {
         presets = try promptPresetStore.fetchAll()

         if let presetId = settings.selectedPresetId {
            if let preset = presets.first(where: { $0.id.uuidString == presetId }) {
               enhancementPrompt = preset.prompt
            } else {
               settings.selectedPresetId = nil
               enhancementPrompt = settings.aiEnhancementPrompt
            }
         } else {
            enhancementPrompt = settings.aiEnhancementPrompt
         }
      } catch {
         Log.ui.error("Failed to load presets: \(error)")
         enhancementPrompt = settings.aiEnhancementPrompt
      }
   }

   private func handlePresetChange(_ presetId: String?) {
      if let presetId, let preset = presets.first(where: { $0.id.uuidString == presetId }) {
         enhancementPrompt = preset.prompt
      }
   }

   private func handlePromptChange(_ newPrompt: String) {
      // If text is modified and we have a selected preset, switch to Custom
      // unless the text matches the preset exactly (e.g. initial load)
      if let presetId = settings.selectedPresetId,
         let preset = presets.first(where: { $0.id.uuidString == presetId })
      {
         if newPrompt != preset.prompt {
            settings.selectedPresetId = nil
         }
      }
   }

   private func refreshPermissionStates() {
      let permissionManager = PermissionManager()
      accessibilityPermissionGranted = permissionManager.checkAccessibilityPermission()
   }

   private func requestAccessibilityPermissionIfNeeded() {
      guard !accessibilityPermissionRequestInFlight else { return }
      let permissionManager = PermissionManager()
      let alreadyGranted = permissionManager.checkAccessibilityPermission()
      accessibilityPermissionGranted = alreadyGranted
      guard !alreadyGranted else { return }

      accessibilityPermissionRequestInFlight = true
      _ = permissionManager.requestAccessibilityPermission(showPrompt: true)
      Task {
         try? await Task.sleep(for: .milliseconds(500))
         let granted = permissionManager.checkAccessibilityPermission()
         accessibilityPermissionGranted = granted
         accessibilityPermissionRequestInFlight = false
         if !granted {
            showAccessibilityAlert = true
         }
      }
   }
}

#Preview {
   AIEnhancementSettingsView(settings: SettingsStore())
      .padding()
      .frame(width: 500)
}

extension AIModelService.AIModel: SearchableDropdownItem {
   public var displayName: String { name }
}

//
//  AIEnhancementSettingsView.swift
//  Pindrop
//
//  Created on 2026-01-25.
//

import SwiftData
import SwiftUI
#if canImport(PindropSharedSettings)
import PindropSharedSettings
#endif
#if canImport(PindropSharedSchema)
import PindropSharedSchema
#endif

struct AIEnhancementSettingsView: View {
   @ObservedObject var settings: SettingsStore
   @Environment(\.modelContext) private var modelContext
   @Environment(\.locale) private var locale

   @State private var selectedProvider: AIProvider = .openai
   @State private var selectedCustomProvider: CustomProviderType = .custom
   @State private var apiKey = ""
   /// Separate draft URL per Custom / Ollama / LM Studio (and future) subtype.
   @State private var customEndpointDrafts: [CustomProviderType: String] = [:]
   @State private var selectedModel = "gpt-4o-mini"
   @State private var customModel = ""
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
   @State private var endpointRefreshTask: Task<Void, Never>?

   private var promptPresetStore: PromptPresetStore {
      PromptPresetStore(modelContext: modelContext)
   }

   #if canImport(PindropSharedSettings)
   private var aiEnhancementViewState: AIEnhancementViewState {
      AIEnhancementPresenter.shared.present(
         draft: AIEnhancementDraft(
            selectedProvider: selectedProvider.coreValue,
            selectedCustomProvider: selectedCustomProvider.coreValue,
            apiKey: apiKey,
            selectedModel: selectedModel,
            customModel: customModel,
            enhancementPrompt: enhancementPrompt,
            noteEnhancementPrompt: noteEnhancementPrompt,
            selectedPromptType: selectedPromptType.coreValue,
            selectedPresetId: settings.selectedPresetId,
            customEndpointText: currentCustomEndpointText,
            availableModels: availableModels.map {
               AIModelSnapshot(id: $0.id, name: $0.name, summary: $0.description)
            },
            modelErrorMessage: modelError,
            isLoadingModels: isLoadingModels,
            aiEnhancementEnabled: settings.aiEnhancementEnabled
         ),
         presets: presets.map {
            PromptPresetSnapshot(
               id: $0.id.uuidString,
               name: $0.name,
               prompt: $0.prompt,
               isBuiltIn: $0.isBuiltIn,
               sortOrder: Int32($0.sortOrder)
            )
         }
      )
   }
   #endif

   private var validatedSelectedPresetId: String? {
      #if canImport(PindropSharedSettings)
      aiEnhancementViewState.validatedPresetId
      #else
      guard let presetId = settings.selectedPresetId,
         presets.contains(where: { $0.id.uuidString == presetId })
      else {
         return nil
      }
      return presetId
      #endif
   }

   private var shouldShowCustomProviderPicker: Bool {
      #if canImport(PindropSharedSettings)
      aiEnhancementViewState.shouldShowCustomProviderPicker
      #else
      selectedProvider == .custom
      #endif
   }

   private var shouldShowPrimaryModelPicker: Bool {
      #if canImport(PindropSharedSettings)
      aiEnhancementViewState.shouldShowModelPicker && selectedProvider != .custom
      #else
      selectedProvider == .openrouter || selectedProvider == .openai || selectedProvider == .anthropic
      #endif
   }

   private var shouldShowCustomModelPicker: Bool {
      #if canImport(PindropSharedSettings)
      shouldShowCustomProviderPicker && aiEnhancementViewState.shouldShowModelPicker
      #else
      selectedProvider == .custom && selectedCustomProvider.supportsModelListing
      #endif
   }

   private var shouldShowCustomModelField: Bool {
      #if canImport(PindropSharedSettings)
      aiEnhancementViewState.shouldShowCustomModelField
      #else
      selectedProvider == .custom && !selectedCustomProvider.supportsModelListing
      #endif
   }

   private var shouldShowCustomEndpointField: Bool {
      #if canImport(PindropSharedSettings)
      aiEnhancementViewState.shouldShowCustomEndpointField
      #else
      selectedProvider == .custom
      #endif
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
             return localized("Sent to the AI model when processing dictation for direct text insertion.", locale: .autoupdatingCurrent)
          case .notes:
             return
                localized("Used when capturing notes via hotkey. Can add markdown formatting for longer content.", locale: .autoupdatingCurrent)
          }
       }
   }

   var body: some View {
      VStack(spacing: AppTheme.Spacing.xl) {
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
      .onChange(of: selectedProvider) { oldValue, newValue in
         if newValue == .custom {
            applyCustomEndpointDefault(forceReset: oldValue != .custom)
         }

         apiKey = settings.loadAPIKey(for: newValue, customLocalProvider: selectedCustomProvider) ?? ""
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
         apiKey = settings.loadAPIKey(for: .custom, customLocalProvider: newValue) ?? ""

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
      .sheet(isPresented: $showPresetManagement) {
         PresetManagementSheet()
            .onDisappear {
               loadPresets()
            }
      }
      .alert(localized("Accessibility Permission Recommended", locale: locale), isPresented: $showAccessibilityAlert) {
         Button(localized("Open System Settings", locale: locale)) {
            PermissionManager().openAccessibilityPreferences()
         }
         Button(localized("Continue Without", locale: locale), role: .cancel) {}
      } message: {
         Text(localized("Vibe mode works best with Accessibility permission. Without it, Pindrop falls back to limited app metadata and transcription still works normally.", locale: locale))
      }
   }

   // MARK: - Enable Toggle Card

   private var enableToggleCard: some View {
      SettingsCard(title: localized("Status", locale: locale), icon: "sparkles") {
         Toggle(isOn: $settings.aiEnhancementEnabled) {
            VStack(alignment: .leading, spacing: 2) {
               Text(localized("Enable AI Enhancement", locale: locale))
                  .font(AppTypography.body)
                  .foregroundStyle(AppColors.textPrimary)
               Text(localized("Improve transcription quality using AI", locale: locale))
                  .font(AppTypography.caption)
                  .foregroundStyle(AppColors.textSecondary)
            }
         }
         .toggleStyle(.switch)
      }
   }

   // MARK: - Provider Card

   private var providerCard: some View {
      SettingsCard(title: localized("Provider", locale: locale), icon: "server.rack") {
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
      SettingsCard(title: localized("Enhancement Prompts", locale: locale), icon: "text.bubble") {
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
         get: { validatedSelectedPresetId },
         set: { settings.selectedPresetId = $0 }
      )
   }

   private var presetPicker: some View {
      VStack(alignment: .leading, spacing: 6) {
         Text(localized("Prompt Preset", locale: locale))
            .font(.subheadline)
            .fontWeight(.medium)

         HStack(spacing: 8) {
            SelectField(
               options: promptPresetOptions,
               selection: promptPresetSelection,
                placeholder: localized("Custom", locale: locale)
            )
            .frame(maxWidth: 260)

            Button(localized("Manage Presets...", locale: locale)) {
               showPresetManagement = true
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Spacer()

            if let presetId = settings.selectedPresetId,
               let preset = presets.first(where: { $0.id.uuidString == presetId })
            {
               Text(preset.isBuiltIn ? localized("Built-in (read-only)", locale: locale) : localized("Custom", locale: locale))
                  .font(AppTypography.caption)
                  .foregroundStyle(AppColors.textSecondary)
                  .padding(.horizontal, 8)
                  .padding(.vertical, 4)
                  .background(AppColors.mutedSurface, in: Capsule())
             }
         }
      }
   }

   // MARK: - Context Card

   private var contextCard: some View {
      SettingsCard(title: localized("Vibe Mode", locale: locale), icon: "wand.and.stars") {
         VStack(alignment: .leading, spacing: 16) {
             Text(localized("Vibe mode captures structured UI context when recording starts so AI enhancement can use your active app state as reference.", locale: locale))
            .font(AppTypography.caption)
            .foregroundStyle(AppColors.textSecondary)

             Toggle(
                localized("Enable vibe mode (UI context)", locale: locale),
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
                localized("Enable live session updates during recording", locale: locale),
               isOn: $settings.vibeLiveSessionEnabled
            )
            .toggleStyle(.switch)
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 6) {
               IconView(icon: accessibilityPermissionGranted ? .check : .info, size: 12)
                  .foregroundStyle(accessibilityPermissionGranted ? AppColors.success : AppColors.textSecondary)
                Text(
                    accessibilityPermissionGranted
                      ? localized("Accessibility permission is enabled. Full UI context is available.", locale: locale)
                      : localized("Accessibility permission is not granted. Vibe mode remains non-blocking with limited context.", locale: locale)
                )
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textSecondary)

               if !accessibilityPermissionGranted {
                  Spacer(minLength: 8)
                  Button(localized("Open Settings", locale: locale)) {
                     PermissionManager().openAccessibilityPreferences()
                  }
                  .buttonStyle(.borderless)
                  .font(.caption)
               }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColors.mutedSurface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
               RoundedRectangle(cornerRadius: 8, style: .continuous)
                  .strokeBorder(AppColors.border.opacity(0.5), lineWidth: 1)
            )

            VStack(alignment: .leading, spacing: 6) {
               HStack(spacing: 6) {
                  Circle()
                     .fill(vibeRuntimeColor)
                     .frame(width: 8, height: 8)
                  Text(String(format: localized("Runtime: %@", locale: locale), vibeRuntimeLabel))
                     .font(.caption.weight(.semibold))
                     .foregroundStyle(vibeRuntimeColor)
               }

                Text(settings.vibeRuntimeDetail)
                   .font(AppTypography.caption)
                   .foregroundStyle(AppColors.textSecondary)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColors.mutedSurface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
               RoundedRectangle(cornerRadius: 8, style: .continuous)
                  .strokeBorder(AppColors.border.opacity(0.5), lineWidth: 1)
            )

            VStack(spacing: 12) {
               Toggle(localized("Include clipboard text", locale: locale), isOn: $settings.enableClipboardContext)
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
         return localized("Ready", locale: locale)
      case .limited:
         return localized("Limited", locale: locale)
      case .degraded:
         return localized("Degraded", locale: locale)
      }
   }

   private var vibeRuntimeColor: Color {
       switch settings.vibeRuntimeState {
       case .ready:
          return AppColors.success
       case .limited:
          return AppColors.warning
       case .degraded:
          return AppColors.error
       }
    }

   private var promptTypeTabs: some View {
      HStack(spacing: 0) {
         ForEach(PromptType.allCases) { type in
            promptTypeTab(type)
         }
      }
      .background(AppColors.mutedSurface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
   }

   private func promptTypeTab(_ type: PromptType) -> some View {
      Button {
         withAnimation(.spring(duration: 0.3)) {
            selectedPromptType = type
         }
      } label: {
         VStack(spacing: 3) {
            IconView(icon: type.icon, size: 14)
            Text(localized(type.rawValue, locale: locale))
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
         .foregroundStyle(selectedPromptType == type ? AppColors.accent : AppColors.textSecondary)
      }
      .buttonStyle(.plain)
   }

   @ViewBuilder
   private var promptContent: some View {
      let currentPrompt =
         selectedPromptType == .transcription ? $enhancementPrompt : $noteEnhancementPrompt
      #if canImport(PindropSharedSettings)
      let charCount = aiEnhancementViewState.selectedPromptCharacterCount
      let isReadOnly = aiEnhancementViewState.isSelectedPromptReadOnly
      #else
      let charCount =
         selectedPromptType == .transcription
         ? enhancementPrompt.count : noteEnhancementPrompt.count
      let isReadOnly = selectedPromptType == .transcription && isBuiltInPresetSelected
      #endif

      VStack(alignment: .leading, spacing: 12) {
          TextEditor(text: currentPrompt)
             .font(AppTypography.body)
             .frame(minHeight: 120, maxHeight: 220)
             .padding(8)
             .scrollContentBackground(.hidden)
             .background(AppColors.inputBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
             .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                   .strokeBorder(AppColors.inputBorder, lineWidth: 1)
             )
             .disabled(isReadOnly)
             .opacity(isReadOnly ? 0.7 : 1)

         HStack {
            Button(localized("Reset to Default", locale: locale)) {
               resetCurrentPrompt()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Spacer()

             Text(String(format: localized("%d characters", locale: locale), charCount))
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textSecondary)
         }

          Text(selectedPromptType.description)
             .font(AppTypography.caption)
             .foregroundStyle(AppColors.textSecondary)

         HStack {
            Button(localized("Save Prompt", locale: locale)) {
               saveCurrentPrompt()
            }
            .buttonStyle(.borderedProminent)
            .disabled(charCount == 0 || isReadOnly)

            Spacer()

            if showingPromptSaveSuccess {
               HStack(spacing: 6) {
                  IconView(icon: .check, size: 12)
                     .foregroundStyle(AppColors.success)
                   Text(localized("Saved", locale: locale))
                     .font(AppTypography.caption)
                     .foregroundStyle(AppColors.success)
               }
            }
         }
      }
   }

   private var isBuiltInPresetSelected: Bool {
      #if canImport(PindropSharedSettings)
      aiEnhancementViewState.isBuiltInPresetSelected
      #else
      guard let id = settings.selectedPresetId,
         let preset = presets.first(where: { $0.id.uuidString == id })
      else { return false }
      return preset.isBuiltIn
      #endif
   }

   private func resetCurrentPrompt() {
      switch selectedPromptType {
      case .transcription:
         settings.selectedPresetId = nil  // Reset preset to Custom
         enhancementPrompt = localizedTranscriptionPrompt(AIEnhancementService.defaultSystemPrompt)
      case .notes:
         noteEnhancementPrompt = localizedNotePrompt(SettingsDefaults.shared.noteEnhancementPrompt)
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
      .background(AppColors.mutedSurface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
   }

   private func providerTab(_ provider: AIProvider) -> some View {
      Button {
         withAnimation(.spring(duration: 0.3)) {
            selectedProvider = provider
         }
      } label: {
         VStack(spacing: 3) {
            IconView(icon: provider.icon, size: 14)
            Text(localized(provider.displayName, locale: locale))
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
         .foregroundStyle(selectedProvider == provider ? AppColors.accent : AppColors.textSecondary)
      }
      .buttonStyle(.plain)
   }

   @ViewBuilder
   private var providerConfigContent: some View {
      if !selectedProvider.isImplemented {
         comingSoonView
      } else {
          VStack(spacing: 16) {
            if shouldShowCustomProviderPicker {
               customProviderPicker
            }

            apiKeyField

             if shouldShowPrimaryModelPicker {
               modelPicker
             }

             if shouldShowCustomProviderPicker {
                if shouldShowCustomModelPicker {
                   modelPicker
                }
                if shouldShowCustomModelField {
                   customModelField
                }
                if shouldShowCustomEndpointField {
                   customEndpointField
                }
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
            .foregroundStyle(AppColors.textSecondary)

         Text(String(format: localized("%@ Coming Soon", locale: locale), localized(selectedProvider.displayName, locale: locale)))
            .font(.headline)

          Text(
             "This provider will be available in a future update.\nTry OpenAI or use a Custom endpoint."
          )
          .font(AppTypography.caption)
          .foregroundStyle(AppColors.textSecondary)
         .multilineTextAlignment(.center)
      }
      .padding(.vertical, 24)
      .frame(maxWidth: .infinity)
   }

   private var apiKeyField: some View {
      VStack(alignment: .leading, spacing: 6) {
         HStack(spacing: 8) {
             Text(localized("API Key", locale: locale))
               .font(.subheadline)
               .fontWeight(.medium)

            if isAPIKeyOptional {
               Text(localized("Optional", locale: locale))
                  .font(AppTypography.caption)
                  .foregroundStyle(AppColors.textSecondary)
                  .padding(.horizontal, 8)
                  .padding(.vertical, 4)
                  .background(AppColors.mutedSurface, in: Capsule())
            }
         }

          HStack(spacing: 8) {
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
                   .foregroundStyle(AppColors.textSecondary)
           }
           .buttonStyle(.plain)
         }
          .aiSettingsInputChrome()

          if let apiKeyHelpText {
             Text(apiKeyHelpText)
                .font(AppTypography.caption)
               .foregroundStyle(AppColors.textSecondary)
          }
        }
     }

    private var customProviderPicker: some View {
       VStack(alignment: .leading, spacing: 6) {
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
       VStack(alignment: .leading, spacing: 6) {
         HStack {
             Text(localized("API Endpoint", locale: locale))
               .font(.subheadline)
               .fontWeight(.medium)

            Spacer()

              Text(selectedCustomProvider == .custom ? localized("Must be OpenAI-compatible", locale: locale) : localized("OpenAI-compatible local server", locale: locale))
                 .font(AppTypography.caption)
                 .foregroundStyle(AppColors.textSecondary)
          }

           TextField(selectedCustomProvider.endpointPlaceholder, text: customEndpointTextBinding())
              .textFieldStyle(.plain)
              .aiSettingsInputChrome()
        }
     }

   private var customModelField: some View {
      VStack(alignment: .leading, spacing: 6) {
          Text(localized("AI Model", locale: locale))
             .font(.subheadline)
             .fontWeight(.medium)

           TextField(selectedCustomProvider.modelPlaceholder, text: $customModel)
              .textFieldStyle(.plain)
              .aiSettingsInputChrome()
        }
     }

    private var modelPicker: some View {
      VStack(alignment: .leading, spacing: 6) {
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
                   await refreshModels(
                      for: selectedProvider,
                      customLocalProvider: selectedCustomProvider
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
                 .font(AppTypography.caption)
                 .foregroundStyle(AppColors.textSecondary)
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
                    .foregroundStyle(AppColors.error)
                 Text(modelError)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.error)
             }
          }
       }
       .zIndex(10)
    }


   private var emptyModelsMessage: String {
      #if canImport(PindropSharedSettings)
      return localized(aiEnhancementViewState.emptyModelsMessageKey, locale: locale)
      #else
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
      #endif
     }

   private var saveButton: some View {
      HStack {
         Spacer()

         Button(localized("Save Credentials", locale: locale)) {
            saveCredentials()
         }
         .buttonStyle(.borderedProminent)
         .disabled(!canSave)
      }
   }

   private var successMessage: some View {
      HStack(spacing: 6) {
         IconView(icon: .check, size: 14)
            .foregroundStyle(AppColors.success)
         Text(localized("Credentials saved successfully", locale: locale))
            .font(AppTypography.caption)
            .foregroundStyle(AppColors.success)
      }
      .frame(maxWidth: .infinity)
      .padding(10)
      .background(AppColors.successBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

   private func errorMessageView(_ message: String) -> some View {
      HStack(spacing: 6) {
         IconView(icon: .warning, size: 14)
            .foregroundStyle(AppColors.error)
         Text(message)
            .font(AppTypography.caption)
            .foregroundStyle(AppColors.error)
      }
      .frame(maxWidth: .infinity)
      .padding(10)
      .background(AppColors.errorBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var keychainNote: some View {
       HStack(spacing: 6) {
         IconView(icon: .shield, size: 12)
            .foregroundStyle(AppColors.textSecondary)
         Text(localized("Credentials are stored securely in Keychain", locale: locale))
            .font(AppTypography.caption)
            .foregroundStyle(AppColors.textSecondary)
       }
    }

    private var isAPIKeyOptional: Bool {
       #if canImport(PindropSharedSettings)
       aiEnhancementViewState.isApiKeyOptional
       #else
       selectedProvider == .custom && !selectedCustomProvider.requiresAPIKey
       #endif
    }

    private var currentAPIKeyPlaceholder: String {
       #if canImport(PindropSharedSettings)
       aiEnhancementViewState.currentApiKeyPlaceholder
       #else
       selectedProvider == .custom ? selectedCustomProvider.apiKeyPlaceholder : selectedProvider.apiKeyPlaceholder
       #endif
    }

    private var apiKeyHelpText: String? {
       #if canImport(PindropSharedSettings)
       aiEnhancementViewState.apiKeyHelpText
       #else
       guard selectedProvider == .custom else { return nil }

       switch selectedCustomProvider {
       case .custom:
          return nil
       case .ollama:
          return "Ollama usually does not require authentication for local requests."
       case .lmStudio:
          return "LM Studio only needs a token if local server authentication is enabled."
       }
       #endif
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
          if let stored = settings.storedAPIEndpoint(forCustomLocalProvider: type) {
             customEndpointDrafts[type] = stored
          } else if !type.defaultEndpoint.isEmpty {
             customEndpointDrafts[type] = type.defaultEndpoint
          } else {
             customEndpointDrafts[type] = ""
          }
       }
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

    // MARK: - Model Fetching

    @MainActor
    private func loadModelsIfNeeded(
       for provider: AIProvider,
       customLocalProvider: CustomProviderType? = nil,
       forceRefresh: Bool = false
    ) async {
       if provider == .anthropic {
          availableModels = Self.anthropicModels
          updateSelectedModelIfNeeded(for: provider, models: availableModels)
          return
       }

       let resolvedCustomProvider = customLocalProvider ?? selectedCustomProvider
       let shouldUseCachedModels = !(provider == .custom && resolvedCustomProvider.supportsModelListing)
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
             apiKey: settings.configuredAPIKey(
                for: provider,
                customLocalProvider: resolvedCustomProvider
             ) ?? apiKey,
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

   private static let anthropicModels: [AIModelService.AIModel] = [
      AIModelService.AIModel(id: "claude-haiku-4-5", name: "Claude Haiku 4.5", provider: .anthropic,
                             description: "Fast and affordable", contextLength: 200_000),
      AIModelService.AIModel(id: "claude-sonnet-4-6", name: "Claude Sonnet 4.6", provider: .anthropic,
                             description: "Balanced performance", contextLength: 1_000_000),
      AIModelService.AIModel(id: "claude-opus-4-6", name: "Claude Opus 4.6", provider: .anthropic,
                             description: "Most capable", contextLength: 1_000_000),
   ]

   private func defaultModelIdentifier(for provider: AIProvider) -> String {
      switch provider {
      case .openrouter:
         return "openai/gpt-4o-mini"
      case .openai:
         return "gpt-4o-mini"
      case .anthropic:
         return "claude-haiku-4-5"
      default:
         return "gpt-4o-mini"
      }
   }

    // MARK: - Logic

    private var canSave: Bool {
       #if canImport(PindropSharedSettings)
       aiEnhancementViewState.canSave
       #else
       guard selectedProvider.isImplemented else { return false }
       if settings.requiresAPIKey(for: selectedProvider, customLocalProvider: selectedCustomProvider)
          && apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
       {
          return false
       }
       if selectedProvider == .custom {
          if currentCustomEndpointText.isEmpty { return false }
          let configuredModel = selectedCustomProvider.supportsModelListing ? selectedModel : customModel
          if configuredModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return false }
       }
       if (selectedProvider == .openrouter || selectedProvider == .openai || selectedProvider == .anthropic)
          && selectedModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
       {
          return false
       }
       return true
       #endif
    }

    private func loadCredentialsAndPrompt() {
       let loadedModel = settings.aiModel
       selectedModel = loadedModel
       selectedCustomProvider = settings.currentCustomLocalProvider

       loadCustomEndpointDrafts()

       #if canImport(PindropSharedSettings)
       let inferredSelection = AISettingsCatalog.shared.inferProviderSelection(
          endpoint: settings.apiEndpoint,
          fallbackCustomProvider: settings.currentCustomLocalProvider.coreValue,
          currentProviderIsCustom: settings.currentAIProvider == .custom
       )
       selectedProvider = AIProvider(coreValue: inferredSelection.provider)
       selectedCustomProvider = CustomProviderType(coreValue: inferredSelection.customProvider)
       #else
       if let endpoint = settings.apiEndpoint {
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
             selectedCustomProvider = settings.inferredCustomLocalProvider(for: endpoint) ?? settings.currentCustomLocalProvider
          }
       } else if settings.currentAIProvider == .custom {
          selectedProvider = .custom
       }
       #endif
       customModel = loadedModel
       apiKey = settings.loadAPIKey(
          for: selectedProvider,
          customLocalProvider: selectedCustomProvider
       ) ?? ""

       noteEnhancementPrompt = localizedNotePrompt(settings.noteEnhancementPrompt)

       Task {
          await loadModelsIfNeeded(
             for: selectedProvider,
             customLocalProvider: selectedCustomProvider
          )
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
          if selectedProvider == .custom {
             settings.customLocalProviderType = selectedCustomProvider.rawValue
             for type in CustomProviderType.allCases {
                let raw = (customEndpointDrafts[type] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                try settings.saveAPIEndpoint(raw, for: .custom, customLocalProvider: type)
             }
          } else {
             try settings.saveAPIEndpoint(
                selectedProvider.defaultEndpoint,
                for: selectedProvider,
                customLocalProvider: nil
             )
          }

          try settings.saveAPIKey(
             apiKey,
             for: selectedProvider,
             customLocalProvider: selectedCustomProvider
          )

          if selectedProvider == .custom && !selectedCustomProvider.supportsModelListing {
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
          errorMessage = String(format: localized("Failed to save: %@", locale: locale), error.localizedDescription)
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
               enhancementPrompt = localizedTranscriptionPrompt(settings.aiEnhancementPrompt)
            }
         } else {
            enhancementPrompt = localizedTranscriptionPrompt(settings.aiEnhancementPrompt)
         }
      } catch {
         Log.ui.error("Failed to load presets: \(error)")
         enhancementPrompt = localizedTranscriptionPrompt(settings.aiEnhancementPrompt)
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

private extension AIEnhancementSettingsView {
   var promptPresetOptions: [SelectFieldOption] {
      [SelectFieldOption(id: customPromptPresetId, displayName: localized("Custom", locale: locale))]
         + presets.map {
            SelectFieldOption(
               id: $0.id.uuidString,
               displayName: $0.name
            )
         }
   }

   var promptPresetSelection: Binding<String> {
      Binding(
         get: { settings.selectedPresetId ?? customPromptPresetId },
         set: { newValue in
            settings.selectedPresetId = (newValue == customPromptPresetId) ? nil : newValue
         }
      )
   }

   var customProviderOptions: [SelectFieldOption] {
      CustomProviderType.allCases.map {
         SelectFieldOption(
            id: $0.id,
            displayName: localized($0.rawValue, locale: locale)
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

   var customPromptPresetId: String { "__custom__" }

   func localizedTranscriptionPrompt(_ prompt: String) -> String {
      if prompt == AIEnhancementService.defaultSystemPrompt {
         return localized("You are a text enhancement assistant. Improve the grammar, punctuation, and formatting of the provided text while preserving its original meaning and tone. Return only the enhanced text without any additional commentary.", locale: locale)
      }

      return prompt
   }

   func localizedNotePrompt(_ prompt: String) -> String {
      if prompt == SettingsDefaults.shared.noteEnhancementPrompt {
         return localized("You are a note formatting assistant. Transform the transcribed text into a well-structured note.\n\nRules:\n- Fix grammar, punctuation, and spelling errors\n- For longer content (3+ paragraphs), add markdown formatting:\n  - Use headers (## or ###) to organize sections\n  - Use bullet points or numbered lists where appropriate\n  - Use **bold** for emphasis on key terms\n- For shorter content, keep it simple with minimal formatting\n- Preserve the original meaning and tone\n- Do not add content that wasn't in the original\n- Return only the formatted note without any commentary", locale: locale)
      }

      return prompt
   }
}

extension AIModelService.AIModel: SearchableDropdownItem {
    public var displayName: String { name }

    public var searchableValues: [String] {
       [name, id, description].compactMap { $0 }
    }
}

#if canImport(PindropSharedSettings)
private extension AIEnhancementSettingsView.PromptType {
   var coreValue: PromptTypeCore {
      switch self {
      case .transcription: .transcription
      case .notes: .notes
      }
   }
}
#endif

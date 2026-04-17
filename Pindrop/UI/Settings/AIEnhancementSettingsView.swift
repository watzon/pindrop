//
//  AIEnhancementSettingsView.swift
//  Pindrop
//
//  Created on 2026-01-25.
//  Redesigned 2026-04-16 for AI Configuration v2: Providers + Assignments.
//

#if canImport(FoundationModels)
import FoundationModels
#endif
import SwiftData
import SwiftUI

struct AIEnhancementSettingsView: View {
   @ObservedObject var settings: SettingsStore
   @Environment(\.modelContext) private var modelContext
   @Environment(\.locale) private var locale

   @State private var presets: [PromptPreset] = []
   @State private var showPresetManagement = false

   // Provider sheet state
   @State private var editingProvider: ProviderEditState?
   @State private var providerPendingDeletion: ProviderConfig?

   // Vibe / accessibility state
   @State private var showAccessibilityAlert = false
   @State private var accessibilityPermissionGranted = false
   @State private var accessibilityPermissionRequestInFlight = false

   // Model lists per provider (keyed by provider UUID).
   @State private var modelListCache: [UUID: [AIModelService.AIModel]] = [:]
   @State private var modelListLoading: Set<UUID> = []
   @State private var modelListErrors: [UUID: String] = [:]
   @State private var modelService = AIModelService()

   // Inline prompt-override drafts per purpose, keyed by purpose.rawValue.
   @State private var promptOverrideDrafts: [String: String] = [:]

   private var promptPresetStore: PromptPresetStore {
      PromptPresetStore(modelContext: modelContext)
   }

   var body: some View {
      VStack(spacing: AppTheme.Spacing.xl) {
         providersCard
         assignmentsCard
         streamingEnhancementCard
         contextCard
      }
      .task {
         loadPresets()
         refreshPermissionStates()
         await preloadModelsForAllProviders()
      }
      .sheet(item: $editingProvider) { state in
         ProviderEditSheet(
            settings: settings,
            modelService: modelService,
            initial: state,
            onSave: { savedProvider in
               editingProvider = nil
               Task {
                  await refreshModels(for: savedProvider, force: true)
               }
            },
            onCancel: {
               editingProvider = nil
            }
         )
      }
      .sheet(isPresented: $showPresetManagement) {
         PresetManagementSheet()
            .onDisappear { loadPresets() }
      }
      .alert(
         localized("Remove Provider", locale: locale),
         isPresented: Binding(
            get: { providerPendingDeletion != nil },
            set: { if !$0 { providerPendingDeletion = nil } }
         ),
         presenting: providerPendingDeletion
      ) { provider in
         Button(localized("Remove", locale: locale), role: .destructive) {
            settings.removeProvider(withID: provider.id)
            providerPendingDeletion = nil
         }
         Button(localized("Cancel", locale: locale), role: .cancel) {
            providerPendingDeletion = nil
         }
      } message: { provider in
         Text(
            String(
               format: localized(
                  "Remove \"%@\" and clear any assignments that reference it? Stored credentials will be deleted.",
                  locale: locale
               ),
               provider.displayName
            )
         )
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

   // MARK: - Providers Card

   private var providersCard: some View {
      SettingsCard(
         title: localized("Providers", locale: locale),
         icon: "server.rack",
         detail: localized("Configure AI providers and credentials. Apple Intelligence runs on-device; other providers require API keys.", locale: locale)
      ) {
         VStack(spacing: 10) {
            if settings.providers.isEmpty {
               emptyProvidersPlaceholder
            } else {
               ForEach(settings.providers) { provider in
                  providerRow(provider)
               }
            }

            HStack {
               Spacer()
               Button {
                  editingProvider = ProviderEditState.newProvider()
               } label: {
                  HStack(spacing: 6) {
                     Image(systemName: "plus")
                     Text(localized("Add Provider", locale: locale))
                  }
               }
               .buttonStyle(.borderedProminent)
            }
         }
      }
   }

   private var emptyProvidersPlaceholder: some View {
      VStack(spacing: 8) {
         IconView(icon: .server, size: 28)
            .foregroundStyle(AppColors.textSecondary)
         Text(localized("No providers configured yet.", locale: locale))
            .font(AppTypography.body)
            .foregroundStyle(AppColors.textPrimary)
         Text(localized("Add a provider to start using AI enhancement.", locale: locale))
            .font(AppTypography.caption)
            .foregroundStyle(AppColors.textSecondary)
      }
      .frame(maxWidth: .infinity)
      .padding(.vertical, 16)
   }

   private func providerRow(_ provider: ProviderConfig) -> some View {
      HStack(alignment: .center, spacing: 12) {
         ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
               .fill(AppColors.accentBackground)
               .frame(width: 32, height: 32)
            IconView(icon: provider.kind.icon, size: 16)
               .foregroundStyle(AppColors.accent)
         }

         VStack(alignment: .leading, spacing: 2) {
            Text(provider.displayName)
               .font(AppTypography.body)
               .foregroundStyle(AppColors.textPrimary)

            HStack(spacing: 6) {
               Text(providerKindLabel(provider))
                  .font(AppTypography.caption)
                  .foregroundStyle(AppColors.textSecondary)

               Text("•")
                  .font(AppTypography.caption)
                  .foregroundStyle(AppColors.textSecondary)

               Text(providerStatusLine(provider))
                  .font(AppTypography.caption)
                  .foregroundStyle(AppColors.textSecondary)
                  .lineLimit(1)
                  .truncationMode(.middle)
            }
         }

         Spacer(minLength: 0)

         if provider.kind == .apple {
            Button(localized("Rename", locale: locale)) {
               editingProvider = ProviderEditState(existing: provider, settings: settings)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
         } else {
            Button(localized("Edit", locale: locale)) {
               editingProvider = ProviderEditState(existing: provider, settings: settings)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Button(localized("Remove", locale: locale)) {
               providerPendingDeletion = provider
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(AppColors.error)
         }
      }
      .padding(12)
      .background(AppColors.mutedSurface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
      .overlay(
         RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(AppColors.border.opacity(0.5), lineWidth: 1)
      )
   }

   private func providerKindLabel(_ provider: ProviderConfig) -> String {
      switch provider.kind {
      case .openai: return localized("OpenAI", locale: locale)
      case .anthropic: return localized("Anthropic", locale: locale)
      case .google: return localized("Google", locale: locale)
      case .openrouter: return localized("OpenRouter", locale: locale)
      case .apple: return localized("Apple Intelligence", locale: locale)
      case .custom:
         switch provider.customKind ?? .custom {
         case .ollama: return localized("Ollama", locale: locale)
         case .lmStudio: return localized("LM Studio", locale: locale)
         case .custom: return localized("Custom (OpenAI-compatible)", locale: locale)
         }
      }
   }

   private func providerStatusLine(_ provider: ProviderConfig) -> String {
      if provider.kind == .apple {
         return localized("On-device, no credentials required", locale: locale)
      }

      let hasKey = settings.loadProviderAPIKey(forProviderID: provider.id) != nil
      if provider.kind == .custom {
         let endpoint = settings.loadProviderEndpoint(forProviderID: provider.id)
            ?? (provider.customKind ?? .custom).defaultEndpoint
         let displayEndpoint = shortEndpoint(endpoint)
         let requiresKey = (provider.customKind ?? .custom).requiresAPIKey
         if requiresKey {
            if hasKey {
               return String(format: localized("API key saved • Endpoint: %@", locale: locale), displayEndpoint)
            } else {
               return String(format: localized("No API key • Endpoint: %@", locale: locale), displayEndpoint)
            }
         } else {
            return String(format: localized("Endpoint: %@", locale: locale), displayEndpoint)
         }
      }

      return hasKey
         ? localized("API key saved", locale: locale)
         : localized("No API key", locale: locale)
   }

   private func shortEndpoint(_ endpoint: String) -> String {
      guard !endpoint.isEmpty else { return localized("Not set", locale: locale) }
      // Strip trailing path for a concise display.
      if let url = URL(string: endpoint), let host = url.host {
         if let port = url.port {
            return "\(host):\(port)"
         }
         return host
      }
      return endpoint
   }

   // MARK: - Assignments Card

   private var assignmentsCard: some View {
      SettingsCard(
         title: localized("Assignments", locale: locale),
         icon: "arrow.triangle.branch",
         detail: localized("Pick which provider and model handles each AI task. Leave as \"Not assigned\" to skip a purpose.", locale: locale)
      ) {
         VStack(spacing: AppTheme.Spacing.lg) {
            ForEach(EnhancementPurpose.allCases, id: \.self) { purpose in
               assignmentRow(for: purpose)
               if purpose != EnhancementPurpose.allCases.last {
                  Divider().overlay(AppColors.divider)
               }
            }
         }
      }
   }

   @ViewBuilder
   private func assignmentRow(for purpose: EnhancementPurpose) -> some View {
      let assignment = settings.assignment(for: purpose)
      let selectedProvider = assignment.flatMap { settings.provider(withID: $0.providerID) }

      VStack(alignment: .leading, spacing: 10) {
         HStack(alignment: .firstTextBaseline) {
            Text(purposeLabel(purpose))
               .font(AppTypography.body)
               .fontWeight(.medium)
               .foregroundStyle(AppColors.textPrimary)

            Spacer()
         }

         if let helper = purposeHelperText(purpose) {
            Text(helper)
               .font(AppTypography.caption)
               .foregroundStyle(AppColors.textSecondary)
               .fixedSize(horizontal: false, vertical: true)
         }

         // Provider picker
         HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
               Text(localized("Provider", locale: locale))
                  .font(AppTypography.caption)
                  .foregroundStyle(AppColors.textSecondary)
               SelectField(
                  options: providerOptions,
                  selection: providerSelectionBinding(for: purpose),
                  placeholder: localized("Not assigned", locale: locale)
               )
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
               Text(localized("Model", locale: locale))
                  .font(AppTypography.caption)
                  .foregroundStyle(AppColors.textSecondary)
               modelPicker(for: purpose, provider: selectedProvider)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
         }

         // Preset picker + inline custom editor — only exposed for purposes whose prompt
         // the user can customize. Locked purposes (streaming refinement, metadata
         // generators) use a built-in prompt that's tuned for a specific output schema or
         // coordinator diff path; letting users change it silently breaks those systems.
         if purpose.supportsUserPrompt {
            VStack(alignment: .leading, spacing: 4) {
               HStack {
                  Text(localized("Prompt Preset", locale: locale))
                     .font(AppTypography.caption)
                     .foregroundStyle(AppColors.textSecondary)
                  Spacer()
                  Button(localized("Manage Presets...", locale: locale)) {
                     showPresetManagement = true
                  }
                  .buttonStyle(.borderless)
                  .controlSize(.small)
                  .font(.caption)
               }
               SelectField(
                  options: presetOptions,
                  selection: presetSelectionBinding(for: purpose),
                  placeholder: localized("Custom", locale: locale)
               )
               .disabled(selectedProvider == nil)

               if isCustomPresetSelected(for: purpose) {
                  customPromptEditor(for: purpose)
               }
            }
         } else {
            Text(localized("Uses a built-in prompt tuned for this task.", locale: locale))
               .font(AppTypography.caption)
               .foregroundStyle(AppColors.textSecondary)
               .fixedSize(horizontal: false, vertical: true)
         }

         // Apple availability inline warning
         if let provider = selectedProvider, provider.kind == .apple,
            !isAppleIntelligenceAvailable
         {
            HStack(alignment: .top, spacing: 6) {
               IconView(icon: .warning, size: 12)
                  .foregroundStyle(AppColors.warning)
               Text(localized("Apple Intelligence is unavailable on this system. This assignment will not resolve until Apple Intelligence is enabled.", locale: locale))
                  .font(AppTypography.caption)
                  .foregroundStyle(AppColors.textSecondary)
                  .fixedSize(horizontal: false, vertical: true)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColors.warningBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
         }
      }
      .padding(.vertical, 4)
   }

   private func purposeLabel(_ purpose: EnhancementPurpose) -> String {
      switch purpose {
      case .transcriptionEnhancement:
         return localized("Transcription Enhancement", locale: locale)
      case .streamingRefinement:
         return localized("Live Streaming Refinement", locale: locale)
      case .noteEnhancement:
         return localized("Note Enhancement", locale: locale)
      case .noteMetadata:
         return localized("Note Metadata", locale: locale)
      case .transcriptionMetadata:
         return localized("Transcription Metadata", locale: locale)
      }
   }

   private func purposeHelperText(_ purpose: EnhancementPurpose) -> String? {
      switch purpose {
      case .streamingRefinement:
         return localized("Requires a fast provider (Apple Foundation Models recommended). Cloud providers will issue one API call per pause.", locale: locale)
      case .transcriptionMetadata:
         return localized("Optional — used for auto-generated titles and summaries on media transcription imports.", locale: locale)
      default:
         return nil
      }
   }

   // MARK: - Provider selection binding

   private var providerOptions: [SelectFieldOption] {
      var opts: [SelectFieldOption] = [
         SelectFieldOption(id: unassignedProviderID, displayName: localized("Not assigned", locale: locale))
      ]
      opts.append(
         contentsOf: settings.providers.map {
            SelectFieldOption(id: $0.id.uuidString, displayName: $0.displayName)
         }
      )
      return opts
   }

   private func providerSelectionBinding(for purpose: EnhancementPurpose) -> Binding<String> {
      Binding(
         get: {
            settings.assignment(for: purpose)?.providerID.uuidString ?? unassignedProviderID
         },
         set: { newValue in
            if newValue == unassignedProviderID {
               settings.setAssignment(nil, for: purpose)
               syncLegacyPresetPointer(for: purpose)
               return
            }
            guard let uuid = UUID(uuidString: newValue),
               let provider = settings.provider(withID: uuid)
            else { return }

            let existing = settings.assignment(for: purpose)
            let defaultModelID = defaultModelID(for: provider)
            let newAssignment = ModelAssignment(
               providerID: provider.id,
               modelID: existing?.modelID.isEmpty == false
                  ? existing!.modelID : defaultModelID,
               promptPresetID: existing?.promptPresetID ?? defaultPresetID(for: purpose),
               promptOverride: existing?.promptOverride
            )
            settings.setAssignment(newAssignment, for: purpose)
            syncLegacyPresetPointer(for: purpose)

            Task { await refreshModels(for: provider, force: false) }
         }
      )
   }

   private func defaultModelID(for provider: ProviderConfig) -> String {
      if provider.kind == .apple { return "apple_intelligence" }
      if let cached = modelListCache[provider.id]?.first {
         return cached.id
      }
      switch provider.kind {
      case .openai: return "gpt-4o-mini"
      case .openrouter: return "openai/gpt-4o-mini"
      case .anthropic: return "claude-haiku-4-5"
      case .google: return ""
      case .apple: return "apple_intelligence"
      case .custom: return ""
      }
   }

   private func defaultPresetID(for purpose: EnhancementPurpose) -> String? {
      switch purpose {
      case .transcriptionEnhancement:
         return BuiltInPresetID.cleanTranscript
      case .streamingRefinement:
         return BuiltInPresetID.liveStreamingRefinement
      default:
         return nil
      }
   }

   // MARK: - Model picker

   @ViewBuilder
   private func modelPicker(
      for purpose: EnhancementPurpose,
      provider: ProviderConfig?
   ) -> some View {
      if let provider {
         if provider.kind == .apple {
            Text(localized("Apple Foundation Models (on-device)", locale: locale))
               .font(AppTypography.body)
               .foregroundStyle(AppColors.textSecondary)
               .frame(maxWidth: .infinity, alignment: .leading)
               .aiSettingsInputChrome()
         } else if provider.kind == .custom
            && !(provider.customKind ?? .custom).supportsModelListing
         {
            TextField(
               (provider.customKind ?? .custom).modelPlaceholder,
               text: modelTextFieldBinding(for: purpose, provider: provider)
            )
            .textFieldStyle(.plain)
            .aiSettingsInputChrome()
         } else {
            let models = modelListCache[provider.id] ?? []
            if models.isEmpty {
               HStack(spacing: 6) {
                  if modelListLoading.contains(provider.id) {
                     ProgressView().controlSize(.small)
                     Text(localized("Loading models...", locale: locale))
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textSecondary)
                  } else if let err = modelListErrors[provider.id] {
                     Text(err)
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.error)
                        .lineLimit(1)
                        .truncationMode(.tail)
                  } else {
                     Text(localized("No models loaded. Open Edit to fetch models.", locale: locale))
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textSecondary)
                  }
                  Spacer()
                  Button(localized("Refresh", locale: locale)) {
                     Task { await refreshModels(for: provider, force: true) }
                  }
                  .buttonStyle(.borderless)
                  .font(.caption)
                  .controlSize(.small)
               }
               .frame(maxWidth: .infinity, alignment: .leading)
               .aiSettingsInputChrome()
            } else {
               SearchableDropdown(
                  items: models,
                  selection: modelSelectionBinding(for: purpose, provider: provider),
                  placeholder: localized("Select a model", locale: locale),
                  emptyMessage: localized("No models found.", locale: locale),
                  searchPlaceholder: localized("Search models...", locale: locale)
               )
            }
         }
      } else {
         Text(localized("Choose a provider first", locale: locale))
            .font(AppTypography.body)
            .foregroundStyle(AppColors.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .aiSettingsInputChrome()
      }
   }

   private func modelSelectionBinding(
      for purpose: EnhancementPurpose,
      provider: ProviderConfig
   ) -> Binding<String?> {
      Binding(
         get: {
            let currentID = settings.assignment(for: purpose)?.modelID
            if let currentID, !currentID.isEmpty { return currentID }
            return nil
         },
         set: { newValue in
            guard let newValue else { return }
            var existing = settings.assignment(for: purpose)
               ?? ModelAssignment(
                  providerID: provider.id,
                  modelID: newValue,
                  promptPresetID: defaultPresetID(for: purpose)
               )
            existing.modelID = newValue
            existing.providerID = provider.id
            settings.setAssignment(existing, for: purpose)
         }
      )
   }

   private func modelTextFieldBinding(
      for purpose: EnhancementPurpose,
      provider: ProviderConfig
   ) -> Binding<String> {
      Binding(
         get: { settings.assignment(for: purpose)?.modelID ?? "" },
         set: { newValue in
            var existing = settings.assignment(for: purpose)
               ?? ModelAssignment(
                  providerID: provider.id,
                  modelID: newValue,
                  promptPresetID: defaultPresetID(for: purpose)
               )
            existing.modelID = newValue
            existing.providerID = provider.id
            settings.setAssignment(existing, for: purpose)
         }
      )
   }

   // MARK: - Preset binding

   private var presetOptions: [SelectFieldOption] {
      var opts: [SelectFieldOption] = [
         SelectFieldOption(id: customPresetSentinel, displayName: localized("Custom", locale: locale))
      ]
      opts.append(
         contentsOf: presets.map {
            SelectFieldOption(
               id: $0.builtInIdentifier ?? $0.id.uuidString,
               displayName: $0.name
            )
         }
      )
      return opts
   }

   private func presetSelectionBinding(for purpose: EnhancementPurpose) -> Binding<String> {
      Binding(
         get: {
            guard let assignment = settings.assignment(for: purpose) else {
               return customPresetSentinel
            }
            if assignment.promptOverride != nil { return customPresetSentinel }
            return assignment.promptPresetID ?? customPresetSentinel
         },
         set: { newValue in
            guard var existing = settings.assignment(for: purpose) else { return }
            if newValue == customPresetSentinel {
               existing.promptPresetID = nil
               // Seed override with the current preset copy so the text editor has something
               // to show when the user flips to Custom.
               if existing.promptOverride == nil {
                  existing.promptOverride = resolvePresetPromptText(existing.promptPresetID)
                     ?? ""
               }
               settings.setAssignment(existing, for: purpose)
               promptOverrideDrafts[purpose.rawValue] = existing.promptOverride ?? ""
            } else {
               existing.promptPresetID = newValue
               existing.promptOverride = nil
               settings.setAssignment(existing, for: purpose)
               promptOverrideDrafts[purpose.rawValue] = nil
            }
            syncLegacyPresetPointer(for: purpose)
         }
      )
   }

   private func isCustomPresetSelected(for purpose: EnhancementPurpose) -> Bool {
      guard let a = settings.assignment(for: purpose) else { return false }
      return a.promptOverride != nil || (a.promptPresetID == nil)
   }

   @ViewBuilder
   private func customPromptEditor(for purpose: EnhancementPurpose) -> some View {
      let binding = promptOverrideBinding(for: purpose)
      VStack(alignment: .leading, spacing: 6) {
         TextEditor(text: binding)
            .font(AppTypography.body)
            .frame(minHeight: 110, maxHeight: 220)
            .padding(8)
            .scrollContentBackground(.hidden)
            .background(AppColors.inputBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
               RoundedRectangle(cornerRadius: 8, style: .continuous)
                  .strokeBorder(AppColors.inputBorder, lineWidth: 1)
            )

         Text(
            String(
               format: localized("%d characters", locale: locale),
               binding.wrappedValue.count
            )
         )
         .font(AppTypography.caption)
         .foregroundStyle(AppColors.textSecondary)
         .frame(maxWidth: .infinity, alignment: .trailing)
      }
   }

   private func promptOverrideBinding(for purpose: EnhancementPurpose) -> Binding<String> {
      Binding(
         get: {
            if let draft = promptOverrideDrafts[purpose.rawValue] { return draft }
            return settings.assignment(for: purpose)?.promptOverride ?? ""
         },
         set: { newValue in
            promptOverrideDrafts[purpose.rawValue] = newValue
            guard var existing = settings.assignment(for: purpose) else { return }
            existing.promptOverride = newValue.isEmpty ? nil : newValue
            existing.promptPresetID = nil
            settings.setAssignment(existing, for: purpose)
         }
      )
   }

   private func resolvePresetPromptText(_ presetID: String?) -> String? {
      guard let presetID else { return nil }
      if let preset = presets.first(where: { $0.builtInIdentifier == presetID }) {
         return preset.prompt
      }
      if let preset = presets.first(where: { $0.id.uuidString == presetID }) {
         return preset.prompt
      }
      return nil
   }

   /// The legacy menu-bar "prompt preset" hotkey reads `settings.selectedPresetId` directly.
   /// Mirror whatever the transcription-enhancement row picks so the hotkey keeps working.
   private func syncLegacyPresetPointer(for purpose: EnhancementPurpose) {
      guard purpose == .transcriptionEnhancement else { return }
      let assignment = settings.assignment(for: .transcriptionEnhancement)
      guard let presetID = assignment?.promptPresetID else {
         settings.selectedPresetId = nil
         return
      }
      // Legacy pointer expects a preset UUID string. If the assignment points to a built-in
      // identifier, map it back to the SwiftData row's UUID.
      if let uuid = presets.first(where: { $0.builtInIdentifier == presetID })?.id.uuidString {
         settings.selectedPresetId = uuid
      } else if UUID(uuidString: presetID) != nil {
         settings.selectedPresetId = presetID
      } else {
         settings.selectedPresetId = nil
      }
   }

   // MARK: - Streaming Enhancement Card

   private var streamingEnhancementCard: some View {
      SettingsCard(
         title: localized("Streaming Enhancement", locale: locale),
         icon: "text.bubble.fill",
         detail: localized("Controls how the live dictation path polishes transcripts. The deterministic cleaner (filler removal, capitalization, spoken punctuation, number normalization, split-word merging) runs either way — this toggle gates the optional LLM polish pass that fires once dictation stops.", locale: locale)
      ) {
         VStack(alignment: .leading, spacing: 12) {
            Toggle(
               localized("Run LLM polish after dictation stops", locale: locale),
               isOn: $settings.streamingPostStopEnhancementEnabled
            )
            .toggleStyle(.switch)
            .frame(maxWidth: .infinity, alignment: .leading)

            if settings.streamingPostStopEnhancementEnabled {
               Text(localized("Uses the Transcription Enhancement assignment. If none is set, the deterministic cleaner output is kept as-is.", locale: locale))
                  .font(AppTypography.caption)
                  .foregroundStyle(AppColors.textSecondary)
            } else {
               Text(localized("Recommended: the deterministic cleaner handles most dictation cleanly. Enable the LLM pass only if you want extra polish and accept occasional model quirks (preamble, conversational replies).", locale: locale))
                  .font(AppTypography.caption)
                  .foregroundStyle(AppColors.textSecondary)
            }
         }
      }
   }

   // MARK: - Context Card (vibe mode)

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
      }
   }

   private var vibeRuntimeLabel: String {
      switch settings.vibeRuntimeState {
      case .ready: return localized("Ready", locale: locale)
      case .limited: return localized("Limited", locale: locale)
      case .degraded: return localized("Degraded", locale: locale)
      }
   }

   private var vibeRuntimeColor: Color {
      switch settings.vibeRuntimeState {
      case .ready: return AppColors.success
      case .limited: return AppColors.warning
      case .degraded: return AppColors.error
      }
   }

   // MARK: - Model loading

   private func preloadModelsForAllProviders() async {
      for provider in settings.providers where provider.kind != .apple {
         await refreshModels(for: provider, force: false)
      }
   }

   @MainActor
   private func refreshModels(for provider: ProviderConfig, force: Bool) async {
      guard provider.kind != .apple else { return }

      // Anthropic: use static catalog.
      if provider.kind == .anthropic {
         modelListCache[provider.id] = Self.anthropicModels
         modelListErrors[provider.id] = nil
         return
      }

      let customKind = provider.customKind ?? .custom
      let supportsListing: Bool = {
         switch provider.kind {
         case .openrouter, .openai: return true
         case .custom: return customKind.supportsModelListing
         default: return false
         }
      }()
      guard supportsListing else {
         modelListCache[provider.id] = []
         return
      }

      if !force,
         let cached = modelService.getCachedModels(
            for: provider.kind,
            customLocalProvider: customKind
         )
      {
         modelListCache[provider.id] = cached
         return
      }

      // OpenAI requires a key to fetch.
      let apiKey = settings.loadProviderAPIKey(forProviderID: provider.id)
      if provider.kind == .openai, (apiKey?.isEmpty ?? true) {
         return
      }

      let endpointOverride: String? = provider.kind == .custom
         ? settings.loadProviderEndpoint(forProviderID: provider.id)
         : nil

      modelListLoading.insert(provider.id)
      modelListErrors[provider.id] = nil
      defer { modelListLoading.remove(provider.id) }

      do {
         let models = try await modelService.refreshModels(
            for: provider.kind,
            apiKey: apiKey,
            endpointOverride: endpointOverride,
            customLocalProvider: customKind
         )
         modelListCache[provider.id] = models
      } catch {
         Log.aiEnhancement.error("Failed to fetch models for provider \(provider.id): \(error)")
         modelListErrors[provider.id] = error.localizedDescription
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

   // MARK: - Presets

   private func loadPresets() {
      do {
         presets = try promptPresetStore.fetchAll()
      } catch {
         Log.ui.error("Failed to load presets: \(error)")
      }
   }

   // MARK: - Apple Intelligence availability

   private var isAppleIntelligenceAvailable: Bool {
      #if canImport(FoundationModels)
      if #available(macOS 26, *) {
         return SystemLanguageModel.default.availability == .available
      }
      return false
      #else
      return false
      #endif
   }

   // MARK: - Accessibility

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

   // MARK: - Constants

   private var unassignedProviderID: String { "__unassigned__" }
   private var customPresetSentinel: String { "__custom__" }
}

// MARK: - Model conformance

extension AIModelService.AIModel: SearchableDropdownItem {
   public var displayName: String { name }
   public var searchableValues: [String] {
      [name, id, description].compactMap { $0 }
   }
}

#Preview {
   AIEnhancementSettingsView(settings: SettingsStore())
      .padding()
      .frame(width: 600)
}

// MARK: - Provider Edit Sheet

struct ProviderEditState: Identifiable {
   let id = UUID()
   var providerID: UUID
   var kind: AIProvider
   var customKind: CustomProviderType
   var displayName: String
   var apiKey: String
   var endpoint: String
   var isNew: Bool

   static func newProvider() -> ProviderEditState {
      ProviderEditState(
         providerID: UUID(),
         kind: .openai,
         customKind: .custom,
         displayName: "OpenAI",
         apiKey: "",
         endpoint: "",
         isNew: true
      )
   }

   init(
      providerID: UUID,
      kind: AIProvider,
      customKind: CustomProviderType,
      displayName: String,
      apiKey: String,
      endpoint: String,
      isNew: Bool
   ) {
      self.providerID = providerID
      self.kind = kind
      self.customKind = customKind
      self.displayName = displayName
      self.apiKey = apiKey
      self.endpoint = endpoint
      self.isNew = isNew
   }

   @MainActor
   init(existing: ProviderConfig, settings: SettingsStore) {
      self.providerID = existing.id
      self.kind = existing.kind
      self.customKind = existing.customKind ?? .custom
      self.displayName = existing.displayName
      self.apiKey = settings.loadProviderAPIKey(forProviderID: existing.id) ?? ""
      self.endpoint = settings.loadProviderEndpoint(forProviderID: existing.id)
         ?? (existing.kind == .custom ? (existing.customKind ?? .custom).defaultEndpoint : "")
      self.isNew = false
   }
}

private struct ProviderEditSheet: View {
   @ObservedObject var settings: SettingsStore
   let modelService: AIModelService
   @State var initial: ProviderEditState
   let onSave: (ProviderConfig) -> Void
   let onCancel: () -> Void

   @Environment(\.locale) private var locale
   @State private var showingAPIKey = false
   @State private var errorText: String?
   @State private var isLoadingModels = false
   @State private var loadedModelCount: Int?

   private var isApple: Bool { initial.kind == .apple }
   private var isCustom: Bool { initial.kind == .custom }

   var body: some View {
      VStack(alignment: .leading, spacing: 16) {
         Text(initial.isNew
            ? localized("Add Provider", locale: locale)
            : localized("Edit Provider", locale: locale))
            .font(.title2.weight(.semibold))

         // Provider kind picker (only on new; for Apple we allow renaming only)
         if initial.isNew {
            VStack(alignment: .leading, spacing: 6) {
               Text(localized("Provider Kind", locale: locale))
                  .font(.subheadline.weight(.medium))
               SelectField(
                  options: kindOptions,
                  selection: Binding(
                     get: { initial.kind.rawValue },
                     set: { newRaw in
                        if let provider = AIProvider(rawValue: newRaw) {
                           initial.kind = provider
                           initial.displayName = Self.defaultDisplayName(
                              for: provider, customKind: initial.customKind
                           )
                           loadedModelCount = nil
                        }
                     }
                  ),
                  placeholder: localized("Select a provider kind", locale: locale)
               )
            }

            if isCustom {
               VStack(alignment: .leading, spacing: 6) {
                  Text(localized("Provider Type", locale: locale))
                     .font(.subheadline.weight(.medium))
                  SelectField(
                     options: customKindOptions,
                     selection: Binding(
                        get: { initial.customKind.rawValue },
                        set: { newRaw in
                           if let kind = CustomProviderType(rawValue: newRaw) {
                              initial.customKind = kind
                              initial.displayName = Self.defaultDisplayName(
                                 for: .custom, customKind: kind
                              )
                              if initial.endpoint.isEmpty {
                                 initial.endpoint = kind.defaultEndpoint
                              }
                           }
                        }
                     ),
                     placeholder: localized("Select a provider type", locale: locale)
                  )
               }
            }
         }

         // Display name
         VStack(alignment: .leading, spacing: 6) {
            Text(localized("Display Name", locale: locale))
               .font(.subheadline.weight(.medium))
            TextField(localized("Display name", locale: locale), text: $initial.displayName)
               .textFieldStyle(.plain)
               .aiSettingsInputChrome()
         }

         if !isApple {
            // API key
            VStack(alignment: .leading, spacing: 6) {
               HStack(spacing: 8) {
                  Text(localized("API Key", locale: locale))
                     .font(.subheadline.weight(.medium))
                  if isCustom && !initial.customKind.requiresAPIKey {
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
                        TextField(apiKeyPlaceholder, text: $initial.apiKey)
                     } else {
                        SecureField(apiKeyPlaceholder, text: $initial.apiKey)
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
            }

            // Custom endpoint
            if isCustom {
               VStack(alignment: .leading, spacing: 6) {
                  HStack {
                     Text(localized("API Endpoint", locale: locale))
                        .font(.subheadline.weight(.medium))
                     Spacer()
                     Text(initial.customKind == .custom
                        ? localized("Must be OpenAI-compatible", locale: locale)
                        : localized("OpenAI-compatible local server", locale: locale))
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textSecondary)
                  }
                  TextField(initial.customKind.endpointPlaceholder, text: $initial.endpoint)
                     .textFieldStyle(.plain)
                     .aiSettingsInputChrome()
               }
            }

            // Credential validation
            HStack(spacing: 8) {
               Button(localized("Load Models", locale: locale)) {
                  Task { await loadModels() }
               }
               .buttonStyle(.bordered)
               .disabled(isLoadingModels || !canLoadModels)

               if isLoadingModels {
                  ProgressView().controlSize(.small)
               }

               if let count = loadedModelCount {
                  HStack(spacing: 6) {
                     IconView(icon: .check, size: 12)
                        .foregroundStyle(AppColors.success)
                     Text(String(format: localized("Loaded %d models", locale: locale), count))
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.success)
                  }
               }

               Spacer()
            }

            HStack(spacing: 6) {
               IconView(icon: .shield, size: 12)
                  .foregroundStyle(AppColors.textSecondary)
               Text(localized("Credentials are stored securely in Keychain", locale: locale))
                  .font(AppTypography.caption)
                  .foregroundStyle(AppColors.textSecondary)
            }
         } else {
            HStack(spacing: 8) {
               IconView(icon: .sparkles, size: 14)
                  .foregroundStyle(AppColors.accent)
               Text(localized("Apple Intelligence runs on-device and requires no credentials.", locale: locale))
                  .font(AppTypography.caption)
                  .foregroundStyle(AppColors.textSecondary)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColors.mutedSurface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
         }

         if let errorText {
            HStack(spacing: 6) {
               IconView(icon: .warning, size: 12)
                  .foregroundStyle(AppColors.error)
               Text(errorText)
                  .font(AppTypography.caption)
                  .foregroundStyle(AppColors.error)
            }
         }

         HStack {
            Spacer()
            Button(localized("Cancel", locale: locale)) { onCancel() }
               .buttonStyle(.bordered)
            Button(localized("Save", locale: locale)) { save() }
               .buttonStyle(.borderedProminent)
               .disabled(!canSave)
         }
         .padding(.top, 6)
      }
      .padding(20)
      .frame(minWidth: 520)
   }

   private var apiKeyPlaceholder: String {
      isCustom ? initial.customKind.apiKeyPlaceholder : initial.kind.apiKeyPlaceholder
   }

   private var canSave: Bool {
      let nameOK = !initial.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      if !nameOK { return false }
      if isApple { return true }
      if isCustom {
         if initial.customKind.requiresAPIKey
            && initial.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return false
         }
         if initial.endpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return false
         }
         return true
      }
      // Cloud providers require key.
      return !initial.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
   }

   private var canLoadModels: Bool {
      switch initial.kind {
      case .anthropic, .apple:
         return false
      case .openai:
         return !initial.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      case .google, .openrouter:
         return !initial.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      case .custom:
         return initial.customKind.supportsModelListing
            && !initial.endpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      }
   }

   @MainActor
   private func loadModels() async {
      isLoadingModels = true
      errorText = nil
      loadedModelCount = nil
      defer { isLoadingModels = false }

      do {
         let models = try await modelService.refreshModels(
            for: initial.kind,
            apiKey: initial.apiKey,
            endpointOverride: isCustom ? initial.endpoint : nil,
            customLocalProvider: isCustom ? initial.customKind : .custom
         )
         loadedModelCount = models.count
      } catch {
         errorText = error.localizedDescription
      }
   }

   private func save() {
      let trimmedName = initial.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmedName.isEmpty else { return }

      let config = ProviderConfig(
         id: initial.providerID,
         kind: initial.kind,
         customKind: isCustom ? initial.customKind : nil,
         displayName: trimmedName
      )
      settings.upsertProvider(config)

      do {
         if !isApple {
            try settings.saveProviderAPIKey(initial.apiKey, forProviderID: config.id)
         }
         if isCustom {
            try settings.saveProviderEndpoint(
               initial.endpoint.trimmingCharacters(in: .whitespacesAndNewlines),
               forProviderID: config.id
            )
         }
         onSave(config)
      } catch {
         errorText = String(format: localized("Failed to save: %@", locale: locale), error.localizedDescription)
      }
   }

   private var kindOptions: [SelectFieldOption] {
      AIProvider.allCases
         .filter { $0.isImplemented }
         .map {
            SelectFieldOption(
               id: $0.rawValue,
               displayName: Self.kindDisplayName($0, locale: locale)
            )
         }
   }

   private var customKindOptions: [SelectFieldOption] {
      CustomProviderType.allCases.map {
         SelectFieldOption(
            id: $0.rawValue,
            displayName: Self.customKindDisplayName($0, locale: locale)
         )
      }
   }

   private static func kindDisplayName(_ kind: AIProvider, locale: Locale) -> String {
      switch kind {
      case .openai: return localized("OpenAI", locale: locale)
      case .anthropic: return localized("Anthropic", locale: locale)
      case .google: return localized("Google", locale: locale)
      case .openrouter: return localized("OpenRouter", locale: locale)
      case .apple: return localized("Apple Intelligence", locale: locale)
      case .custom: return localized("Custom / Local", locale: locale)
      }
   }

   private static func customKindDisplayName(_ kind: CustomProviderType, locale: Locale) -> String {
      switch kind {
      case .custom: return localized("Custom (OpenAI-compatible)", locale: locale)
      case .ollama: return localized("Ollama", locale: locale)
      case .lmStudio: return localized("LM Studio", locale: locale)
      }
   }

   private static func defaultDisplayName(for kind: AIProvider, customKind: CustomProviderType) -> String {
      switch kind {
      case .openai: return "OpenAI"
      case .anthropic: return "Anthropic"
      case .google: return "Google"
      case .openrouter: return "OpenRouter"
      case .apple: return "Apple Intelligence"
      case .custom:
         switch customKind {
         case .ollama: return "Ollama"
         case .lmStudio: return "LM Studio"
         case .custom: return "Custom"
         }
      }
   }
}

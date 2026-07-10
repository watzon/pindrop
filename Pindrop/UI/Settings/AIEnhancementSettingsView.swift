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
   @State private var modelPickerPurpose: EnhancementPurpose?

   // Inline prompt-override drafts per purpose, keyed by purpose.rawValue.
   @State private var promptOverrideDrafts: [String: String] = [:]
   @State private var showAdvancedAssignments = false
   @State private var showPromptEditor = false
   @State private var promptEditorDraft = ""

   private var promptPresetStore: PromptPresetStore {
      PromptPresetStore(modelContext: modelContext)
   }

   var body: some View {
      SettingsPaneStack {
         simplifiedEnhancementCard
         promptPresetCard
         if let example = activePresetExample {
            exampleBlock(example)
         }
         DisclosureGroup(isExpanded: $showAdvancedAssignments) {
            VStack(spacing: SettingsLayoutMetrics.groupGap) {
               providersCardChrome
               assignmentsCardChrome
               streamingEnhancementCardChrome
               contextCardChrome
            }
            .padding(.top, 8)
         } label: {
            Text(localized("Advanced assignments", locale: locale))
               .font(AppTypography.labelStrong)
               .foregroundStyle(AppColors.textPrimary)
         }
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
      .sheet(item: $modelPickerPurpose) { purpose in
         modelPickerSheet(for: purpose)
      }
      .sheet(isPresented: $showPromptEditor) {
         promptEditorSheet
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

   // MARK: - Simplified enhance flow (B10 adapter)

   private var simplifiedEnhancementCard: some View {
      SettingsGroupCard {
         SettingsRow(showSeparator: settings.enhanceTranscriptsEnabled) {
            SettingsRowLabel(title: localized("Enhance transcripts", locale: locale))
         } control: {
            SettingsToggle(
               isOn: enhanceTranscriptsBinding,
               label: localized("Enhance transcripts", locale: locale)
            )
               .accessibilityIdentifier("settings.toggle.enhanceTranscripts")
         }

         if settings.enhanceTranscriptsEnabled {
            SettingsRow(showSeparator: true) {
               SettingsRowLabel(title: localized("Provider", locale: locale))
            } control: {
               Menu {
                  ForEach(settings.providers) { provider in
                     Button(provider.displayName) {
                        settings.enhanceTranscriptsProviderID = provider.id
                        Task { await refreshModels(for: provider, force: false) }
                     }
                  }
                  Divider()
                  Button(localized("Add Provider", locale: locale)) {
                     editingProvider = ProviderEditState.newProvider()
                  }
               } label: {
                  SettingsMenuButton(title: selectedProviderLabel)
               }
               .menuStyle(.borderlessButton)
               .menuIndicator(.hidden)
               .accessibilityIdentifier("settings.picker.enhanceProvider")
            }

            SettingsRow(showSeparator: false) {
               SettingsRowLabel(title: localized("Model", locale: locale))
            } control: {
               simplifiedModelControl
            }
         }
      }
   }

   private var promptPresetCard: some View {
      SettingsGroupCard {
         SettingsRow(showSeparator: true) {
            SettingsRowLabel(title: localized("Prompt Preset", locale: locale))
         } control: {
            Menu {
               ForEach(presets) { preset in
                  Button(preset.name) {
                     let id = preset.builtInIdentifier ?? preset.id.uuidString
                     settings.enhanceTranscriptsPresetID = id
                     syncLegacyPresetPointer(for: .transcriptionEnhancement)
                  }
               }
               Divider()
               Button(localized("Manage Presets…", locale: locale)) {
                  showPresetManagement = true
               }
            } label: {
               SettingsMenuButton(title: selectedPresetLabel)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .disabled(!settings.enhanceTranscriptsEnabled)
            .accessibilityIdentifier("settings.picker.promptPreset")
         }

         VStack(alignment: .leading, spacing: 8) {
            Text(promptPreviewText)
               .font(AppTypography.monoSmall)
               .foregroundStyle(AppColors.textPrimary)
               .frame(maxWidth: .infinity, alignment: .leading)
               .padding(12)
               .background(
                  RoundedRectangle(cornerRadius: 8, style: .continuous)
                     .fill(AppColors.windowBackground)
               )
               .overlay(
                  RoundedRectangle(cornerRadius: 8, style: .continuous)
                     .strokeBorder(AppColors.border, lineWidth: 1)
               )
               .textSelection(.enabled)

            HStack {
               SettingsAccentLink(title: localized("Edit prompt…", locale: locale)) {
                  promptEditorDraft = promptPreviewText
                  showPromptEditor = true
               }
               .disabled(!settings.enhanceTranscriptsEnabled)
               Spacer()
            }

            Text(localized(SettingsStore.promptsSentInEnglishNoteKey, locale: locale))
               .font(AppTypography.caption)
               .foregroundStyle(AppColors.textTertiary)
         }
         .padding(.horizontal, SettingsLayoutMetrics.rowHorizontalPadding)
         .padding(.bottom, SettingsLayoutMetrics.rowVerticalPadding)
      }
   }

   private func exampleBlock(_ example: BuiltInPresets.PresetExample) -> some View {
      VStack(alignment: .leading, spacing: 8) {
         Text(localized("EXAMPLE", locale: locale))
            .font(AppTypography.sectionHeader)
            .tracking(0.08 * 11)
            .foregroundStyle(AppColors.accent)
            .textCase(.uppercase)

         Text(localized(example.input, locale: locale))
            .font(AppTypography.body)
            .foregroundStyle(AppColors.textTertiary)
            .strikethrough(true, color: AppColors.textTertiary)
            .fixedSize(horizontal: false, vertical: true)

         Text(localized(example.output, locale: locale))
            .font(AppTypography.transcriptBody)
            .foregroundStyle(AppColors.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
      }
      .padding(16)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(
         RoundedRectangle(cornerRadius: SettingsLayoutMetrics.cardRadius, style: .continuous)
            .fill(AppColors.accentBackground)
      )
   }

   private var enhanceTranscriptsBinding: Binding<Bool> {
      Binding(
         get: { settings.enhanceTranscriptsEnabled },
         set: { settings.enhanceTranscriptsEnabled = $0 }
      )
   }

   private var selectedProviderLabel: String {
      if let id = settings.enhanceTranscriptsProviderID,
         let provider = settings.provider(withID: id) {
         return provider.displayName
      }
      return localized("Choose a provider", locale: locale)
   }

   private var selectedPresetLabel: String {
      if let override = settings.enhanceTranscriptsPromptOverride, !override.isEmpty {
         return localized("Custom", locale: locale)
      }
      if let id = settings.enhanceTranscriptsPresetID {
         if let preset = presets.first(where: { $0.builtInIdentifier == id || $0.id.uuidString == id }) {
            return preset.name
         }
         if let definition = BuiltInPresets.definition(for: id) {
            return localized(definition.name, locale: locale)
         }
      }
      return localized("Clean Transcript", locale: locale)
   }

   private var promptPreviewText: String {
      settings.enhanceTranscriptsResolvedEnglishPrompt()
         ?? BuiltInPresets.cleanTranscript.prompt
   }

   private var activePresetExample: BuiltInPresets.PresetExample? {
      if let id = settings.enhanceTranscriptsPresetID,
         let example = BuiltInPresets.definition(for: id)?.example {
         return example
      }
      return BuiltInPresets.cleanTranscript.example
   }

   @ViewBuilder
   private var simplifiedModelControl: some View {
      if let providerID = settings.enhanceTranscriptsProviderID,
         let provider = settings.provider(withID: providerID) {
         if provider.kind == .apple {
            Text(localized("Apple Foundation Models (on-device)", locale: locale))
               .font(AppTypography.label)
               .foregroundStyle(AppColors.textSecondary)
         } else {
            Button {
               modelPickerPurpose = .transcriptionEnhancement
            } label: {
               SettingsMenuButton(
                  title: settings.enhanceTranscriptsModelID?.isEmpty == false
                     ? (settings.enhanceTranscriptsModelID ?? "")
                     : localized("Choose Model…", locale: locale)
               )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("settings.button.chooseModel.transcriptionEnhancement")
         }
      } else {
         Text(localized("Choose a provider first", locale: locale))
            .font(AppTypography.label)
            .foregroundStyle(AppColors.textTertiary)
      }
   }

   private var promptEditorSheet: some View {
      VStack(spacing: 0) {
         HStack {
            Text(localized("Edit prompt…", locale: locale))
               .font(AppTypography.labelStrongSelected)
            Spacer()
            Button(localized("Cancel", locale: locale)) {
               showPromptEditor = false
            }
            Button(localized("Save", locale: locale)) {
               settings.enhanceTranscriptsPromptOverride = promptEditorDraft
               showPromptEditor = false
            }
            .keyboardShortcut(.defaultAction)
         }
         .padding(16)

         TextEditor(text: $promptEditorDraft)
            .font(AppTypography.monoSmall)
            .padding(12)
      }
      .frame(minWidth: 480, minHeight: 360)
   }

   // MARK: - Advanced cards (chrome wrappers)

   private var providersCardChrome: some View {
      SettingsGroupCard {
         VStack(alignment: .leading, spacing: 0) {
            if settings.providers.isEmpty {
               emptyProvidersPlaceholder
                  .padding()
            } else {
               ForEach(settings.providers) { provider in
                  // Always separate: the Add Provider button follows the last row.
                  SettingsRow(showSeparator: true) {
                     VStack(alignment: .leading, spacing: 2) {
                        Text(provider.displayName)
                           .font(AppTypography.labelStrong)
                           .foregroundStyle(AppColors.textPrimary)
                        Text("\(providerKindLabel(provider)) · \(providerStatusLine(provider))")
                           .font(AppTypography.caption)
                           .foregroundStyle(AppColors.textSecondary)
                           .lineLimit(1)
                           .truncationMode(.middle)
                     }
                  } control: {
                     HStack {
                        if provider.kind == .apple {
                           Button(localized("Rename", locale: locale)) {
                              editingProvider = ProviderEditState(existing: provider, settings: settings)
                           }
                           .buttonStyle(.plain)
                        } else {
                           Button(localized("Edit", locale: locale)) {
                              editingProvider = ProviderEditState(existing: provider, settings: settings)
                           }
                           .buttonStyle(.plain)

                           Button(localized("Remove", locale: locale), role: .destructive) {
                              providerPendingDeletion = provider
                           }
                           .buttonStyle(.plain)
                        }
                     }
                  }
               }
            }

            Button {
               editingProvider = ProviderEditState.newProvider()
            } label: {
               Label(localized("Add Provider", locale: locale), systemImage: "plus")
                  .font(AppTypography.label)
                  .foregroundStyle(AppColors.accent)
                  .padding(SettingsLayoutMetrics.rowHorizontalPadding)
                  .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("settings.button.addProvider")
         }
      }
   }

   private var assignmentsCardChrome: some View {
      SettingsGroupCard {
         ForEach(Array(EnhancementPurpose.allCases.enumerated()), id: \.element) { index, purpose in
            VStack(alignment: .leading, spacing: 8) {
               assignmentRow(for: purpose)
            }
            .padding(.vertical, SettingsLayoutMetrics.rowVerticalPadding)
            .padding(.horizontal, SettingsLayoutMetrics.rowHorizontalPadding)
            if index < EnhancementPurpose.allCases.count - 1 {
               Rectangle()
                  .fill(AppColors.border)
                  .frame(height: 1)
                  .padding(.leading, SettingsLayoutMetrics.rowHorizontalPadding)
            }
         }
      }
   }

   private var streamingEnhancementCardChrome: some View {
      SettingsGroupCard {
         SettingsRow(showSeparator: false) {
            SettingsRowLabel(
               title: localized("Run LLM polish after dictation stops", locale: locale),
               subtitle: settings.streamingPostStopEnhancementEnabled
                  ? localized("Uses the Transcription Enhancement assignment. If none is set, the deterministic cleaner output is kept as-is.", locale: locale)
                  : localized("Recommended: the deterministic cleaner handles most dictation cleanly. Enable the LLM pass only if you want extra polish and accept occasional model quirks.", locale: locale)
            )
         } control: {
            SettingsToggle(
               isOn: $settings.streamingPostStopEnhancementEnabled,
               label: localized("Run LLM polish after dictation stops", locale: locale)
            )
               .accessibilityIdentifier("settings.toggle.streamingPostStopEnhancement")
         }
      }
   }

   private var contextCardChrome: some View {
      SettingsGroupCard {
         SettingsRow(showSeparator: true) {
            SettingsRowLabel(title: localized("Enable vibe mode (UI context)", locale: locale))
         } control: {
            SettingsToggle(
               isOn: Binding(
                  get: { settings.enableUIContext },
                  set: { newValue in
                     settings.enableUIContext = newValue
                     if newValue {
                        requestAccessibilityPermissionIfNeeded()
                     }
                  }
               ),
               label: localized("Enable vibe mode (UI context)", locale: locale)
            )
            .accessibilityIdentifier("settings.toggle.enableUIContext")
         }

         if settings.enableUIContext {
            SettingsRow(showSeparator: true) {
               SettingsRowLabel(title: localized("Enable live session updates during recording", locale: locale))
            } control: {
               SettingsToggle(
                  isOn: $settings.vibeLiveSessionEnabled,
                  label: localized("Enable live session updates during recording", locale: locale)
               )
                  .accessibilityIdentifier("settings.toggle.vibeLiveSessionEnabled")
            }

            SettingsRow(showSeparator: true) {
               SettingsRowLabel(title: localized("Include clipboard text", locale: locale))
            } control: {
               SettingsToggle(
                  isOn: $settings.enableClipboardContext,
                  label: localized("Include clipboard text", locale: locale)
               )
                  .accessibilityIdentifier("settings.toggle.enableClipboardContext")
            }
         }

         SettingsRow(showSeparator: false) {
            SettingsRowLabel(
               title: localized("Accessibility Permission", locale: locale),
               subtitle: accessibilityPermissionGranted
                  ? localized("Enabled", locale: locale)
                  : localized("Not Granted", locale: locale)
            )
         } control: {
            if !accessibilityPermissionGranted {
               Button(localized("Open System Settings", locale: locale)) {
                  PermissionManager().openAccessibilityPreferences()
               }
               .buttonStyle(.plain)
            }
         }
      }
   }

   // MARK: - Providers helpers

   private var emptyProvidersPlaceholder: some View {
      ContentUnavailableView {
         Label(localized("No providers configured yet", locale: locale), systemImage: "server.rack")
      } description: {
         Text(localized("Add a provider to start using AI enhancement.", locale: locale))
      }
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

   // MARK: - Assignments helpers

   @ViewBuilder
   private func assignmentRow(for purpose: EnhancementPurpose) -> some View {
      let assignment = settings.assignment(for: purpose)
      let selectedProvider = assignment.flatMap { settings.provider(withID: $0.providerID) }

      VStack(alignment: .leading, spacing: 8) {
         Text(purposeLabel(purpose))
            .font(.headline)

         if let helper = purposeHelperText(purpose) {
            Text(helper)
               .font(.caption)
               .foregroundStyle(.secondary)
               .fixedSize(horizontal: false, vertical: true)
         }

         Picker(
            localized("Provider", locale: locale),
            selection: providerSelectionBinding(for: purpose)
         ) {
            Text(localized("Not assigned", locale: locale))
               .tag(unassignedProviderID)
            ForEach(settings.providers) { provider in
               Text(provider.displayName)
                  .tag(provider.id.uuidString)
            }
         }

         LabeledContent(localized("Model", locale: locale)) {
            modelPicker(for: purpose, provider: selectedProvider)
               .frame(maxWidth: 300)
         }

         if purpose.supportsUserPrompt {
            LabeledContent(localized("Prompt Preset", locale: locale)) {
               HStack {
                  Picker("", selection: presetSelectionBinding(for: purpose)) {
                     Text(localized("Custom", locale: locale))
                        .tag(customPresetSentinel)
                     ForEach(presets) { preset in
                        Text(preset.name)
                           .tag(preset.builtInIdentifier ?? preset.id.uuidString)
                     }
                  }
                  .labelsHidden()
                  .disabled(selectedProvider == nil)

                  Button(localized("Manage Presets…", locale: locale)) {
                     showPresetManagement = true
                  }
               }
            }

            if isCustomPresetSelected(for: purpose) {
               customPromptEditor(for: purpose)
            }
         } else {
            Label(
               localized("Uses a built-in prompt tuned for this task.", locale: locale),
               systemImage: "lock.fill"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
         }

         if let provider = selectedProvider, provider.kind == .apple,
            !isAppleIntelligenceAvailable
         {
            Label(
               localized("Apple Intelligence is unavailable on this system. This assignment will not resolve until Apple Intelligence is enabled.", locale: locale),
               systemImage: "exclamationmark.triangle.fill"
            )
            .font(.caption)
            .foregroundStyle(.orange)
         }
      }
      .padding(.vertical, 2)
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
               .foregroundStyle(.secondary)
         } else if provider.kind == .custom
            && !(provider.customKind ?? .custom).supportsModelListing
         {
            TextField(
               (provider.customKind ?? .custom).modelPlaceholder,
               text: modelTextFieldBinding(for: purpose, provider: provider)
            )
            .textFieldStyle(.roundedBorder)
            .accessibilityIdentifier("settings.field.model.\(purpose.rawValue)")
         } else {
            let models = modelListCache[provider.id] ?? []
            if models.isEmpty {
               HStack(spacing: 6) {
                  if modelListLoading.contains(provider.id) {
                     ProgressView().controlSize(.small)
                     Text(localized("Loading models...", locale: locale))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                  } else if let err = modelListErrors[provider.id] {
                     Text(err)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(1)
                        .truncationMode(.tail)
                  } else {
                     Text(localized("No models loaded. Open Edit to fetch models.", locale: locale))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                  }
                  Spacer()
                  Button(localized("Refresh", locale: locale)) {
                     Task { await refreshModels(for: provider, force: true) }
                  }
                  .accessibilityIdentifier("settings.button.refreshModels.\(purpose.rawValue)")
               }
            } else {
               Button {
                  modelPickerPurpose = purpose
               } label: {
                  HStack {
                     Text(selectedModelLabel(for: purpose, models: models))
                        .lineLimit(1)
                        .truncationMode(.middle)
                     Spacer(minLength: 4)
                     Image(systemName: "chevron.up.chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                  }
               }
               .buttonStyle(.bordered)
               .accessibilityIdentifier("settings.button.chooseModel.\(purpose.rawValue)")
            }
         }
      } else {
         Text(localized("Choose a provider first", locale: locale))
            .foregroundStyle(.secondary)
      }
   }

   private func selectedModelLabel(
      for purpose: EnhancementPurpose,
      models: [AIModelService.AIModel]
   ) -> String {
      let currentID = settings.assignment(for: purpose)?.modelID
      if let currentID, !currentID.isEmpty {
         if let match = models.first(where: { $0.id == currentID }) {
            return match.name
         }
         return currentID
      }
      return localized("Choose Model…", locale: locale)
   }

   @ViewBuilder
   private func modelPickerSheet(for purpose: EnhancementPurpose) -> some View {
      let assignment = settings.assignment(for: purpose)
      let provider = assignment.flatMap { settings.provider(withID: $0.providerID) }
      let models = provider.map { modelListCache[$0.id] ?? [] } ?? []
      let titleParts = [
         purposeLabel(purpose),
         provider?.displayName,
      ].compactMap { $0 }
      ModelPickerSheet(
         title: titleParts.joined(separator: " · "),
         models: models,
         selected: assignment?.modelID,
         onSelect: { modelID in
            guard let provider else { return }
            var existing = settings.assignment(for: purpose)
               ?? ModelAssignment(
                  providerID: provider.id,
                  modelID: modelID,
                  promptPresetID: defaultPresetID(for: purpose)
               )
            existing.modelID = modelID
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
            .frame(minHeight: 110, maxHeight: 220)
            .accessibilityIdentifier("settings.editor.prompt.\(purpose.rawValue)")

         Text(
            String(
               format: localized("%d characters", locale: locale),
               binding.wrappedValue.count
            )
         )
         .font(.caption)
         .foregroundStyle(.secondary)
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
            // Empty or unedited built-in English text → store nil override (English guarantee).
            let normalized = BuiltInPresets.normalizedPromptOverride(
               newValue.isEmpty ? nil : newValue,
               presetID: existing.promptPresetID
            )
            existing.promptOverride = normalized
            if normalized != nil {
               // True custom text: leave Custom mode (no preset pointer).
               existing.promptPresetID = nil
            } else if existing.promptPresetID == nil {
               // Custom mode with empty/unedited text would leave both nil — fall back to
               // the purpose default built-in so resolve always has a deterministic English source.
               existing.promptPresetID =
                  defaultPresetID(for: purpose) ?? BuiltInPresetID.cleanTranscript
            }
            settings.setAssignment(existing, for: purpose)
         }
      )
   }

   /// English source for a preset. Prefer `BuiltInPresets` so custom-editor seeding never
   /// captures a display-localized string for built-ins.
   private func resolvePresetPromptText(_ presetID: String?) -> String? {
      guard let presetID else { return nil }
      if let english = BuiltInPresets.englishPrompt(for: presetID) {
         return english
      }
      if let preset = presets.first(where: { $0.builtInIdentifier == presetID }) {
         // User-authored presets keep their stored prompt; built-ins should already have
         // been handled above. If a built-in row lacks a matching BuiltInPresets entry,
         // fall back to the English store text from seeding.
         return preset.prompt
      }
      if let preset = presets.first(where: { $0.id.uuidString == presetID }) {
         if let builtInID = preset.builtInIdentifier,
            let english = BuiltInPresets.englishPrompt(for: builtInID) {
            return english
         }
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

// MARK: - Sheet identity

extension EnhancementPurpose: Identifiable {
   public var id: String { rawValue }
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
   @State private var initial: ProviderEditState
   let onSave: (ProviderConfig) -> Void
   let onCancel: () -> Void

   @Environment(\.locale) private var locale
   @State private var showingAPIKey = false
   @State private var errorText: String?
   @State private var isLoadingModels = false
   @State private var loadedModelCount: Int?

   private var isApple: Bool { initial.kind == .apple }
   private var isCustom: Bool { initial.kind == .custom }

   init(
      settings: SettingsStore,
      modelService: AIModelService,
      initial: ProviderEditState,
      onSave: @escaping (ProviderConfig) -> Void,
      onCancel: @escaping () -> Void
   ) {
      self.settings = settings
      self.modelService = modelService
      _initial = State(initialValue: initial)
      self.onSave = onSave
      self.onCancel = onCancel
   }

   var body: some View {
      VStack(spacing: 0) {
         Form {
            Section {
               if initial.isNew {
                  Picker(localized("Provider Kind", locale: locale), selection: $initial.kind) {
                     ForEach(AIProvider.allCases.filter(\.isImplemented), id: \.self) { kind in
                        Text(Self.kindDisplayName(kind, locale: locale))
                           .tag(kind)
                     }
                  }
                  .onChange(of: initial.kind) { _, newKind in
                     initial.displayName = Self.defaultDisplayName(
                        for: newKind,
                        customKind: initial.customKind
                     )
                     loadedModelCount = nil
                  }

                  if isCustom {
                     Picker(localized("Provider Type", locale: locale), selection: $initial.customKind) {
                        ForEach(CustomProviderType.allCases, id: \.self) { kind in
                           Text(Self.customKindDisplayName(kind, locale: locale))
                              .tag(kind)
                        }
                     }
                     .onChange(of: initial.customKind) { _, newKind in
                        initial.displayName = Self.defaultDisplayName(for: .custom, customKind: newKind)
                        if initial.endpoint.isEmpty {
                           initial.endpoint = newKind.defaultEndpoint
                        }
                     }
                  }
               }

               TextField(localized("Display Name", locale: locale), text: $initial.displayName)

               if !isApple {
                  LabeledContent(localized("API Key", locale: locale)) {
                     HStack {
                        Group {
                           if showingAPIKey {
                              TextField(apiKeyPlaceholder, text: $initial.apiKey)
                           } else {
                              SecureField(apiKeyPlaceholder, text: $initial.apiKey)
                           }
                        }

                        Button {
                           showingAPIKey.toggle()
                        } label: {
                           Image(systemName: showingAPIKey ? "eye.slash" : "eye")
                        }
                        .help(
                           showingAPIKey
                              ? localized("Hide API Key", locale: locale)
                              : localized("Show API Key", locale: locale)
                        )
                        .accessibilityLabel(
                           showingAPIKey
                              ? localized("Hide API Key", locale: locale)
                              : localized("Show API Key", locale: locale)
                        )
                     }
                  }

                  if isCustom {
                     TextField(
                        localized("API Endpoint", locale: locale),
                        text: $initial.endpoint,
                        prompt: Text(initial.customKind.endpointPlaceholder)
                     )
                  }

                  LabeledContent(localized("Model Validation", locale: locale)) {
                     HStack {
                        Button(localized("Load Models", locale: locale)) {
                           Task { await loadModels() }
                        }
                        .disabled(isLoadingModels || !canLoadModels)

                        if isLoadingModels {
                           ProgressView().controlSize(.small)
                        }

                        if let count = loadedModelCount {
                           Label(
                              String(format: localized("Loaded %d models", locale: locale), count),
                              systemImage: "checkmark.circle.fill"
                           )
                           .foregroundStyle(.green)
                        }
                     }
                  }
               } else {
                  Label(
                     localized("Apple Intelligence runs on-device and requires no credentials.", locale: locale),
                     systemImage: "sparkles"
                  )
                  .foregroundStyle(.secondary)
               }
            } header: {
               Text(
                  initial.isNew
                     ? localized("Add Provider", locale: locale)
                     : localized("Edit Provider", locale: locale)
               )
            } footer: {
               if !isApple {
                  Text(localized("Credentials are stored securely in Keychain.", locale: locale))
               }
            }

            if let errorText {
               Section {
                  Label(errorText, systemImage: "exclamationmark.triangle.fill")
                     .foregroundStyle(.red)
               }
            }
         }
         .formStyle(.grouped)

         Divider()
         HStack {
            Spacer()
            Button(localized("Cancel", locale: locale)) { onCancel() }
            Button(localized("Save", locale: locale)) { save() }
               .disabled(!canSave)
         }
         .padding()
      }
      .frame(minWidth: 520, minHeight: 420)
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

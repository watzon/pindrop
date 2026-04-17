//
//  SettingsStore+AIConfigV2.swift
//  Pindrop
//
//  Created on 2026-04-16.
//
//  V2 AI config accessors on SettingsStore: provider CRUD, per-purpose assignment
//  lookups, credential resolution, and one-shot migration from the legacy singleton
//  settings. See AIConfigurationV2.swift for the data model.
//

import Foundation

extension SettingsStore {

   // MARK: - Provider CRUD

   /// All configured providers, decoded from `aiConfigProvidersJSON`.
   var providers: [ProviderConfig] {
      get {
         guard let data = aiConfigProvidersJSON.data(using: .utf8), !data.isEmpty else {
            return []
         }
         return (try? JSONDecoder().decode([ProviderConfig].self, from: data)) ?? []
      }
      set {
         guard let data = try? JSONEncoder().encode(newValue),
            let json = String(data: data, encoding: .utf8)
         else { return }
         aiConfigProvidersJSON = json
         objectWillChange.send()
      }
   }

   /// Look up a provider by its stable UUID.
   func provider(withID id: UUID) -> ProviderConfig? {
      providers.first { $0.id == id }
   }

   /// Insert or update a provider. Matched on `id`.
   func upsertProvider(_ config: ProviderConfig) {
      var list = providers
      if let idx = list.firstIndex(where: { $0.id == config.id }) {
         list[idx] = config
      } else {
         list.append(config)
      }
      providers = list
   }

   /// Remove a provider and its Keychain secrets, plus any assignments that referenced it.
   func removeProvider(withID id: UUID) {
      var list = providers
      list.removeAll { $0.id == id }
      providers = list

      try? deleteProviderAPIKey(forProviderID: id)
      try? deleteProviderEndpoint(forProviderID: id)

      var map = assignments
      for purpose in EnhancementPurpose.allCases where map[purpose]?.providerID == id {
         map.removeValue(forKey: purpose)
      }
      assignments = map
   }

   // MARK: - Assignment CRUD

   /// Purpose → assignment map, decoded from `aiConfigAssignmentsJSON`.
   var assignments: [EnhancementPurpose: ModelAssignment] {
      get {
         guard let data = aiConfigAssignmentsJSON.data(using: .utf8), !data.isEmpty else {
            return [:]
         }
         return (try? JSONDecoder().decode(
            [EnhancementPurpose: ModelAssignment].self, from: data)) ?? [:]
      }
      set {
         guard let data = try? JSONEncoder().encode(newValue),
            let json = String(data: data, encoding: .utf8)
         else { return }
         aiConfigAssignmentsJSON = json
         objectWillChange.send()
      }
   }

   func assignment(for purpose: EnhancementPurpose) -> ModelAssignment? {
      assignments[purpose]
   }

   func setAssignment(_ assignment: ModelAssignment?, for purpose: EnhancementPurpose) {
      var map = assignments
      if let assignment {
         map[purpose] = assignment
      } else {
         map.removeValue(forKey: purpose)
      }
      assignments = map
   }

   // MARK: - UUID-keyed Keychain accounts

   func apiKeyAccount(forProviderID id: UUID) -> String {
      "api-key-provider-\(id.uuidString)"
   }

   func apiEndpointAccount(forProviderID id: UUID) -> String {
      "api-endpoint-provider-\(id.uuidString)"
   }

   func saveProviderAPIKey(_ key: String, forProviderID id: UUID) throws {
      let account = apiKeyAccount(forProviderID: id)
      let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
      if trimmed.isEmpty {
         try deleteFromKeychain(account: account)
      } else {
         try saveToKeychain(value: trimmed, account: account)
      }
   }

   func loadProviderAPIKey(forProviderID id: UUID) -> String? {
      let raw = try? loadFromKeychain(account: apiKeyAccount(forProviderID: id))
      guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
         return nil
      }
      return raw
   }

   func deleteProviderAPIKey(forProviderID id: UUID) throws {
      try deleteFromKeychain(account: apiKeyAccount(forProviderID: id))
   }

   func saveProviderEndpoint(_ endpoint: String?, forProviderID id: UUID) throws {
      let account = apiEndpointAccount(forProviderID: id)
      let trimmed = endpoint?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      if trimmed.isEmpty {
         try deleteFromKeychain(account: account)
      } else {
         try saveToKeychain(value: trimmed, account: account)
      }
   }

   func loadProviderEndpoint(forProviderID id: UUID) -> String? {
      let raw = try? loadFromKeychain(account: apiEndpointAccount(forProviderID: id))
      guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
         return nil
      }
      return raw
   }

   func deleteProviderEndpoint(forProviderID id: UUID) throws {
      try deleteFromKeychain(account: apiEndpointAccount(forProviderID: id))
   }

   // MARK: - Resolver

   /// Resolves a purpose into the full bundle (provider + creds + model + prompt) needed to
   /// make an AI call. Returns `nil` when:
   ///   - the purpose is unassigned,
   ///   - the referenced provider no longer exists,
   ///   - the provider requires an API key but none is stored,
   ///   - the purpose is `.streamingRefinement` and the provider is Apple but Foundation
   ///     Models is unavailable at runtime (availability is checked by the caller; this
   ///     resolver does not special-case OS version gating).
   func resolveAssignment(for purpose: EnhancementPurpose) -> ResolvedAssignment? {
      guard let assignment = assignment(for: purpose) else { return nil }
      guard let provider = provider(withID: assignment.providerID) else { return nil }

      let key = loadProviderAPIKey(forProviderID: provider.id)
      let endpoint =
         loadProviderEndpoint(forProviderID: provider.id)
         ?? defaultEndpoint(for: provider)

      // Gate on required creds. Apple never requires a key. Custom Ollama/LM Studio don't.
      let requiresKey: Bool
      switch provider.kind {
      case .apple:
         requiresKey = false
      case .custom:
         requiresKey = (provider.customKind ?? .custom).requiresAPIKey
      default:
         requiresKey = true
      }
      if requiresKey && (key?.isEmpty ?? true) {
         return nil
      }

      // Purposes whose prompt is owned by the app (e.g. streaming refinement's diff-coupled
      // prompt, the `@Generable` schema prompts inside AppleFoundationModelsEnhancer) must
      // surface nil here regardless of what's stored. That prevents a stored preset or
      // override from ever sneaking through, and signals to callers that they should use
      // their purpose-specific built-in prompt.
      let exposesPrompt = purpose.supportsUserPrompt
      return ResolvedAssignment(
         purpose: purpose,
         providerID: provider.id,
         kind: provider.kind,
         customKind: provider.customKind,
         displayName: provider.displayName,
         modelID: assignment.modelID,
         endpoint: endpoint,
         apiKey: key,
         prompt: exposesPrompt ? assignment.promptOverride : nil,
         promptPresetID: exposesPrompt ? assignment.promptPresetID : nil
      )
   }

   /// Default endpoint for a provider when no per-provider override is stored.
   private func defaultEndpoint(for provider: ProviderConfig) -> String? {
      switch provider.kind {
      case .apple:
         return nil
      case .custom:
         let value = (provider.customKind ?? .custom).defaultEndpoint
         return value.isEmpty ? nil : value
      default:
         let value = provider.kind.defaultEndpoint
         return value.isEmpty ? nil : value
      }
   }

   // MARK: - Migration

   /// One-shot migration from the legacy singleton `aiProvider`/`aiModel`/… settings to the
   /// v2 provider + assignments model. Idempotent — gated on `aiConfigV2Migrated`.
   ///
   /// Strategy:
   ///   1. Always emit an Apple provider (Foundation Models).
   ///   2. Always emit a provider for the currently-selected legacy `aiProvider`, even if
   ///      no API key is stored — this preserves the active assignment on upgrade.
   ///   3. Emit providers for every populated Keychain key slot.
   ///   4. Emit Ollama and LM Studio providers without keys if the user selected them.
   ///   5. Write `transcriptionEnhancement`, `noteEnhancement`, `noteMetadata`,
   ///      `transcriptionMetadata` assignments pointing at the currently-active legacy
   ///      provider with the legacy `aiModel` and legacy prompts preserved as overrides.
   ///   6. Leave `streamingRefinement` unset.
   ///
   /// Legacy `@AppStorage` + per-provider Keychain slots are preserved for one release as a
   /// rollback path; they are no longer consulted after migration.
   func migrateToAIConfigV2IfNeeded() {
      guard !aiConfigV2Migrated else { return }
      guard !SettingsStoreRuntime_isPreview else { return }

      var newProviders: [ProviderConfig] = []
      let activeLegacyKind: AIProvider = currentAIProvider
      let activeLegacyCustomKind: CustomProviderType? =
         activeLegacyKind == .custom ? currentCustomLocalProvider : nil

      func ensureProvider(
         kind: AIProvider,
         customKind: CustomProviderType? = nil,
         displayName: String
      ) -> ProviderConfig {
         if let existing = newProviders.first(where: {
            $0.kind == kind && $0.customKind == customKind
         }) {
            return existing
         }
         let config = ProviderConfig(
            kind: kind,
            customKind: customKind,
            displayName: displayName
         )
         newProviders.append(config)
         return config
      }

      // 1. Apple is always available.
      _ = ensureProvider(kind: .apple, displayName: "Apple Intelligence")

      // 2. The active legacy provider — always emitted so the legacy assignment is preserved.
      let activeProviderConfig = ensureProvider(
         kind: activeLegacyKind,
         customKind: activeLegacyKind == .custom ? (activeLegacyCustomKind ?? .custom) : nil,
         displayName: defaultDisplayName(for: activeLegacyKind, customKind: activeLegacyCustomKind)
      )

      // 3. Every populated legacy key slot → a provider entry.
      for kind in AIProvider.allCases {
         switch kind {
         case .apple:
            continue  // already emitted
         case .custom:
            for custom in CustomProviderType.allCases {
               if loadAPIKey(for: .custom, customLocalProvider: custom) != nil {
                  _ = ensureProvider(
                     kind: .custom,
                     customKind: custom,
                     displayName: defaultDisplayName(for: .custom, customKind: custom)
                  )
               }
            }
         default:
            if loadAPIKey(for: kind) != nil {
               _ = ensureProvider(
                  kind: kind,
                  displayName: defaultDisplayName(for: kind, customKind: nil)
               )
            }
         }
      }

      // 4. Ollama and LM Studio — keyless, but users often rely on them.
      if currentCustomLocalProvider == .ollama || activeLegacyCustomKind == .ollama {
         _ = ensureProvider(
            kind: .custom,
            customKind: .ollama,
            displayName: defaultDisplayName(for: .custom, customKind: .ollama)
         )
      }
      if currentCustomLocalProvider == .lmStudio || activeLegacyCustomKind == .lmStudio {
         _ = ensureProvider(
            kind: .custom,
            customKind: .lmStudio,
            displayName: defaultDisplayName(for: .custom, customKind: .lmStudio)
         )
      }

      // Persist providers first so UUIDs stabilize before we copy secrets and build
      // assignments off them.
      providers = newProviders

      // 5. Copy secrets into UUID-keyed Keychain slots.
      for config in newProviders {
         switch config.kind {
         case .apple:
            continue
         case .custom:
            let custom = config.customKind ?? .custom
            if let legacyKey = loadAPIKey(for: .custom, customLocalProvider: custom) {
               try? saveProviderAPIKey(legacyKey, forProviderID: config.id)
            }
            if let legacyEndpoint = storedAPIEndpoint(forCustomLocalProvider: custom) {
               try? saveProviderEndpoint(legacyEndpoint, forProviderID: config.id)
            }
         default:
            if let legacyKey = loadAPIKey(for: config.kind) {
               try? saveProviderAPIKey(legacyKey, forProviderID: config.id)
            }
            // Legacy global `apiEndpoint` belongs to whichever built-in provider was active.
            if config.kind == activeLegacyKind, let legacyEndpoint = apiEndpoint {
               try? saveProviderEndpoint(legacyEndpoint, forProviderID: config.id)
            }
         }
      }

      // 6. Seed assignments pointing at the active legacy provider.
      let legacyModel = aiModel
      let legacyEnhancementPrompt = aiEnhancementPrompt
      let legacyNotePrompt = noteEnhancementPrompt
      let defaultCleanPrompt = Defaults.aiEnhancementPrompt
      let defaultNotePrompt = Defaults.noteEnhancementPrompt

      func promptOverride(_ value: String, defaultValue: String) -> String? {
         value == defaultValue ? nil : value
      }

      var newAssignments: [EnhancementPurpose: ModelAssignment] = [:]

      if aiEnhancementEnabled {
         newAssignments[.transcriptionEnhancement] = ModelAssignment(
            providerID: activeProviderConfig.id,
            modelID: legacyModel,
            promptPresetID: selectedPresetId ?? BuiltInPresetID.cleanTranscript,
            promptOverride: promptOverride(legacyEnhancementPrompt, defaultValue: defaultCleanPrompt)
         )
         newAssignments[.noteEnhancement] = ModelAssignment(
            providerID: activeProviderConfig.id,
            modelID: legacyModel,
            promptPresetID: BuiltInPresetID.noteFormatting,
            promptOverride: promptOverride(legacyNotePrompt, defaultValue: defaultNotePrompt)
         )
         newAssignments[.noteMetadata] = ModelAssignment(
            providerID: activeProviderConfig.id,
            modelID: legacyModel
         )
         newAssignments[.transcriptionMetadata] = ModelAssignment(
            providerID: activeProviderConfig.id,
            modelID: legacyModel
         )
      }

      assignments = newAssignments
      aiConfigV2Migrated = true
   }

   /// Human-readable default name for an inferred provider during migration.
   private func defaultDisplayName(
      for kind: AIProvider,
      customKind: CustomProviderType?
   ) -> String {
      switch kind {
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
   }

   // Runtime preview guard used inside the migrator (the underlying enum in SettingsStore
   // is private, so the extension queries the env var directly).
   fileprivate var SettingsStoreRuntime_isPreview: Bool {
      ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
   }
}

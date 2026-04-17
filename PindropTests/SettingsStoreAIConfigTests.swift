//
//  SettingsStoreAIConfigTests.swift
//  PindropTests
//
//  Created on 2026-04-16.
//
//  Migration + resolver tests for the v2 AI configuration (providers + per-purpose
//  assignments). The tests drive SettingsStore's public v2 API directly and exercise the
//  one-shot migrateToAIConfigV2IfNeeded() path by seeding the legacy singleton fields and
//  then constructing a fresh SettingsStore so init() runs.
//

import Testing
@testable import Pindrop

@MainActor
@Suite
struct SettingsStoreAIConfigTests {

   // MARK: - Scaffolding

   /// Returns a SettingsStore whose v2 state has been reset to a known "not yet migrated"
   /// posture, so the next init()-triggered migration can run deterministically.
   private func makeCleanStore() -> SettingsStore {
      let store = SettingsStore()
      store.resetAllSettings()
      try? store.deleteAPIEndpoint()
      try? store.deleteAPIKey()
      return store
   }

   /// Seeds legacy singleton fields on `store` and returns a NEW store whose init() runs
   /// the migrator against that state. This mirrors the upgrade path from a prior Pindrop
   /// version.
   private func migrateAfterSeeding(
      _ seed: (SettingsStore) throws -> Void
   ) throws -> SettingsStore {
      let seeder = makeCleanStore()
      try seed(seeder)
      #expect(!seeder.aiConfigV2Migrated)
      // Pindrop's SettingsStore reads from a per-PID UserDefaults suite during tests, so a
      // second SettingsStore() instance sees the same backing store and re-runs init().
      let migrated = SettingsStore()
      #expect(migrated.aiConfigV2Migrated)
      return migrated
   }

   // MARK: - Migration: cloud provider with API key

   @Test func migrationCloudWithKeyCreatesProviderAndAssignments() throws {
      let store = try migrateAfterSeeding { seeder in
         seeder.aiProvider = AIProvider.openai.rawValue
         seeder.aiModel = "gpt-4o-mini"
         seeder.aiEnhancementEnabled = true
         try seeder.saveAPIKey("sk-test", for: .openai)
      }
      defer { store.resetAllSettings() }

      // Apple (always) + OpenAI (active legacy) should both exist.
      let openai = store.providers.first(where: { $0.kind == .openai })
      #expect(openai != nil)
      #expect(store.providers.contains(where: { $0.kind == .apple }))

      // Assignments point at the OpenAI provider with the legacy model.
      let assignment = store.assignment(for: .transcriptionEnhancement)
      #expect(assignment?.providerID == openai?.id)
      #expect(assignment?.modelID == "gpt-4o-mini")
      #expect(store.assignment(for: .streamingRefinement) == nil)

      // UUID-keyed Keychain slot holds the migrated API key.
      #expect(store.loadProviderAPIKey(forProviderID: openai!.id) == "sk-test")

      // Resolver produces a fully-populated ResolvedAssignment.
      let resolved = store.resolveAssignment(for: .transcriptionEnhancement)
      #expect(resolved?.kind == .openai)
      #expect(resolved?.modelID == "gpt-4o-mini")
      #expect(resolved?.apiKey == "sk-test")
   }

   // MARK: - Migration: Apple Intelligence

   @Test func migrationAppleProducesAppleAssignment() throws {
      let store = try migrateAfterSeeding { seeder in
         seeder.aiProvider = AIProvider.apple.rawValue
         seeder.aiModel = "apple_intelligence"
         seeder.aiEnhancementEnabled = true
      }
      defer { store.resetAllSettings() }

      let apple = store.providers.first(where: { $0.kind == .apple })
      #expect(apple != nil)

      let assignment = store.assignment(for: .transcriptionEnhancement)
      #expect(assignment?.providerID == apple?.id)
      #expect(assignment?.modelID == "apple_intelligence")

      // Apple never requires a key — resolver should succeed even with no Keychain entry.
      let resolved = store.resolveAssignment(for: .transcriptionEnhancement)
      #expect(resolved?.kind == .apple)
      #expect(resolved?.apiKey == nil)
   }

   // MARK: - Migration: custom subtype with key

   @Test func migrationCustomWithKeyCopiesKeyAndEndpoint() throws {
      let store = try migrateAfterSeeding { seeder in
         seeder.aiProvider = AIProvider.custom.rawValue
         seeder.customLocalProviderType = CustomProviderType.custom.rawValue
         seeder.aiModel = "my-model"
         seeder.aiEnhancementEnabled = true
         try seeder.saveAPIKey("custom-key", for: .custom, customLocalProvider: .custom)
         try seeder.saveAPIEndpoint(
            "https://api.example.com/v1/chat/completions",
            for: .custom,
            customLocalProvider: .custom
         )
      }
      defer { store.resetAllSettings() }

      let customProvider = store.providers.first(where: {
         $0.kind == .custom && $0.customKind == .custom
      })
      #expect(customProvider != nil)

      #expect(store.loadProviderAPIKey(forProviderID: customProvider!.id) == "custom-key")
      #expect(
         store.loadProviderEndpoint(forProviderID: customProvider!.id)
            == "https://api.example.com/v1/chat/completions"
      )

      let resolved = store.resolveAssignment(for: .transcriptionEnhancement)
      #expect(resolved?.kind == .custom)
      #expect(resolved?.customKind == .custom)
      #expect(resolved?.modelID == "my-model")
      #expect(resolved?.apiKey == "custom-key")
   }

   // MARK: - Migration: Ollama without key

   @Test func migrationOllamaWithoutKeyCreatesUsableAssignment() throws {
      let store = try migrateAfterSeeding { seeder in
         seeder.aiProvider = AIProvider.custom.rawValue
         seeder.customLocalProviderType = CustomProviderType.ollama.rawValue
         seeder.aiModel = "llama3.2"
         seeder.aiEnhancementEnabled = true
      }
      defer { store.resetAllSettings() }

      let ollama = store.providers.first(where: {
         $0.kind == .custom && $0.customKind == .ollama
      })
      #expect(ollama != nil)

      let resolved = store.resolveAssignment(for: .transcriptionEnhancement)
      #expect(resolved?.kind == .custom)
      #expect(resolved?.customKind == .ollama)
      #expect(resolved?.modelID == "llama3.2")
      // Ollama doesn't require an API key — resolver must still succeed.
      #expect(resolved?.apiKey == nil)
      #expect(resolved?.endpoint?.isEmpty == false)
   }

   // MARK: - Migration: fresh install (AI enhancement disabled)

   @Test func migrationFreshInstallLeavesAssignmentsEmpty() throws {
      let store = try migrateAfterSeeding { _ in
         // Intentionally leave aiEnhancementEnabled at its default (false).
      }
      defer { store.resetAllSettings() }

      // Apple should still be emitted; OpenAI (the default legacy provider) should also
      // exist because currentAIProvider is always emitted.
      #expect(store.providers.contains(where: { $0.kind == .apple }))

      // But there are no assignments, which is what "AI enhancement off" meant pre-v2.
      #expect(store.assignment(for: .transcriptionEnhancement) == nil)
      #expect(store.assignment(for: .noteEnhancement) == nil)
      #expect(store.assignment(for: .streamingRefinement) == nil)
      #expect(store.resolveAssignment(for: .transcriptionEnhancement) == nil)
   }

   // MARK: - Migration: legacy custom prompts preserved as overrides

   @Test func migrationPreservesNonDefaultLegacyPrompts() throws {
      let customPrompt = "You are a legal-writing assistant. Be concise."
      let customNotePrompt = "Format as a meeting note with bullet points only."

      let store = try migrateAfterSeeding { seeder in
         seeder.aiProvider = AIProvider.openai.rawValue
         seeder.aiModel = "gpt-4o-mini"
         seeder.aiEnhancementEnabled = true
         seeder.aiEnhancementPrompt = customPrompt
         seeder.noteEnhancementPrompt = customNotePrompt
         try seeder.saveAPIKey("sk-test", for: .openai)
      }
      defer { store.resetAllSettings() }

      #expect(
         store.assignment(for: .transcriptionEnhancement)?.promptOverride == customPrompt
      )
      #expect(store.assignment(for: .noteEnhancement)?.promptOverride == customNotePrompt)
   }

   @Test func migrationDoesNotStoreDefaultPromptAsOverride() throws {
      let store = try migrateAfterSeeding { seeder in
         seeder.aiProvider = AIProvider.openai.rawValue
         seeder.aiModel = "gpt-4o-mini"
         seeder.aiEnhancementEnabled = true
         seeder.aiEnhancementPrompt = SettingsStore.Defaults.aiEnhancementPrompt
         seeder.noteEnhancementPrompt = SettingsStore.Defaults.noteEnhancementPrompt
         try seeder.saveAPIKey("sk-test", for: .openai)
      }
      defer { store.resetAllSettings() }

      // When the legacy prompt is exactly the default, the migrator stores nil so the
      // built-in preset is used as-is.
      #expect(store.assignment(for: .transcriptionEnhancement)?.promptOverride == nil)
      #expect(store.assignment(for: .noteEnhancement)?.promptOverride == nil)
   }

   // MARK: - Resolver: unassigned and missing creds

   @Test func resolverReturnsNilForUnassignedPurpose() {
      let store = makeCleanStore()
      defer { store.resetAllSettings() }
      #expect(store.resolveAssignment(for: .streamingRefinement) == nil)
   }

   @Test func resolverReturnsNilWhenCloudProviderHasNoKey() {
      let store = makeCleanStore()
      defer { store.resetAllSettings() }

      let openai = ProviderConfig(kind: .openai, displayName: "OpenAI")
      store.upsertProvider(openai)
      store.setAssignment(
         ModelAssignment(providerID: openai.id, modelID: "gpt-4o-mini"),
         for: .transcriptionEnhancement
      )

      // No API key is saved for this provider — resolver should decline to produce an
      // assignment rather than hand back a half-complete one.
      #expect(store.resolveAssignment(for: .transcriptionEnhancement) == nil)
   }

   @Test func resolverReturnsAssignmentWhenKeyIsPresent() throws {
      let store = makeCleanStore()
      defer { store.resetAllSettings() }

      let openai = ProviderConfig(kind: .openai, displayName: "OpenAI")
      store.upsertProvider(openai)
      try store.saveProviderAPIKey("sk-present", forProviderID: openai.id)
      store.setAssignment(
         ModelAssignment(providerID: openai.id, modelID: "gpt-4o-mini"),
         for: .transcriptionEnhancement
      )

      let resolved = store.resolveAssignment(for: .transcriptionEnhancement)
      #expect(resolved?.apiKey == "sk-present")
      #expect(resolved?.modelID == "gpt-4o-mini")
   }

   // MARK: - Locked-prompt purposes

   @Test func resolverMasksPromptFieldsForStreamingRefinement() throws {
      let store = makeCleanStore()
      defer { store.resetAllSettings() }

      let apple = ProviderConfig(kind: .apple, displayName: "Apple Intelligence")
      store.upsertProvider(apple)
      store.setAssignment(
         ModelAssignment(
            providerID: apple.id,
            modelID: "apple_intelligence",
            promptPresetID: "user-authored-preset",
            promptOverride: "a user-supplied prompt that shouldn't leak through"
         ),
         for: .streamingRefinement
      )

      let resolved = store.resolveAssignment(for: .streamingRefinement)
      #expect(resolved != nil)
      // Even though override + presetID were stored, the resolver must mask them so
      // downstream callers receive "use your built-in prompt" signal.
      #expect(resolved?.prompt == nil)
      #expect(resolved?.promptPresetID == nil)
   }

   @Test func resolverMasksPromptFieldsForMetadataPurposes() throws {
      let store = makeCleanStore()
      defer { store.resetAllSettings() }

      let openai = ProviderConfig(kind: .openai, displayName: "OpenAI")
      store.upsertProvider(openai)
      try store.saveProviderAPIKey("sk-test", forProviderID: openai.id)
      for purpose: EnhancementPurpose in [.noteMetadata, .transcriptionMetadata] {
         store.setAssignment(
            ModelAssignment(
               providerID: openai.id,
               modelID: "gpt-4o-mini",
               promptPresetID: "x",
               promptOverride: "stored override"
            ),
            for: purpose
         )
         let resolved = store.resolveAssignment(for: purpose)
         #expect(resolved?.prompt == nil, "prompt leaked for \(purpose)")
         #expect(resolved?.promptPresetID == nil, "promptPresetID leaked for \(purpose)")
      }
   }

   @Test func resolverExposesPromptFieldsForUnlockedPurposes() throws {
      let store = makeCleanStore()
      defer { store.resetAllSettings() }

      let openai = ProviderConfig(kind: .openai, displayName: "OpenAI")
      store.upsertProvider(openai)
      try store.saveProviderAPIKey("sk-test", forProviderID: openai.id)
      store.setAssignment(
         ModelAssignment(
            providerID: openai.id,
            modelID: "gpt-4o-mini",
            promptPresetID: "clean",
            promptOverride: "custom user prompt"
         ),
         for: .transcriptionEnhancement
      )

      let resolved = store.resolveAssignment(for: .transcriptionEnhancement)
      #expect(resolved?.prompt == "custom user prompt")
      #expect(resolved?.promptPresetID == "clean")
   }

   // MARK: - Provider removal cleans up related assignments

   @Test func removeProviderClearsItsAssignments() throws {
      let store = makeCleanStore()
      defer { store.resetAllSettings() }

      let openai = ProviderConfig(kind: .openai, displayName: "OpenAI")
      store.upsertProvider(openai)
      try store.saveProviderAPIKey("sk-X", forProviderID: openai.id)
      store.setAssignment(
         ModelAssignment(providerID: openai.id, modelID: "gpt-4o-mini"),
         for: .transcriptionEnhancement
      )
      store.setAssignment(
         ModelAssignment(providerID: openai.id, modelID: "gpt-4o"),
         for: .noteEnhancement
      )

      store.removeProvider(withID: openai.id)

      #expect(store.provider(withID: openai.id) == nil)
      #expect(store.assignment(for: .transcriptionEnhancement) == nil)
      #expect(store.assignment(for: .noteEnhancement) == nil)
      #expect(store.loadProviderAPIKey(forProviderID: openai.id) == nil)
   }
}

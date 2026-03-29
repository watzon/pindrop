# Phase 1: Shared Core Authority - Context

**Gathered:** 2026-03-29
**Status:** Ready for planning

<domain>
## Phase Boundary

Supported desktop clients use one authoritative shared Kotlin core for non-native product rules and localization while macOS remains native where it must. This phase covers:

1. A shared settings schema (types, defaults, validation) that all desktop clients consume
2. A shared localization source of truth replacing per-platform translation systems
3. New shared business logic for dictionary cleanup, AI enhancement behavior, and history/search semantics
4. Removing Swift fallback branches so KMP is a required compile-time dependency

macOS UI stays native SwiftUI/AppKit. macOS WhisperKit transcription stays native. These are hard constraints from PROJECT.md.

</domain>

<decisions>
## Implementation Decisions

### Settings Schema Authority

- **D-01:** Kotlin owns the complete settings schema — types, keys, default values, valid ranges, and validation rules for all ~50 settings. This is the single source of truth for settings definitions.
- **D-02:** Swift keeps `@AppStorage` + Keychain for persistence. The schema is the contract; storage is platform-native. Linux will use its own persistence reading the same schema.
- **D-03:** All settings go into one shared schema — not just transcription-related. Includes model selection, language, hotkeys, theme, AI provider/prompt, output mode, feature flags, context/vibe, onboarding state, and mention templates.
- **D-04:** Schema + adapter pattern for Swift consumption. Kotlin defines the schema as a compilable artifact (XCFramework). Swift reads schema values at compile time and maps KMP keys to `@AppStorage` property wrappers. The existing `SettingsStore` API stays the same for callers.
- **D-05:** Secret schema (which providers need API keys, which need endpoints, required vs optional) moves to KMP. Actual Keychain storage stays Swift-native. Linux uses its own secure storage.
- **D-06:** Kotlin defaults replace the Swift `Defaults` enum entirely. The `Defaults` enum in `SettingsStore.swift` is deleted; Swift reads defaults from the KMP schema.
- **D-07:** Validate on write with user feedback. KMP validation functions return structured results (valid/invalid + reason). Swift calls validation before writing to `@AppStorage` and shows errors to the user.

### Localization Source of Truth

- **D-08:** All UI strings move to Kotlin entirely. The existing `.xcstrings` catalogs are replaced.
- **D-09:** Use Kotlin Multiplatform Resources (JetBrains library). Per-locale `values/strings.xml` files. Supports compile-time safety, IDE tooling, and all KMP targets.
- **D-10:** Swift calls `Res.string` directly at runtime. The existing `localized()` function in `AppLocalization.swift` is rewritten to call KMP instead of `Bundle.main`. SwiftUI views that use `LocalizedStringKey` keep working (constructed from resolved strings).
- **D-11:** Full migration this phase. The 43K-line `.xcstrings` catalog is converted to KMP resources. `.xcstrings` files are deleted at phase end.

### New Shared Domains

- **D-12:** Dictionary cleanup, AI enhancement behavior, and history/search semantics move to KMP with types + validation + business logic (not just types).
- **D-13:** These domains extend existing KMP modules rather than creating new ones. History/search semantics likely extend `ui-workspace`. AI enhancement behavior extends `ui-settings`. Dictionary cleanup extends `feature-transcription` or `core`.

### Swift Fallback Strategy

- **D-14:** Remove all Swift `#else` fallback branches from KMP bridges. KMP frameworks become a required compile-time dependency. The app will not compile without them.
- **D-15:** Remove all `#if canImport(PindropShared*)` view-level guards. `MainWindow`, `SettingsWindow`, `TranscribeView`, and all other views always use KMP navigation/presentation objects.
- **D-16:** Approximately 500 lines of duplicated Swift logic deleted. Tests only need to cover the KMP path.

### Agent's Discretion

- Exact internal structure of the settings schema KMP module (file organization within the module)
- Migration script/tooling approach for .xcstrings → KMP resources conversion
- Granular validation rules for each setting (researcher/planner should reference existing Swift defaults and business constraints)
- How many Gradle sub-modules the settings schema needs (one flat module or split by domain)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Existing KMP Modules (must understand current architecture before extending)

- `shared/core/src/commonMain/kotlin/tech/watzon/pindrop/shared/core/TranscriptionContracts.kt` — Foundational domain types and port interfaces
- `shared/feature-transcription/src/commonMain/kotlin/tech/watzon/pindrop/shared/feature/transcription/SharedTranscriptionOrchestrator.kt` — Stateless policy/orchestration singleton (389 lines)
- `shared/feature-transcription/src/commonMain/kotlin/tech/watzon/pindrop/shared/feature/transcription/VoiceSessionCoordinator.kt` — Stateful voice recording lifecycle coordinator (491 lines)
- `shared/feature-transcription/src/commonMain/kotlin/tech/watzon/pindrop/shared/feature/transcription/MediaTranscriptionJobStateMachine.kt` — Media transcription pipeline state machine
- `shared/runtime-transcription/src/commonMain/kotlin/tech/watzon/pindrop/shared/runtime/transcription/LocalTranscriptionCatalog.kt` — 31-model static catalog
- `shared/runtime-transcription/src/commonMain/kotlin/tech/watzon/pindrop/shared/runtime/transcription/LocalTranscriptionRuntime.kt` — Central model lifecycle runtime (282 lines)
- `shared/ui-shell/src/commonMain/kotlin/tech/watzon/pindrop/shared/ui/shell/ShellState.kt` — Navigation + settings browse state
- `shared/ui-settings/src/commonMain/kotlin/tech/watzon/pindrop/shared/ui/settings/AISettingsPresentation.kt` — AI provider catalog + presentation (363 lines)
- `shared/ui-theme/src/commonMain/kotlin/tech/watzon/pindrop/shared/ui/theme/ThemeEngine.kt` — Theme resolution pipeline (590 lines)
- `shared/ui-workspace/src/commonMain/kotlin/tech/watzon/pindrop/shared/ui/workspace/WorkspacePresentation.kt` — 7 workspace presenters (567 lines)

### Swift Bridge and Settings (must understand what's being replaced)

- `Pindrop/Services/SettingsStore.swift` — Current 1068-line settings store with all ~50 settings, Defaults enum, Keychain integration
- `Pindrop/Services/Transcription/KMPTranscriptionBridge.swift` — 29 `#if canImport` bridge sites to be simplified
- `Pindrop/Services/Transcription/NativeTranscriptionAdapters.swift` — Runtime bridge class to be simplified
- `Pindrop/AppLocalization.swift` — Current localization system to be rewritten
- `Pindrop/Localization/Localizable.xcstrings` — 43K-line catalog to be migrated to KMP resources
- `Pindrop/UI/Main/MainWindow.swift` — KMP navigation guards to remove
- `Pindrop/UI/Settings/SettingsWindow.swift` — KMP settings guards to remove
- `Pindrop/UI/Settings/AIEnhancementSettingsView.swift` — AI provider presentation guards to remove
- `Pindrop/UI/Theme/Theme.swift` — Theme token resolution guards to remove

### Build System

- `shared/build.gradle.kts` — Root Gradle config with stub verification tasks
- `shared/settings.gradle.kts` — Module registry (7 modules)
- `justfile` — Build commands including `shared-xcframework`, `shared-test`
- `scripts/build-shared-frameworks-if-needed.sh` — XCFramework build orchestration

### Codebase Reference Maps

- `.planning/codebase/ARCHITECTURE.md` — Full architecture overview
- `.planning/codebase/STACK.md` — Technology stack and targets
- `.planning/codebase/CONVENTIONS.md` — Coding conventions

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets

- **7 KMP modules already implemented** with full test coverage: `core`, `feature-transcription`, `runtime-transcription`, `ui-shell`, `ui-settings`, `ui-theme`, `ui-workspace`
- **11 test files** across KMP modules provide proven patterns for new domain logic
- **TranscriptionContracts.kt** — pattern for defining enums, data classes, and port interfaces that this phase should follow
- **AISettingsPresentation.kt** — pattern for provider catalogs, presentation logic, and validation that settings schema should follow
- **ThemeEngine.kt** — pattern for resolution engines with capability-aware adaptation
- **KMPTranscriptionBridge.swift** — existing type-mapping layer (~260 lines) shows exactly how Swift ↔ KMP type conversion works today
- **SettingsStore.Defaults enum** — documents every default value that needs to move to KMP

### Established Patterns

- **Port/adapter pattern**: KMP defines SPI interfaces (`*Port`), Swift implements them with platform APIs. All new shared domains should follow this.
- **Singleton objects for pure logic**: `SharedTranscriptionOrchestrator`, `LocalTranscriptionCatalog`, `ThemeEngine`, `SettingsShell` — all stateless singletons. Settings schema should follow this.
- **Stateful classes for lifecycle coordination**: `VoiceSessionCoordinator`, `LocalTranscriptionRuntime` — injected ports, state machines. If settings needs runtime coordination, follow this.
- **Presenter objects for view state**: `HistoryPresenter`, `DashboardPresenter`, etc. — pure functions computing view state from snapshots.
- **Conditional compilation bridges**: `#if canImport(PindropShared*)` — pattern being removed this phase.

### Integration Points

- **SettingsStore ↔ SwiftUI**: `@AppStorage` property wrappers bound to SwiftUI views. Must be preserved; only default values change source.
- **SettingsStore ↔ Keychain**: Secret storage via Security framework. Must be preserved; schema moves to KMP.
- **KMPTranscriptionBridge ↔ SharedTranscriptionOrchestrator**: 29 bridge methods that lose their `#else` branches and become direct calls.
- **AppLocalization.swift ↔ Bundle.main**: Replaced with direct `Res.string` calls.
- **MainWindow/SettingsWindow ↔ PindropSharedNavigation**: Conditional navigation becomes always-on.
- **Gradle build ↔ Xcode build**: `shared-xcframework` must produce new schema/resources frameworks alongside existing ones.

</code_context>

<specifics>
## Specific Ideas

- Settings schema module should follow the established port/adapter pattern — Kotlin defines the contract, Swift implements platform storage
- The `Defaults` enum pattern (nested enum with static let constants) should map naturally to a Kotlin object with const properties
- Validation functions should return a sealed/result type like `SettingsValidationResult.Valid | .Invalid(reason: String)` so Swift can display user-facing errors
- The 10 current locales (en, de, es, fr, it, ja, ko, nl, pt-BR, zh-Hans, tr) must all be preserved in the KMP resources migration
- Secret schema should include the per-provider key structure (api-key-openai, api-key-anthropic, api-key-openrouter, api-key-custom-ollama, etc.) that already exists in SettingsStore

</specifics>

<deferred>
## Deferred Ideas

- **Linux/Windows target expansion** — Adding `linuxX64`/`mingwX64` compile targets to `ui-shell`, `ui-settings`, `ui-theme`, `ui-workspace` modules. Currently only `core` and `runtime-transcription` have these. Not discussed this phase — likely belongs in Phase 2 (Linux Shell) or Phase 6 (Packaged Release) when Linux actually needs to consume these frameworks.

</deferred>

---

*Phase: 01-shared-core-authority*
*Context gathered: 2026-03-29*

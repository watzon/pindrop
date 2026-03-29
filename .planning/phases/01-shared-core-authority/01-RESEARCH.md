# Phase 1: Shared Core Authority - Research

**Researched:** 2026-03-29
**Status:** Complete

## Summary

Phase 1 makes Kotlin authoritative for non-native product rules and localization across desktop clients. Research confirms the work decomposes into four streams: (1) KMP settings schema, (2) localization migration, (3) new shared domain logic, and (4) Swift fallback removal. All four are architecturally sound with existing patterns to follow.

## Standard Stack

- **Kotlin Multiplatform**: 2.3.10 (configured in root build.gradle.kts)
- **Existing modules**: 7 modules (core, feature-transcription, runtime-transcription, ui-shell, ui-settings, ui-theme, ui-workspace)
- **Module pattern**: Each has commonMain + commonTest, macOS XCFramework targets, some have JVM
- **Apple targets**: macOS ARM64 + x64 via XCFramework; only `core` and `runtime-transcription` also have `linuxX64` + `mingwX64`
- **KMP Resources**: JetBrains multiplatform-resources library (not yet in project — needs adding)

## Architecture Patterns

### Established Patterns to Follow

1. **Port/Adapter**: KMP defines SPI interfaces (*Port), Swift implements with platform APIs. `TranscriptionEnginePort` in TranscriptionContracts.kt is the canonical example.
2. **Singleton objects for pure logic**: `SharedTranscriptionOrchestrator`, `LocalTranscriptionCatalog`, `ThemeEngine`, `AISettingsCatalog` — all stateless singletons with pure functions.
3. **Data classes for snapshots**: `TranscriptionSettingsSnapshot`, `AIEnhancementDraft`, `AIModelSnapshot` — immutable data classes consumed by presenters.
4. **Object catalogs**: `AISettingsCatalog` with private lists + public accessor functions — pattern for settings schema catalog.
5. **Presenter objects**: `HistoryPresenter`, `DashboardPresenter` — pure functions computing view state from snapshots.
6. **Gradle module structure**: `build.gradle.kts` per module, registered in `settings.gradle.kts`, XCFramework config in build file.

### Settings Store Analysis

**SettingsStore.swift**: 1068 lines, ~50 settings across these domains:

| Domain | Settings | Key Pattern |
|--------|----------|-------------|
| Model/transcription | selectedModel, selectedLanguage, selectedInputDeviceUID | direct key |
| Hotkeys (4 hotkeys × 3 attrs each) | toggleHotkey/Code/Modifiers, pushToTalk..., copyLast..., quickCapturePTT..., quickCaptureToggle... | named per hotkey |
| Output | outputMode, addTrailingSpace | direct key |
| Theme | themeMode, lightThemePresetID, darkThemePresetID | namespaced via PindropThemeStorageKeys |
| Floating indicator | floatingIndicatorEnabled, floatingIndicatorType, pillOffsetX/Y | direct key |
| AI enhancement | aiEnhancementEnabled, aiProvider, customLocalProviderType, aiModel, aiEnhancementPrompt, noteEnhancementPrompt, selectedPresetId | direct key |
| AI cache timestamps | openRouterModelsCacheTimestamp, openAIModelsCacheTimestamp | direct key |
| Context/vibe | enableClipboardContext, enableUIContext, contextCaptureTimeoutSeconds, vibeLiveSessionEnabled, vibeRuntimeState, vibeRuntimeDetail | direct key |
| Feature flags | vadFeatureEnabled, diarizationFeatureEnabled, streamingFeatureEnabled | direct key |
| Onboarding | hasCompletedOnboarding, currentOnboardingStep | direct key |
| Dictionary | automaticDictionaryLearningEnabled | direct key |
| Mention templates | mentionTemplateOverridesJSON | JSON blob |
| Misc | showInDock, launchAtLogin, pauseMediaOnRecording, muteAudioDuringRecording | direct key |

**Defaults enum** (lines 119-172): All defaults as static let constants. Nested `Hotkeys` enum. This entire enum maps to a KMP object.

**Keychain secrets**: API endpoints and API keys per provider. Complex per-provider account naming scheme (`api-key-openai`, `api-key-custom-ollama`, etc.). The secret *schema* (which providers need keys, storage keys, per-custom-subtype accounts) should move to KMP. The actual Keychain operations stay Swift-native.

**Validation**: Currently minimal — only type checking via Swift's type system. D-07 adds structured validation with user feedback.

### Localization Migration Analysis

**Localizable.xcstrings**: 43K lines, 607 string keys, 11 locales (en, de, es, fr, it, ja, ko, nl, pt-BR, tr, zh-Hans).

Key migration considerations:
- **54 keys with format specifiers** (`%@`, `%lld`) — these need positional parameters in KMP (`%1$s`, `%2$s`)
- **14 multiline/whitespace keys** — Apple uses the full English text as the key; KMP needs short identifiers
- **607 keys total** — substantial but manageable with a conversion script
- All existing English keys become KMP string identifiers (need to create short IDs for long English-key-as-key patterns)

**AppLocalization.swift**: 45 lines. Simple function: `localized(_ key:, locale:)` → Bundle.main lookup. This gets rewritten to call KMP `Res.string.*` instead.

**InfoPlist.xcstrings**: Separate file for permission/bundle strings. Per CONTEXT.md this should also migrate but it's smaller.

### Swift Fallback Branch Analysis

**136 `#if canImport` sites** across Swift codebase:

| File | Sites | Framework |
|------|-------|-----------|
| KMPTranscriptionBridge.swift | ~20 | PindropSharedTranscription |
| AIEnhancementSettingsView.swift | ~17 | PindropSharedSettings |
| MainWindow.swift | ~10 | PindropSharedNavigation |
| PresetManagementSheet.swift | ~6 | PindropSharedSettings |
| ModelsSettingsView.swift | ~3 | PindropSharedUIWorkspace |
| SettingsWindow.swift | ~2 | PindropSharedNavigation |
| ThemeModels.swift | ~2 | PindropSharedUITheme |
| Other files | ~76 | Various |

Each site follows pattern: `#if canImport(Framework) ... KMP code ... #else ... Swift fallback ... #endif`. The `#else` branches are what gets deleted (~500 lines estimated).

### XCFramework Build System

**Current XCFrameworks**:
- `PindropSharedCore` (from core module)
- `PindropSharedTranscription` (from feature-transcription, exports runtime-transcription + core)
- `PindropSharedSettings` (from ui-settings)
- `PindropSharedUITheme` (from ui-theme)
- `PindropSharedUIWorkspace` (from ui-workspace)
- `PindropSharedNavigation` (from ui-shell)

New frameworks needed this phase:
- Settings schema module → new XCFramework (or extend existing ui-settings)
- Localization resources → may need resource bundling in XCFrameworks

**Build commands**: `just shared-xcframework` orchestrates via `scripts/build-shared-frameworks-if-needed.sh`

## Don't Hand Roll

- **Localization conversion script**: The xcstrings → strings.xml conversion is mechanical but error-prone. Write a script, don't do it manually.
- **Settings defaults**: Copy exact values from the existing `Defaults` enum — don't re-derive.
- **Type mappings**: Follow existing patterns in `TranscriptionContracts.kt` and `AISettingsPresentation.kt` for Kotlin enum/data class structure.

## Common Pitfalls

1. **Format specifier mismatch**: Apple `%@` → Kotlin `%s`, Apple `%lld` → Kotlin `%d`. Positional args `%1$s` for multi-parameter strings. The conversion script must handle this.
2. **KMP resource access from Swift**: Multiplatform-resources generates `Res` class. Swift accesses via the XCFramework. Need to verify the generated accessor pattern works across the Obj-C bridge.
3. **Settings key stability**: Existing users have values stored in UserDefaults with specific key names. The KMP schema must use the same key strings to avoid migration issues.
4. **XCFramework resource bundling**: KMP resources in XCFrameworks require careful configuration. The multiplatform-resources plugin handles this but it needs testing on macOS.
5. **Circular module dependencies**: Settings schema is foundational — other modules will depend on it. Keep it in `core` or a new minimal module that nothing else depends on.

## Validation Architecture

### Critical Validation Points

1. **Settings schema completeness**: Every setting in `Defaults` enum must have a KMP counterpart with matching key, type, and default value
2. **Localization completeness**: All 607 keys × 11 locales must exist in KMP resources
3. **Swift compilation**: After removing `#else` branches, app must compile with only KMP code paths
4. **Runtime behavior**: Settings read/write, localization lookups, and all KMP-presented views must function identically

### Automated Verification Strategy

- **KMP tests**: Unit test schema validation logic, default values, and key coverage
- **Conversion verification**: Script compares xcstrings keys vs generated strings.xml files
- **Build verification**: `just build` succeeds after all changes
- **Test verification**: `just test` and `just shared-test` both pass

## Recommended Plan Structure

| Plan | Wave | Focus | Tasks |
|------|------|-------|-------|
| 01 | 1 | Settings Schema Authority | Create KMP settings schema + wire Swift |
| 02 | 1 | Localization Source of Truth | Convert xcstrings → KMP resources + rewrite AppLocalization |
| 03 | 2 | Shared Domain Logic + Fallback Cleanup | Move new domains to KMP + remove all #if canImport |

Plans 01 and 02 are independent (no file overlap, different modules) → Wave 1 parallel.
Plan 03 depends on both (needs settings types and localization working) → Wave 2.

---

*Phase: 01-shared-core-authority*
*Research completed: 2026-03-29*

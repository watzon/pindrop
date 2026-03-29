---
phase: 01-shared-core-authority
plan: 03
subsystem: core
tags: [kmp, kotlin-multiplatform, shared-logic, dictionary-cleanup, history-semantics, ai-enhancement, conditional-compilation-removal]

# Dependency graph
requires:
  - phase: 01-01
    provides: "KMP settings-schema module with SettingsValidationResult"
  - phase: 01-02
    provides: "KMP transcription bridge with unconditional imports"
provides:
  - "DictionaryCleanup shared object with custom replacements, auto-learning, validation"
  - "HistorySemantics shared object with sort, search, dedup generics"
  - "AIEnhancementBehavior shared object with enhancement decision logic"
  - "Zero conditional compilation guards — KMP frameworks are mandatory"
affects: [02-linux-gui, any-future-phase-consuming-shared-logic]

# Tech tracking
tech-stack:
  added: []
  patterns: [shared-pure-functions-with-generics, kmp-validation-result-reuse]

key-files:
  created:
    - shared/core/src/commonMain/kotlin/tech/watzon/pindrop/shared/core/DictionaryCleanup.kt
    - shared/core/src/commonMain/kotlin/tech/watzon/pindrop/shared/core/HistorySemantics.kt
    - shared/ui-settings/src/commonMain/kotlin/tech/watzon/pindrop/shared/uisettings/AIEnhancementBehavior.kt
    - shared/core/src/commonTest/kotlin/tech/watzon/pindrop/shared/core/DictionaryCleanupTest.kt
    - shared/core/src/commonTest/kotlin/tech/watzon/pindrop/shared/core/HistorySemanticsTest.kt
    - shared/ui-settings/src/commonTest/kotlin/tech/watzon/pindrop/shared/uisettings/AIEnhancementBehaviorTest.kt
  modified:
    - shared/core/build.gradle.kts
    - shared/ui-settings/build.gradle.kts
    - Pindrop/Services/Transcription/KMPTranscriptionBridge.swift
    - Pindrop/UI/Main/MainWindow.swift
    - Pindrop/UI/Settings/AIEnhancementSettingsView.swift
    - Pindrop/UI/Settings/PresetManagementSheet.swift
    - Pindrop/UI/Settings/ModelsSettingsView.swift
    - Pindrop/UI/Settings/SettingsWindow.swift
    - Pindrop/UI/Theme/ThemeModels.swift
    - Pindrop/UI/Theme/Theme.swift
    - Pindrop/UI/Main/DashboardView.swift
    - Pindrop/UI/Main/TranscribeView.swift
    - Pindrop/UI/Main/HistoryView.swift
    - Pindrop/UI/Main/DictionaryView.swift
    - Pindrop/UI/Main/NotesView.swift
    - Pindrop/UI/Onboarding/AIEnhancementStepView.swift
    - Pindrop/AppCoordinator.swift
    - Pindrop/Models/MediaTranscriptionTypes.swift
    - Pindrop/Services/ModelManager.swift
    - Pindrop/Services/SettingsStore.swift
    - Pindrop/Services/Transcription/NativeTranscriptionAdapters.swift
    - Pindrop/Services/TranscriptionService.swift

key-decisions:
  - "DictionaryCleanup and HistorySemantics live in core module; AIEnhancementBehavior lives in ui-settings module"
  - "HistorySemantics uses generics with extractors so it works with any data class"
  - "Reused SettingsValidationResult from settings-schema for dictionary and prompt validation"
  - "Added settings-schema as dependency of core and ui-settings modules"

patterns-established:
  - "Shared business logic as Kotlin objects with pure functions"
  - "Generic functions with lambda extractors for cross-platform type flexibility"

requirements-completed: [SHRD-01, SHRD-03]

# Metrics
duration: 15min
completed: 2026-03-29
---

# Phase 1 Plan 3: Shared Domain Logic & Conditional Removal Summary

**Three shared domain logic objects (DictionaryCleanup, HistorySemantics, AIEnhancementBehavior) in KMP; 950 lines of Swift conditional fallback code removed; 139 conditional compilation sites eliminated**

## Performance

- **Duration:** 15 min
- **Started:** 2026-03-29T20:20:18Z
- **Completed:** 2026-03-29T20:35:56Z
- **Tasks:** 2 (TDD: RED + GREEN + commit, auto + commit)
- **Files modified:** 24

## Accomplishments
- Created DictionaryCleanup (custom word replacements, auto-learning from enhancement diffs, entry validation)
- Created HistorySemantics (sort by date/asc/desc/relevance, case-insensitive search, dedup within time window using generics)
- Created AIEnhancementBehavior (shouldAttemptEnhancement, buildEnhancementRequest, fallbackBehavior, validatePrompt)
- Removed all 139 `#if canImport(PindropShared*)` conditional compilation sites across 20+ Swift files
- Deleted ~950 lines of duplicated Swift fallback code
- KMP frameworks are now mandatory compile-time dependencies (app won't build without them)

## Task Commits

Each task was committed atomically:

1. **Task 1 RED: Failing tests for shared domain logic** - `f79008c` (test)
2. **Task 1 GREEN: Implement DictionaryCleanup, HistorySemantics, AIEnhancementBehavior** - `42dc492` (feat)
3. **Task 2: Remove all #if canImport fallback branches** - `df413c4` (feat)

## Files Created/Modified
- `shared/core/src/commonMain/kotlin/tech/watzon/pindrop/shared/core/DictionaryCleanup.kt` - Custom word replacement, auto-learning, dictionary entry validation
- `shared/core/src/commonMain/kotlin/tech/watzon/pindrop/shared/core/HistorySemantics.kt` - Sort, search, dedup with generics for cross-platform flexibility
- `shared/ui-settings/src/commonMain/kotlin/tech/watzon/pindrop/shared/uisettings/AIEnhancementBehavior.kt` - Enhancement decision logic, request construction, fallback, prompt validation
- `shared/core/src/commonTest/kotlin/tech/watzon/pindrop/shared/core/DictionaryCleanupTest.kt` - 8 tests for cleanup logic
- `shared/core/src/commonTest/kotlin/tech/watzon/pindrop/shared/core/HistorySemanticsTest.kt` - 9 tests for history semantics
- `shared/ui-settings/src/commonTest/kotlin/tech/watzon/pindrop/shared/uisettings/AIEnhancementBehaviorTest.kt` - 8 tests for AI enhancement behavior
- `shared/core/build.gradle.kts` - Added settings-schema dependency
- `shared/ui-settings/build.gradle.kts` - Added settings-schema dependency
- `Pindrop/Services/Transcription/KMPTranscriptionBridge.swift` - 235 lines removed (all conditional branches)
- `Pindrop/UI/Main/MainWindow.swift` - 26 lines removed
- `Pindrop/UI/Settings/AIEnhancementSettingsView.swift` - 129 lines removed
- `Pindrop/Models/MediaTranscriptionTypes.swift` - 173 lines removed
- `Pindrop/UI/Onboarding/AIEnhancementStepView.swift` - 117 lines removed
- `Pindrop/UI/Main/TranscribeView.swift` - 52 lines removed
- 15 additional files with conditional compilation removed

## Decisions Made
- **SettingsValidationResult reuse:** DictionaryCleanup and AIEnhancementBehavior use the same `SettingsValidationResult` sealed class from settings-schema rather than defining their own, maintaining consistency across the shared codebase
- **Generic HistorySemantics:** Used `<T>` with lambda extractors (`textExtractor`, `timeExtractor`) so the same sort/search/dedup logic works with any data class regardless of platform-specific field names
- **No refactoring pass:** The GREEN implementations were already clean and minimal, so no separate refactor commit was needed

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Added settings-schema dependency to core and ui-settings modules**
- **Found during:** Task 1 (DictionaryCleanup and AIEnhancementBehavior implementation)
- **Issue:** DictionaryCleanup.validateDictionaryEntry and AIEnhancementBehavior.validatePrompt return SettingsValidationResult from the settings-schema module, but neither core nor ui-settings had that module as a dependency
- **Fix:** Added `implementation(project(":settings-schema"))` to both build.gradle.kts files
- **Files modified:** shared/core/build.gradle.kts, shared/ui-settings/build.gradle.kts
- **Verification:** All KMP tests pass (`:core:allTests :ui-settings:allTests`)
- **Committed in:** 42dc492

**2. [Rule 1 - Bug] Restored #if os() platform check after script removed it**
- **Found during:** Task 2 (build verification)
- **Issue:** The Python script that removed `#if canImport` blocks also incorrectly removed the `#if os(macOS)` / `#else` / `#endif` block inside `localPlatform()` since it didn't distinguish between `#if canImport()` and `#if os()` conditionals
- **Fix:** Manually restored the `#if os(macOS) / #elseif os(Windows) / #else .linux / #endif` block
- **Files modified:** Pindrop/Services/Transcription/KMPTranscriptionBridge.swift
- **Verification:** `just build` succeeds
- **Committed in:** df413c4

---

**Total deviations:** 2 auto-fixed (1 blocking infrastructure, 1 bug)
**Impact on plan:** Both auto-fixes necessary for correct compilation. No scope creep.

## Issues Encountered
- Xcode `just test` reports "TEST FAILED" with exit code 65 even when all 215 tests pass — known Xcode test runner infrastructure noise (documented in 01-01 SUMMARY)
- Plan estimated ~500 lines removed but actual was ~950 lines — more fallback code existed than initially counted (particularly in MediaTranscriptionTypes.swift and AIEnhancementStepView.swift)

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- All shared business logic (dictionary cleanup, history/search, AI enhancement behavior) now lives in KMP
- All conditional compilation guards removed — KMP frameworks are mandatory
- Phase 01 complete: settings schema, transcription bridge, and shared domain logic all in KMP
- Ready for Phase 02 (Linux GUI implementation)

## Self-Check: PASSED

- All 7 created files verified present
- All 3 task commits found (f79008c, 42dc492, df413c4)
- SUMMARY.md created at expected path
- Zero `#if canImport(PindropShared*)` sites remain
- `just build` succeeds
- All 215 tests pass

---
*Phase: 01-shared-core-authority*
*Completed: 2026-03-29*

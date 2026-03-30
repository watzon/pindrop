---
phase: 03-linux-offline-transcription
plan: 02
subsystem: ui-shell
tags: [linux, gtk4, onboarding, settings, model-management, runtime-transcription]

# Dependency graph
requires:
  - phase: 03-01
    provides: "Linux whisper runtime bootstrap, XDG path policy, and shared model installer wiring"
  - phase: 02-03
    provides: "Linux onboarding and settings shells that Phase 03 replaces with real model flows"
provides:
  - "LinuxModelController for runtime-backed catalog, install, load, and delete actions"
  - "Onboarding model selection and download steps backed by LocalTranscriptionCatalog and persisted selected-model state"
  - "Settings models page with Download, Use, and Remove actions for local models"
affects: [phase-03-recording-flow, phase-04-linux-capture-output-loop]

# Tech tracking
tech-stack:
  added: [kotlinx-coroutines-core]
  patterns: [runtime-backed-gtk-controller, onboarding-model-install-flow, catalog-driven-model-list]

key-files:
  created:
    - shared/ui-shell/src/linuxX64Main/kotlin/tech/watzon/pindrop/shared/ui/shell/linux/models/LinuxModelController.kt
  modified:
    - shared/ui-shell/build.gradle.kts
    - shared/ui-shell/src/linuxX64Main/kotlin/tech/watzon/pindrop/shared/ui/shell/linux/settings/SettingsDialog.kt
    - shared/ui-shell/src/linuxX64Main/kotlin/tech/watzon/pindrop/shared/ui/shell/linux/settings/ModelsSettingsPage.kt
    - shared/ui-shell/src/linuxX64Main/kotlin/tech/watzon/pindrop/shared/ui/shell/linux/onboarding/ModelSelectionStep.kt
    - shared/ui-shell/src/linuxX64Main/kotlin/tech/watzon/pindrop/shared/ui/shell/linux/onboarding/ModelDownloadStep.kt
    - shared/ui-shell/src/linuxX64Main/kotlin/tech/watzon/pindrop/shared/ui/shell/linux/onboarding/OnboardingWizard.kt

key-decisions:
  - "Linux model UI reads LocalTranscriptionCatalog and persisted settings instead of maintaining a second hardcoded Linux-only list"
  - "GTK pages call through LinuxModelController so runtime install/load/delete remains in shared runtime-transcription"
  - "Onboarding downloads use the already-persisted SettingsKeys.selectedModel value so model selection and installation stay aligned"

patterns-established:
  - "Linux GTK surfaces should receive thin controllers that translate persisted settings into shared-runtime actions"
  - "Onboarding and settings model rows derive state from catalog availability plus installed-model records"

requirements-completed: [DICT-05]

# Metrics
duration: unknown
completed: 2026-03-30
---

# Phase 3 Plan 2: Model download/select/remove UI in onboarding + settings Summary

**Linux onboarding and settings model management backed by shared catalog data and runtime install/load/remove actions**

## Performance

- **Duration:** unknown
- **Started:** unknown
- **Completed:** 2026-03-30T00:15:30Z
- **Tasks:** 2
- **Files modified:** 7

## Accomplishments
- Added `LinuxModelController` as the Linux shell adapter over `LinuxWhisperRuntimeBootstrap` and persisted model settings
- Replaced the hardcoded onboarding model list with `LocalTranscriptionCatalog`-driven recommended and advanced selections
- Replaced the onboarding download placeholder and settings text fields with runtime-backed Download, Use, and Remove actions

## Task Commits

Each task was committed atomically:

1. **Task 1: Add a Linux model controller that wraps shared runtime actions** - `5a52597` (feat)
2. **Task 2: Replace placeholder model onboarding/settings UI with install-select-remove flows** - `5094c9c` (feat), `43569af` (fix)

## Files Created/Modified
- `shared/ui-shell/src/linuxX64Main/kotlin/tech/watzon/pindrop/shared/ui/shell/linux/models/LinuxModelController.kt` - Linux runtime-backed model controller for catalog, install, load, delete, and selected-model persistence
- `shared/ui-shell/src/linuxX64Main/kotlin/tech/watzon/pindrop/shared/ui/shell/linux/settings/SettingsDialog.kt` - settings shell now injects `LinuxModelController` into the models page
- `shared/ui-shell/src/linuxX64Main/kotlin/tech/watzon/pindrop/shared/ui/shell/linux/settings/ModelsSettingsPage.kt` - model list UI with Download, Use, Remove, and disabled setup states
- `shared/ui-shell/src/linuxX64Main/kotlin/tech/watzon/pindrop/shared/ui/shell/linux/onboarding/ModelSelectionStep.kt` - catalog-driven recommended and advanced model chooser
- `shared/ui-shell/src/linuxX64Main/kotlin/tech/watzon/pindrop/shared/ui/shell/linux/onboarding/ModelDownloadStep.kt` - onboarding install action and visible download status for the persisted selected model
- `shared/ui-shell/src/linuxX64Main/kotlin/tech/watzon/pindrop/shared/ui/shell/linux/onboarding/OnboardingWizard.kt` - passes settings into the runtime-backed download step
- `shared/ui-shell/build.gradle.kts` - runtime-transcription and coroutines dependencies required for Linux model actions

## Decisions Made
- Reused `LocalTranscriptionCatalog` directly in onboarding so Linux does not diverge from the shared curated model policy.
- Centralized Linux model install/load/delete behavior in `LinuxModelController` instead of scattering runtime calls across multiple GTK pages.
- Read `SettingsKeys.selectedModel` inside onboarding downloads so the install step always matches the user's previously chosen model.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Added missing ui-shell dependencies required for runtime-backed model actions**
- **Found during:** Task 1 (Add a Linux model controller that wraps shared runtime actions)
- **Issue:** `ui-shell` did not yet depend on `:runtime-transcription` or coroutines, so the Linux controller could not call the shared runtime from GTK code.
- **Fix:** Added `:runtime-transcription` and `kotlinx-coroutines-core` to `shared/ui-shell/build.gradle.kts` and converted the controller to thin blocking wrappers over the shared runtime.
- **Files modified:** shared/ui-shell/build.gradle.kts, shared/ui-shell/src/linuxX64Main/kotlin/tech/watzon/pindrop/shared/ui/shell/linux/models/LinuxModelController.kt
- **Verification:** `./gradlew :runtime-transcription:jvmTest`
- **Committed in:** `5a52597`, `5094c9c`

---

**Total deviations:** 1 auto-fixed (1 blocking)
**Impact on plan:** The auto-fix was required to wire GTK pages to the shared runtime. No scope creep beyond the planned model-management flow.

## Issues Encountered
- `:ui-shell:compileKotlinLinuxX64` remains blocked on this macOS host because the Linux GTK/libadwaita/appindicator cinterop artifacts are unavailable here. This is a pre-existing environment limitation and was logged in `deferred-items.md` instead of being treated as a task regression.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Linux now has install/select/remove model surfaces that can be reused by the recording flow without adding parallel state machines.
- Plan 03-03 can bootstrap `VoiceSessionCoordinator` against the same selected-model setting and runtime foundation used here.
- Linux-host verification is still needed for end-to-end GTK behavior because macOS cannot compile or run the Linux cinterop target.

## Self-Check: PASSED

- Summary file exists at `.planning/phases/03-linux-offline-transcription/03-02-SUMMARY.md`
- Task commits verified in git history: `5a52597`, `5094c9c`, `43569af`

---
*Phase: 03-linux-offline-transcription*
*Completed: 2026-03-30*

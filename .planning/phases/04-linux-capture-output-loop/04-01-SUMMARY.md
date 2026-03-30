---
phase: 04-linux-capture-output-loop
plan: 01
subsystem: ui-shell
tags: [linux, hotkeys, x11, wayland, gtk, kotlin-multiplatform]

# Dependency graph
requires:
  - phase: 02-02
    provides: "LinuxCoordinator, tray menu, and tray fallback shell surfaces"
  - phase: 03-03
    provides: "Linux VoiceSessionCoordinator wiring for recording start/stop"
provides:
  - "Shared hotkey runtime models with backend selection, runtime state labels, and action routing"
  - "Linux capability-based hotkey runtime with X11, portal placeholder, and unavailable backends"
  - "Shell-visible hotkey status on tray, tray fallback, and hotkeys settings surfaces"
affects: [04-02, 04-03, linux-hotkeys, linux-shell]

# Tech tracking
tech-stack:
  added: [x11-cinterop]
  patterns: [capability-based-hotkey-runtime, non-fatal-hotkey-degradation, shell-visible-binding-status]

key-files:
  created:
    - shared/ui-shell/src/commonMain/kotlin/tech/watzon/pindrop/shared/ui/shell/hotkeys/HotkeyRuntimeModels.kt
    - shared/ui-shell/src/commonTest/kotlin/tech/watzon/pindrop/shared/ui/shell/hotkeys/HotkeyRuntimeModelsTest.kt
    - shared/ui-shell/src/linuxX64Main/cinterop/x11.def
    - shared/ui-shell/src/linuxX64Main/kotlin/tech/watzon/pindrop/shared/ui/shell/linux/hotkeys/LinuxHotkeyRuntime.kt
    - shared/ui-shell/src/linuxX64Main/kotlin/tech/watzon/pindrop/shared/ui/shell/linux/hotkeys/LinuxHotkeyBackend.kt
    - shared/ui-shell/src/linuxX64Main/kotlin/tech/watzon/pindrop/shared/ui/shell/linux/hotkeys/LinuxHotkeyStatus.kt
  modified:
    - shared/ui-shell/build.gradle.kts
    - shared/ui-shell/src/linuxX64Main/kotlin/tech/watzon/pindrop/shared/ui/shell/linux/LinuxCoordinator.kt
    - shared/ui-shell/src/linuxX64Main/kotlin/tech/watzon/pindrop/shared/ui/shell/linux/TrayMenu.kt
    - shared/ui-shell/src/linuxX64Main/kotlin/tech/watzon/pindrop/shared/ui/shell/linux/TrayFallback.kt
    - shared/ui-shell/src/linuxX64Main/kotlin/tech/watzon/pindrop/shared/ui/shell/linux/settings/HotkeysSettingsPage.kt

key-decisions:
  - "Shared hotkey contracts reuse feature-transcription HotkeyBinding and HotkeyMode so Linux shell code does not fork recording semantics."
  - "Linux hotkey startup is capability-based: prefer X11, expose a portal placeholder surface on supported Wayland sessions, and degrade to unavailable guidance without blocking startup."
  - "Tray, fallback, and settings surfaces consume binding snapshots so hotkey failures stay visible while manual recording controls remain usable."

patterns-established:
  - "Use commonMain runtime models plus linuxX64Main adapters for platform-sensitive shell integration."
  - "Treat Linux desktop capability gaps as status-bearing degradations instead of startup failures."

requirements-completed: [DICT-01, DICT-02]

# Metrics
duration: 11min
completed: 2026-03-30
---

# Phase 4 Plan 1: Hotkey runtime, capability detection, and shell-visible binding status Summary

**Linux hotkey runtime contracts, X11-first backend selection, and visible toggle/push-to-talk status across tray, fallback, and settings surfaces**

## Performance

- **Duration:** 11 min
- **Started:** 2026-03-30T03:18:51Z
- **Completed:** 2026-03-30T03:30:08Z
- **Tasks:** 2
- **Files modified:** 11

## Accomplishments
- Added pure shared hotkey runtime models with tests for binding-state mapping, action routing, and backend capability selection.
- Added Linux hotkey runtime adapters with X11 registration, portal placeholder handling, and non-fatal unavailable guidance.
- Surfaced hotkey runtime state in the tray menu, tray fallback window, and Linux hotkeys settings page while keeping recording controls usable without hotkeys.

## Task Commits

Each task was committed atomically:

1. **Task 1: Define hotkey runtime contracts and testable status mapping** - `4923272` (test), `d3cce16` (feat)
2. **Task 2: Implement capability-based Linux hotkey runtime and surface binding status** - `5da4a9d` (feat)

_Note: Task 1 followed TDD and produced separate RED and GREEN commits._

## Files Created/Modified
- `shared/ui-shell/build.gradle.kts` - adds shared feature-transcription access for common hotkey contracts and Linux X11 cinterop wiring.
- `shared/ui-shell/src/commonMain/kotlin/tech/watzon/pindrop/shared/ui/shell/hotkeys/HotkeyRuntimeModels.kt` - defines backend IDs, binding runtime states, action IDs, event phases, and routing helpers.
- `shared/ui-shell/src/commonTest/kotlin/tech/watzon/pindrop/shared/ui/shell/hotkeys/HotkeyRuntimeModelsTest.kt` - verifies status mapping, toggle/PTT routing, and backend selection behavior.
- `shared/ui-shell/src/linuxX64Main/cinterop/x11.def` - links X11 headers for Linux hotkey backend interop.
- `shared/ui-shell/src/linuxX64Main/kotlin/tech/watzon/pindrop/shared/ui/shell/linux/hotkeys/LinuxHotkeyRuntime.kt` - owns backend selection, binding refresh, and invocation dispatch.
- `shared/ui-shell/src/linuxX64Main/kotlin/tech/watzon/pindrop/shared/ui/shell/linux/hotkeys/LinuxHotkeyBackend.kt` - defines unavailable, portal, and X11 backend implementations.
- `shared/ui-shell/src/linuxX64Main/kotlin/tech/watzon/pindrop/shared/ui/shell/linux/hotkeys/LinuxHotkeyStatus.kt` - parses saved shortcut strings and formats UI status snapshots.
- `shared/ui-shell/src/linuxX64Main/kotlin/tech/watzon/pindrop/shared/ui/shell/linux/LinuxCoordinator.kt` - initializes and disposes the hotkey runtime, refreshes bindings from saved settings, and routes toggle/PTT invocations into VoiceSessionCoordinator start/stop calls.
- `shared/ui-shell/src/linuxX64Main/kotlin/tech/watzon/pindrop/shared/ui/shell/linux/TrayMenu.kt` - shows disabled status rows for toggle and push-to-talk runtime state.
- `shared/ui-shell/src/linuxX64Main/kotlin/tech/watzon/pindrop/shared/ui/shell/linux/TrayFallback.kt` - shows multiline hotkey guidance alongside recording controls.
- `shared/ui-shell/src/linuxX64Main/kotlin/tech/watzon/pindrop/shared/ui/shell/linux/settings/HotkeysSettingsPage.kt` - adds explicit runtime-style status labels beneath hotkey fields.

## Decisions Made
- Used shared runtime models instead of Linux-only enums so hotkey status and action semantics stay testable on the JVM.
- Kept Wayland portal support as an explicit adapter surface that degrades with guidance instead of crashing startup on unsupported desktops.
- Routed hotkey actions back through existing `startRecording()` / `stopRecording()` coordinator methods so Linux still has one recording lifecycle.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Added missing shared dependency for hotkey runtime contracts**
- **Found during:** Task 1 (Define hotkey runtime contracts and testable status mapping)
- **Issue:** `ui-shell` commonMain tests could not compile against `HotkeyBinding` and `HotkeyMode` until `:feature-transcription` was available to shared contract code.
- **Fix:** Added `implementation(project(":feature-transcription"))` to `shared/ui-shell/build.gradle.kts` and kept the common hotkey contract pure Kotlin.
- **Files modified:** `shared/ui-shell/build.gradle.kts`, `shared/ui-shell/src/commonMain/kotlin/tech/watzon/pindrop/shared/ui/shell/hotkeys/HotkeyRuntimeModels.kt`
- **Verification:** `./gradlew :ui-shell:jvmTest`
- **Committed in:** `d3cce16`

---

**Total deviations:** 1 auto-fixed (1 blocking)
**Impact on plan:** The auto-fix was required to compile and test the shared hotkey contract. No scope creep beyond the planned Linux hotkey runtime work.

## Issues Encountered
- linuxX64 hotkey code cannot be compile-validated on this macOS host because X11 and GTK native artifacts are Linux-only; JVM verification stayed green and Linux-host validation remains the next gate.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- Linux shell surfaces now expose whether toggle and push-to-talk are active, unavailable, failed, or unconfigured.
- Phase 04-02 can build floating indicator behavior on the same coordinator-owned shell state without inventing a second status model.
- Linux-host verification is still required to prove the X11 event loop and desktop-specific binding behavior in a real session.

## Known Stubs
- `shared/ui-shell/src/linuxX64Main/kotlin/tech/watzon/pindrop/shared/ui/shell/linux/hotkeys/LinuxHotkeyBackend.kt` — the portal backend is an intentional placeholder adapter surface that currently degrades with guidance instead of activating real Wayland global shortcuts. This matches the plan’s placeholder requirement and preserves tray/fallback recovery paths.

## Self-Check: PASSED

- Summary file exists at `.planning/phases/04-linux-capture-output-loop/04-01-SUMMARY.md`
- Task commits verified in git history: `4923272`, `d3cce16`, `5da4a9d`

---
*Phase: 04-linux-capture-output-loop*
*Completed: 2026-03-30*

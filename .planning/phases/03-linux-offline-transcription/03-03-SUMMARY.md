---
phase: 03-linux-offline-transcription
plan: 03
subsystem: ui-shell
tags: [linux, voice-session, audio-capture, whisper.cpp, gtk4, transcript-dialog]

# Dependency graph
requires:
  - phase: 03-01
    provides: "Linux whisper runtime bootstrap and whisper.cpp bridge"
  - phase: 03-02
    provides: "Selected-model persistence and Linux model-management surfaces"
provides:
  - "LinuxAudioCapture for completed-file microphone recording via pw-record or parecord"
  - "LinuxVoiceSessionFactory for bootstrapping VoiceSessionCoordinator with Linux settings and runtime wiring"
  - "Linux tray and fallback recording controls with in-app transcript presentation"
affects: [phase-04-linux-capture-output-loop, phase-05-history-dictionary-ai]

# Tech tracking
tech-stack:
  added: []
  patterns: [cli-audio-capture-adapter, in-app-transcript-delivery, shell-owned-voice-session]

key-files:
  created:
    - shared/ui-shell/src/linuxX64Main/kotlin/tech/watzon/pindrop/shared/ui/shell/linux/transcription/LinuxAudioCapture.kt
    - shared/ui-shell/src/linuxX64Main/kotlin/tech/watzon/pindrop/shared/ui/shell/linux/transcription/LinuxVoiceSessionFactory.kt
    - shared/ui-shell/src/linuxX64Main/kotlin/tech/watzon/pindrop/shared/ui/shell/linux/transcription/LinuxTranscriptDialog.kt
  modified:
    - shared/ui-shell/build.gradle.kts
    - shared/ui-shell/src/linuxX64Main/kotlin/tech/watzon/pindrop/shared/ui/shell/linux/LinuxCoordinator.kt
    - shared/ui-shell/src/linuxX64Main/kotlin/tech/watzon/pindrop/shared/ui/shell/linux/TrayMenu.kt
    - shared/ui-shell/src/linuxX64Main/kotlin/tech/watzon/pindrop/shared/ui/shell/linux/TrayFallback.kt

key-decisions:
  - "Linux recording reuses VoiceSessionCoordinator with a Linux-specific factory instead of rebuilding dictation state in the GTK shell"
  - "Completed transcripts surface in a GTK dialog while the coordinator receives an in-memory clipboard port, avoiding automatic clipboard writes in Phase 03"
  - "Linux audio capture prefers pw-record and falls back to parecord so the first offline recording path stays simple and platform-native"

patterns-established:
  - "Linux shell owns one long-lived voice-session handle and mirrors its state into tray and fallback controls"
  - "CLI-backed platform adapters should write completed artifacts to XDG temp paths and return bytes to shared feature coordinators"

requirements-completed: [DICT-04]

# Metrics
duration: unknown
completed: 2026-03-30
---

# Phase 3 Plan 3: In-app recording flow + transcript result dialog Summary

**Linux completed-file recording flow backed by VoiceSessionCoordinator, pw-record/parecord capture, and an in-app transcript dialog**

## Performance

- **Duration:** unknown
- **Started:** unknown
- **Completed:** 2026-03-30T00:21:20Z
- **Tasks:** 2
- **Files modified:** 7

## Accomplishments
- Added a Linux audio-capture adapter that records WAV files through `pw-record` first or `parecord` second and returns completed bytes to shared dictation logic
- Added a Linux voice-session factory that bootstraps `VoiceSessionCoordinator` with persisted settings, Linux runtime wiring, and transcript/error event callbacks
- Wired start/stop recording controls into the tray and tray-less fallback UI, then presented completed transcripts in a GTK dialog instead of auto-copying from `LinuxCoordinator`

## Task Commits

Each task was committed atomically:

1. **Task 1: Add Linux voice-session bootstrap and completed-file audio capture** - `90e58cf` (feat)
2. **Task 2: Wire recording actions into the GTK shell and show transcript results in-app** - `5ee4b1a` (feat)

## Files Created/Modified
- `shared/ui-shell/src/linuxX64Main/kotlin/tech/watzon/pindrop/shared/ui/shell/linux/transcription/LinuxAudioCapture.kt` - Linux `AudioCapturePort` implementation using `pw-record` or `parecord`
- `shared/ui-shell/src/linuxX64Main/kotlin/tech/watzon/pindrop/shared/ui/shell/linux/transcription/LinuxVoiceSessionFactory.kt` - Linux `VoiceSessionCoordinator` bootstrap plus settings, permission, and clipboard adapters
- `shared/ui-shell/src/linuxX64Main/kotlin/tech/watzon/pindrop/shared/ui/shell/linux/transcription/LinuxTranscriptDialog.kt` - transcript viewer dialog with Copy and Close actions
- `shared/ui-shell/src/linuxX64Main/kotlin/tech/watzon/pindrop/shared/ui/shell/linux/LinuxCoordinator.kt` - owns the Linux voice session and exposes start/stop recording actions
- `shared/ui-shell/src/linuxX64Main/kotlin/tech/watzon/pindrop/shared/ui/shell/linux/TrayMenu.kt` - Start Recording and Stop Recording tray actions
- `shared/ui-shell/src/linuxX64Main/kotlin/tech/watzon/pindrop/shared/ui/shell/linux/TrayFallback.kt` - tray-less recording controls and inline status updates
- `shared/ui-shell/build.gradle.kts` - feature-transcription dependency needed for shared voice-session orchestration

## Decisions Made
- Used `VoiceSessionCoordinator` as the sole recording/transcription state machine so Linux shell code stays thin and aligned with shared offline dictation rules.
- Kept Phase 03 transcript delivery inside GTK by pairing an in-memory clipboard adapter with a dedicated transcript dialog, leaving real clipboard/direct-insert behavior to Phase 04.
- Chose `pw-record` with `parecord` fallback for the first Linux audio adapter so microphone capture stays simple and native without inventing a second conversion subsystem.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Added missing feature-transcription dependency before creating the Linux voice-session factory**
- **Found during:** Task 1 (Add Linux voice-session bootstrap and completed-file audio capture)
- **Issue:** `ui-shell` could not reference `VoiceSessionCoordinator` or the recording contracts until `:feature-transcription` was added to the linuxX64 source set.
- **Fix:** Added the dependency in `shared/ui-shell/build.gradle.kts` and wired Linux-specific adapters through `LinuxVoiceSessionFactory.kt`.
- **Files modified:** shared/ui-shell/build.gradle.kts, shared/ui-shell/src/linuxX64Main/kotlin/tech/watzon/pindrop/shared/ui/shell/linux/transcription/LinuxVoiceSessionFactory.kt
- **Verification:** `./gradlew :feature-transcription:jvmTest`
- **Committed in:** `90e58cf`

---

**Total deviations:** 1 auto-fixed (1 blocking)
**Impact on plan:** The auto-fix was required to connect Linux shell code to the shared dictation flow. No scope creep beyond the planned recording feature.

## Issues Encountered
- linuxX64 GTK compilation remains blocked on this macOS host because the Linux GTK/libadwaita/appindicator cinterop artifacts are unavailable here. Shared `:feature-transcription:jvmTest` passed, but final Linux-shell compilation still requires a Linux host.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Linux now has a full in-app offline recording loop from shell controls through local transcript presentation.
- Phase 04 can build on the same voice-session handle to add hotkeys, floating feedback, and real clipboard/direct-insert output.
- Linux-host verification is still required to validate GTK dialogs and audio-helper execution in a real desktop session.

## Self-Check: PASSED

- Summary file exists at `.planning/phases/03-linux-offline-transcription/03-03-SUMMARY.md`
- Task commits verified in git history: `90e58cf`, `5ee4b1a`

---
*Phase: 03-linux-offline-transcription*
*Completed: 2026-03-30*

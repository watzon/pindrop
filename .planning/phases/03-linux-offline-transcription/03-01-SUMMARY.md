---
phase: 03-linux-offline-transcription
plan: 01
subsystem: runtime-transcription
tags: [linux, whisper.cpp, kotlin-native, okio, ktor, offline-transcription]

# Dependency graph
requires:
  - phase: 02-03
    provides: "Linux shell placeholders and settings persistence surfaces that need a real offline runtime"
provides:
  - "LinuxWhisperRuntimePaths for explicit helper, model, and temp directory resolution"
  - "WhisperCppCommandBuilder for deterministic whisper-cli argv generation"
  - "LinuxWhisperCppBridge and LinuxWhisperRuntimeBootstrap for shared runtime-backed Linux transcription"
affects: [phase-03-model-management, phase-03-recording-flow, phase-06-linux-packaging]

# Tech tracking
tech-stack:
  added: [ktor-client-curl]
  patterns: [xdg-runtime-path-policy, cli-bridge-adapter, shared-runtime-bootstrap]

key-files:
  created:
    - shared/runtime-transcription/src/commonMain/kotlin/tech/watzon/pindrop/shared/runtime/transcription/WhisperCppCommandBuilder.kt
    - shared/runtime-transcription/src/commonTest/kotlin/tech/watzon/pindrop/shared/runtime/transcription/WhisperCppCommandBuilderTest.kt
    - shared/runtime-transcription/src/linuxX64Main/kotlin/tech/watzon/pindrop/shared/runtime/transcription/LinuxWhisperRuntimePaths.kt
    - shared/runtime-transcription/src/linuxX64Main/kotlin/tech/watzon/pindrop/shared/runtime/transcription/LinuxWhisperCppBridge.kt
    - shared/runtime-transcription/src/linuxX64Main/kotlin/tech/watzon/pindrop/shared/runtime/transcription/LinuxWhisperRuntimeBootstrap.kt
  modified:
    - shared/runtime-transcription/build.gradle.kts

key-decisions:
  - "Linux runtime paths resolve through explicit XDG-style defaults instead of repo-relative discovery"
  - "Linux whisper.cpp integration shells out through a small bridge while keeping model install/load/delete in shared runtime-transcription"
  - "Model downloads reuse KtorDownloadClient and WhisperCppRemoteModelRepository rather than adding Linux-only downloader code"

patterns-established:
  - "Command-line inference adapters build deterministic argv lists in common code and resolve platform paths in linuxX64Main"
  - "Linux runtime bootstrap is a single factory entry point that composes FileSystem, downloader, repository, and bridge"

requirements-completed: [DICT-04, DICT-05]

# Metrics
duration: unknown
completed: 2026-03-30
---

# Phase 3 Plan 1: Linux runtime bootstrap + whisper.cpp bridge Summary

**Linux whisper.cpp runtime bootstrap with explicit XDG path policy, deterministic CLI arguments, and shared model installer wiring**

## Performance

- **Duration:** unknown
- **Started:** unknown
- **Completed:** 2026-03-30T00:06:46Z
- **Tasks:** 2
- **Files modified:** 6

## Accomplishments
- Added test-backed Linux path and command contracts for helper lookup, model install roots, runtime temp roots, and whisper-cli flags
- Added a linuxX64 whisper.cpp bridge that loads installed GGML models, writes completed WAV payloads to temp storage, and surfaces command failures as thrown errors
- Added a Linux runtime bootstrap that composes `FileSystemModelInstaller`, `KtorDownloadClient`, and `WhisperCppRemoteModelRepository` through `WhisperCppRuntimeFactory`

## Task Commits

Each task was committed atomically:

1. **Task 1: Define and test Linux whisper runtime path + command contracts** - `0260ef4` (test), `cc25096` (feat)
2. **Task 2: Implement the linuxX64 runtime bootstrap and whisper bridge** - `42cba14` (feat)

## Files Created/Modified
- `shared/runtime-transcription/src/commonMain/kotlin/tech/watzon/pindrop/shared/runtime/transcription/WhisperCppCommandBuilder.kt` - shared helper for Linux XDG path policy and deterministic whisper-cli command vectors
- `shared/runtime-transcription/src/commonTest/kotlin/tech/watzon/pindrop/shared/runtime/transcription/WhisperCppCommandBuilderTest.kt` - regression coverage for env override lookup, XDG defaults, and `-m/-f/-l` command output
- `shared/runtime-transcription/src/linuxX64Main/kotlin/tech/watzon/pindrop/shared/runtime/transcription/LinuxWhisperRuntimePaths.kt` - linuxX64 path resolver for helper, models, and runtime temp directories
- `shared/runtime-transcription/src/linuxX64Main/kotlin/tech/watzon/pindrop/shared/runtime/transcription/LinuxWhisperCppBridge.kt` - Linux `WhisperCppBridgePort` implementation for completed-file transcription
- `shared/runtime-transcription/src/linuxX64Main/kotlin/tech/watzon/pindrop/shared/runtime/transcription/LinuxWhisperRuntimeBootstrap.kt` - Linux runtime factory that reuses shared installer/index logic
- `shared/runtime-transcription/build.gradle.kts` - linuxX64 curl client dependency needed for runtime downloads

## Decisions Made
- Used XDG-style defaults for Linux runtime data so packaged and developer runs resolve the same helper/model/temp locations.
- Kept whisper.cpp execution behind `WhisperCppBridgePort` so Phase 03 shell work can consume the shared runtime without duplicating install or backend logic.
- Reused the existing `KtorDownloadClient` and `WhisperCppRemoteModelRepository` to avoid creating a second Linux-only model download path.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Replaced deprecated native timestamp helper during linuxX64 compile**
- **Found during:** Task 2 (Implement the linuxX64 runtime bootstrap and whisper bridge)
- **Issue:** The first bridge implementation used a deprecated time helper that linuxX64 treated as a compilation error, blocking the required compile verification.
- **Fix:** Switched temp-file naming to `platform.posix.time()` and `getpid()` so the bridge compiles cleanly on linuxX64.
- **Files modified:** shared/runtime-transcription/src/linuxX64Main/kotlin/tech/watzon/pindrop/shared/runtime/transcription/LinuxWhisperCppBridge.kt
- **Verification:** `./gradlew :runtime-transcription:jvmTest :runtime-transcription:compileKotlinLinuxX64`
- **Committed in:** `42cba14`

---

**Total deviations:** 1 auto-fixed (1 blocking)
**Impact on plan:** The auto-fix was required to satisfy the plan's linuxX64 compile gate. No scope creep.

## Issues Encountered
- The TDD RED step failed at compile time because `WhisperCppCommandBuilder` and Linux path helpers did not exist yet; the missing symbols were then implemented in the GREEN step as planned.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Linux now has one runtime bootstrap entry point that later shell code can use for model install, load, and transcription behavior.
- Plan 03-02 can bind onboarding/settings model surfaces to shared runtime state without adding duplicate installer logic.
- Plan 03-03 can wire completed-file audio capture into `LinuxWhisperRuntimeBootstrap` and present in-app transcript results.

## Self-Check: PASSED

- Summary file exists at `.planning/phases/03-linux-offline-transcription/03-01-SUMMARY.md`
- Task commits verified in git history: `0260ef4`, `cc25096`, `42cba14`

---
*Phase: 03-linux-offline-transcription*
*Completed: 2026-03-30*

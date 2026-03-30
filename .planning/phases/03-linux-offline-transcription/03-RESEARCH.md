# Phase 03 Research: Linux Offline Transcription

**Phase:** 03 — Linux Offline Transcription  
**Date:** 2026-03-29  
**Inputs:** `.planning/ROADMAP.md`, `.planning/REQUIREMENTS.md`, `.planning/STATE.md`, `.planning/research/*.md`, Phase 02 summaries, current `shared/` Linux shell and runtime-transcription modules

## Research Outcome

Phase 03 should extend the **existing GTK4/libadwaita Kotlin/Native Linux shell** already committed in Phase 02 and wire it to the **existing shared runtime-transcription + feature-transcription contracts** already present in `shared/runtime-transcription` and `shared/feature-transcription`.

Do **not** pivot the Linux shell to Compose in this phase. Earlier top-level research recommended Compose for a greenfield Linux client, but the repository now already has an implemented GTK/Linux shell, AppIndicator integration, onboarding flow, settings dialog, and linuxX64 build/cinterop path. Replacing the shell now would reset shipped progress and create unnecessary architecture churn.

## What Already Exists

### Reusable shared runtime contracts

- `LocalTranscriptionRuntime` already owns model install/load/delete/transcribe state transitions.
- `FileSystemInstalledModelIndex` and `FileSystemModelInstaller` already implement on-disk model inventory and atomic downloads.
- `KtorDownloadClient` already exists in `desktopMain` for JVM/Linux model downloads.
- `WhisperCppRemoteModelRepository` already maps curated Whisper model IDs to concrete download URLs.
- `VoiceSessionCoordinator` already defines the end-to-end offline dictation flow around:
  - settings bootstrap
  - permission checks
  - audio capture via `AudioCapturePort`
  - transcription through `LocalTranscriptionRuntime`
  - transcript delivery through `VoiceSessionEventSink`
  - optional history persistence

### Existing Linux shell surfaces waiting for real wiring

- `ModelSelectionStep.kt` currently uses a hardcoded model list.
- `ModelDownloadStep.kt` is a placeholder spinner.
- `ModelsSettingsPage.kt` is plain text-entry storage with explicit Phase 3 placeholder copy.
- `TrayMenu.kt` and `TrayFallback.kt` have no dictation actions yet.
- `LinuxCoordinator.kt` already owns settings, secrets, onboarding, tray, fallback, and lifecycle; it is the correct composition point for runtime/bootstrap wiring.

## Recommendation

### 1. Use whisper.cpp as a Linux CLI bridge, not a new engine abstraction

Implement the missing Linux bridge behind `WhisperCppBridgePort` by wrapping a local `whisper-cli` executable.

Recommended lookup order for the executable:

1. `PINDROP_WHISPER_CPP_BIN` environment override
2. `~/.local/share/pindrop/bin/whisper-cli`
3. `whisper-cli` on `PATH`

This keeps dev-run and packaged-run behavior explicit and avoids repo-relative path assumptions.

### 2. Make runtime paths explicit now

Use XDG-style paths so Phase 06 packaging does not have to unwind implicit dev-only behavior:

- Models: `~/.local/share/pindrop/models`
- Runtime helper cache/temp audio: `~/.cache/pindrop/runtime-transcription`
- Settings remain at the already-established `~/.config/pindrop/settings.toml`

### 3. Reuse shared model catalog directly in Linux UI

Linux model UI should read from `LocalTranscriptionCatalog.models(LocalPlatformId.LINUX)` and `recommendedModels(...)`, not maintain a separate hardcoded list.

Important consequence:

- `ModelAvailability.AVAILABLE` → show install/select actions
- `ModelAvailability.REQUIRES_SETUP` → show disabled/manual-setup messaging
- `ModelAvailability.COMING_SOON` → show disabled state only

### 4. Keep Phase 03 output local to the app, not system insertion

Phase 04 owns hotkeys, floating indicator, clipboard-first output, and direct insertion. Phase 03 should stop at:

- record microphone audio
- run local offline transcription
- show the completed transcript in-app (dialog/sheet/fallback surface)

That satisfies `DICT-04` without stealing Phase 04 scope.

### 5. Use capability-driven Linux capture with a CLI-backed first pass

For this phase, the most direct Linux audio path is a small `AudioCapturePort` adapter that records to a temporary WAV file using Linux-native capture tooling, with this order:

1. `pw-record`
2. `parecord`

Capture should target **16 kHz mono WAV** to match Whisper input expectations and avoid introducing a second conversion subsystem in the GTK shell. If neither tool exists, the adapter should fail with a typed user-facing message and keep the app responsive.

This is acceptable for Phase 03 because:

- hotkey/indicator polish is deferred to Phase 04
- the goal is a complete offline workflow, not final Linux integration parity
- the shared `VoiceSessionCoordinator` already isolates the capture mechanism behind `AudioCapturePort`

## Concrete Planning Guidance

### Plan split that fits current codebase

1. **Runtime bootstrap + Linux whisper bridge**
   - Create linuxX64 runtime bootstrap around explicit helper/model/temp paths
   - Add `WhisperCppBridgePort` Linux implementation
   - Keep verification focused on `runtime-transcription` tests + linux compile

2. **Model management surfaces**
   - Replace onboarding/settings placeholders with real model install/remove/select UI
   - Reuse `LocalTranscriptionCatalog` and runtime install progress
   - Avoid touching tray/recording files so this plan can run in parallel with the recording plan

3. **Recording flow in the Linux shell**
   - Add Linux audio capture adapter
   - Wire `VoiceSessionCoordinator` into `LinuxCoordinator`
   - Add tray/fallback controls and transcript result dialog
   - Keep transcript delivery in-app only; defer automatic clipboard/direct insertion to Phase 04

## Don't Hand Roll

- **Model download logic**: reuse `FileSystemModelInstaller` and `KtorDownloadClient`; do not create a second downloader in `ui-shell`.
- **Model metadata**: reuse `LocalTranscriptionCatalog`; do not keep hardcoded Linux-only model arrays.
- **Session flow**: reuse `VoiceSessionCoordinator`; do not rebuild recording/transcription state transitions directly in `LinuxCoordinator`.
- **Runtime state**: reuse `LocalTranscriptionRuntime` observer hooks for install/load/error state rather than ad-hoc booleans in GTK code.

## Common Pitfalls

1. **Repo-relative runtime paths** — Phase 03 must not assume models/helpers live next to the source tree.
2. **Duplicate model catalogs** — `ModelSelectionStep.kt` hardcodes models today; Phase 03 must delete that duplication.
3. **Leaking Phase 04 work into Phase 03** — do not add automatic clipboard/direct insertion/hotkey-only entry points yet.
4. **Silent helper failures** — missing `whisper-cli`, `pw-record`, or `parecord` must surface as explicit Linux UI messages.
5. **Treating install progress as UI-only** — model install state must come from shared runtime records so settings/onboarding stay consistent after restart.

## Validation Architecture

### Critical Validation Points

1. Linux runtime bootstrap resolves helper, model, and temp paths without referencing the repo working directory.
2. Linux model UI reads from `LocalTranscriptionCatalog` and persisted installed-model records instead of hardcoded lists/placeholders.
3. Linux shell can install a model, load it, record audio, and surface a local transcript without cloud calls.
4. Phase 03 verification stays split between fast JVM/shared tests and linuxX64 compile checks.

### Automated Verification Strategy

- `./gradlew :runtime-transcription:jvmTest` for model/runtime contracts
- `./gradlew :feature-transcription:jvmTest` for session orchestration contracts
- `./gradlew :runtime-transcription:compileKotlinLinuxX64 :ui-shell:compileKotlinLinuxX64` for Linux build regressions

## Recommended Plan Structure

| Plan | Wave | Focus | Why |
|------|------|-------|-----|
| 01 | 1 | Linux runtime bootstrap + whisper bridge | Shared foundation for model install/load/transcribe |
| 02 | 2 | Model download/select/remove UI | Depends on runtime bootstrap, stays isolated from tray/recording files |
| 03 | 2 | Recording flow + transcript result UI | Depends on runtime bootstrap, can run parallel with model UI |

---

*Phase: 03-linux-offline-transcription*  
*Research completed: 2026-03-29*

# Phase 4: Linux Capture & Output Loop - Context

**Gathered:** 2026-03-29
**Status:** Ready for planning

<domain>
## Phase Boundary

Phase 4 turns the Linux shell from a tray-driven recording demo into a daily-use dictation loop. This phase covers:

1. Global shortcut-driven start/stop dictation for toggle and push-to-talk flows
2. Visible active-recording feedback while dictation is in progress
3. Automatic transcript delivery through the clipboard by default
4. Best-effort direct insertion when the Linux environment supports it, with a clear clipboard fallback when it does not

This phase does not add history, dictionary cleanup, AI enhancement, notes, or packaged distribution. It extends the Phase 2 Linux shell and the Phase 3 offline recording path without introducing a second recording state machine.

</domain>

<decisions>
## Implementation Decisions

### Shortcut Activation

- **D-01:** Linux uses a best-effort global shortcut runtime instead of making hotkeys a hard platform requirement. X11 bindings and supported Wayland portal bindings should both plug into the same runtime surface, with capability detection deciding what is available at launch.
- **D-02:** Phase 4 must support both configurable toggle recording and push-to-talk shortcuts from the existing settings keys. Binding state should flow back into tray/fallback UI so users can see whether each shortcut is active.
- **D-03:** Shortcut bind failures are non-fatal. When a shortcut cannot be registered, the app keeps tray and fallback-window recording entry points available and shows explicit Linux guidance instead of silently failing.

### Recording Feedback

- **D-04:** Active recording should show a lightweight floating indicator in addition to tray/fallback status updates. The overlay only appears while a voice session is actively recording or stopping, and it reuses the existing floating-indicator settings surface where practical.
- **D-05:** The indicator, tray labels, and fallback window status all derive from `VoiceSessionCoordinator` state changes. Linux keeps one authoritative recording lifecycle and does not fork a second UI-only state model.
- **D-06:** If the overlay cannot be presented in a given desktop environment, recording still proceeds and the degraded feedback path is tray/fallback status text rather than a broken session.

### Transcript Delivery

- **D-07:** Normal successful completion should deliver text automatically instead of opening the modal transcript dialog used in Phase 3. The daily path is background completion, not review-first.
- **D-08:** Clipboard delivery is the baseline completion mode. Linux should write the finished transcript immediately with platform clipboard tools and only surface manual copy/review UI when delivery fails or when the user explicitly asks to inspect the result.
- **D-09:** Direct insert remains opt-in and best-effort. When the current environment supports insertion at the cursor, Linux may attempt it; on unsupported environments or insertion failures, the same transcript falls back to clipboard with clear status messaging.

### Agent's Discretion

- Exact hotkey backend split between X11, portals, and any adapter abstractions
- The Linux floating-indicator window/widget implementation details
- How completion/failure messaging is surfaced after automatic clipboard or direct-insert delivery
- Whether manual transcript review lives in the tray menu, a notification action, or another lightweight affordance

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Roadmap And Requirements

- `.planning/ROADMAP.md` — Phase 4 goal, success criteria, and milestone ordering
- `.planning/PROJECT.md` — Linux near-parity, offline-first, and platform-fidelity constraints
- `.planning/REQUIREMENTS.md` — DICT-01, DICT-02, DICT-03, DICT-06, and DICT-07 acceptance targets
- `.planning/STATE.md` — current milestone status and outstanding Linux concerns

### Prior Phase Outputs

- `.planning/phases/02-linux-shell-settings/02-CONTEXT.md` — Linux shell decisions for tray fallback, best-effort hotkeys, and settings persistence
- `.planning/phases/03-linux-offline-transcription/03-01-SUMMARY.md` — runtime/bootstrap decisions that Phase 4 builds on
- `.planning/phases/03-linux-offline-transcription/03-02-SUMMARY.md` — model-management decisions already validated for Linux
- `.planning/phases/03-linux-offline-transcription/03-03-SUMMARY.md` — current Linux voice-session and transcript-result behavior
- `.planning/phases/03-linux-offline-transcription/03-HUMAN-UAT.md` — partial UAT coverage that should inform Phase 4 risk handling

### Existing Linux Implementation

- `shared/ui-shell/src/linuxX64Main/kotlin/tech/watzon/pindrop/shared/ui/shell/linux/LinuxCoordinator.kt` — current Linux lifecycle, tray/fallback wiring, and voice-session integration point
- `shared/ui-shell/src/linuxX64Main/kotlin/tech/watzon/pindrop/shared/ui/shell/linux/transcription/LinuxVoiceSessionFactory.kt` — current `VoiceSessionCoordinator` composition, output-mode mapping, and direct-insert support flag
- `shared/ui-shell/src/linuxX64Main/kotlin/tech/watzon/pindrop/shared/ui/shell/linux/transcription/LinuxTranscriptDialog.kt` — current manual transcript review/copy behavior to replace or demote
- `shared/ui-shell/src/linuxX64Main/kotlin/tech/watzon/pindrop/shared/ui/shell/linux/settings/HotkeysSettingsPage.kt` — existing Linux shortcut settings UI and Wayland guidance text
- `shared/ui-shell/src/linuxX64Main/kotlin/tech/watzon/pindrop/shared/ui/shell/linux/settings/OutputSettingsPage.kt` — existing Linux output and floating-indicator settings surface
- `shared/ui-shell/src/linuxX64Main/kotlin/tech/watzon/pindrop/shared/ui/shell/linux/TrayMenu.kt` — tray command surface that will need recording/output status updates

### Shared And macOS Reference Behavior

- `shared/feature-transcription/src/commonMain/kotlin/tech/watzon/pindrop/shared/feature/transcription/VoiceSessionCoordinator.kt` — authoritative recording state machine and output event flow
- `Pindrop/AppCoordinator.swift` — reference hotkey lifecycle, conflict handling, and recording orchestration on macOS
- `Pindrop/Services/HotkeyManager.swift` — existing hotkey semantics and binding expectations
- `Pindrop/Services/OutputManager.swift` — output delivery semantics and clipboard/direct-insert reference behavior
- `Pindrop/UI/FloatingIndicator.swift` — macOS floating-indicator state contract
- `Pindrop/UI/Settings/HotkeysSettingsView.swift` — reference UX for shortcut configuration
- `Pindrop/UI/Settings/FloatingIndicatorSettingsCard.swift` — reference UX for indicator settings and offsets

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets

- **`LinuxCoordinator`** already owns tray, fallback window, onboarding, settings, and voice-session startup. It is the right composition point for hotkey registration and recording feedback updates.
- **`LinuxVoiceSessionFactory`** already builds `VoiceSessionCoordinator` with Linux audio capture and settings-backed output mode, so Phase 4 should extend that assembly rather than adding a second recording service.
- **`HotkeysSettingsPage`** and **`OutputSettingsPage`** already expose the user-facing settings needed for this phase, including toggle/PTT keys, output mode, and floating-indicator preferences.
- **`TrayMenu`** and **`TrayFallback`** already provide non-hotkey recording controls that can remain as capability fallbacks.

### Established Patterns

- Linux shell work stays inside existing KMP modules and `linuxX64Main` source sets rather than adding a standalone Linux app module.
- Desktop capability differences are handled with best-effort adapters plus explicit user messaging, not hard blockers. Phase 2 already established that pattern for Linux hotkeys.
- Recording lifecycle should stay anchored on shared `VoiceSessionCoordinator` events. UI surfaces subscribe to state changes; they do not invent new session rules.

### Integration Points

- Hotkey runtime plugs into `LinuxCoordinator` startup/shutdown and updates the existing tray/fallback command surfaces.
- Floating feedback plugs into the same session-state callbacks already used for tray status updates in `LinuxCoordinator`.
- Clipboard/direct-insert delivery plugs into `LinuxVoiceSessionFactory` output ports and whatever Linux output adapter replaces the current in-memory clipboard stub.

</code_context>

<specifics>
## Specific Ideas

- Keep the transcript dialog available only as a fallback or debug affordance, not the default success path.
- Surface shortcut capability clearly in Linux settings so users can tell whether toggle and push-to-talk are currently bound.
- Prefer a small always-on-top overlay for recording feedback instead of a full review window, keeping the Linux loop fast and close to the macOS feel.

</specifics>

<deferred>
## Deferred Ideas

- Linux history review and search belong to Phase 5.
- Linux dictionary cleanup and AI enhancement workflows belong to Phase 5.
- Packaged distro-specific install work belongs to Phase 6.

</deferred>

---

*Phase: 04-linux-capture-output-loop*
*Context gathered: 2026-03-29*

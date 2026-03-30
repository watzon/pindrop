---
phase: 04-linux-capture-output-loop
status: complete
created: 2026-03-29
updated: 2026-03-29
requirements: [DICT-01, DICT-02, DICT-03, DICT-06, DICT-07]
---

# Phase 04 Research — Linux Capture & Output Loop

## Question

What does Phase 04 need so Linux can support configurable hotkeys, active-recording feedback, clipboard-first transcript delivery, and best-effort direct insert without forking the existing voice-session lifecycle?

## Current Baseline

- `LinuxCoordinator` already owns the shell lifecycle, tray/fallback UI, and one long-lived `LinuxVoiceSessionHandle`.
- `VoiceSessionCoordinator` is already the authoritative dictation state machine and already supports toggle-style `startRecording()` / `stopRecording()`, `VoiceOutputMode`, and transcript-ready/error callbacks.
- Linux currently uses an in-memory clipboard stub plus `LinuxTranscriptDialog`, so Phase 03 proves the recording path but not the real delivery path.
- Linux hotkey settings exist in `HotkeysSettingsPage`, but no runtime registration path exists yet.
- Output settings already persist output mode and floating-indicator preferences, so Phase 04 should consume existing keys instead of inventing new ones.

## Research Findings

### 1. Global hotkeys should use a capability-based adapter, not a single Linux-only mechanism

**Why:** user decision D-01 locks a best-effort runtime with capability detection.

Recommended adapter split:

1. **X11 backend** — native X11/XGrabKey-style registration for sessions running under X11.
2. **Wayland portal backend** — `org.freedesktop.portal.GlobalShortcuts` when the desktop portal/backend supports it.
3. **Unavailable backend** — explicit disabled adapter returning binding failures + guidance text.

Why portal support is worth planning for:

- Official `org.freedesktop.portal.GlobalShortcuts` supports `CreateSession`, `BindShortcuts`, `ListShortcuts`, plus `Activated` and `Deactivated` signals.
- `Activated` + `Deactivated` map directly onto Phase 04’s two modes:
  - **toggle** → trigger on `Activated`
  - **push-to-talk** → start on `Activated`, stop on `Deactivated`

Important constraint:

- Portal bindings are user-mediated and compositor/backend dependent. They are not guaranteed on every Wayland session.
- Therefore binding failures must stay non-fatal and feed UI status back into tray/settings/fallback surfaces per D-03.

### 2. Reuse `VoiceSessionCoordinator` state instead of adding Linux-local recording state

The current shared coordinator already emits:

- `STARTING`
- `RECORDING`
- `PROCESSING`
- `COMPLETED`
- `ERROR`

This is sufficient for:

- tray menu enable/disable state
- fallback status text
- floating indicator visibility/content
- completion/failure messaging

So Phase 04 should add Linux shell observers and output ports around existing events, not a second Linux recording model. This directly satisfies D-05.

### 3. Floating indicator should be a lightweight GTK window layered over the shell

Recommended approach:

- Create a tiny undecorated GTK window owned by `LinuxCoordinator`.
- Show it only for `STARTING`, `RECORDING`, and `PROCESSING`.
- Hide it for `IDLE`, `COMPLETED`, and terminal `ERROR` states.
- Read `SettingsKeys.floatingIndicatorEnabled`, `floatingIndicatorType`, `pillFloatingIndicatorOffsetX`, and `pillFloatingIndicatorOffsetY` for placement/styling.
- If the window cannot be shown on a given compositor/session, keep recording active and degrade to tray/fallback text only per D-06.

This keeps parity with macOS’s “authoritative runtime state drives indicator UI” pattern without porting AppKit-specific behavior.

### 4. Clipboard delivery should replace the transcript dialog’s ad-hoc command logic with a reusable Linux output port

Current Linux transcript copy already tries:

- `wl-copy`
- `xclip -selection clipboard`
- `xsel --clipboard --input`

That command chain is useful, but it lives in `LinuxTranscriptDialog` instead of the voice-session runtime.

Recommended Phase 04 change:

- Extract command-based clipboard writing into a reusable Linux clipboard/output adapter.
- Use that adapter as the `ClipboardPort` passed into `VoiceSessionCoordinator`.
- Keep transcript dialog/manual copy only as failure/review fallback, not the default success path.

Why this is the best near-term fit:

- It reuses already-proven command choices from the repo.
- It preserves clipboard-first completion (D-08) without requiring large GTK clipboard refactors first.
- It lets the shell surface failure status if no clipboard tool is available.

### 5. Direct insert should be best-effort and command-backed, with clipboard always written first

Direct insert on Linux is the most environment-fragile requirement in this phase.

Recommended support matrix:

- **X11:** prefer `xdotool`-style typed/paste automation if present.
- **Wayland (wlroots/compositors exposing virtual-keyboard support):** allow `wtype` if present.
- **Do not choose `ydotool` as the primary path** — it requires `ydotoold`, `/dev/uinput`, and often elevated/system configuration, which conflicts with a smooth packaged first-class app default.

Delivery rule:

1. Always copy transcript to clipboard first.
2. If output mode is direct insert and a supported inserter is available, attempt insertion.
3. On any unsupported environment, missing command, or insertion failure, keep clipboard content and emit a clear fallback message.

This matches D-09 and mirrors macOS `OutputManager` semantics: clipboard is the reliable floor; direct insertion is an optimization.

### 6. Hotkey state must surface back into Linux UI, not live invisibly

Because settings already persist desired hotkeys, Phase 04 should add runtime binding status objects with fields like:

- requested binding text
- active/inactive state
- backend used (`x11`, `portal`, `unavailable`)
- failure reason/guidance

Those statuses should drive:

- tray status or menu labels
- fallback window guidance
- settings reopen summaries/badges

This is necessary to satisfy D-02 and D-03: users must see whether toggle/PTT are actually active.

## Recommended Architecture

### A. Add Linux runtime adapters around existing shared contracts

Add Linux shell adapters rather than changing the app shape:

- `LinuxHotkeyManager` / `LinuxHotkeyBackend` abstraction
- `LinuxClipboardPort` for command-backed clipboard writes
- `LinuxDirectInsertPort` / `LinuxOutputPort` for command-backed insertion + fallback reason reporting
- `LinuxFloatingIndicator` presenter owned by `LinuxCoordinator`

### B. Make `LinuxVoiceSessionFactory` the assembly point for output capability

`LinuxVoiceSessionFactory` should stop using `InMemoryClipboardPort()` and instead compose:

- real clipboard port
- direct-insert capability flag
- optional output strategy wrapper if direct insert needs Linux-only orchestration

This keeps completion behavior aligned with the shared coordinator and avoids pushing shell-only output logic into unrelated UI files.

### C. Keep `LinuxCoordinator` as the shell integration point

`LinuxCoordinator` should own:

- hotkey backend startup/shutdown
- state-to-indicator mirroring
- tray/fallback status updates
- completion/failure messaging surface

It should **not** own transcript transformation or duplicate record/stop logic already in `VoiceSessionCoordinator`.

## Don’t Hand-Roll / Avoid

- **Do not add a second Linux-only recording state machine.** Reuse `VoiceSessionCoordinator` state.
- **Do not make hotkeys a hard startup requirement.** Use disabled/unavailable backends with messaging.
- **Do not make `ydotool` the main insertion plan.** Root/daemon/uinput requirements are too heavy.
- **Do not keep transcript dialog as the primary success path.** That conflicts with D-07 and D-08.
- **Do not bypass existing settings keys.** `toggleHotkey`, `pushToTalkHotkey`, `outputMode`, and floating-indicator keys already exist.

## Common Pitfalls

1. **Portal-only assumption**
   - Not every Wayland desktop exposes a usable GlobalShortcuts backend.
   - Mitigation: capability detector + unavailable backend.

2. **Treating direct insert as guaranteed**
   - Linux desktop integration varies too much across X11/Wayland/compositors.
   - Mitigation: clipboard first, insert second, explicit fallback messaging.

3. **Binding hotkeys only in settings UI**
   - Persisted preference does not mean active runtime registration.
   - Mitigation: separate desired binding from active binding status.

4. **Indicator failures breaking dictation**
   - Overlay windows can fail or behave differently on some compositors.
   - Mitigation: indicator presenter must fail open and leave tray/fallback updates intact.

5. **Planning Linux-shell compile verification on macOS**
   - GTK/AppIndicator/linuxX64 cinterop still requires a Linux host.
   - Mitigation: use JVM/common tests for shared logic on all hosts and reserve Linux compile/UAT for Linux-host/manual validation steps.

## Validation Architecture

### Fast feedback

- **Primary quick command:** `./gradlew :feature-transcription:jvmTest`
- **Expanded quick command:** `./gradlew :feature-transcription:jvmTest :runtime-transcription:jvmTest`
- **Linux-only compile gate:** `./gradlew :ui-shell:compileKotlinLinuxX64` on a Linux host

### What should be test-backed in this phase

1. `VoiceSessionCoordinator` behavior for clipboard/direct-insert fallback messages and failure handling.
2. Any hotkey binding parser/status mapper that can be expressed as common or JVM-testable logic.
3. Linux output capability selection logic (command presence → supported mode/fallback reason) if extracted into pure Kotlin helpers.

### What remains manual/Linux-host only

- real portal/X11 hotkey registration
- real floating-indicator presentation on target desktops
- real clipboard/direct-insert command execution in a Linux desktop session
- tray/fallback UI messaging in GNOME/KDE/Wayland/X11 environments

## Planning Implications

The cleanest Phase 04 split is:

1. **Hotkey runtime + binding status**
2. **Floating indicator + shell state mirroring**
3. **Real clipboard/direct-insert delivery path replacing transcript-dialog default flow**

That keeps file ownership mostly separate while still respecting the shared dependency point in `LinuxCoordinator` and `LinuxVoiceSessionFactory`.

## Recommended Plan Constraints

- Every plan should explicitly reference D-01 through D-09 where relevant.
- At least one plan should include Linux-host human verification because hotkeys and overlay behavior cannot be fully proven on macOS.
- The transcript dialog should be retained only as fallback/debug/manual-review UI, not removed outright in this phase.

---

Research complete for Phase 04.

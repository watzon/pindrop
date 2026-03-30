# Phase 4 UI Contract: Linux Capture & Output Loop

**Phase:** 04-linux-capture-output-loop
**Created:** 2026-03-29
**Status:** Ready for planning
**Requirements covered:** DICT-01, DICT-02, DICT-03, DICT-06, DICT-07

## Purpose

Define the user-facing Linux UI contract for Phase 4 so implementation can extend the existing GTK shell without inventing a second recording state model or regressing the Phase 3 recording flow.

This contract covers:

1. Global shortcut-driven dictation for toggle and push-to-talk
2. Visible active-recording feedback during recording and stop/transcribe transitions
3. Automatic clipboard delivery after successful dictation
4. Best-effort direct insert with explicit clipboard fallback messaging

This contract does not cover history, dictionary cleanup, AI enhancement, notes, or Linux packaging.

## Canonical Inputs

- `.planning/phases/04-linux-capture-output-loop/04-CONTEXT.md`
- `.planning/ROADMAP.md`
- `.planning/PROJECT.md`
- `.planning/REQUIREMENTS.md`
- `.planning/phases/03-linux-offline-transcription/03-03-SUMMARY.md`

## Product Intent

Phase 3 proved that Linux can record, transcribe, and present transcript results in-app. Phase 4 changes the default daily loop from review-first to delivery-first.

The Linux user should be able to:

1. Start dictation quickly without opening settings or a review window
2. Understand whether recording is active from lightweight system-level feedback
3. Receive output automatically on completion
4. Understand when the environment degraded to clipboard fallback instead of direct insert

## UX Principles

1. One recording state machine: all surfaces mirror `VoiceSessionCoordinator` state and never maintain competing UI-only recording truth.
2. Delivery-first completion: successful dictation should not open a transcript review dialog by default.
3. Best-effort desktop integration: hotkeys, floating overlay, and direct insert can degrade, but recording itself must remain usable.
4. Explicit capability messaging: when Linux environment support is limited, show that clearly in settings and fallback status surfaces.
5. Preserve existing entry points: tray and tray-less fallback controls remain available even when global shortcuts fail.

## UI Surfaces In Scope

### 1. Tray Menu

Phase 4 tray behavior must expose:

1. `Start Recording`
2. `Stop Recording`
3. Shortcut capability/status row or label for toggle and push-to-talk
4. Existing `Settings`, `Launch at Login`, `About Pindrop`, and `Quit`

Tray state rules:

1. `Start Recording` is enabled only when session state allows recording.
2. `Stop Recording` is enabled only while recording is active or a push-to-talk session is being held.
3. Tray label/status must reflect degraded hotkey support when bindings fail.
4. Completion should not open the transcript dialog for the normal success path.

### 2. Tray Fallback Window

The tray-less fallback window remains the non-hotkey recovery path.

Phase 4 fallback behavior must expose:

1. Current status text
2. `Start Recording` button
3. `Stop Recording` button
4. `Settings`
5. `Quit`

Fallback state rules:

1. Status text mirrors shared session events and hotkey degradation messages.
2. Recording controls follow the same enabled-state contract as tray controls.
3. If tray is unavailable and hotkeys are unavailable, this window becomes the primary recovery surface.

### 3. Hotkeys Settings Page

The existing hotkeys page remains the configuration surface for:

1. Toggle hotkey
2. Push-to-talk hotkey
3. Copy-last-transcript hotkey if already present

Phase 4 additions to the contract:

1. Show per-hotkey runtime status: `Active`, `Unavailable`, or `Not Bound`
2. Show environment guidance when the current session does not support a requested binding
3. Distinguish configuration from activation: a saved hotkey can exist even if runtime binding failed

Required copy intent:

1. X11 or supported Wayland path available: communicate that shortcuts are active
2. Unsupported Wayland/compositor path: communicate that tray/fallback controls are still available
3. Bind conflict or registration failure: communicate that the app remains usable without hotkeys

### 4. Output Settings Page

The existing output settings page remains the configuration surface for:

1. Output mode: `Clipboard` or `Direct Insert`
2. Floating indicator enabled/disabled
3. Floating indicator style
4. Existing offset settings where applicable

Phase 4 additions to the contract:

1. Direct insert must be labeled as best-effort
2. When direct insert is selected, communicate that clipboard fallback will be used if unsupported
3. Floating indicator controls affect only visibility/style of the overlay, not session state

### 5. Floating Recording Indicator

Phase 4 introduces a lightweight floating indicator that appears only while the session is active.

Indicator contract:

1. Appears during `STARTING`, `RECORDING`, and `PROCESSING`
2. Hides during `IDLE`, `COMPLETED`, and `ERROR`
3. Never blocks recording if the environment cannot present it
4. Uses a compact, non-review UI intended for glanceable state only

Indicator content by state:

1. `STARTING`: show starting copy such as `Starting microphone capture...`
2. `RECORDING`: show active capture copy such as `Recording...`
3. `PROCESSING`: show completion/transcription copy such as `Transcribing locally...`

Indicator non-goals:

1. No transcript review/editing
2. No persistent history affordance
3. No secondary recording controls required in the overlay

### 6. Transcript Review Surface

The Phase 3 transcript dialog is demoted from default success UI to fallback/debug/manual review UI.

Transcript dialog rules in Phase 4:

1. Do not show on normal successful clipboard delivery
2. Do not show on normal successful direct insert
3. May be shown when clipboard delivery fails and manual recovery is needed
4. May be exposed later as an explicit user action such as `Review Last Transcript`, but that action is optional in this phase

## Interaction Contracts

### A. Toggle Recording Flow

1. User presses configured toggle hotkey
2. App starts recording if idle
3. Indicator appears and tray/fallback state updates
4. User presses the same toggle hotkey again
5. App stops recording and enters processing
6. On success, transcript is delivered automatically
7. UI shows a brief completion/fallback status message without forcing a review dialog

Failure/degraded behavior:

1. If toggle hotkey binding is unavailable, tray/fallback controls remain available
2. If start fails, show explicit error state in fallback/tray status surfaces

### B. Push-to-Talk Flow

1. User holds configured push-to-talk shortcut
2. App begins recording while the key is held
3. Indicator appears and tray/fallback state updates
4. Releasing the shortcut stops recording and begins processing
5. On success, transcript is delivered automatically

Failure/degraded behavior:

1. If push-to-talk cannot be bound, show `Unavailable` state in settings and keep other entry points usable
2. Push-to-talk failure must not disable toggle recording or tray controls

### C. Clipboard Delivery Flow

1. Transcription finishes successfully
2. App copies transcript to system clipboard immediately
3. App shows completion status such as `Copied transcript to the clipboard.`
4. No transcript dialog appears by default

Failure/degraded behavior:

1. If clipboard write fails, surface explicit failure status
2. Manual review/copy UI may be used for recovery

### D. Direct Insert Flow

1. User selects `Direct Insert` in output settings
2. Transcription finishes successfully
3. App attempts insertion at the current cursor location when the environment supports it
4. If insertion succeeds, app may still keep clipboard populated, but success messaging should prioritize inserted output
5. If insertion is unsupported or fails, app copies transcript to clipboard and communicates fallback clearly

Required fallback message intent:

1. `Direct insert unavailable. Copied transcript to the clipboard instead.`

## State Model Contract

All UI surfaces derive from `VoiceSessionCoordinator` state.

| Shared state | Tray/Fallback | Floating Indicator | Delivery expectation |
|-------------|---------------|--------------------|----------------------|
| `IDLE` | Start enabled, Stop disabled | Hidden | None |
| `STARTING` | Start disabled, Stop disabled or guarded | Visible | None |
| `RECORDING` | Start disabled, Stop enabled | Visible | None |
| `PROCESSING` | Start disabled, Stop disabled | Visible | Pending clipboard/direct insert |
| `COMPLETED` | Return to idle controls | Hidden | Completion/fallback message only |
| `ERROR` | Return to recoverable controls when possible | Hidden | Explicit error message |

## Capability States

Phase 4 requires runtime capability reporting for three platform-sensitive areas.

### Hotkeys

Per binding, one of:

1. `Active`
2. `Unavailable in this environment`
3. `Failed to bind`
4. `Not configured`

### Floating Indicator

One of:

1. `Enabled and available`
2. `Enabled but unavailable in this environment`
3. `Disabled by user`

### Direct Insert

One of:

1. `Available`
2. `Unavailable; clipboard fallback will be used`

## Copy Contract

User-visible copy does not need exact final wording here, but must preserve these meanings:

1. Recording start: clear capture start message
2. Recording active: clear active recording message
3. Processing: clear local transcription-in-progress message
4. Clipboard success: transcript copied successfully
5. Direct insert degraded: direct insert unavailable, clipboard fallback used
6. Hotkey degradation: shortcut unavailable, tray/fallback still usable
7. Delivery failure: transcript completed but automatic delivery failed

## Accessibility And Desktop Behavior

1. All critical actions remain reachable without global hotkeys.
2. Floating indicator must be glanceable and transient, not a new primary window.
3. Status messaging must appear somewhere visible even when tray support is absent.
4. Desktop environment limitations must be explained in settings rather than hidden.

## Acceptance Criteria

This UI contract is satisfied when all of the following are true:

1. Linux exposes toggle and push-to-talk as configurable runtime-bound shortcuts with visible status.
2. Linux shows lightweight active-recording feedback while dictation is starting, recording, or processing.
3. Successful dictation delivers transcript through clipboard automatically by default without opening the transcript dialog.
4. Direct insert is explicitly opt-in and degrades to clipboard with clear user messaging when unsupported.
5. Tray and tray-less fallback controls remain usable when hotkeys or overlay presentation are unavailable.
6. All stateful UI behavior derives from the existing shared voice-session lifecycle rather than a second Linux-only state machine.

## Implementation Notes For Planning

Recommended plan split for Phase 4:

1. Plan 04-01: hotkey runtime, capability detection, and settings/tray status wiring
2. Plan 04-02: floating indicator and state-driven feedback surfaces
3. Plan 04-03: automatic clipboard delivery, direct insert attempt path, and transcript-dialog demotion

## Out Of Scope For This Phase

1. Transcript history UI
2. Search/recovery workflows
3. Dictionary cleanup workflows
4. AI enhancement flows
5. Linux packaging/distribution

---

*Artifact: UI contract for Phase 04-linux-capture-output-loop*

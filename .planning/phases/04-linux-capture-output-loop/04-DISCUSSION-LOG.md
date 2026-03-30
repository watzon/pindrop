# Phase 4: Linux Capture & Output Loop - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in `04-CONTEXT.md`.

**Date:** 2026-03-29
**Phase:** 04-linux-capture-output-loop
**Areas discussed:** Shortcut activation, recording feedback, transcript delivery, direct insertion fallback

---

## Shortcut Activation

| Option | Description | Selected |
|--------|-------------|----------|
| X11 only | Support global shortcuts only where `XGrabKey` is available | |
| Best-effort multi-environment | Support X11 and supported Wayland portal bindings behind one capability-aware runtime | ✓ |
| No global shortcuts | Keep tray and fallback window only | |

**User's choice:** Best-effort multi-environment
**Notes:** Auto-selected recommended option. Matches Phase 2 guidance: support Linux capability variance without blocking the core app.

---

## Recording Feedback

| Option | Description | Selected |
|--------|-------------|----------|
| Tray status only | Reuse tray/fallback labels without adding an overlay | |
| Floating overlay plus tray status | Show active recording visually while keeping tray/fallback updates in sync | ✓ |
| Review dialog while recording | Use a larger window to show state and transcript progress | |

**User's choice:** Floating overlay plus tray status
**Notes:** Auto-selected recommended option. Best fits DICT-03 and reuses existing floating-indicator settings already present in Linux settings.

---

## Transcript Delivery

| Option | Description | Selected |
|--------|-------------|----------|
| Modal transcript dialog | Keep review-first completion from Phase 3 | |
| Automatic clipboard delivery | Finish in the background and put the text on the clipboard immediately | ✓ |
| Save-only history flow | Defer transcript retrieval until Phase 5 history exists | |

**User's choice:** Automatic clipboard delivery
**Notes:** Auto-selected recommended option. Aligns with DICT-06 and makes the Linux loop suitable for daily use without an extra modal step.

---

## Direct Insertion Fallback

| Option | Description | Selected |
|--------|-------------|----------|
| Skip direct insert in Phase 4 | Clipboard only for all Linux environments | |
| Best-effort direct insert with clipboard fallback | Attempt insertion where supported and fall back cleanly everywhere else | ✓ |
| Require direct insert support | Treat unsupported environments as incomplete | |

**User's choice:** Best-effort direct insert with clipboard fallback
**Notes:** Auto-selected recommended option. Matches DICT-07 and keeps Linux environment differences visible without turning them into fatal errors.

---

## the agent's Discretion

- Exact hotkey backend and adapter boundaries
- Linux overlay widget/window implementation
- Completion messaging surface for clipboard/direct-insert success or fallback

## Deferred Ideas

- None added during auto discussion

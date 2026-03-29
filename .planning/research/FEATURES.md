# Feature Landscape

**Domain:** Linux-first native desktop dictation app with near-macOS parity for Pindrop
**Researched:** 2026-03-29
**Overall confidence:** MEDIUM

## Scope Lens

This file answers a narrow product question: **when a mature macOS dictation app expands to Linux, which features are mandatory for daily-use parity versus nice-to-have differentiation?**

The bar is not “Linux demo works.” The bar is **a Linux user can install Pindrop, leave it running in the tray, trigger dictation from anywhere, get reliable text output, manage models, review history, optionally enhance text with AI, and trust that the app behaves like a real native background utility.**

## Expected Linux v1 Parity Boundary

### Must feel materially equivalent to macOS for:

- App lives primarily in the **tray/background**, not as a foreground-only windowed app
- **Global hotkey** dictation from anywhere
- **Toggle** and **push-to-talk** recording flows
- **Floating recording indicator** / obvious recording state
- **Local transcription** with downloadable model management
- **Clipboard-first output**, with direct insertion where Linux platform support allows it
- **History + search** for previous dictations
- **Optional AI enhancement** after transcription
- **Auto-start on login**
- **Localized UI** sourced from the same shared catalog/logic where possible

### Acceptable Linux v1 gaps relative to macOS:

- **Notes parity is deferred**
- **Video/media transcription extras are deferred**
- **Direct insertion may be less universal than macOS** because Linux desktop/session security and app compatibility vary
- **Desktop-environment-specific polish can be narrower** as long as GNOME/KDE/common Wayland/X11 paths are covered well enough for the core loop

---

## Table Stakes

Features users will expect immediately. Missing any of the first eight materially weakens Linux v1.

| Feature | Why Expected | Complexity | Dependencies / Notes |
|---------|--------------|------------|----------------------|
| Background tray app entry point | A dictation tool must be launchable, discoverable, and controllable without living in the taskbar/full window. Linux users expect a desktop utility to minimize to tray/status area when it is always-on. | Med | Requires native tray/status notifier integration and sane behavior when no main window is open. |
| Global hotkey from anywhere | This is the core trigger for dictation. If users must focus the app first, the product stops feeling like dictation software. | High | Must support configurable shortcuts, conflict handling, and reliable behavior across desktop/session variations. |
| Toggle mode + push-to-talk | Mature dictation products are expected to support both “press once to start/stop” and “hold to talk.” Different users depend on different muscle memory. | Med | Depends on hotkey infrastructure and clear recording state transitions. |
| Clear recording state via floating indicator | Users need immediate feedback that the microphone is live. Without it, trust drops and accidental recordings increase. | Med | Floating indicator should be visible without stealing focus; ideally lightweight and always-on-top where permitted. |
| Local transcription with first-run model download | Pindrop’s value proposition is privacy-first, offline dictation. Linux v1 must preserve that rather than becoming a cloud-only port. | High | Needs engine/backend choice, model storage, download progress, failure states, and disk-space awareness. |
| Model management UI | Users expect to choose/download/remove models, see size/speed tradeoffs, and recover from missing/corrupt models. | Med | Required for onboarding and long-term maintenance of local transcription. |
| Fast “record → transcribe → output” loop | The whole point is fast daily dictation. A user should be able to trigger, speak, stop, and immediately use the result. | High | Depends on audio capture, transcription orchestration, output, and sensible defaults. |
| Clipboard output by default | Clipboard is the most portable Linux output path and the safest baseline for near-parity text delivery. | Low | Should work even when direct insertion is unavailable or disabled. |
| Direct text insertion when possible | Mature dictation apps are expected to insert text at the cursor, but on Linux this is a “best effort with guardrails” feature rather than an absolute guarantee. | High | Must be capability-aware; degrade to clipboard cleanly instead of failing silently. |
| History of past dictations | Users expect to recover text they dictated five minutes ago. Without history, transcription mistakes and accidental overwrites are far more painful. | Med | Local persistence required; should work offline. |
| Search across history | Once history exists, search becomes table stakes quickly. Otherwise history becomes a junk drawer. | Med | Depends on local indexing/query support and good result metadata. |
| AI enhancement as an optional post-process | For Pindrop specifically, Linux parity means users can clean up raw transcripts similarly to macOS, but it must remain optional and off by default. | Med | Separate from core transcription; should not block offline use. |
| AI provider configuration + secure credential storage | If AI enhancement exists, users expect endpoint/model/key configuration and secure storage rather than plaintext settings. | Med | Native Linux secret storage may vary; fallback behavior must be explicit. |
| Auto-start on login | A tray dictation app that must be opened manually every boot feels unfinished. | Med | Should use standard XDG autostart behavior and be user-toggleable. |
| Permission / prerequisite onboarding | Linux does not have one universal permission model, so users need guided setup for microphone access, hotkeys, and any direct-input caveats. | Med | Must explain environment-specific limitations instead of pretending parity is universal. |
| Settings for language, output mode, hotkeys, and models | These are baseline controls for a daily dictation app, not advanced preferences. | Low-Med | Good defaults matter more than endless configuration. |
| Localized core UI strings | If macOS already ships localized UI, Linux support that forks or lags translations will feel second-class immediately. | Med | Should share string ownership/source-of-truth with macOS/KMP where practical. |
| Packaged installable Linux app | Near-parity means a real app artifact, not “clone repo and run Gradle.” Users expect installable binaries/packages. | High | Packaging/distribution is product work, not just build work. |

### Table-stakes behaviors that should be explicitly specified

1. **Cold start to first dictation** should be short and guided:
   - Launch app
   - Grant microphone / review prerequisites
   - Download a starter model
   - Set a hotkey
   - Dictate immediately

2. **Failure handling** must be first-class:
   - Missing model
   - Microphone unavailable
   - Hotkey conflict
   - AI endpoint/key invalid
   - Direct insertion unsupported in current environment

3. **Background behavior** must be trustworthy:
   - Closing the window does not quit unexpectedly
   - Tray menu exposes primary actions
   - Recording state is always obvious

---

## Differentiators

These are not the first reasons a Linux user tries Pindrop, but they are the reasons they may prefer it over a thinner Whisper wrapper.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Near-macOS workflow parity instead of “Linux-lite” | Most cross-platform voice tools ship a weaker Linux experience. Matching the same daily loop, settings concepts, and product language is itself a differentiator. | High | Important strategic differentiator for Pindrop specifically. |
| Privacy-first local default with optional AI cleanup | Users can stay fully local for transcription, then opt into AI cleanup only if they want polish. | Med | Strong product positioning; should be obvious in onboarding and settings. |
| Shared history/search semantics across macOS and Linux | If shared business logic produces the same sorting, filtering, and behavior across platforms, support burden drops and users switching machines get consistency. | Med | More architectural than flashy, but very valuable. |
| Custom dictionary / vocabulary replacement | This materially improves real-world dictation accuracy for names, jargon, and repeated phrases. | Med | Strong daily-use differentiator after baseline parity lands. |
| Prompt presets / configurable AI cleanup style | Lets users choose between terse cleanup, email polish, punctuation normalization, etc. | Med | Valuable for professional use without changing the core transcription engine. |
| Strong model UX instead of “download files manually” | Presenting model size, speed, disk impact, and recommendation logic makes local inference approachable. | Med | A polished model manager is a real product differentiator. |
| Cross-platform localization from one shared source | Prevents Linux from becoming the neglected translation fork and makes future Windows support easier. | High | Differentiator mostly in team efficiency and long-term quality. |
| Desktop-utility polish across tray + indicator + startup | Linux users notice when always-running utilities feel bolted on. Smooth tray behavior, autostart, and visible recording state create trust. | Med-High | Not novel, but differentiating in execution quality. |

### Good differentiators for post-v1 or late-v1 if capacity allows

- Export/search filtering improvements in history
- Better onboarding diagnostics for Linux environments
- Smarter output post-processing (punctuation cleanup, formatting presets)
- More than one local backend if it improves hardware coverage without fragmenting UX

---

## Anti-Features

Things to deliberately **not** build for Linux v1, even if they sound attractive.

| Anti-Feature | Why Avoid | What to Do Instead |
|--------------|-----------|-------------------|
| Full notes-system parity | Project scope already defers notes for Linux v1. It adds substantial UI/persistence surface without being required for the core dictation loop. | Keep transcription history strong; add notes later as a separate milestone. |
| Video/media transcription parity | This expands the product from desktop dictation into broader media workflows and will dilute focus. | Ship best-in-class live dictation first. |
| Cloud account/sync requirements | This cuts against Pindrop’s privacy-first/offline positioning and adds auth, sync conflict, and data-policy complexity. | Keep Linux v1 local-first. |
| Plugin ecosystem / scripting API | Attractive for power users, but premature before the core Linux behavior is stable across environments. | Expose a small, polished settings surface first. |
| Desktop-environment-specific feature branches | Separate GNOME-only, KDE-only, and compositor-specific UX branches will explode maintenance early. | Build around common XDG/native abstractions; document known limitations. |
| Over-optimizing on rare advanced transcription features | Streaming partials, diarization, context capture, media pausing, etc. can become rabbit holes. | Hold the line on the daily record/transcribe/output loop unless a feature clearly improves that loop. |
| Massive settings surface at launch | Linux apps often drift into configuration bloat. A dictation tool should feel fast and comprehensible. | Provide sane defaults plus only the settings that unblock actual workflows. |

---

## Feature Dependencies

```text
Packaged app → Tray/background entry point → Onboarding → Model download → Global hotkey

Global hotkey → Recording modes (toggle / push-to-talk) → Floating indicator → Transcription → Output

Local transcription + model management → Core daily dictation loop

Core daily dictation loop → History persistence → History search

Core transcription result → Optional AI enhancement → Copy / insert final text

Shared localization source → Onboarding + settings + tray + history + AI UI parity

XDG autostart support → “always available” daily-use expectation
```

---

## MVP Recommendation for Linux v1 Requirements

Prioritize in this order:

1. **Always-available dictation loop**
   - Tray app
   - Global hotkey
   - Toggle + push-to-talk
   - Floating recording indicator
   - Clipboard-first output

2. **Offline transcription reliability**
   - First-run onboarding
   - Model download/manage/delete
   - Language/model settings
   - Clear missing-model and mic-error recovery

3. **Recovery and repeat use**
   - History persistence
   - Search history
   - Auto-start on login

4. **Near-parity polish**
   - Optional AI enhancement
   - Secure API credential handling
   - Shared localization pipeline and translated core UI

### Defer deliberately

- **Notes parity**: explicitly out of Linux v1 scope
- **Video/media transcription**: explicitly out of Linux v1 scope
- **Deep Linux-environment specialization**: only after common paths are stable
- **Non-core advanced workflows**: only after the base dictation loop feels boringly reliable

---

## Requirements Framing: What “table stakes” means for Pindrop Linux

For this project, a feature should be treated as **table stakes** if at least one of these is true:

1. Removing it makes Linux feel like a downgrade from the current macOS product’s daily loop
2. Users cannot reasonably rely on the app as an always-available dictation utility without it
3. It is required to preserve Pindrop’s core promise: **native-feeling, privacy-first, local-first dictation**

That means **history/search, AI enhancement, model management, hotkeys, tray behavior, floating indicator, autostart, and localization plumbing are not “extra polish” in this milestone**. They are part of the product bar for “near-macOS parity in daily use.”

---

## Confidence Notes

| Area | Confidence | Notes |
|------|------------|-------|
| Core dictation loop expectations | HIGH | Strongly supported by existing Pindrop product definition and the nature of desktop dictation workflows. |
| Linux tray/autostart/localization expectations | MEDIUM | Supported by Freedesktop/XDG standards, but UX details vary by desktop environment. |
| Differentiator prioritization | MEDIUM | Product-strategy judgment based on current scope and existing Pindrop positioning. |
| Anti-feature boundaries | HIGH | Directly supported by current project out-of-scope statements. |

## Sources

- Pindrop project brief: `/Users/watzon/Projects/personal/pindrop/.planning/PROJECT.md` — HIGH
- Pindrop README: `/Users/watzon/Projects/personal/pindrop/README.md` — HIGH
- Freedesktop Desktop Application Autostart Specification: https://specifications.freedesktop.org/autostart-spec/latest/ — MEDIUM
- Freedesktop Desktop Entry Specification: https://specifications.freedesktop.org/desktop-entry-spec/latest-single/ — MEDIUM

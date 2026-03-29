# Project Research Summary

**Project:** Pindrop
**Domain:** Linux desktop expansion for a privacy-first native dictation app
**Researched:** 2026-03-29
**Confidence:** MEDIUM-HIGH

## Executive Summary

Pindrop Linux should be built as a **native Linux shell on top of a stronger Kotlin Multiplatform core**, not as a UI rewrite and not as a thin port of today’s macOS coordinator logic. The research is consistent on the shape: keep macOS native with SwiftUI/AppKit and WhisperKit, expand shared Kotlin ownership for deterministic product logic, and ship Linux with Compose Multiplatform Desktop plus Linux-specific adapters for tray, hotkeys, audio capture, autostart, packaging, and output behavior.

For Linux v1, the bar is not “transcription runs on Linux.” The bar is an always-available tray utility with global hotkeys, toggle and push-to-talk recording, a visible recording indicator, offline transcription with model management, clipboard-first output, history/search, optional AI enhancement, autostart, and shared localization. The recommended Linux transcription path is a packaged **whisper.cpp sidecar**, with PipeWire-oriented audio capture and Wayland-first desktop integration via XDG portals where possible.

The main delivery risk is sequencing. If the team starts with Linux UI parity before shared contracts, localization, and authoritative shared state machines are in place, Pindrop will ship two coordinators and two sets of business rules. The safe path is to first harden shared ports and state, migrate macOS onto those contracts, then build Linux persistence/localization/foundation, then the Linux dictation loop, then integration and packaging validation on real desktop environments.

## Key Findings

### Recommended Stack

The strongest direction is **Kotlin Multiplatform 2.3.20 + Compose Multiplatform Desktop 1.10.3** for Linux, while preserving the existing **SwiftUI/AppKit** macOS app. Shared Kotlin should take on domain models, workflow state, history/search semantics, settings/defaults, localization ownership, and orchestration policy. Linux-native integrations should stay behind narrow platform ports.

For Linux transcription and packaging, research points to **whisper.cpp v1.8.4** as the pragmatic offline ASR engine, ideally isolated as a sidecar process, with **SQLDelight 2.1.0** for new shared persistence domains and **moko-resources 0.26.1** as the shared localization source of truth. Linux desktop integration should be built around **XDG portals, D-Bus, PipeWire, StatusNotifier/AppIndicator behavior, and freedesktop packaging/autostart standards**.

**Core technologies:**
- **Kotlin Multiplatform 2.3.20**: shared product logic and contracts — best leverage from the repo’s existing KMP investment.
- **Compose Multiplatform Desktop 1.10.3**: Linux UI shell — Kotlin-first path with packaging support and lower maintenance than a second native toolkit.
- **whisper.cpp 1.8.4 sidecar**: Linux offline transcription — isolates native/runtime complexity from the JVM UI process.
- **SQLDelight 2.1.0**: shared persistence for new domains — typed SQLite that works cleanly across Linux and future Windows.
- **moko-resources 0.26.1**: shared localization — the most direct path to one string source for macOS and Linux.
- **dbus-java 5.2.x + XDG portals + PipeWire**: Linux integration layer — required for modern Wayland-first shortcuts, background behavior, and audio capture.

### Expected Features

Linux v1 table stakes cluster around one outcome: the app must behave like a trustworthy always-running dictation utility, not a foreground demo. That means the tray, hotkey, recording-state feedback, local model workflow, output fallback behavior, history, onboarding, and autostart are all part of the minimum product bar.

Differentiators should come from workflow parity and polish, not feature sprawl. Shared history/search semantics, privacy-first local defaults with optional AI cleanup, strong model UX, and one localization pipeline all strengthen the product without widening scope. Notes parity and media/video transcription should remain explicitly deferred.

**Must have (table stakes):**
- Tray/background app behavior — Linux v1 must feel always available.
- Global hotkey with toggle and push-to-talk — core dictation trigger.
- Floating recording indicator — recording state must be obvious.
- Local transcription with model download/manage/remove — preserves Pindrop’s offline value.
- Clipboard-first output with best-effort direct insertion — reliable baseline across Linux environments.
- History and search — recovery is part of daily use, not optional polish.
- Optional AI enhancement + secure credential handling — near-parity with current product expectations.
- Autostart, onboarding, settings, and shared localization — needed for repeatable daily use.

**Should have (competitive):**
- Near-macOS workflow parity rather than a reduced “Linux-lite” port.
- Strong model UX with recommendations and recovery paths.
- Shared history/search behavior across platforms.
- Prompt presets or configurable AI cleanup styles.
- Custom dictionary/vocabulary replacement once baseline parity is stable.

**Defer (v2+):**
- Notes parity.
- Video/media transcription extras.
- Deep desktop-environment-specific branches.
- Broader advanced transcription workflows that do not improve the core dictation loop.

### Architecture Approach

The recommended architecture is **shared core + native shells**. Shared Kotlin owns product rules, session and job state machines, model policy, history/search/filter logic, AI enhancement request shaping, settings schema, and localization resources. macOS remains a native shell. Linux becomes a separate native shell that consumes the same shared contracts but implements its own adapters for audio, transcription runtime, output insertion, hotkeys, tray, autostart, persistence, secrets, and packaging.

**Major components:**
1. **Shared Kotlin core** — domain models, policies, reducers/state machines, localization, repositories/interfaces.
2. **macOS native shell** — existing SwiftUI/AppKit app, WhisperKit path, SwiftData, Apple integrations.
3. **Linux native shell** — Compose app shell plus Linux adapters for portals, tray, PipeWire, output, secrets, and packaging.
4. **Linux transcription runtime** — whisper.cpp sidecar, model/runtime management, backend detection, filesystem rules.

### Critical Pitfalls

1. **Over-sharing platform shell behavior into Kotlin** — keep tray, windowing, hotkeys, recorder/runtime details, and autostart behind narrow platform ports.
2. **Keeping dual authority paths during migration** — for each migrated feature, pick one source of truth and remove Swift/Kotlin fallback drift.
3. **Treating Linux integration as uniform** — build a capability matrix for Wayland/X11, tray, shortcuts, direct insertion, and packaging constraints.
4. **Leaving packaging until the end** — test packaged `.deb`/`.rpm` builds early on Linux builders, not just IDE runs.
5. **Ignoring runtime environment around transcription** — define model paths, helper discovery, bundled assets, and packaged-app smoke tests up front.

## Implications for Roadmap

Based on research, suggested phase structure:

### Phase 1: Shared Contract Extraction and Foundation
**Rationale:** Everything else depends on authoritative ports, state machines, localization ownership, and a clean split from today’s AppCoordinator-heavy behavior.
**Delivers:** Shared ports for recording, transcription, persistence, output, hotkeys, secrets, localization, and autostart; initial shared state machines; localization source-of-truth decision.
**Addresses:** Shared localization, settings/defaults, model policy, parity preconditions.
**Avoids:** Over-sharing platform behavior; split localization authority.

### Phase 2: macOS Migration onto Shared Authority
**Rationale:** macOS should be the first consumer of the new architecture before Linux multiplies drift risk.
**Delivers:** macOS uses shared rules for history/search semantics, settings schema, enhancement policy, model selection, and localization contracts without changing native UX.
**Addresses:** Behavior parity and deletion of fallback logic.
**Avoids:** Dual authority between Swift and Kotlin.

### Phase 3: Linux Foundation Shell
**Rationale:** Linux needs persistence, localization, app boot, windows, and tray plumbing before the dictation loop can feel like a real product.
**Delivers:** Compose Linux shell, tray/background entry, onboarding shell, Linux persistence adapter, secrets adapter, localization consumption, basic settings/history surfaces.
**Uses:** Compose Desktop, SQLDelight, moko-resources, dbus-java.
**Implements:** Linux native shell and repository/adaptor layer.

### Phase 4: Linux Core Dictation Loop
**Rationale:** Once the shell exists, build the core daily workflow end to end before extra polish.
**Delivers:** Microphone capture, whisper.cpp sidecar integration, first-run model download/manage/delete, toggle/push-to-talk flows, floating indicator, clipboard-first output, history save.
**Addresses:** The essential daily-use parity bar.
**Avoids:** Shipping a Linux UI without a reliable record → transcribe → output loop.

### Phase 5: Linux Desktop Integration and Fallbacks
**Rationale:** Hotkeys, direct insertion, autostart, and degraded-mode UX are where Linux parity succeeds or fails.
**Delivers:** Portal-first global shortcuts, X11 fallback path, direct insertion capability matrix with clipboard fallback, autostart, diagnostics, and explicit degraded-mode UX.
**Addresses:** Global hotkeys, autostart, direct insertion, supportability.
**Avoids:** Assuming Linux desktop APIs are uniform.

### Phase 6: Packaging, Environment Validation, and Release Hardening
**Rationale:** Packaging is part of the product surface, not a final chore.
**Delivers:** `.deb`/`.rpm` installers, bundled runtime/resources/helpers, packaged smoke tests, GNOME/KDE/Wayland/X11 validation matrix, release pipeline readiness.
**Addresses:** “Done means packaged app” and distro/session confidence.
**Avoids:** Dev-only success masking installed-app failures.

### Phase Ordering Rationale

- Shared contracts come first because Linux should consume authoritative product logic, not copy today’s Swift orchestration.
- macOS migration comes before Linux parity so divergence is removed before a second platform lands.
- Linux shell foundations precede dictation runtime so persistence, localization, tray behavior, and onboarding do not become throwaway glue.
- Desktop integrations and packaging are late in sequence but early in validation; they should be exercised continuously once introduced.

### Research Flags

Phases likely needing deeper research during planning:
- **Phase 3:** Linux tray/status notifier behavior and secure secret-storage support across target environments.
- **Phase 4:** whisper.cpp sidecar packaging, backend selection, model/runtime filesystem strategy, and PipeWire capture shape.
- **Phase 5:** Wayland/X11 capability matrix for global shortcuts and direct insertion.
- **Phase 6:** Target distro/build matrix and packaged validation strategy on Linux builders.

Phases with standard patterns (skip research-phase):
- **Phase 1:** Ports/adapters extraction and shared state-machine migration patterns are well-supported by KMP architecture guidance.
- **Phase 2:** Migrating macOS to shared business rules is largely internal architecture work, not an external integration unknown.

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | Strongly supported by official KMP, Compose, portal, and packaging docs; main uncertainty is Linux tray/runtime specifics. |
| Features | MEDIUM | Product bar is clear, but direct insertion and some Linux UX expectations remain environment-dependent. |
| Architecture | HIGH | Shared-core/native-shell split is well supported and aligns tightly with current constraints. |
| Pitfalls | MEDIUM-HIGH | Risks are credible and cross-confirmed by project context plus Linux desktop/platform realities. |

**Overall confidence:** MEDIUM-HIGH

### Gaps to Address

- **Linux capability matrix:** Validate GNOME/KDE, Wayland/X11, tray support, and portal availability before locking detailed parity claims.
- **Direct insertion behavior:** Treat as capability-driven and verify acceptable fallback UX rather than promising uniform support.
- **Secret storage strategy:** Confirm whether libsecret/keyring coverage is sufficient for supported distros and packaging formats.
- **Packaged runtime behavior:** Validate bundled helper/model/resource paths in installed builds early.
- **arm64 Linux policy:** Current research assumes linuxX64-first; decide whether Linux arm64 matters in v1 or explicitly defer it.

## Sources

### Primary (HIGH confidence)
- `.planning/PROJECT.md` — product scope, constraints, and parity target.
- Kotlin Multiplatform official docs — shared/platform boundaries, expect/actual, platform APIs.
- JetBrains Compose official docs — desktop UI and native distribution behavior.
- XDG Desktop Portal official docs — GlobalShortcuts, Background, InputCapture, RemoteDesktop.
- Freedesktop Desktop Entry and Autostart specs — Linux packaging/autostart behavior.
- whisper.cpp official repository/docs — Linux-capable local ASR baseline.

### Secondary (MEDIUM confidence)
- SQLDelight docs — multiplatform SQLite strategy for new shared stores.
- moko-resources docs/repo — shared resource/localization strategy across JVM and Apple.
- dbus-java repo/docs — pragmatic JVM D-Bus client choice.
- PipeWire docs — modern Linux audio-stack direction.

### Tertiary (LOW confidence)
- Ayatana/AppIndicator ecosystem references — tray behavior still needs real-environment validation.
- JNativeHook repo — useful mainly as evidence for what not to use as the primary Linux hotkey path.

---
*Research completed: 2026-03-29*
*Ready for roadmap: yes*

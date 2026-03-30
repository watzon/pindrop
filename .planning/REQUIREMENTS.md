# Requirements: Pindrop

**Defined:** 2026-03-29
**Core Value:** Users can get a native-feeling, offline-first dictation experience on each desktop platform without sacrificing platform fidelity or maintaining separate business logic for every app.

## v1 Requirements

Requirements for the Linux support initiative and shared-core expansion. Each maps to roadmap phases.

### Shared Platform

- [x] **SHRD-01**: Supported desktop clients use one authoritative Kotlin implementation for non-native product rules including settings schema, model policy, transcription session policy, history/search semantics, dictionary cleanup, and AI enhancement behavior.
- [x] **SHRD-02**: Supported desktop clients consume one shared localization source of truth for shipped UI strings.
- [x] **SHRD-03**: Shared platform contracts keep macOS UI and macOS WhisperKit transcription native while exposing reusable adapters needed by Linux and future Windows clients.

### Linux Shell

- [ ] **LNX-01**: Linux user can install and launch Pindrop as a packaged desktop app.
- [x] **LNX-02**: Linux user can keep Pindrop available from the system tray without keeping a main window open.
- [x] **LNX-03**: Linux user can configure Pindrop to start automatically on login.
- [x] **LNX-04**: Linux user can complete first-run onboarding for microphone setup, model setup, hotkey setup, and environment-specific limitations.
- [x] **LNX-05**: Linux user can manage native app settings for language, hotkeys, output behavior, model preferences, history, dictionary, and AI enhancement.

### Dictation

- [ ] **DICT-01**: Linux user can start and stop dictation with a configurable global toggle hotkey.
- [ ] **DICT-02**: Linux user can use push-to-talk dictation with a configurable hold shortcut.
- [ ] **DICT-03**: Linux user can see a floating recording indicator while dictation is active.
- [x] **DICT-04**: Linux user can record microphone audio and receive a local offline transcription.
- [x] **DICT-05**: Linux user can download, select, and remove local transcription models from the app.
- [ ] **DICT-06**: Linux user receives transcribed text via clipboard by default immediately after dictation completes.
- [ ] **DICT-07**: Linux user can insert transcription directly at the cursor when the current Linux environment supports it, with a clear clipboard fallback when it does not.

### History

- [ ] **HIST-01**: Linux user can review previous dictations in local history.
- [ ] **HIST-02**: Linux user can search history to recover prior transcriptions.

### Language Tools

- [ ] **LANG-01**: Linux user can manage custom word replacements or vocabulary that improve transcription accuracy and apply during transcript cleanup.

### AI Enhancement

- [ ] **AI-01**: Linux user can optionally run AI enhancement on a completed transcription without making cloud services mandatory for core dictation.
- [ ] **AI-02**: Linux user can configure AI provider settings and store credentials securely on Linux.
- [ ] **AI-03**: Linux user can manage reusable prompt presets for AI enhancement workflows.

## v2 Requirements

Deferred to future release. Tracked but not in the current roadmap.

### Linux Expansion

- **LNX-06**: Linux user can use a notes experience with parity to the current macOS app.
- **LNX-07**: Linux user can transcribe imported audio/video media with parity to the current macOS media workflows.
- **LNX-08**: Linux user gets deeper desktop-environment-specific optimization beyond common GNOME/KDE and Wayland/X11 support paths.

### Advanced Transcription

- **DICT-08**: Linux user can view streaming partial transcription updates during active recording.
- **DICT-09**: Linux user can choose among multiple Linux transcription backends beyond the baseline offline engine when hardware/runtime support allows it.

## Out of Scope

Explicitly excluded. Documented to prevent scope creep.

| Feature | Reason |
|---------|--------|
| Linux notes parity in v1 | Explicitly deferred so the first Linux release stays focused on the core dictation loop |
| Linux media or video transcription parity in v1 | Expands scope away from the core daily dictation workflow |
| Shared cross-platform UI replacing native macOS UI | Native macOS UI fidelity is part of the product value and must remain intact |
| Replacing macOS WhisperKit transcription with a shared engine | WhisperKit is intentionally kept macOS-native |
| Cloud-required transcription or account sync | Conflicts with Pindrop's privacy-first local-first core value |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| SHRD-01 | Phase 1 | Complete |
| SHRD-02 | Phase 1 | Complete |
| SHRD-03 | Phase 1 | Complete |
| LNX-01 | Phase 6 | Pending |
| LNX-02 | Phase 2 | Complete |
| LNX-03 | Phase 2 | Complete |
| LNX-04 | Phase 2 | Complete |
| LNX-05 | Phase 2 | Complete |
| DICT-01 | Phase 4 | Pending |
| DICT-02 | Phase 4 | Pending |
| DICT-03 | Phase 4 | Pending |
| DICT-04 | Phase 3 | Complete |
| DICT-05 | Phase 3 | Complete |
| DICT-06 | Phase 4 | Pending |
| DICT-07 | Phase 4 | Pending |
| HIST-01 | Phase 5 | Pending |
| HIST-02 | Phase 5 | Pending |
| LANG-01 | Phase 5 | Pending |
| AI-01 | Phase 5 | Pending |
| AI-02 | Phase 5 | Pending |
| AI-03 | Phase 5 | Pending |

**Coverage:**
- v1 requirements: 21 total
- Mapped to phases: 21
- Unmapped: 0 ✓

---
*Requirements defined: 2026-03-29*
*Last updated: 2026-03-29 after roadmap creation*

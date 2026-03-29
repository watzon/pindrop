# Roadmap: Pindrop Linux Support Initiative

## Overview

Pindrop already delivers a native macOS dictation experience. This roadmap expands the product into a Linux-first, Windows-ready desktop architecture by first making shared Kotlin ownership authoritative for non-native product rules and localization, then delivering the Linux shell, dictation loop, recovery/enhancement workflows, and finally a packaged Linux release that preserves macOS-native UI and macOS-native WhisperKit transcription.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

- [ ] **Phase 1: Shared Core Authority** - Make shared Kotlin rules and localization authoritative without breaking native macOS boundaries.
- [ ] **Phase 2: Linux Shell & Settings** - Deliver the Linux tray app shell, onboarding flow, autostart, and daily settings surfaces.
- [ ] **Phase 3: Linux Offline Transcription** - Deliver Linux microphone transcription and local model management as a complete offline workflow.
- [ ] **Phase 4: Linux Capture & Output Loop** - Deliver hotkey-driven recording, recording feedback, and reliable text delivery behavior.
- [ ] **Phase 5: History, Dictionary & AI Workflows** - Deliver transcript recovery, cleanup tools, and optional AI enhancement on Linux.
- [ ] **Phase 6: Packaged Linux Release** - Ship Linux as an installable packaged app instead of a source-only build.

## Phase Details

### Phase 1: Shared Core Authority
**Goal**: Supported desktop clients use one authoritative shared core for non-native product rules and localization while macOS remains native where it must.
**Depends on**: Nothing (first phase)
**Requirements**: SHRD-01, SHRD-02, SHRD-03
**Success Criteria** (what must be TRUE):
  1. Supported desktop clients apply the same shared rules for settings schema, model policy, transcription session policy, history/search semantics, dictionary cleanup, and AI enhancement behavior.
  2. Shipped UI strings for supported desktop clients come from one shared localization source instead of separate per-platform translation systems.
  3. macOS users still get native SwiftUI/AppKit UI and native WhisperKit transcription while Linux- and Windows-ready adapters are exposed through shared contracts.
**Plans**: 3 plans

- [x] 01-01-PLAN.md — Settings Schema Authority (KMP module + Swift wiring)
- [x] 01-02-PLAN.md — Localization Source of Truth (xcstrings → KMP resources)
- [x] 01-03-PLAN.md — Shared Domain Logic + Fallback Cleanup

### Phase 2: Linux Shell & Settings
**Goal**: Linux users can keep Pindrop available as a real desktop utility with onboarding, tray presence, autostart, and daily settings control.
**Depends on**: Phase 1
**Requirements**: LNX-02, LNX-03, LNX-04, LNX-05
**Success Criteria** (what must be TRUE):
  1. Linux user can keep Pindrop available from the system tray without leaving a main window open.
  2. Linux user can complete first-run onboarding for microphone setup, model setup, hotkey setup, and environment-specific limitations.
  3. Linux user can enable start-on-login and have Pindrop relaunch automatically in a new desktop session.
  4. Linux user can manage language, hotkeys, output behavior, model preferences, history, dictionary, and AI enhancement settings from the Linux app.
**Plans**: TBD
**UI hint**: yes

### Phase 3: Linux Offline Transcription
**Goal**: Linux users can record microphone audio locally and manage offline transcription models from the app.
**Depends on**: Phase 2
**Requirements**: DICT-04, DICT-05
**Success Criteria** (what must be TRUE):
  1. Linux user can record microphone audio and receive a local offline transcription.
  2. Linux user can download, select, and remove local transcription models without leaving the app.
  3. Linux user can complete the core offline transcription flow without requiring cloud services.
**Plans**: TBD

### Phase 4: Linux Capture & Output Loop
**Goal**: Linux users can trigger dictation quickly, see recording state clearly, and receive text reliably in daily desktop workflows.
**Depends on**: Phase 3
**Requirements**: DICT-01, DICT-02, DICT-03, DICT-06, DICT-07
**Success Criteria** (what must be TRUE):
  1. Linux user can start and stop dictation with a configurable global toggle hotkey.
  2. Linux user can use a configurable push-to-talk shortcut for hold-to-record dictation.
  3. Linux user can see a floating recording indicator while dictation is active.
  4. Linux user receives completed transcriptions through the clipboard by default immediately after dictation finishes.
  5. Linux user can insert transcription directly at the cursor when the current environment supports it, with a clear clipboard fallback when it does not.
**Plans**: TBD
**UI hint**: yes

### Phase 5: History, Dictionary & AI Workflows
**Goal**: Linux users can recover past work, improve transcript cleanup, and optionally enhance output without losing offline-first core dictation.
**Depends on**: Phase 4
**Requirements**: HIST-01, HIST-02, LANG-01, AI-01, AI-02, AI-03
**Success Criteria** (what must be TRUE):
  1. Linux user can review previous dictations in local history and search them to recover prior transcriptions.
  2. Linux user can manage custom word replacements or vocabulary that improve transcript cleanup behavior.
  3. Linux user can optionally run AI enhancement on a completed transcription without making cloud services mandatory for core dictation.
  4. Linux user can configure AI provider settings, store credentials securely on Linux, and reuse prompt presets for enhancement workflows.
**Plans**: TBD
**UI hint**: yes

### Phase 6: Packaged Linux Release
**Goal**: Linux users can install and launch Pindrop as a distributable desktop product instead of a source-only developer preview.
**Depends on**: Phase 5
**Requirements**: LNX-01
**Success Criteria** (what must be TRUE):
  1. Linux user can install Pindrop from a packaged Linux app artifact without building from source.
  2. Linux user can launch the installed app through normal desktop entry points after installation.
  3. Linux user can open the installed app and reach the same core Linux workflows delivered in earlier phases.
**Plans**: TBD

## Progress

**Execution Order:**
Phases execute in numeric order: 1 → 2 → 3 → 4 → 5 → 6

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Shared Core Authority | 0/3 | Planning complete | - |
| 2. Linux Shell & Settings | 0/TBD | Not started | - |
| 3. Linux Offline Transcription | 0/TBD | Not started | - |
| 4. Linux Capture & Output Loop | 0/TBD | Not started | - |
| 5. History, Dictionary & AI Workflows | 0/TBD | Not started | - |
| 6. Packaged Linux Release | 0/TBD | Not started | - |

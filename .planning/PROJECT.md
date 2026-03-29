# Pindrop

## What This Is

Pindrop is a privacy-first dictation app that already ships as a native macOS menu bar app and is evolving into a cross-platform desktop product with a shared Kotlin Multiplatform core. The current initiative is to complete Linux support with a native GUI and near-macOS parity for the core daily experience while moving more reusable product logic, state, and localization into Kotlin.

## Core Value

Users can get a native-feeling, offline-first dictation experience on each desktop platform without sacrificing platform fidelity or maintaining separate business logic for every app.

## Requirements

### Validated

- ✓ Native macOS dictation app with menu bar workflow, hotkeys, and floating recording UI — existing
- ✓ Local transcription on macOS with native engines and platform-specific adapters — existing
- ✓ History, search, notes, dictionary, model management, and optional AI enhancement in the shipped app — existing
- ✓ Kotlin Multiplatform shared core already owns part of the domain logic and transcription policy surface — existing
- ✓ Shared business logic moved into Kotlin (settings schema, dictionary cleanup, history semantics, AI enhancement behavior) — Validated in Phase 01: shared-core-authority
- ✓ Localization maintained from one shared source of truth (KMP Multiplatform Resources, 606 strings, 11 locales) — Validated in Phase 01: shared-core-authority

### Active

- [ ] Linux users can launch a native desktop app and complete the core daily dictation workflow with near-macOS parity.
- [ ] Linux includes required desktop integrations for v1: global hotkey, tray app entry point, floating indicator, and auto-start support.
- [ ] Linux supports transcription, AI enhancement, history/search, and model management as first-class user workflows.
- [ ] Linux support ships as a packaged, distributable app rather than a source-only developer preview.

### Out of Scope

- Linux notes parity in v1 — not required for the first Linux release.
- Linux video/media transcription parity in v1 — explicitly deferred to keep the first release focused on core dictation workflows.
- Replacing the native macOS UI with shared UI technology — macOS UI remains native.
- Replacing WhisperKit on macOS — WhisperKit-based transcription remains macOS-native.

## Context

Pindrop already has a substantial native macOS app implemented in SwiftUI/AppKit with SwiftData persistence, native transcription adapters, and multiple user-facing workflows beyond basic dictation. The repository also already contains Kotlin Multiplatform modules for shared transcription policies, model-selection logic, and pieces of shared UI/domain state, which makes this a brownfield platform-expansion effort rather than a new product.

The immediate goal is not a minimal Linux prototype. The target is a first Linux release that feels close to the existing macOS product in day-to-day use for launching the app, configuring it, recording, transcribing, enhancing output, managing models, and reviewing prior transcript history. Linux should be treated as the first non-macOS desktop target, but the architectural work should leave the codebase better positioned for a future native Windows client.

This project also needs to reduce long-term maintenance cost. In practice, that means moving remaining shareable product logic into Kotlin where it makes architectural sense, preserving platform-native execution where required, and establishing a single localization source that all desktop clients can consume.

## Constraints

- **Platform architecture**: macOS UI must remain native SwiftUI/AppKit — preserving the shipped Mac experience is a hard requirement.
- **Transcription backend**: WhisperKit transcription flow stays native to macOS — it cannot be abstracted away into a cross-platform implementation.
- **Linux UX**: Linux must ship with a native GUI and near-macOS parity for core flows — a web wrapper or heavily reduced experience does not meet the goal.
- **Scope control**: Linux v1 excludes notes and video/media transcription extras — focus stays on the core dictation product loop.
- **Localization**: Strings need one shared source of truth — separate translation maintenance for each desktop app is not acceptable.
- **Packaging**: “Done” includes a packaged Linux app artifact — not just local developer builds.
- **Future compatibility**: Shared logic decisions should make Windows easier later — Linux-first work should not box the project into Linux-only abstractions.

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Keep macOS UI native | The current app’s platform fidelity is part of the product value and should not regress | — Pending |
| Keep WhisperKit transcription native on macOS | WhisperKit is explicitly platform-bound and one of the few areas that must stay outside the shared Kotlin layer | — Pending |
| Target Linux near-parity for core daily workflows | The goal is a real desktop product, not a stripped-down proof of concept | — Pending |
| Move remaining shareable business logic into Kotlin | Shared logic lowers maintenance cost and enables Linux-first now without blocking future Windows support | ✓ Done — Phase 01 |
| Use one shared localization source | Maintaining parallel translations across three apps is too expensive and error-prone | ✓ Done — Phase 01 |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd-transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `/gsd-complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-03-29 after Phase 01 completion*

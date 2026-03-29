---
gsd_state_version: 1.0
milestone: v1.0
milestone_name: milestone
status: planning
stopped_at: Phase 1 context gathered
last_updated: "2026-03-29T19:21:40.631Z"
last_activity: 2026-03-29 — Initial roadmap created for Linux support initiative
progress:
  total_phases: 6
  completed_phases: 0
  total_plans: 0
  completed_plans: 0
  percent: 0
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-03-29)

**Core value:** Users can get a native-feeling, offline-first dictation experience on each desktop platform without sacrificing platform fidelity or maintaining separate business logic for every app.
**Current focus:** Phase 1 - Shared Core Authority

## Current Position

Phase: 1 of 6 (Shared Core Authority)
Plan: 0 of TBD in current phase
Status: Ready to plan
Last activity: 2026-03-29 — Initial roadmap created for Linux support initiative

Progress: [░░░░░░░░░░] 0%

## Performance Metrics

**Velocity:**

- Total plans completed: 0
- Average duration: -
- Total execution time: 0.0 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| - | - | - | - |

**Recent Trend:**

- Last 5 plans: none
- Trend: Stable

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- [Phase 1]: Shared Kotlin becomes the authority for non-native product rules and shared localization.
- [Phase 1]: macOS UI stays native SwiftUI/AppKit and macOS WhisperKit stays native.
- [Phase 2-6]: Linux is treated as a packaged first-class desktop product, not a source-only preview.

### Pending Todos

None yet.

### Blockers/Concerns

- Linux Wayland/X11 capability differences may affect hotkeys and direct insertion behavior.
- Linux secure secret storage and tray behavior still need environment validation across target desktops.
- Packaged runtime/model/helper paths must be validated early so installer success matches dev-run success.

## Session Continuity

Last session: 2026-03-29T19:21:40.628Z
Stopped at: Phase 1 context gathered
Resume file: .planning/phases/01-shared-core-authority/01-CONTEXT.md

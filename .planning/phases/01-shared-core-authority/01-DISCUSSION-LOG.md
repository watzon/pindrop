# Phase 1: Shared Core Authority - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-03-29
**Phase:** 1-shared-core-authority
**Areas discussed:** Settings schema authority, Localization source of truth, New shared domains, Swift fallback strategy

---

## Settings Schema Authority

### What does Kotlin own for settings?

| Option | Description | Selected |
|--------|-------------|----------|
| Types + defaults + validation | Kotlin defines schema (keys, types, defaults, valid ranges, validation). Swift persists via @AppStorage + Keychain. | ✓ |
| Types + defaults only | Kotlin defines keys, types, defaults but no validation. | |
| Full storage ownership | Kotlin owns persistence too. Bigger refactor, harder SwiftUI binding. | |

**User's choice:** Types + defaults + validation
**Notes:** Schema is the contract; platform storage stays native.

### Which settings move into the shared schema?

| Option | Description | Selected |
|--------|-------------|----------|
| All settings in one schema | All ~50 settings. Maximum cross-platform consistency. | ✓ |
| Shared product rules only | Model policy, language, output, feature flags. Hotkeys/indicators stay Swift-only. | |
| Transcription settings first | Smallest scope, fastest to ship. | |

**User's choice:** All settings in one schema

### How should Swift consume the Kotlin schema?

| Option | Description | Selected |
|--------|-------------|----------|
| Schema + adapter pattern | Kotlin defines schema as XCFramework. Swift maps KMP keys → @AppStorage. SettingsStore API unchanged for callers. | ✓ |
| Schema + runtime validation | KMP provides SettingsSnapshotProvider. More tightly coupled. | |
| Code generation bridge | Maximum compile-time safety but more boilerplate. | |

**User's choice:** Schema + adapter pattern

### How should the shared schema handle secrets?

| Option | Description | Selected |
|--------|-------------|----------|
| Schema only, Keychain stays | KMP defines which secrets exist. Swift Keychain storage unchanged. Linux uses its own secure storage. | ✓ |
| Secrets stay Swift-only | No KMP schema for secrets. Simpler but duplicated when Linux arrives. | |

**User's choice:** Schema only, Keychain stays

### Should Kotlin defaults replace Swift Defaults enum?

| Option | Description | Selected |
|--------|-------------|----------|
| Kotlin defaults replace Swift | Defaults enum deleted. Swift reads defaults from KMP. Single source. | ✓ |
| Gradual migration with fallback | Two sources coexist temporarily. Safer but longer inconsistency. | |

**User's choice:** Kotlin defaults replace Swift

### How should validation surface?

| Option | Description | Selected |
|--------|-------------|----------|
| Validate on write with user feedback | KMP returns structured results. Swift shows errors. | ✓ |
| Validate on read, silent correction | Invalid values corrected to defaults silently. Simpler but less transparent. | |

**User's choice:** Validate on write with user feedback

---

## Localization Source of Truth

### Where should the authoritative source live?

| Option | Description | Selected |
|--------|-------------|----------|
| Strings move to Kotlin entirely | All strings in Kotlin. macOS reads via KMP. Loses Xcode string catalog tooling. | ✓ |
| .xcstrings as source + KMP reader | Keep .xcstrings, build KMP parser for Linux. macOS keeps native path. | |
| Kotlin source, .xcstrings generated | Canonical in Kotlin, .xcstrings generated. Adds build step. | |

**User's choice:** Strings move to Kotlin entirely

### What format for Kotlin string resources?

| Option | Description | Selected |
|--------|-------------|----------|
| Kotlin Multiplatform Resources | Official JetBrains library. Per-locale values/strings.xml. Compile-time safety. | ✓ |
| Plain Kotlin string maps | Simple but no tooling support. | |
| JSON resource files | Easiest migration but no compile-time safety. | |

**User's choice:** Kotlin Multiplatform Resources

### How should macOS consume Kotlin strings?

| Option | Description | Selected |
|--------|-------------|----------|
| Swift calls KMP Res.string | localized() rewritten to call KMP. SwiftUI views keep working. | ✓ |
| Abstracted strings provider | Extra interface layer. Useful for future caching/A/B testing. | |

**User's choice:** Swift calls KMP Res.string

### Migration timing?

| Option | Description | Selected |
|--------|-------------|----------|
| Full migration this phase | 43K-line .xcstrings converted. Deleted at phase end. Clean cut. | ✓ |
| Incremental over phases | New strings in KMP, existing stay in .xcstrings. Less risk. | |

**User's choice:** Full migration this phase

---

## New Shared Domains

### What level of shared authority?

| Option | Description | Selected |
|--------|-------------|----------|
| Types + validation + business logic | Full shared logic. Maximum reusability. | ✓ |
| Types + validation only | Logic stays per-platform. Less reusable. | |
| Types only | Just shared enums and data classes. Minimum. | |

**User's choice:** Types + validation + business logic

### Module organization?

| Option | Description | Selected |
|--------|-------------|----------|
| Extend existing modules | History → ui-workspace, AI → ui-settings, Dictionary → feature-transcription. Less sprawl. | ✓ |
| New dedicated modules | Clean separation but more Gradle modules. | |

**User's choice:** Extend existing modules

---

## Swift Fallback Strategy

### What happens to #else fallback branches?

| Option | Description | Selected |
|--------|-------------|----------|
| Remove fallbacks, KMP required | All #else branches deleted. ~500 lines removed. KMP is required dependency. | ✓ |
| Remove fallback logic, keep guards | Guards remain for documentation but #else blocks empty. | |
| Keep fallbacks as safety net | Lowest risk but continued drift potential. | |

**User's choice:** Remove fallbacks, KMP required

### View-level #if canImport guards?

| Option | Description | Selected |
|--------|-------------|----------|
| Remove all view guards | Views always use KMP objects. If KMP missing, build error. | ✓ |
| Keep view guards as fallback | Belt-and-suspenders approach. | |

**User's choice:** Remove all view guards

---

## Agent's Discretion

- Exact internal structure of settings schema KMP module
- Migration tooling approach for .xcstrings → KMP resources
- Granular validation rules per setting
- Gradle sub-module organization within settings schema

## Deferred Ideas

- Linux/Windows target expansion for ui-shell, ui-settings, ui-theme, ui-workspace — likely Phase 2 or Phase 6

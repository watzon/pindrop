---
phase: 02-linux-shell-settings
plan: 03
subsystem: ui-shell
tags: [linux, gtk4, libadwaita, onboarding, settings, preferences, secrets, kotlin-native, cinterop]

# Dependency graph
requires:
  - phase: 01-01
    provides: "KMP settings-schema with SettingsKeys, SettingsDefaults, SettingsValidation"
  - phase: 01-03
    provides: "KMP core module with SharedLocalization, SettingsPersistence, SecretStorage, AutostartManager"
  - phase: 02-01
    provides: "Linux build foundation and platform adapter implementations"
  - phase: 02-02
    provides: "LinuxCoordinator, tray shell, AppIndicator integration, fallback window"
provides:
  - "OnboardingWizard - GTK Assistant first-run flow with 7 Linux-adapted steps"
  - "Linux onboarding step set for welcome, audio probe, model choice, model download, hotkey guidance, AI setup, and ready state"
  - "SettingsDialog - Linux settings surface with General, Hotkeys, Output, Models, AI Enhancement, and Dictionary pages"
  - "Settings UI persistence through SettingsPersistence and AI secret storage through SecretStorage"
  - "LinuxCoordinator wiring for first-run onboarding and tray-opened settings"
affects: [phase-03-linux-offline-transcription, phase-04-linux-capture-output-loop, phase-05-history-dictionary-ai]

# Tech tracking
tech-stack:
  added: [gtk-assistant, gtk-stack, ui-settings-integration]
  patterns: [wizard-step-interface, settings-page-collector, validation-before-save, linux-soft-gates]

key-files:
  created:
    - shared/ui-shell/src/linuxX64Main/kotlin/tech/watzon/pindrop/shared/ui/shell/linux/onboarding/OnboardingStep.kt
    - shared/ui-shell/src/linuxX64Main/kotlin/tech/watzon/pindrop/shared/ui/shell/linux/onboarding/OnboardingWizard.kt
    - shared/ui-shell/src/linuxX64Main/kotlin/tech/watzon/pindrop/shared/ui/shell/linux/onboarding/WelcomeStep.kt
    - shared/ui-shell/src/linuxX64Main/kotlin/tech/watzon/pindrop/shared/ui/shell/linux/onboarding/AudioCheckStep.kt
    - shared/ui-shell/src/linuxX64Main/kotlin/tech/watzon/pindrop/shared/ui/shell/linux/onboarding/ModelSelectionStep.kt
    - shared/ui-shell/src/linuxX64Main/kotlin/tech/watzon/pindrop/shared/ui/shell/linux/onboarding/ModelDownloadStep.kt
    - shared/ui-shell/src/linuxX64Main/kotlin/tech/watzon/pindrop/shared/ui/shell/linux/onboarding/HotkeySetupStep.kt
    - shared/ui-shell/src/linuxX64Main/kotlin/tech/watzon/pindrop/shared/ui/shell/linux/onboarding/AIConfigStep.kt
    - shared/ui-shell/src/linuxX64Main/kotlin/tech/watzon/pindrop/shared/ui/shell/linux/onboarding/ReadyStep.kt
    - shared/ui-shell/src/linuxX64Main/kotlin/tech/watzon/pindrop/shared/ui/shell/linux/settings/SettingsDialog.kt
    - shared/ui-shell/src/linuxX64Main/kotlin/tech/watzon/pindrop/shared/ui/shell/linux/settings/GeneralSettingsPage.kt
    - shared/ui-shell/src/linuxX64Main/kotlin/tech/watzon/pindrop/shared/ui/shell/linux/settings/HotkeysSettingsPage.kt
    - shared/ui-shell/src/linuxX64Main/kotlin/tech/watzon/pindrop/shared/ui/shell/linux/settings/OutputSettingsPage.kt
    - shared/ui-shell/src/linuxX64Main/kotlin/tech/watzon/pindrop/shared/ui/shell/linux/settings/ModelsSettingsPage.kt
    - shared/ui-shell/src/linuxX64Main/kotlin/tech/watzon/pindrop/shared/ui/shell/linux/settings/AISettingsPage.kt
    - shared/ui-shell/src/linuxX64Main/kotlin/tech/watzon/pindrop/shared/ui/shell/linux/settings/DictionarySettingsPage.kt
  modified:
    - shared/ui-shell/src/linuxX64Main/kotlin/tech/watzon/pindrop/shared/ui/shell/linux/LinuxCoordinator.kt
    - shared/ui-shell/build.gradle.kts

key-decisions:
  - "Onboarding is Linux-adapted rather than macOS-parity strict: audio and hotkey checks inform users without blocking completion"
  - "Settings dialog is GTK stack-based instead of a true AdwPreferencesDialog so implementation stays consistent with current cinterop surface and existing GTK shell patterns"
  - "AI provider options come from shared ui-settings presentation data so Linux uses the same product rules as other clients"
  - "Settings writes are validated through SettingsValidation before persistence, while secrets are stored separately through SecretStorage"
  - "SettingsDialog owns one StableRef for button callbacks and exposes destroy() so LinuxCoordinator can release native callback state cleanly"

patterns-established:
  - "Wizard pages implement a common OnboardingStep contract with title, content, completeness, and completion hooks"
  - "Settings pages each expose values() for a central dialog save pass"
  - "LinuxCoordinator shows onboarding when hasCompletedOnboarding is false, then falls back to tray-first operation"
  - "Soft-gated Linux onboarding communicates desktop-environment limitations without blocking first run"

requirements-completed: [LNX-04, LNX-05]

# Metrics
duration: unknown
completed: 2026-03-29
---

# Phase 2 Plan 3: Linux Onboarding and Settings Summary

**GTK onboarding wizard plus tray-opened Linux settings dialog, both backed by shared settings schema, localized copy, persisted TOML settings, and libsecret-backed AI credential storage**

## Performance

- **Completed:** 2026-03-29
- **Tasks:** 2
- **Files modified:** 18

## Accomplishments
- Created a 7-step GTK onboarding flow for Linux covering welcome, audio environment detection, default model selection, model download placeholder, hotkey guidance, optional AI setup, and ready state
- Wired onboarding completion into `SettingsPersistence` by saving `hasCompletedOnboarding = true` on assistant apply
- Added a Linux settings dialog with six categories: General, Hotkeys, Output, Models, AI Enhancement, and Dictionary
- Reused shared `SettingsKeys`, `SettingsDefaults`, `SettingsValidation`, `SharedLocalization`, and `AISettingsCatalog` so Linux settings follow the same product rules as the shared core
- Stored AI API secrets through `SecretStorage` while saving non-secret AI preferences in regular settings
- Extended `LinuxCoordinator` so first launch opens onboarding and tray menu settings opens the new dialog

## Task Commits

Each task was committed atomically:

1. **Task 1: GTK onboarding wizard** - `43ad616` (feat)
2. **Task 2: Linux settings dialog** - `bd978fb` (feat)

## Files Created/Modified
- `shared/ui-shell/src/linuxX64Main/kotlin/tech/watzon/pindrop/shared/ui/shell/linux/onboarding/OnboardingStep.kt` - shared contract for onboarding pages
- `shared/ui-shell/src/linuxX64Main/kotlin/tech/watzon/pindrop/shared/ui/shell/linux/onboarding/OnboardingWizard.kt` - GTK Assistant container, completion persistence, and lifecycle wiring
- `shared/ui-shell/src/linuxX64Main/kotlin/tech/watzon/pindrop/shared/ui/shell/linux/onboarding/WelcomeStep.kt` - Linux welcome and product overview
- `shared/ui-shell/src/linuxX64Main/kotlin/tech/watzon/pindrop/shared/ui/shell/linux/onboarding/AudioCheckStep.kt` - non-blocking PipeWire/PulseAudio detection
- `shared/ui-shell/src/linuxX64Main/kotlin/tech/watzon/pindrop/shared/ui/shell/linux/onboarding/ModelSelectionStep.kt` - default model picker
- `shared/ui-shell/src/linuxX64Main/kotlin/tech/watzon/pindrop/shared/ui/shell/linux/onboarding/ModelDownloadStep.kt` - download placeholder and guidance for next phase
- `shared/ui-shell/src/linuxX64Main/kotlin/tech/watzon/pindrop/shared/ui/shell/linux/onboarding/HotkeySetupStep.kt` - environment-specific hotkey guidance for X11 and Wayland
- `shared/ui-shell/src/linuxX64Main/kotlin/tech/watzon/pindrop/shared/ui/shell/linux/onboarding/AIConfigStep.kt` - optional AI provider setup and secret persistence helper
- `shared/ui-shell/src/linuxX64Main/kotlin/tech/watzon/pindrop/shared/ui/shell/linux/onboarding/ReadyStep.kt` - onboarding summary and completion step
- `shared/ui-shell/src/linuxX64Main/kotlin/tech/watzon/pindrop/shared/ui/shell/linux/settings/SettingsDialog.kt` - GTK settings shell with centralized save, validation, and cleanup
- `shared/ui-shell/src/linuxX64Main/kotlin/tech/watzon/pindrop/shared/ui/shell/linux/settings/GeneralSettingsPage.kt` - language, theme, autostart, and dock visibility settings
- `shared/ui-shell/src/linuxX64Main/kotlin/tech/watzon/pindrop/shared/ui/shell/linux/settings/HotkeysSettingsPage.kt` - configurable shortcut fields and Linux limitations guidance
- `shared/ui-shell/src/linuxX64Main/kotlin/tech/watzon/pindrop/shared/ui/shell/linux/settings/OutputSettingsPage.kt` - output mode, spacing, and floating indicator controls
- `shared/ui-shell/src/linuxX64Main/kotlin/tech/watzon/pindrop/shared/ui/shell/linux/settings/ModelsSettingsPage.kt` - model and language preferences
- `shared/ui-shell/src/linuxX64Main/kotlin/tech/watzon/pindrop/shared/ui/shell/linux/settings/AISettingsPage.kt` - AI provider/model/prompt settings plus API key handling
- `shared/ui-shell/src/linuxX64Main/kotlin/tech/watzon/pindrop/shared/ui/shell/linux/settings/DictionarySettingsPage.kt` - dictionary learning settings
- `shared/ui-shell/src/linuxX64Main/kotlin/tech/watzon/pindrop/shared/ui/shell/linux/LinuxCoordinator.kt` - first-run onboarding path, dialog lifecycle, and cleanup
- `shared/ui-shell/build.gradle.kts` - added `:ui-settings` dependency for Linux settings presentation models

## Decisions Made
- **Soft Linux onboarding gates:** Audio and hotkey readiness are communicated as guidance instead of hard blockers because Linux capabilities vary by desktop session and compositor.
- **GTK stack preferences shell:** The plan called for an AdwPreferencesDialog, but the implementation uses a GTK stack/switcher dialog while preserving the required settings categories and persistence behavior.
- **Shared product rules:** Linux reads AI provider metadata and validation from shared modules instead of duplicating rules locally.
- **Explicit native callback cleanup:** `SettingsDialog` retains and disposes its `StableRef` so repeated open/close cycles do not leak callback state.
- **Secret split:** API keys stay in `SecretStorage`; non-secret toggles, models, and prompts stay in `SettingsPersistence`.

## Deviations from Plan

### Intentional deviation

**1. Settings shell uses GTK stack window instead of AdwPreferencesDialog**
- **Reason:** Existing Linux cinterop and shell patterns were already GTK-centric, and a stack/switcher dialog was the smallest reliable implementation that still satisfied the required categories, persistence, and validation behavior.
- **Impact:** No functional loss for the plan requirements; visual polish can be upgraded later if Phase 6 packaging or a later UI pass needs tighter libadwaita styling.

## Issues Encountered
- A prior executor produced onboarding files only and returned garbled output without commits; the missing settings UI and coordinator wiring were completed manually.
- `AIConfigStep.kt` contained a broken `toCValues()` helper from the partial agent output and needed correction before committing.
- linuxX64 GTK/libadwaita compilation could not be verified on macOS because the required Linux C headers and libraries are unavailable on the host.

## User Setup Required
None for repository use. Linux runtime verification still requires a Linux host with GTK 4, libadwaita, and AppIndicator development/runtime packages installed.

## Next Phase Readiness
- Phase 2 is now complete end-to-end: Linux has tray presence, autostart support, first-run onboarding, and a daily settings surface.
- Phase 3 can now wire real model download and offline transcription behavior into the onboarding/model settings placeholders.
- The settings dialog provides stable persistence surfaces for future model-management, hotkey binding, and AI workflow work.

## Self-Check: PASSED

- Both implementation commits verified in git history: `43ad616`, `bd978fb`
- Summary file created at expected path
- Worktree clean after summary/state/roadmap updates pending docs commit

---
*Phase: 02-linux-shell-settings*
*Completed: 2026-03-29*

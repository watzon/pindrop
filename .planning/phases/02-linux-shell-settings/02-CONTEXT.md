# Phase 2: Linux Shell & Settings - Context

**Gathered:** 2026-03-29
**Status:** Ready for planning

<domain>
## Phase Boundary

Pindrop expands to Linux with a native GTK 4 / libadwaita desktop shell. This phase covers:

1. Linux system tray integration (LNX-02) — AppIndicator/KStatusNotifierItem via D-Bus
2. Auto-start on login (LNX-03) — XDG `.desktop` file in `~/.config/autostart/`
3. First-run onboarding adapted from macOS (LNX-04) — 7-step GTK wizard
4. Full settings management UI (LNX-05) — GTK settings dialogs reading KMP schema
5. Linux-specific adapters — TOML config persistence, libsecret secure storage, best-effort global hotkeys

The Linux app is a native binary (Kotlin/Native + GTK 4), not a JVM app, not a web wrapper. It consumes the KMP shared core built in Phase 1 (settings schema, localization, domain logic).

macOS UI stays native SwiftUI/AppKit — no changes to macOS code this phase.

</domain>

<decisions>
## Implementation Decisions

### GUI Framework

- **D-01:** GTK 4 / libadwaita as the Linux GUI framework. Produces a native binary via Kotlin/Native cinterop with GTK C libraries. No JVM runtime. Feels native on GNOME; acceptable on KDE/XFCE.
- **D-02:** Kotlin/Native cinterop with GTK 4 via `.def` files. Wrap the minimal GTK/libadwaita API surface needed (GApplication, GtkWindow, GtkBuilder/ui files, AdwPreferencesDialog). Generate wrappers iteratively, starting with the smallest usable subset.

### Onboarding

- **D-03:** Adapt the macOS 7-step onboarding flow for Linux. Steps: Welcome → Audio Check (PipeWire/PulseAudio probe) → Model Selection → Model Download → Hotkey Setup (best-effort) → AI Enhancement Config → Ready.
- **D-04:** Linux onboarding has fewer hard gates than macOS. No Accessibility API permission. Audio check is a soft probe (inform, don't block). Hotkey step documents limitations and offers alternatives (tray click, CLI trigger).

### Settings Persistence

- **D-05:** TOML format at `~/.config/pindrop/settings.toml`. Human-readable, hand-editable, idiomatic for Linux. Kotlin serialization with a TOML library (`ktoml` or equivalent).
- **D-06:** Linux reads the same KMP settings schema (types, keys, defaults, validation) from Phase 1's `settings-schema` module. TOML is the persistence adapter; schema is the authority.

### Autostart

- **D-07:** XDG autostart via `.desktop` file. Create `~/.config/autostart/pindrop.desktop` when user enables launch-at-login. Remove it when disabled. This works across GNOME, KDE, XFCE, and most desktop environments.

### System Tray

- **D-08:** AppIndicator / KStatusNotifierItem via D-Bus for system tray. This is the Linux standard — works on GNOME (with AppIndicator extension), KDE, XFCE, etc.
- **D-09:** Fallback for tray-less environments (tiling WMs, minimal setups): show a small persistent GTK window or provide CLI-only mode with guidance. Don't crash or silently disappear.

### Secure Storage

- **D-10:** libsecret as primary secret storage (GNOME Keyring backend). KWallet support as secondary if feasible without significant complexity.
- **D-11:** Encrypted-file fallback at `~/.config/pindrop/secrets.enc` for environments without a keyring daemon. Use libsodium or platform crypto for encryption. User-facing warning when fallback is active.

### Global Hotkeys

- **D-12:** Best-effort global hotkeys. X11: XGrabKey via Xlib cinterop. Wayland: GlobalShortcuts portal (org.freedesktop.portal.GlobalShortcuts) where compositor supports it; otherwise disabled with in-app guidance explaining the limitation.
- **D-13:** Hotkey configuration in settings allows users to set their desired shortcut. If the runtime can't bind it, show a warning badge and suggest alternatives (tray click, CLI trigger, manual desktop shortcut).

### Module Structure

- **D-14:** Add `linuxX64` target to existing KMP modules (`ui-shell`, `ui-settings`, `settings-schema`). Linux-specific implementations go in `linuxX64Main` source sets. No new standalone Linux module.
- **D-15:** linuxX64 only for now. linuxArm64 deferred until hardware demand exists. The architecture is designed so adding ARM64 later is a target addition, not a refactor.

### Agent's Discretion

- Exact cinterop `.def` file structure and which GTK APIs to wrap first
- GTK UI layout details (GtkBuilder XML vs programmatic construction)
- TOML library choice and integration approach
- Onboarding window management (GtkAssistant vs custom wizard)
- Settings UI widget layout and organization
- CI/CD pipeline for Linux builds (can be deferred to packaging phase)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### KMP Shared Core (Phase 1 outputs — Linux will consume these)

- `shared/settings-schema/src/commonMain/kotlin/tech/watzon/pindrop/shared/settings/SettingsSchema.kt` — Complete settings schema Linux reads
- `shared/settings-schema/src/commonMain/kotlin/tech/watzon/pindrop/shared/settings/SettingsDefaults.kt` — Default values
- `shared/settings-schema/src/commonMain/kotlin/tech/watzon/pindrop/shared/settings/SettingsValidation.kt` — Validation rules
- `shared/settings-schema/src/commonMain/kotlin/tech/watzon/pindrop/shared/settings/SecretSchema.kt` — Secret key structure
- `shared/ui-shell/src/commonMain/kotlin/tech/watzon/pindrop/shared/ui/shell/ShellState.kt` — Shell navigation state
- `shared/ui-settings/src/commonMain/kotlin/tech/watzon/pindrop/shared/ui/settings/AISettingsPresentation.kt` — Settings presentation patterns

### macOS Reference Implementations (adapt for Linux, don't port)

- `Pindrop/UI/Onboarding/` — 7 onboarding step files to adapt
- `Pindrop/Services/StatusBarController.swift` — Tray/menu bar pattern to adapt
- `Pindrop/Services/SettingsStore.swift` — Settings management pattern to adapt
- `Pindrop/AppCoordinator.swift` — Coordinator composition pattern to follow

### Build System

- `shared/build.gradle.kts` — Root Gradle config
- `shared/settings.gradle.kts` — Module registry (will need linuxX64 targets)
- `justfile` — Build commands (will need Linux build recipes)

### Codebase Reference Maps

- `.planning/codebase/ARCHITECTURE.md` — Full architecture overview
- `.planning/codebase/STACK.md` — Technology stack and targets
- `.planning/codebase/CONVENTIONS.md` — Coding conventions

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable KMP Assets (Phase 1)

- **settings-schema module** — Complete settings types, defaults, validation. Linux reads these directly.
- **SecretSchema.kt** — Key structure for API keys. Linux implements storage adapter.
- **KMP Multiplatform Resources** — All UI strings. Linux uses `Res.string` calls.
- **ShellState.kt** — Navigation state model. Linux GTK shell consumes this.
- **AISettingsPresentation.kt** — Provider catalog presentation. Linux settings UI uses this.

### macOS Patterns to Adapt (Not Port)

- **OnboardingWindowController** — Step-by-step wizard pattern → GTK Assistant
- **StatusBarController** — NSStatusItem tray → AppIndicator
- **SettingsStore @AppStorage** — UserDefaults persistence → TOML adapter
- **SettingsStore Keychain** — macOS Keychain → libsecret adapter
- **SMAppService** — macOS launch-at-login → XDG .desktop autostart
- **Coordinator pattern** — AppCoordinator drives lifecycle → Linux GApplication lifecycle

### Linux-Specific New Code

- **GTK Application** — `GApplication` lifecycle (activate, open, shutdown)
- **GTK Windows** — Main window, settings dialog, onboarding wizard, about dialog
- **AppIndicator tray** — D-Bus tray icon with menu
- **TOML config adapter** — Read/write `~/.config/pindrop/settings.toml`
- **libsecret adapter** — Read/write secrets via GNOME Keyring
- **XDG autostart** — Create/remove `.desktop` file in autostart dir
- **Hotkey binding** — X11 XGrabKey + Wayland portal
- **cinterop .def files** — GTK 4, libadwaita, AppIndicator, libsecret, X11

### Integration Points

- **KMP settings-schema ↔ Linux TOML adapter** — Linux implements the schema's persistence port with TOML I/O
- **KMP SecretSchema ↔ Linux libsecret adapter** — Linux implements the secret port with libsecret calls
- **KMP Multiplatform Resources ↔ GTK UI** — `Res.string` calls populate GTK labels/buttons
- **KMP ShellState ↔ GTK navigation** — ShellState drives which GTK window is active
- **KMP AISettingsPresentation ↔ GTK settings UI** — Provider catalog populates GTK combo boxes/lists

</code_context>

<assumptions>
## Assumptions

| ID | Assumption | Risk | Mitigation |
|---|---|---|---|
| A-01 | Kotlin/Native cinterop can wrap GTK 4 + libadwaita with reasonable effort | Medium — cinterop is proven but large APIs need careful .def files | Start with minimal subset, generate wrappers iteratively |
| A-02 | TOML parser available or buildable in KMP (ktoml or similar) | Low — libraries exist | Validate early in build setup |
| A-03 | libsecret available on target Linux distros | Low — standard on GNOME/KDE | Encrypted-file fallback for custom setups |
| A-04 | AppIndicator works on Wayland GNOME (requires extension) | Medium — user may need to install extension | Detect missing extension, show guidance |
| A-05 | GTK 4 GApplication lifecycle maps cleanly to coordinator pattern | Low — GApplication has standard activate/command-line signals | Adapter layer isolates GTK specifics |
| A-06 | XDG autostart is universal across Linux desktop environments | Low — well-established standard | Document any known exceptions |
| A-07 | GlobalShortcuts portal available on major Wayland compositors | Medium — support varies (GNOME: yes, Sway: partial) | Best-effort with clear fallback messaging |
| A-08 | K/N linuxX64 target produces working binaries with GTK linking | Low — proven target | Verify in CI early |

</assumptions>

<specifics>
## Specific Ideas

- GTK UI should use GtkBuilder `.ui` XML files for layout where practical — separates layout from logic, allows future theming
- Onboarding wizard should use GtkAssistant (built-in wizard widget) for the step flow
- Settings should use AdwPreferencesDialog (libadwaita) for the standard GNOME settings pattern
- Tray icon should use the Pindrop logo SVG, same as macOS status bar icon
- Config directory follows XDG: `~/.config/pindrop/` for settings, `~/.local/share/pindrop/` for data (models, history)
- Linux binary name: `pindrop` (lowercase, standard Linux convention)
- `.desktop` file should include `StartupWMClass` for proper window grouping

</specifics>

<deferred>
## Deferred Ideas

- **linuxArm64 target** — Add when ARM64 Linux hardware demand exists
- **AppImage / Flatpak / Snap packaging** — Belongs in a later packaging/distribution phase
- **KWallet native support** — libsecret covers GNOME; KWallet can be added later if KDE users need it
- **Full accessibility support** — GTK 4 has a11y built in, but explicit a11y testing deferred
- **Linux CI/CD pipeline** — Can be established during implementation; full CI belongs in packaging phase
- **CLI-only mode** — A terminal-driven mode for headless/tmux users; interesting but not in scope

</deferred>

---

*Phase: 02-linux-shell-settings*
*Context gathered: 2026-03-29*

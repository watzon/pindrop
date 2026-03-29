# Domain Pitfalls

**Domain:** Linux-first native desktop expansion for a shipped macOS dictation app with increasing Kotlin Multiplatform ownership
**Researched:** 2026-03-29
**Overall confidence:** MEDIUM

## Critical Pitfalls

### Pitfall 1: Over-sharing platform shell behavior into Kotlin
**What goes wrong:** Teams move tray behavior, window lifecycles, global hotkeys, recorder lifecycle, and startup policy into shared Kotlin because “desktop is desktop,” then end up with leaky abstractions that fit neither macOS nor Linux well.

**Why it happens:** The pressure to increase shared ownership is real, but Kotlin docs explicitly steer projects toward interfaces/DI and small `expect`/`actual` seams rather than stuffing complex platform behavior behind giant common abstractions. Pindrop is especially exposed because `AppCoordinator` already mixes boot, hotkeys, windowing, and transcription lifecycle in one place.

**Consequences:**
- Linux integrations become awkward wrappers around macOS-shaped assumptions.
- Shared code becomes hard to test because it now models OS behavior instead of product policy.
- Future Windows support inherits Linux/macOS compromise APIs instead of clean ports.

**Warning signs:**
- Shared modules start defining concepts like tray icon state, floating window geometry, or recorder permission UX directly.
- `expect`/`actual` counts rise quickly for app-shell concerns instead of staying small and capability-oriented.
- Linux implementation needs many “if desktop environment is X” branches inside shared code.

**Prevention:**
- Keep shared Kotlin authoritative for product policy, state machines, model selection, localization, history/query logic, and transcription orchestration policy.
- Keep platform shell concerns behind narrow ports: `GlobalShortcutPort`, `TrayPort`, `AutostartPort`, `AudioCapturePort`, `WindowingPort`, `SecretStorePort`.
- Use interfaces + DI as the default; reserve `expect`/`actual` for tiny primitives or capability probes.
- Split `AppCoordinator` before or while adding Linux so platform boot code has clean ownership boundaries.

**Detection:**
- Shared code reviews become dominated by desktop-environment edge cases.
- Linux work frequently requires changing common code for UI-shell behavior.

**Phase to address:** Phase 1 — shared/platform boundary design.

**Linux-specific operational or packaging traps:** None directly, but this pitfall is what causes later Wayland/X11/tray/autostart packaging pain to spill into the shared layer.

### Pitfall 2: Keeping dual authority paths during migration
**What goes wrong:** Swift fallback logic and Kotlin logic both remain live for the same feature, so behavior diverges by build configuration or platform.

**Why it happens:** Pindrop already has this risk today: multiple features have `#if canImport(...)` KMP paths plus local Swift fallbacks. When Linux lands, teams often add yet another branch instead of deleting the old authority.

**Consequences:**
- macOS and Linux disagree on business rules even when “shared” logic supposedly owns them.
- Bugs reproduce only in packaged builds or only on machines missing shared artifacts.
- Roadmap work looks complete before real parity exists.

**Warning signs:**
- Same rule exists in Swift and Kotlin with slightly different defaults or enum mappings.
- QA failures mention “works on Mac but not Linux” for non-platform-specific behavior.
- Packaged builds behave differently from dev builds with embedded/shared artifacts.

**Prevention:**
- For each migrated feature, declare one source of truth and delete or hard-fail the old path.
- Add parity tests at the contract level for shared-owned features.
- Track migration feature-by-feature, not file-by-file: history search, transcription policy, model management, localization, AI enhancement request shaping.
- Replace silent fallback with explicit capability failure where shared artifacts are required.

**Detection:**
- Snapshot/contract tests differ across macOS Swift and Linux Kotlin-backed implementations.
- Build scripts need special-case logic to guess whether shared frameworks are present.

**Phase to address:** Phase 2 — shared-logic migration and parity hardening.

**Linux-specific operational or packaging traps:** Packaged Linux builds can accidentally omit a shared artifact or resource and silently fall onto a non-authoritative local code path unless fallback is removed.

### Pitfall 3: Treating Linux desktop integration like a solved, uniform API surface
**What goes wrong:** Teams assume global shortcuts, tray presence, background execution, and autostart behave like macOS system APIs. They discover late that Linux integration is capability-based and desktop-environment dependent.

**Why it happens:** macOS offers a much more centralized platform story. Linux desktop features are spread across freedesktop specs, portals, D-Bus conventions, and varying environment support. The XDG portal docs encourage using portals for unified integration, and global shortcuts/background/autostart are explicitly portal/spec-managed concerns.

**Consequences:**
- “Near-macOS parity” slips because hotkeys or tray flows fail on some desktops.
- Support load spikes with GNOME/KDE/Wayland/X11-specific bugs.
- The Linux app feels broken rather than gracefully degraded.

**Warning signs:**
- Engineering language says “Linux supports global hotkeys” without specifying Wayland/X11/session requirements.
- No capability matrix exists for tray, global shortcuts, autostart, background status, microphone access, and notifications.
- UI has no fallback path when tray or global shortcuts are unavailable.

**Prevention:**
- Build a Linux capability matrix early: Wayland vs X11, portal available vs unavailable, tray supported vs unsupported, packaged vs unpackaged.
- Prefer portal-backed integrations where possible for shortcuts/background/file flows.
- Design graceful degradation: if global shortcut registration fails, surface settings guidance and allow manual start from tray/window.
- Make capabilities queryable from platform ports and visible in diagnostics.

**Detection:**
- Early test sessions fail only on specific desktop sessions.
- Support logs show `isSupported == false` style capability failures or missing portal services.

**Phase to address:** Phase 2 — Linux shell/integration spike.

**Linux-specific operational or packaging traps:**
- Global shortcuts should be treated as a runtime capability, not guaranteed behavior.
- Tray support must be probed at runtime; official Java tray APIs explicitly do not guarantee support on all platforms.
- Autostart should use correct `.desktop`/portal semantics, not ad-hoc shell scripts.

### Pitfall 4: Leaving packaging and distribution until the end
**What goes wrong:** The app works from IDE/dev shell, but the first packaged Linux build fails because resources, JDK modules, desktop entry metadata, icons, executable paths, or shared/native assets are wrong.

**Why it happens:** Packaging feels like release plumbing, but for Linux desktop apps it is part of the product surface. Compose native distributions require explicit packaging configuration, Linux package metadata, resource inclusion strategy, and sometimes explicit JDK modules. Cross-compilation is also not supported for native distribution tasks.

**Consequences:**
- “Feature complete” milestone is followed by a long packaging death march.
- Installer launches but app cannot find models, icons, or helper binaries.
- CI can build macOS artifacts yet still cannot prove Linux distributability.

**Warning signs:**
- Linux work is validated only with `run`/IDE launches, never with packaged artifacts.
- No plan exists for `.deb`/`.rpm` metadata, icons, `.desktop` file behavior, or bundled resources.
- Team assumes macOS CI can generate final Linux installers.

**Prevention:**
- Decide distribution format strategy early: at minimum one first-class package format plus install docs; ideally test both `.deb` and `.rpm` if promised.
- Introduce packaged-app smoke tests early, not after feature parity.
- Maintain a packaging manifest for models, native helpers, icons, desktop entry, autostart entry, and translations.
- Run Linux packaging on Linux builders.
- Start with `runDistributable`/packaged execution, not only IDE runs.

**Detection:**
- Packaged app throws `ClassNotFoundException`, cannot find resources, or uses wrong executable path.
- Installer succeeds but tray/autostart/menu entries do not.

**Phase to address:** Phase 3 — packaging and release pipeline.

**Linux-specific operational or packaging traps:**
- Compose packaging docs explicitly warn that required JDK modules may need manual inclusion.
- Linux package versions have format-specific rules.
- Cross-building Linux installers from macOS should not be assumed.

### Pitfall 5: Shipping Linux transcription as “the engine” instead of “engine + runtime environment”
**What goes wrong:** Teams implement the transcription backend but forget the operational reality: model download/storage paths, helper executable discovery, CPU architecture, sandboxed file access, temp directories, and packaged resource lookup.

**Why it happens:** On macOS, WhisperKit is already integrated natively and much of the runtime context is hidden inside the app’s current packaging assumptions. Linux will need explicit runtime rules, and Pindrop’s shared runtime-transcription module already hints at multi-target runtime orchestration, not just business logic.

**Consequences:**
- Transcription works in dev but not from installed packages.
- Model management becomes flaky or distro-specific.
- Large model assets land in the wrong location or are lost across updates.

**Warning signs:**
- Model paths are hard-coded relative to the repo or current working directory.
- Backend tests run only on JVM unit tests, not packaged Linux environments.
- Linux packaging discussions ignore model/cache migration and disk quota behavior.

**Prevention:**
- Treat Linux transcription as a deployable subsystem: define install-time vs first-run assets, cache directories, migration rules, cleanup rules, and diagnostics.
- Make runtime paths explicit through injected filesystem/environment ports.
- Add smoke tests for packaged app + model download + first transcription.
- Decide early whether helper binaries are bundled, downloaded, or user-provided.

**Detection:**
- First-run transcription fails only outside the repo checkout.
- Support logs show missing model files, permission errors, or wrong architecture binaries.

**Phase to address:** Phase 2 for design, Phase 3 for packaged validation.

**Linux-specific operational or packaging traps:**
- Include models/native helpers via a deliberate resource strategy; packaged apps do not share the repo’s filesystem layout.
- Current shared runtime targets show `linuxX64` only; if arm64 Linux support matters later, architecture policy must be explicit.

### Pitfall 6: Ignoring secrets, startup state, and background permissions on Linux
**What goes wrong:** API keys, login/autostart state, and background execution are treated like simple preference fields instead of OS-integrated capabilities.

**Why it happens:** macOS already has Keychain/login-item patterns in the app. Linux equivalents are more fragmented: background/autostart are spec/portal-driven, and secret handling often needs a keyring or portal-backed approach.

**Consequences:**
- Sensitive settings end up in plain-text config too early.
- Autostart feels unreliable or impossible to disable cleanly.
- Background behavior differs between packaged and unpackaged installations.

**Warning signs:**
- API key storage is planned as “just save it in settings JSON for now.”
- Autostart is implemented as a shell script without `.desktop` ownership.
- No user-facing diagnostics explain whether background/autostart permission was granted.

**Prevention:**
- Define `SecretStorePort` and `AutostartPort` as first-class platform services.
- Use freedesktop-compliant `.desktop`/autostart behavior and portal background requests where applicable.
- Add settings diagnostics for secret storage availability and autostart state.
- Treat unsupported secure storage as a product decision, not a silent fallback.

**Detection:**
- Credentials disappear between sessions or are visible in config exports.
- Users report autostart entries that cannot be disabled cleanly.

**Phase to address:** Phase 2 — Linux system integration.

**Linux-specific operational or packaging traps:**
- Autostart belongs in XDG autostart locations with valid desktop entry semantics.
- Background/autostart may require portal-mediated permission in sandboxed environments.

## Moderate Pitfalls

### Pitfall 7: Keeping localization split across Apple catalogs and Linux resources too long
**What goes wrong:** macOS continues to use `.xcstrings` as the real source while Linux starts its own resource catalog, producing translation drift and mismatched keys.

**Why it happens:** The current shipped app is Apple-native and its localization pipeline is already real. Without an explicit migration plan, Linux adds a second truth source by convenience.

**Consequences:**
- Cross-platform copy diverges.
- Feature work slows because every copy change requires multiple translation systems.
- Shared Kotlin presenters cannot reliably reference canonical keys.

**Warning signs:**
- Same user-facing string exists in `.xcstrings`, Kotlin resources, and Linux UI code.
- Translation review needs manual reconciliation across platforms.

**Prevention:**
- Pick a single shared localization source before large Linux UI expansion.
- Generate platform-consumable artifacts from that source rather than hand-maintaining both.
- Move shared-presenter copy decisions to key-based interfaces, not inline English strings.

**Detection:**
- QA sees different wording for the same flow on macOS and Linux.

**Phase to address:** Phase 1 — cross-platform product foundations.

**Linux-specific operational or packaging traps:** Ensure packaged Linux builds include generated localization bundles/resources; do not rely on dev-path resource loading.

### Pitfall 8: Testing only business logic, not packaged desktop behavior
**What goes wrong:** Shared Kotlin tests pass, but installed Linux builds fail on desktop integration, packaged resources, microphone access, tray availability, or autostart behavior.

**Why it happens:** KMP unit tests are easier to automate than real desktop-session tests. Pindrop already has opt-in integration tests and thin UI coverage on macOS; Linux would inherit that blind spot unless test strategy changes.

**Consequences:**
- Regressions appear only in dogfooding or first release candidates.
- Teams misread unit-test health as product readiness.

**Warning signs:**
- CI proves only JVM/shared tests.
- No matrix exists for packaged Linux smoke tests on real sessions.
- Linux QA relies on one developer workstation.

**Prevention:**
- Add layered validation: shared contract tests, platform-port tests, packaged smoke tests, and manual desktop-matrix verification.
- Treat Wayland/X11 and packaged/unpackaged as explicit QA dimensions.
- Capture diagnostics from portal availability, tray support, and hotkey registration.

**Detection:**
- “Works on my machine” dominates Linux bug triage.

**Phase to address:** Phase 3 — release hardening.

**Linux-specific operational or packaging traps:** Run smoke tests against actual installed artifacts, not just Gradle `run`.

## Minor Pitfalls

### Pitfall 9: Assuming current linuxX64 stubs equal product readiness
**What goes wrong:** The existence of `linuxX64()` targets in shared modules is mistaken for meaningful Linux support progress.

**Why it happens:** Target declarations create a false sense of portability. In Pindrop, root tasks explicitly say Linux support is still a stub.

**Consequences:**
- Planning underestimates platform-expansion cost.
- Critical Linux-only work is discovered late.

**Warning signs:**
- Milestone language cites compile targets instead of shipped workflows.

**Prevention:**
- Track readiness by user workflow and packaged artifact, not by Gradle target presence.

**Detection:**
- Demos show successful compilation but no installable Linux app.

**Phase to address:** Immediately in roadmap framing.

**Linux-specific operational or packaging traps:** None beyond planning distortion.

## Phase-Specific Warnings

| Phase Topic | Likely Pitfall | Mitigation |
|-------------|---------------|------------|
| Shared/platform boundary design | Over-sharing OS shell behavior into Kotlin | Freeze clear port boundaries before migrating features |
| Shared logic migration | Dual authority between Swift and Kotlin | One owner per feature; remove fallback after migration |
| Linux shell integration | Assuming hotkeys/tray/background are uniform on Linux | Build capability matrix; use portals/specs; design graceful degradation |
| Linux transcription/runtime | Backend works in dev but not packaged app | Define runtime filesystem/resource model and packaged smoke tests |
| Packaging/distribution | Delaying `.deb`/`.rpm` and resource bundling until the end | Package early on Linux builders; validate installed artifacts continuously |
| QA/release hardening | Unit tests pass while desktop product fails | Add packaged-session smoke tests and desktop-matrix verification |

## Sources

### High confidence
- Pindrop project context: `.planning/PROJECT.md`
- Current codebase risks: `.planning/codebase/CONCERNS.md`
- Current stack and target status: `.planning/codebase/STACK.md`, `shared/README.md`, `shared/build.gradle.kts`, `shared/runtime-transcription/build.gradle.kts`
- Kotlin Multiplatform docs — use platform-specific APIs: https://www.jetbrains.com/help/kotlin-multiplatform-dev/multiplatform-connect-to-apis.html
- Kotlin Multiplatform docs — expected and actual declarations: https://www.jetbrains.com/help/kotlin-multiplatform-dev/multiplatform-expect-actual.html
- Kotlin Multiplatform docs — hierarchical project structure: https://www.jetbrains.com/help/kotlin-multiplatform-dev/multiplatform-hierarchy.html
- Compose Multiplatform docs — native distributions: https://www.jetbrains.com/help/kotlin-multiplatform-dev/compose-native-distribution.html
- XDG Desktop Portal — reasons to use portals: https://flatpak.github.io/xdg-desktop-portal/docs/reasons-to-use-portals.html
- XDG Desktop Portal — Global Shortcuts: https://flatpak.github.io/xdg-desktop-portal/docs/doc-org.freedesktop.portal.GlobalShortcuts.html
- XDG Desktop Portal — Background: https://flatpak.github.io/xdg-desktop-portal/docs/doc-org.freedesktop.portal.Background.html
- XDG Desktop Portal — Secret: https://flatpak.github.io/xdg-desktop-portal/docs/doc-org.freedesktop.portal.Secret.html
- Freedesktop Autostart spec: https://specifications.freedesktop.org/autostart-spec/latest/
- Freedesktop Desktop Entry spec: https://specifications.freedesktop.org/desktop-entry-spec/latest/
- Oracle JDK 21 `SystemTray` docs: https://docs.oracle.com/en/java/javase/21/docs/api/java.desktop/java/awt/SystemTray.html

### Low confidence / validate in phase research
- Exact desktop-environment support matrix for tray and global shortcuts across GNOME/KDE/Wayland/X11 combinations.
- Exact Linux packaging toolchain to be used for the future native GUI if it differs from Compose Multiplatform assumptions.

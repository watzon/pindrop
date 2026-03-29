# Technology Stack

**Project:** Pindrop Linux desktop expansion
**Researched:** 2026-03-29
**Scope:** Linux-native client delta + more Kotlin Multiplatform reuse
**Overall confidence:** MEDIUM-HIGH

## Recommendation in One Sentence

Use **Kotlin Multiplatform 2.3.x + Compose Multiplatform Desktop (JVM) on Linux**, keep **macOS UI native SwiftUI/AppKit**, move reusable domain/runtime/localization into **shared KMP modules**, run Linux local ASR through a **packaged whisper.cpp sidecar**, and handle Linux desktop integration through a **small Linux integration layer** built around **D-Bus/XDG portals, PipeWire, and freedesktop desktop-entry/autostart standards**.

## Recommended Stack

### Core application stack

| Layer | Technology | Version / line | Purpose | Why this fits Pindrop | Confidence |
|---|---|---:|---|---|---|
| Shared business logic | Kotlin Multiplatform | **2.3.20 latest**; repo is on **2.3.10** | Shared domain logic, orchestration, model policy, settings, localization access | The repo already has KMP modules and linux/windows targets stubbed. This is the cheapest path to share more logic without rewriting macOS UI. | HIGH |
| Linux UI | Compose Multiplatform Desktop | **1.10.3 stable**; **1.11.0-beta01 latest** | Native-feeling Linux desktop UI on JVM | Best-supported 2026 path for Kotlin-first desktop UI, integrates directly with the KMP Gradle workspace, and avoids building/maintaining a second UI stack just for Linux. | HIGH |
| macOS UI | SwiftUI + AppKit | existing | Keep shipped macOS UX intact | This is a hard project constraint. Do not regress the current Mac app to gain Linux reuse. | HIGH |
| Shared async/state | kotlinx.coroutines + kotlinx.serialization | current KMP-compatible line | Shared async workflows, state machines, typed config/state payloads | Natural fit for the existing shared runtime modules and future Windows reuse. | MEDIUM |

### Local transcription stack

| Layer | Technology | Version / line | Purpose | Why this fits Pindrop | Confidence |
|---|---|---:|---|---|---|
| macOS local ASR | WhisperKit | existing | Keep current macOS transcription path | Explicitly out of scope to replace. | HIGH |
| Linux local ASR engine | whisper.cpp | **v1.8.4 latest release** | Offline local transcription on Linux | It is the current cross-platform Whisper workhorse, supports Linux, Java bindings exist, and official builds support CPU, Vulkan, CUDA, OpenVINO, FFmpeg, VAD, and streaming examples. | HIGH |
| Linux ASR packaging model | **Sidecar process around whisper.cpp** | repo-defined | Stable engine boundary for JVM app | Better than binding deep inference internals directly into the Compose process. It isolates native deps, GPU backend choices, crashes, and future Windows portability. | MEDIUM-HIGH |
| Audio normalization | FFmpeg | system/package dependency or bundled helper | Convert arbitrary audio to 16 kHz mono PCM for transcription | Whisper already expects normalized audio; this reduces format-specific app code. | MEDIUM |

### Persistence and shared data

| Layer | Technology | Version / line | Purpose | Why this fits Pindrop | Confidence |
|---|---|---:|---|---|---|
| New shared persistence | SQLDelight | **2.1.0** | Shared SQLite schema/query layer for Linux + future Windows and optionally new shared Mac features | Strong KMP fit, typed queries, native + JVM drivers. Good for history/search/model metadata/settings that should stop living in platform-only persistence. | HIGH |
| Existing macOS persistence | SwiftData | existing | Keep current shipped Mac storage working | Do not do a risky big-bang migration just to unlock Linux. Introduce SQLDelight only for newly-shared stores and migrate selectively later. | HIGH |

### Localization and resources

| Layer | Technology | Version / line | Purpose | Why this fits Pindrop | Confidence |
|---|---|---:|---|---|---|
| Shared strings/resources | moko-resources | **0.26.1** | Shared strings/plurals/images/colors/files across KMP, JVM, and Apple targets | It supports JVM and macOS/iOS, exports resource access to Swift, and is materially better aligned with “one localization source of truth” than maintaining Swift string catalogs plus a separate Linux system. | MEDIUM-HIGH |
| Linux UI resource usage | Compose + moko-resources / Compose resources | current | Consume shared strings/assets in Linux UI | Straightforward on the Linux JVM side. | HIGH |
| macOS resource usage | Swift bridging to KMP resources | current | Consume shared strings from native SwiftUI/AppKit UI | This is the key delta: keep native Mac UI while moving string ownership into shared Kotlin. | MEDIUM |

### Linux desktop integration

| Concern | Technology | Version / line | Purpose | Why this fits Pindrop | Confidence |
|---|---|---:|---|---|---|
| D-Bus / portals client | dbus-java | **5.2.x stable** | Call XDG desktop portals and other D-Bus services from JVM | Actively maintained, Java 21-friendly branch, and the pragmatic JVM choice for portal-backed Linux integration. | MEDIUM |
| Global hotkeys (Wayland-first) | XDG Desktop Portal `GlobalShortcuts` | portal interface v2 docs | Register user-approved global shortcuts | This is the standards-aligned path on modern Wayland desktops. Pindrop should treat it as primary, not optional. | HIGH |
| Global hotkeys fallback (X11 only) | X11-specific native hook adapter | repo-defined | Support distros/sessions without portal coverage | Needed for broader Linux reach, but must be behind a platform adapter and never be the primary abstraction. | MEDIUM |
| Tray/status icon | **Linux integration adapter targeting StatusNotifier/AppIndicator** | repo-defined | Tray-first app entry point on Linux | Pindrop is tray-centric. Treat tray as a first-class native integration surface, not a generic widget. | MEDIUM |
| Auto-start (non-sandboxed) | freedesktop `.desktop` + Autostart spec | spec-defined | Login launch | Standard Linux desktop behavior. | HIGH |
| Auto-start/background (sandboxed) | XDG Desktop Portal `Background` | portal interface v2 docs | Flatpak-safe autostart/background request | Necessary if Flatpak becomes a shipping format. | HIGH |
| Audio capture | PipeWire-native Linux adapter | PipeWire 1.6.x docs | Microphone capture on modern Linux desktops | PipeWire is the modern Linux desktop audio stack; do not build Linux dictation around Java Sound. | MEDIUM |

### Packaging and distribution

| Channel | Technology | Purpose | Why this fits Pindrop | Confidence |
|---|---|---|---|---|
| Native installers | Compose Multiplatform `nativeDistributions` + `jpackage` | Build `.deb` and `.rpm` installers | Official Compose path, easiest to automate in the same Gradle build. | HIGH |
| Cross-distro desktop delivery | Flatpak manifest + `flatpak-builder` | Reach mainstream Linux desktops with sandbox-aware integration | Worth adding once portal-based hotkeys/background flows are implemented. | MEDIUM |
| JVM bundling | jlink / bundled runtime via Compose | Ship self-contained app runtime | Avoids “install Java first” support burden. | HIGH |

## Prescriptive Choices

### 1) Linux UI: use Compose Desktop, not GTK/Qt bindings

**Use:** Compose Multiplatform Desktop on JVM for the Linux client.

**Why:**
- It matches the repo’s Kotlin-first sharing direction.
- It reduces context-switching versus building Linux UI in a second native toolkit.
- It works cleanly with shared KMP state, theme, navigation, and settings modules already present.

**Do not use:** GTK/Qt bindings for the first Linux release.

**Why not:** They would produce a more “purely native” Linux feel, but they would also create a second non-Mac UI stack with much higher maintenance cost and much less leverage from the existing KMP work.

### 2) Linux ASR: use whisper.cpp as a sidecar, not in-process JVM-only inference

**Use:** whisper.cpp packaged as a Linux-native helper process, controlled by shared Kotlin orchestration.

**Why:**
- Native inference deps are easier to isolate.
- GPU backend selection can vary by distro/hardware without destabilizing the UI process.
- The same engine boundary can later support Windows.
- Official whisper.cpp support is broad and current on Linux.

**Do not use:** WhisperKit on Linux, or a Linux-only ASR path tightly coupled to Compose/JVM internals.

**Why not:** WhisperKit is Apple-specific, and a JVM-only inference stack would raise support risk for native deps and GPU acceleration.

### 3) Shared persistence: introduce SQLDelight for new shared stores only

**Use:** SQLDelight for new shared persistence domains: transcript history metadata, search indexing metadata, model inventory, shared settings, and job state.

**Why:**
- It is the correct KMP persistence tool for Linux/Windows reuse.
- It avoids duplicating schema/query logic across JVM and Apple.

**Do not use:** a full SwiftData-to-SQLDelight rewrite before Linux ships.

**Why not:** That is roadmap poison. Linux support is the goal; a persistence rewrite is only justified where sharing clearly pays back.

### 4) Localization: use moko-resources as the shared source of truth

**Use:** moko-resources for shared strings/plurals/assets, with Swift bridge usage on macOS and Compose usage on Linux.

**Why:**
- It already supports JVM + Apple targets.
- It explicitly supports resource access from Swift.
- It solves the project’s “single source of truth” requirement better than parallel `.xcstrings` plus Linux resource files.

**Do not use:** separate localization systems per app.

**Why not:** This directly violates the milestone requirement and creates ongoing translation drift.

### 5) Hotkeys: Wayland portal first, X11 fallback second

**Use:** XDG `GlobalShortcuts` portal as the primary Linux global-hotkey implementation.

**Why:**
- Wayland is the platform reality.
- Portal-managed shortcuts are the standards-aligned, user-approved path.

**Fallback:** add an X11-only adapter for sessions where portals are unavailable.

**Do not use:** JNativeHook as the primary solution.

**Why not:** Its own docs say Linux support is **X11 Linux** only, and its latest release surfaced in 2022. That is the wrong foundation for a 2026 Linux desktop app where Wayland matters.

### 6) Tray/app entry: build a Linux-native tray integration layer

**Use:** a Linux integration module that targets StatusNotifier/AppIndicator behavior, exposed to the app through a Kotlin interface.

**Why:**
- Pindrop is a tray-first product, so tray behavior is core product surface, not decoration.
- Linux tray behavior is desktop-environment-specific enough that it deserves a dedicated adapter.

**Do not use:** Compose `Tray` as the only long-term tray implementation.

**Why not:** It is fine for prototypes, but Pindrop needs reliable tray-first behavior across real Linux desktop environments.

### 7) Packaging: ship `.deb`/`.rpm` first, add Flatpak after portal flows work

**Use first:** Compose native distributions for `.deb` and `.rpm`.

**Add next:** Flatpak once global shortcuts/background/autostart are portal-backed and validated.

**Why:**
- `.deb`/`.rpm` are the shortest path to a real installer from the Compose toolchain.
- Flatpak becomes attractive after Linux integrations are designed around portals anyway.

**Do not assume:** Compose gives you AppImage out of the box.

**Why not:** Official Compose packaging docs currently list Linux outputs as `.deb` and `.rpm`, not AppImage.

## Recommended Module Layout Delta

| Module | Recommendation | Notes |
|---|---|---|
| `shared/core` | Expand aggressively | Move settings contracts, transcript formatting rules, history/search policies, localization access, model metadata, onboarding/settings state here. |
| `shared/feature-transcription` | Keep as orchestration layer | Engine selection and job lifecycle should stay shared; engine execution remains platform-specific. |
| `shared/runtime-transcription` | Make cross-platform runtime contract real | Define `TranscriptionEnginePort`, `AudioCapturePort`, `ModelStorePort`, `EnhancementPort`. |
| `shared/persistence-*` | Add | New SQLDelight-backed shared stores. |
| `shared/resources` | Add | Centralize moko-resources strings/plurals/icons/colors. |
| `linux-app` | Add | Compose Desktop app shell, windows, settings, recording UI, history UI, tray wiring. |
| `linux-integration` | Add | D-Bus, portal, tray, autostart, PipeWire, desktop-entry wiring. |
| `linux-transcription-sidecar` | Add | whisper.cpp wrapper, model management, backend detection, optional ffmpeg bridge. |

## Platform Differences to Design For

| Concern | macOS today | Linux recommendation | Future Windows implication |
|---|---|---|---|
| UI toolkit | SwiftUI/AppKit | Compose Desktop | Likely Compose Desktop or native WinUI wrapper later |
| Global hotkey | Carbon/AppKit/native APIs | XDG GlobalShortcuts portal, then X11 fallback | `RegisterHotKey` or low-level Windows hook later |
| Tray | `NSStatusItem` | StatusNotifier/AppIndicator adapter | Windows notification area adapter |
| Auto-start | ServiceManagement / login item patterns | `.desktop` autostart + portal Background for Flatpak | Startup folder / scheduled task / registry |
| Audio capture | AVFoundation | PipeWire-native adapter | WASAPI adapter |
| Local ASR | WhisperKit | whisper.cpp sidecar | whisper.cpp sidecar can be reused |
| Persistence | SwiftData | SQLDelight for new shared domains | SQLDelight reuses cleanly |
| Localization | `.xcstrings` today | move to shared KMP resources | same shared KMP resources |

## What Not to Use

| Avoid | Why |
|---|---|
| Electron / Tauri | Wrong fit for a native desktop dictation app that already has native macOS code and a growing KMP core. |
| JNativeHook as primary hotkey layer | X11-only on Linux and stale release cadence for a Wayland-first world. |
| Big-bang SwiftData replacement | Delays Linux shipping and adds migration risk before value is proven. |
| Compose-only tray abstraction as final design | Too important a product surface to leave to a generic abstraction. |
| Separate translation systems per platform | Violates the milestone’s shared-localization requirement and multiplies ongoing cost. |
| Direct in-process Linux GPU inference inside the UI app as v1 | Harder to debug, package, and stabilize than a sidecar boundary. |

## Recommended Version Targets for Planning

| Technology | Target |
|---|---|
| Kotlin Multiplatform | Upgrade shared workspace from **2.3.10** to **2.3.20** unless a dependency blocks it |
| Compose Multiplatform | Start on **1.10.3 stable**, not 1.11 beta |
| SQLDelight | **2.1.0** |
| moko-resources | **0.26.1** |
| dbus-java | **5.2.x** stable line |
| whisper.cpp | **1.8.4** or current stable at implementation start |

## Roadmap Implications

1. **Do Linux UI and Linux integration as separate tracks.** Compose windows/views are not the hard part; tray, shortcuts, autostart, audio capture, and packaging are.
2. **Create a real engine boundary before shipping Linux transcription.** Shared Kotlin should choose and orchestrate engines; Linux/macOS should each execute their own engine stack.
3. **Move localization into shared Kotlin early.** This is one of the few cross-platform changes that benefits both macOS and Linux immediately.
4. **Adopt SQLDelight only where sharing matters.** Start with new shared stores, not a repo-wide migration.
5. **Treat Wayland as the default Linux target.** Anything that only works on X11 is fallback code.

## Confidence Notes

- **HIGH:** KMP + Compose Desktop + Compose packaging + XDG portal/autostart standards + whisper.cpp capability claims.
- **MEDIUM-HIGH:** moko-resources as the best fit for shared macOS/Linux localization in this repo.
- **MEDIUM:** dbus-java as the D-Bus client choice; PipeWire adapter shape; Linux tray implementation details; sidecar-vs-JNI implementation boundary.
- **LOW:** Any assumption that one tray implementation will behave identically across all Linux desktop environments without distro-specific validation.

## Sources

- Repo context: `.planning/PROJECT.md`, `.planning/codebase/STACK.md`, `.planning/codebase/ARCHITECTURE.md`
- Kotlin Multiplatform Gradle plugin portal — latest `org.jetbrains.kotlin.multiplatform` **2.3.20** (created 2026-03-16): https://plugins.gradle.org/plugin/org.jetbrains.kotlin.multiplatform
- JetBrains Compose Gradle plugin portal — latest `org.jetbrains.compose` **1.11.0-beta01**, latest stable listed **1.10.3** (created 2026-03-26): https://plugins.gradle.org/plugin/org.jetbrains.compose
- JetBrains Compose native distributions docs (updated 2026-03-26): https://www.jetbrains.com/help/kotlin-multiplatform-dev/compose-native-distribution.html
- JetBrains Compose desktop-only API docs (`Tray`, menu bar, desktop APIs; updated 2026-03-26): https://www.jetbrains.com/help/kotlin-multiplatform-dev/compose-desktop-components.html
- JetBrains Compose multiplatform resources overview (updated 2026-03-26): https://www.jetbrains.com/help/kotlin-multiplatform-dev/compose-multiplatform-resources.html
- SQLDelight multiplatform SQLite docs **2.1.0**: https://sqldelight.github.io/sqldelight/2.1.0/multiplatform_sqlite/
- whisper.cpp repo and README, latest release **v1.8.4** (2026-03-19): https://github.com/ggml-org/whisper.cpp
- PipeWire docs site showing **PipeWire 1.6.2**: https://docs.pipewire.org/
- XDG Desktop Portal `GlobalShortcuts` docs: https://flatpak.github.io/xdg-desktop-portal/docs/doc-org.freedesktop.portal.GlobalShortcuts.html
- XDG Desktop Portal `Background` docs: https://flatpak.github.io/xdg-desktop-portal/docs/doc-org.freedesktop.portal.Background.html
- Freedesktop Desktop Entry Specification: https://specifications.freedesktop.org/desktop-entry-spec/latest/
- Freedesktop Desktop Application Autostart Specification: https://specifications.freedesktop.org/autostart-spec/latest/
- Ayatana Indicators overview / SNI context: https://ayatanaindicators.github.io/
- dbus-java repo (Java 21+/current lines documented): https://github.com/hypfvieh/dbus-java
- JNativeHook repo (documents X11 Linux support; latest release surfaced as 2022): https://github.com/kwhat/jnativehook
- moko-resources repo/README, latest release **0.26.1** (2026-03-15): https://github.com/icerockdev/moko-resources

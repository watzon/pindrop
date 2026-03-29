# Architecture Patterns

**Domain:** Linux-first native desktop dictation for an existing macOS app with a Kotlin Multiplatform core  
**Researched:** 2026-03-29  
**Confidence:** MEDIUM-HIGH

## Recommendation

Use a **shared-core + native-shell** architecture:

- **Shared Kotlin Multiplatform** owns product rules, session state, job orchestration, localization keys/resources, sync-free persistence models, search/filter logic, model-selection policy, and transcription workflow state machines.
- **macOS shell** stays fully native (`SwiftUI`/`AppKit`) and keeps **WhisperKit, audio capture, text insertion, permissions, SwiftData, menu bar, hotkeys, and windowing** platform-native.
- **Linux shell** is a separate native desktop client that consumes the shared Kotlin core and provides **Linux-only adapters** for tray, hotkeys, microphone capture, text insertion, packaging, and local persistence.

This is how desktop apps like dictation tools typically avoid a rewrite: **share deterministic business logic, never share OS integration code**.

---

## Recommended Architecture

```text
                +--------------------------------------+
                | Shared Kotlin Multiplatform Core     |
                |--------------------------------------|
                | domain models                        |
                | dictation session state machine      |
                | transcription job orchestration      |
                | model selection / policy             |
                | history search/filter/sort logic     |
                | AI enhancement request shaping       |
                | localization resources + keys        |
                | repository interfaces / ports        |
                +-----------------+--------------------+
                                  |
                  +---------------+---------------+
                  |                               |
     +------------v------------+     +------------v------------+
     | macOS Native Shell      |     | Linux Native Shell      |
     |-------------------------|     |-------------------------|
     | SwiftUI/AppKit UI       |     | Linux GUI/tray UI       |
     | AppCoordinator split    |     | Linux app coordinator   |
     | WhisperKit adapter      |     | Linux transcription     |
     | AVFoundation recorder   |     | Linux recorder adapter  |
     | SwiftData adapter       |     | Linux persistence       |
     | macOS hotkey/output     |     | Linux hotkey/output     |
     +------------+------------+     +------------+------------+
                  |                               |
     +------------v------------+     +------------v------------+
     | macOS OS APIs           |     | Linux OS/Desktop APIs   |
     |-------------------------|     |-------------------------|
     | audio, AX, Carbon,      |     | Pulse/PipeWire, X11/    |
     | menu bar, keychain,     |     | Wayland/portal paths,   |
     | login items             |     | tray, .desktop, keyring |
     +-------------------------+     +-------------------------+
```

### Architectural Rule

If a component depends on **desktop session semantics, window manager behavior, compositor behavior, audio devices, accessibility, keyboard injection, tray APIs, or app packaging**, it is **platform-specific**.

If a component depends on **product rules and deterministic state transitions**, it should be **shared in Kotlin**.

---

## Component Boundaries

### Shared Kotlin modules

| Component | Responsibility | Communicates With |
|-----------|---------------|-------------------|
| `shared:domain` | Canonical models: transcription record, recording session, model metadata, enhancement request, settings DTOs, localization keys | All shared modules, native adapters |
| `shared:application` | Use cases and orchestration: start/stop recording intent handling, finalize transcript flow, enhancement pipeline, history actions | Platform ports, repositories, UI state |
| `shared:state` | Long-lived feature state machines for recorder, transcription jobs, model downloads, history, settings, onboarding | Application layer, platform UI presenters |
| `shared:policy` | Startup model resolution, engine capability policy, feature gating, fallback rules | Application layer |
| `shared:repositories` | Interfaces for persistence, settings, model catalog, transcript history, secure secrets, filesystem/model storage | Native implementations |
| `shared:localization` | Shared string catalog/resources and locale selection logic | macOS bridge, Linux UI |
| `shared:testkit` | Cross-platform parity tests for shared logic and contract tests for adapters | CI on all targets |

### macOS-specific components

| Component | Responsibility | Why Native |
|-----------|---------------|-----------|
| SwiftUI/AppKit UI shell | Menu bar app, windows, floating indicator, onboarding, settings UX | Hard requirement; preserve shipped UX |
| WhisperKit transcription adapter | Local transcription engine, streaming/finalization behavior | Explicitly required to remain native |
| Audio capture adapter | Microphone session, audio format conversion, buffer lifecycle | Uses Apple audio stack |
| Output insertion adapter | Accessibility/text insertion/paste behavior | OS-specific event/accessibility APIs |
| Hotkey/tray/window adapters | Global shortcuts, floating UI, menu bar | OS integration only |
| SwiftData repository adapter | Persistence implementation and migrations | Existing production store |
| Keychain/secrets adapter | Provider tokens and protected settings | OS-specific secure storage |

### Linux-specific components

| Component | Responsibility | Why Platform-Specific |
|-----------|---------------|----------------------|
| Linux desktop shell | App/tray entry point, windows, floating indicator, settings/history/transcribe flows | Different runtime and packaging model |
| Audio capture adapter | PipeWire/Pulse/ALSA-facing capture and buffering | Linux audio stack differs materially from macOS |
| Transcription engine adapter | Linux local engine integration and streaming/final transcript conversion | Engine/runtime likely differs from WhisperKit |
| Output insertion adapter | Clipboard/paste/direct text insertion strategy, X11/Wayland branching | Desktop environment and compositor dependent |
| Global hotkey adapter | Portal/X11/desktop-specific registration | Shortcut support varies by environment |
| Persistence adapter | Linux local DB/filesystem implementation and migrations | SwiftData not portable |
| Secret storage adapter | libsecret/keyring or local fallback | Platform secure storage differs |
| Packaging/autostart adapter | `.desktop`, autostart, update/distribution hooks | Freedesktop packaging/runtime concern |

### Do **not** share these

- UI view layer between macOS and Linux
- Recording device drivers / capture primitives
- WhisperKit integration
- Text insertion and input-simulation code
- Tray/hotkey/window lifecycle code
- Store engine implementation details (`SwiftData` vs Linux DB)

### Do share these aggressively

- Transcription job lifecycle state machine
- Model catalog and active-model decision logic
- Transcript post-processing pipeline
- History filtering/search/sorting logic
- AI enhancement request construction and validation
- Settings schema / defaults / feature flags
- Localization identifiers and copy source of truth
- Error taxonomy and analytics/log event names

---

## Data Flow

### 1. Recording flow

```text
User action (hotkey/tray/UI)
  -> platform shell coordinator
  -> shared application use case: requestStartRecording()
  -> shared policy validates state / active model / feature availability
  -> platform recorder adapter starts audio capture
  -> audio buffers stay platform-local
  -> platform transcription adapter receives buffers if streaming is enabled
  -> shared state machine receives partial/final transcript events
  -> platform UI renders state from shared view state
```

**Important boundary:** raw audio should not be pushed through the full shared layer unless required. Keep high-frequency audio buffer handling platform-local; send only coarse session events and transcript chunks into shared state.

### 2. Transcription flow

```text
Platform engine emits partial/final transcript
  -> shared application layer normalizes transcript event
  -> shared post-processing applies dictionary/prompt/enhancement policy
  -> shared state emits finalized transcript result
  -> platform output adapter inserts text / copies to clipboard / updates UI
  -> platform persistence adapter stores canonical shared record
```

**Why this split:** engine APIs differ by OS, but transcript lifecycle, cleanup, enhancement, and save semantics should stay identical.

### 3. Persistence flow

```text
Shared domain record
  -> shared repository interface
  -> platform repository adapter
  -> platform store (SwiftData on macOS, Linux DB/files on Linux)
  -> adapter maps back to shared domain models
  -> shared search/filter/sort logic prepares UI-facing state
```

**Recommendation:** share the **schema contract** and migration intent, not the database engine.

### 4. UI state flow

```text
Platform UI event
  -> platform presenter/view model
  -> shared use case / reducer / state machine
  -> shared immutable UI state snapshot
  -> platform-specific UI mapping
  -> rendered native controls
```

The shared layer should expose **presentation-ready state**, but each platform should still map it to native idioms.

### 5. Localization flow

```text
Shared localization source
  -> generated/shared resource accessors
  -> Linux UI reads shared resources directly
  -> macOS bridge resolves shared keys into Apple-facing localized strings
  -> selected locale persisted via platform settings adapter
```

**Recommendation:** make Kotlin the source of truth for translation keys and text. macOS should bridge into its current runtime localization system instead of remaining a separate authoring system forever.

---

## Patterns to Follow

### Pattern 1: Ports and adapters
**What:** Shared code defines interfaces; native shells implement them.

**When:** Use for recorder, transcription engine, persistence, hotkeys, output insertion, secrets, file paths.

**Example:**
```kotlin
interface RecordingPort {
    suspend fun start(session: RecordingSessionConfig)
    suspend fun stop(): RecordedAudio?
    val events: Flow<RecordingEvent>
}

interface TranscriptionPort {
    suspend fun beginStreaming(config: TranscriptionConfig)
    suspend fun pushAudio(chunk: AudioChunk)
    suspend fun finalize(): FinalTranscript
}
```

### Pattern 2: Shared state machines, native coordinators
**What:** Shared Kotlin decides valid transitions; native shells own lifecycle wiring.

**When:** Recorder lifecycle, download jobs, onboarding completion, enhancement pipeline.

**Why:** Avoids duplicating logic while keeping OS callbacks and UI boot code local.

### Pattern 3: Canonical shared DTOs at boundaries
**What:** Native adapters translate OS/engine types into shared domain DTOs immediately.

**When:** Transcript segments, model metadata, errors, persisted records.

**Why:** Prevents Swift/Linux runtime types from leaking across the app.

### Pattern 4: Capability-driven feature gating
**What:** Linux adapters report capabilities; shared policy decides which UX/features enable.

**When:** Streaming support, direct insertion vs clipboard fallback, global hotkey availability, autostart support.

**Why:** Linux desktop behavior varies too much for hard assumptions.

---

## Anti-Patterns to Avoid

### Anti-Pattern 1: “Shared UI means shared architecture”
**What:** Forcing macOS and Linux into one UI stack.

**Why bad:** Breaks the explicit macOS-native requirement and creates weakest-common-denominator desktop UX.

**Instead:** Share state/presentation contracts, not rendered views.

### Anti-Pattern 2: Sharing the persistence engine
**What:** Trying to make SwiftData the cross-platform store contract.

**Why bad:** Ties Linux architecture to Apple-only persistence and blocks future Windows support.

**Instead:** Share repository interfaces and record schema, with separate store implementations.

### Anti-Pattern 3: Letting raw OS events leak into shared code
**What:** Shared modules handling X11/Wayland/AppKit/Carbon concepts directly.

**Why bad:** Couples core logic to platform APIs and makes tests brittle.

**Instead:** Convert OS events into shared intents/events at the adapter boundary.

### Anti-Pattern 4: Repeating fallback logic in every client
**What:** One set of rules in Swift, another in Linux UI, a third in KMP.

**Why bad:** Existing codebase already shows drift risk around shared fallback behavior.

**Instead:** Put product rules in shared Kotlin and keep platform code as thin as possible.

---

## Suggested Module/Process Shape

### Shared side

```text
shared/
  core-domain/
  core-application/
  core-state/
  core-localization/
  feature-recording/
  feature-transcription/
  feature-history/
  feature-models/
  feature-settings/
  platform-contracts/
```

### App side

```text
Pindrop-macOS/
  native-ui/
  native-adapters/
  persistence-swiftdata/
  whisperkit-adapter/

Pindrop-linux/
  app-shell/
  linux-ui/
  linux-adapters/
  persistence-linux/
  linux-packaging/
```

---

## Build Order and Dependency Implications

### Recommended build order

1. **Stabilize platform contracts first**
   - Extract ports for recording, transcription, persistence, output insertion, hotkeys, localization access.
   - This is the key dependency inversion step.

2. **Move deterministic product logic into shared Kotlin**
   - Startup model selection
   - Session/transcription state machine
   - History/domain logic
   - Settings schema/defaults
   - Enhancement policy

3. **Refactor macOS to consume shared contracts without changing UX**
   - macOS becomes the first “client of the architecture”.
   - This reduces Linux risk.

4. **Implement Linux persistence + localization adapters**
   - These unblock settings/history screens and reduce the temptation to hardcode Linux-only state.

5. **Implement Linux shell integrations**
   - tray
   - hotkeys
   - floating indicator
   - autostart

6. **Implement Linux recording + transcription path**
   - Build core dictation loop only after shared orchestration already exists.

7. **Implement output insertion strategy matrix**
   - direct insertion where possible
   - clipboard/paste fallback where not
   - explicit UX signaling when capabilities are degraded

8. **Package and validate on real desktop environments**
   - GNOME Wayland
   - KDE Wayland
   - X11

### Dependency implications

- **Linux should depend on shared Kotlin first, not on copied macOS logic.**
- **macOS must be migrated onto the same contracts early** or Linux will fork behavior.
- **Localization should move before large Linux UI work**; otherwise copy is duplicated immediately.
- **Persistence contract must be shared before history/settings parity work**; otherwise Linux-specific stores will calcify.
- **Packaging constraints feed architecture early** because tray, hotkeys, autostart, and direct insertion are runtime capabilities, not just release tasks.

---

## Packaging and Runtime Considerations

### Linux packaging

For v1, architect Linux as an **unsandboxed desktop app first**.

Reason: dictation apps need some combination of:
- global shortcuts
- tray/background presence
- microphone access
- clipboard access
- possible input injection/direct insertion
- autostart

Flatpak portals now define **Global Shortcuts**, **Input Capture**, and **Remote Desktop** interfaces, but compositor/backend support is still an architectural variable, not something the app can assume universally. Build for capability detection, not guaranteed parity.

**Roadmap implication:** prioritize `deb`/`rpm`-style packaged installs first; defer sandboxed distribution until feature parity is proven.

### Autostart

Linux autostart should be treated as a platform adapter around Freedesktop `.desktop` autostart entries, not an app-level boolean alone.

### Wayland vs X11

This is the biggest Linux architectural fork.

- **Global shortcuts:** may use portal-based registration where available; otherwise environment-specific fallback may be required.
- **Direct text insertion/input simulation:** must be isolated behind a Linux output port because behavior differs sharply between X11 and Wayland/compositor support.
- **Floating indicator/window activation:** desktop-shell behavior varies and must stay outside shared logic.

### Audio runtime

Keep microphone capture and audio buffering fully platform-local. If Linux needs PipeWire/Pulse-specific handling, shared code should not know.

### Updates/runtime assets

Treat model files, localization bundles, and optional helper binaries as **platform-installed resources** exposed through a shared filesystem/model-storage contract.

---

## Scalability Considerations

| Concern | At macOS-only | At Linux parity | At future Windows support |
|---------|---------------|-----------------|---------------------------|
| Product logic duplication | Already present in places | Must be removed | Otherwise triples maintenance |
| Persistence divergence | Manageable | Needs shared schema contract | Becomes migration burden |
| Output insertion complexity | One OS path | X11/Wayland split | Windows adds third branch |
| Packaging complexity | Low | Medium-high | High |
| Localization consistency | Manual but possible | Must be centralized | Mandatory |

---

## Roadmap Guidance

### Phase-friendly breakdown

1. **Contract extraction and shared-core hardening**
   - Highest leverage
   - Reduces current `AppCoordinator` concentration risk

2. **macOS migration onto shared contracts**
   - Proves architecture without Linux unknowns

3. **Linux shell foundation**
   - app boot, tray, windows, localization, persistence

4. **Linux dictation loop**
   - recorder, transcription adapter, finalization, history save

5. **Linux desktop integrations**
   - hotkeys, floating indicator, autostart, output insertion

6. **Packaging and environment validation**
   - distro formats, desktop-environment matrix, degraded-mode UX

### Most important architectural dependency

**Do not start Linux UI parity before the shared contracts and shared state machines are authoritative.**

If Linux starts by copying today’s Swift orchestration behavior, the project will ship two coordinators and lose the main benefit of KMP.

---

## Sources

- Kotlin Multiplatform: Share code on platforms — HIGH  
  https://www.jetbrains.com/help/kotlin-multiplatform-dev/multiplatform-share-on-platforms.html
- Kotlin Multiplatform: Expected and actual declarations — HIGH  
  https://www.jetbrains.com/help/kotlin-multiplatform-dev/multiplatform-expect-actual.html
- Kotlin Multiplatform: Use platform-specific APIs — HIGH  
  https://www.jetbrains.com/help/kotlin-multiplatform-dev/multiplatform-connect-to-apis.html
- Kotlin: Swift/Objective-C interop — HIGH  
  https://kotlinlang.org/docs/native-objc-interop.html
- Kotlin: Swift export (experimental; not production-ready) — HIGH  
  https://kotlinlang.org/docs/native-swift-export.html
- Compose Multiplatform: Resources overview — MEDIUM  
  https://www.jetbrains.com/help/kotlin-multiplatform-dev/compose-multiplatform-resources.html
- Compose Multiplatform: Native distributions — MEDIUM  
  https://www.jetbrains.com/help/kotlin-multiplatform-dev/compose-native-distribution.html
- XDG Desktop Portal: Global Shortcuts — HIGH  
  https://flatpak.github.io/xdg-desktop-portal/docs/doc-org.freedesktop.portal.GlobalShortcuts.html
- XDG Desktop Portal: Input Capture — HIGH  
  https://flatpak.github.io/xdg-desktop-portal/docs/doc-org.freedesktop.portal.InputCapture.html
- XDG Desktop Portal: Remote Desktop — HIGH  
  https://flatpak.github.io/xdg-desktop-portal/docs/doc-org.freedesktop.portal.RemoteDesktop.html
- Freedesktop Autostart Specification — MEDIUM  
  https://specifications.freedesktop.org/autostart-spec/latest/

## Confidence Notes

- **High confidence:** shared-core vs native-shell split, expect/actual/DI boundaries, keeping WhisperKit/audio/output integrations native.
- **Medium confidence:** exact Linux UI toolkit choice; this document assumes a separate Linux shell but not a forced shared UI stack.
- **Medium confidence:** Wayland direct-insertion parity. Official portal APIs exist, but desktop/compositor support remains a runtime capability concern that must be validated on target environments.

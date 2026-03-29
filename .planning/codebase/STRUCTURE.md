# Codebase Structure

**Analysis Date:** 2026-03-29

## Directory Layout

```text
pindrop/
├── Pindrop/                 # Swift macOS app source
│   ├── Models/             # SwiftData schemas, model aliases, feature state
│   ├── Services/           # Recording, transcription, persistence, context, media, AI
│   ├── UI/                 # SwiftUI views and AppKit window/menu controllers
│   ├── Utils/              # Logging, alerts, icons, small helpers
│   ├── Resources/          # Built-in prompt presets and bundled assets
│   └── Localization/       # String catalogs
├── PindropTests/           # Swift Testing unit/integration-style tests and test helpers
├── PindropUITests/         # XCTest UI automation entry point
├── shared/                 # Kotlin Multiplatform workspace and XCFramework source
├── scripts/                # Build, signing, DMG, translation, and shared-framework scripts
├── .github/workflows/      # CI build/test workflows
├── justfile                # Primary task runner entry point
└── Pindrop.xcodeproj/      # Xcode project configuration
```

## Directory Purposes

**`Pindrop/`:**
- Purpose: Main app target source.
- Contains: app entry, coordinator, SwiftUI views, AppKit controllers, services, SwiftData models, local resources.
- Key files: `Pindrop/PindropApp.swift`, `Pindrop/AppCoordinator.swift`, `Pindrop/AppLocalization.swift`, `Pindrop/Info.plist`

**`Pindrop/Services/`:**
- Purpose: Non-UI runtime logic.
- Contains: audio/transcription services, stores over SwiftData, permissions, hotkeys, output, AI/context/media services, and transcription engine adapters under `Pindrop/Services/Transcription/`.
- Key files: `Pindrop/Services/AudioRecorder.swift`, `Pindrop/Services/TranscriptionService.swift`, `Pindrop/Services/ModelManager.swift`, `Pindrop/Services/HistoryStore.swift`, `Pindrop/Services/SettingsStore.swift`, `Pindrop/Services/MediaIngestionService.swift`

**`Pindrop/UI/`:**
- Purpose: Visual presentation and AppKit controller glue.
- Contains: main workspace views under `Pindrop/UI/Main/`, settings under `Pindrop/UI/Settings/`, onboarding under `Pindrop/UI/Onboarding/`, note editor, floating indicators, status bar, splash, toasts, reusable components, and theme files.
- Key files: `Pindrop/UI/Main/MainWindow.swift`, `Pindrop/UI/StatusBarController.swift`, `Pindrop/UI/Settings/SettingsWindow.swift`, `Pindrop/UI/Onboarding/OnboardingWindowController.swift`, `Pindrop/UI/SplashScreen.swift`

**`Pindrop/Models/`:**
- Purpose: Persistent model types, schema evolution, and feature state used by views/coordinator.
- Contains: versioned SwiftData schemas, `@Model` entities, enum/value types, and `MediaTranscriptionFeatureState`.
- Key files: `Pindrop/Models/TranscriptionRecordSchema.swift`, `Pindrop/Models/TranscriptionRecord.swift`, `Pindrop/Models/NoteSchema.swift`, `Pindrop/Models/MediaTranscriptionTypes.swift`

**`Pindrop/Utils/`:**
- Purpose: Cross-cutting helper code.
- Contains: logging, alert helpers, icon/theme utilities, image helpers.
- Key files: `Pindrop/Utils/Logger.swift`, `Pindrop/Utils/AlertManager.swift`, `Pindrop/Utils/Icons.swift`

**`PindropTests/`:**
- Purpose: Primary test target.
- Contains: service/coordinator tests, model tests, shared helpers, and protocol-based mocks under `PindropTests/TestHelpers/`.
- Key files: `PindropTests/AppCoordinatorContextFlowTests.swift`, `PindropTests/TranscriptionServiceTests.swift`, `PindropTests/TestSupport.swift`, `PindropTests/TestHelpers/MockAudioCaptureBackend.swift`

**`PindropUITests/`:**
- Purpose: UI automation target.
- Contains: UI test entry file.
- Key files: `PindropUITests/PindropUITests.swift`

**`shared/`:**
- Purpose: Kotlin Multiplatform workspace that produces shared XCFrameworks and JVM-tested policy modules.
- Contains: Gradle root plus `core`, `feature-transcription`, `ui-shell`, `ui-settings`, `ui-theme`, and `ui-workspace` modules.
- Key files: `shared/settings.gradle.kts`, `shared/build.gradle.kts`, `shared/README.md`, `shared/core/src/commonMain/kotlin/tech/watzon/pindrop/shared/core/TranscriptionContracts.kt`

**`scripts/`:**
- Purpose: Build/distribution automation.
- Contains: signing, DMG creation, appcast, shared-framework build, and translation scripts.
- Key files: `scripts/build-shared-frameworks-if-needed.sh`, `scripts/create-dmg.sh`, `scripts/sign-app-bundle.sh`, `scripts/translate_xcstrings.py`

## Key File Locations

**Entry Points:**
- `Pindrop/PindropApp.swift`: app entry and startup delegate
- `Pindrop/AppCoordinator.swift`: runtime composition root and orchestration center
- `Pindrop/UI/Main/MainWindow.swift`: main workspace window + controller
- `Pindrop/UI/StatusBarController.swift`: menu bar entry point and command surface

**Configuration:**
- `Pindrop/Info.plist`: app bundle settings
- `Pindrop/Pindrop.entitlements`: app entitlements
- `Pindrop/Localization/Localizable.xcstrings`: user-facing localization catalog
- `justfile`: canonical local build/test/release commands
- `shared/settings.gradle.kts`: shared-module registry

**Core Logic:**
- `Pindrop/Services/AudioRecorder.swift`: microphone capture and audio buffering
- `Pindrop/Services/TranscriptionService.swift`: transcription orchestration and streaming lifecycle
- `Pindrop/Services/ModelManager.swift`: model catalog/download/storage
- `Pindrop/Services/OutputManager.swift`: clipboard/direct-insert output
- `Pindrop/Services/ContextEngineService.swift`: AX-based context capture
- `Pindrop/Services/MediaIngestionService.swift`: media import/download workflow
- `Pindrop/Services/MediaPreparationService.swift`: media-to-audio conversion

**Testing:**
- `PindropTests/`: unit and coordinator tests
- `PindropUITests/PindropUITests.swift`: UI test surface
- `PindropTests/TestHelpers/`: mocks for hardware/system seams

## Naming Conventions

**Files:**
- Feature/controller/service types use PascalCase filenames matching the main type, for example `Pindrop/AppCoordinator.swift`, `Pindrop/Services/TranscriptionService.swift`, `Pindrop/UI/StatusBarController.swift`.
- Window/view folders group by product area, for example `Pindrop/UI/Main/`, `Pindrop/UI/Settings/`, `Pindrop/UI/Onboarding/`, `Pindrop/UI/NoteEditor/`.
- Test files mirror the source type name with a `Tests` suffix, for example `PindropTests/AudioRecorderTests.swift` and `PindropTests/MediaIngestionServiceTests.swift`.

**Directories:**
- Top-level app directories are broad architectural buckets: `Models`, `Services`, `UI`, `Utils`, `Resources`, `Localization`.
- UI subdirectories are feature-oriented rather than technology-oriented.
- Shared Kotlin modules are split by bounded domain (`core`, `feature-transcription`, `ui-shell`, `ui-settings`, `ui-theme`, `ui-workspace`).

## Where to Add New Code

**New app feature with UI + orchestration:**
- Primary code: add view/controller files under the closest existing UI feature folder in `Pindrop/UI/` and compose them from `Pindrop/AppCoordinator.swift` if they need runtime wiring.
- Tests: add matching tests under `PindropTests/` with the same feature/service naming pattern.

**New persistence-backed feature:**
- Persistent model/schema: add or extend files in `Pindrop/Models/`, following the versioned schema approach already used in `Pindrop/Models/TranscriptionRecordSchema.swift` and `Pindrop/Models/NoteSchema.swift`.
- Store logic: add a focused store/service in `Pindrop/Services/` that accepts `ModelContext` rather than querying SwiftData directly from a view.

**New service or system integration:**
- Implementation: place it in `Pindrop/Services/`.
- Protocol seam or engine adapter: place related abstractions in `Pindrop/Services/Transcription/` when they belong to transcription runtime behavior; otherwise keep the protocol adjacent to the service as seen in `Pindrop/Services/MediaIngestionService.swift` and `Pindrop/Services/ContextEngineService.swift`.

**New main-workspace page:**
- Implementation: add the page view under `Pindrop/UI/Main/`.
- Navigation hookup: extend `MainNavItem` and `detailContent` in `Pindrop/UI/Main/MainWindow.swift`; update `MainWindowController.show(...)` callers if the page needs direct entry.

**New settings surface:**
- Implementation: add a settings view under `Pindrop/UI/Settings/`.
- Navigation hookup: extend `SettingsTab` and the `switch activeTab` block in `Pindrop/UI/Settings/SettingsWindow.swift`.

**Shared policy/navigation logic:**
- KMP source: add it to the closest module under `shared/` and expose it through a Swift bridge file such as `Pindrop/Services/Transcription/KMPTranscriptionBridge.swift`.
- Uncertainty note: exact XCFramework export task wiring is defined in Gradle/Xcode settings not fully inspected here, so mirror an existing shared module before adding a brand-new one.

**Utilities:**
- Shared helpers: place logging/alert/general-purpose helpers under `Pindrop/Utils/`.
- Avoid putting reusable utility code directly into view files unless it is clearly local to that view.

## Special Directories

**`Pindrop/Localization/`:**
- Purpose: localization catalogs for app text and Info.plist strings
- Generated: No
- Committed: Yes

**`Pindrop/Assets.xcassets/`:**
- Purpose: images, icons, colors, and preview assets
- Generated: No
- Committed: Yes

**`shared/build/`:**
- Purpose: Gradle build outputs, test reports, and generated XCFramework artifacts
- Generated: Yes
- Committed: Present in the working tree; treat as build output rather than source of truth

**`DerivedData*/`:**
- Purpose: Xcode-derived build/test artifacts
- Generated: Yes
- Committed: No

**`.planning/codebase/`:**
- Purpose: generated mapping/reference documents for other GSD commands
- Generated: Yes
- Committed: Intended to be committed when updated by mapping workflows

## Structure Rules for Future Changes

- Put app boot changes in `Pindrop/PindropApp.swift` or `Pindrop/AppCoordinator.swift`, not inside arbitrary views.
- Put AppKit window/status-item logic in controller classes under `Pindrop/UI/`, then embed SwiftUI content from there.
- Put persistence access behind store services in `Pindrop/Services/`, not directly in random views.
- Extend `shared/` only for policy/state that benefits from cross-platform reuse; keep macOS-only AppKit and platform hardware code in `Pindrop/`.

---

*Structure analysis: 2026-03-29*

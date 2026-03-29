# Architecture

**Analysis Date:** 2026-03-29

## Pattern Overview

**Overall:** Coordinator-driven macOS desktop app with SwiftUI views, AppKit window/menu controllers, SwiftData persistence, and a Kotlin Multiplatform policy layer.

**Key Characteristics:**
- `Pindrop/PindropApp.swift` bootstraps the app, creates the `ModelContainer`, and hands runtime ownership to `Pindrop/AppCoordinator.swift`.
- `Pindrop/AppCoordinator.swift` is the central composition root; it wires services, AppKit controllers, runtime state, hotkeys, and major async flows.
- UI rendering lives in SwiftUI under `Pindrop/UI/`, while menu bar items, floating windows, and onboarding/splash windows are controlled by AppKit controller types such as `Pindrop/UI/StatusBarController.swift`, `Pindrop/UI/Main/MainWindow.swift`, `Pindrop/UI/Onboarding/OnboardingWindowController.swift`, and `Pindrop/UI/SplashScreen.swift`.
- Shared decision logic is delegated into Kotlin Multiplatform modules under `shared/`, bridged from Swift by `Pindrop/Services/Transcription/KMPTranscriptionBridge.swift` and related feature bridges.

## Layers

**Application lifecycle and composition:**
- Purpose: Boot the app, create persistence, choose startup path, and keep the top-level object graph alive.
- Location: `Pindrop/PindropApp.swift`, `Pindrop/AppCoordinator.swift`
- Contains: `AppDelegate`, `SwiftDataStoreRepairService`, `AppCoordinator`
- Depends on: SwiftData, AppKit, service layer, UI controllers
- Used by: macOS app runtime

**UI layer:**
- Purpose: Render workspace pages, settings, onboarding, splash, floating indicators, and note editing.
- Location: `Pindrop/UI/`
- Contains: SwiftUI views such as `Pindrop/UI/Main/MainWindow.swift`, `Pindrop/UI/Main/TranscribeView.swift`, `Pindrop/UI/Settings/SettingsWindow.swift`, plus controller classes like `MainWindowController`, `StatusBarController`, `ToastWindowController`, and floating-indicator presenters.
- Depends on: `SettingsStore`, feature state objects, stores/services passed from `AppCoordinator`
- Used by: `AppCoordinator`, NotificationCenter navigation posts, status bar/menu actions

**Service layer:**
- Purpose: Hold non-UI runtime logic for recording, transcription, model management, output, permissions, context capture, persistence access, media ingestion, and AI enhancement.
- Location: `Pindrop/Services/`
- Contains: `AudioRecorder`, `TranscriptionService`, `ModelManager`, `HistoryStore`, `NotesStore`, `PermissionManager`, `ContextEngineService`, `MediaIngestionService`, `MediaPreparationService`, `OutputManager`, `HotkeyManager`, and related helpers.
- Depends on: system frameworks, model layer, external SDKs, file system
- Used by: mostly `AppCoordinator`, with some direct view usage via injected stores/state

**Persistence layer:**
- Purpose: Store transcripts, folders, notes, presets, and dictionary data in SwiftData.
- Location: `Pindrop/Models/`, plus store accessors in `Pindrop/Services/HistoryStore.swift`, `Pindrop/Services/NotesStore.swift`, `Pindrop/Services/DictionaryStore.swift`, and `Pindrop/Services/PromptPresetStore.swift`
- Contains: schema versions in `Pindrop/Models/TranscriptionRecordSchema.swift` and `Pindrop/Models/NoteSchema.swift`, current typealiases in `Pindrop/Models/TranscriptionRecord.swift`, and `@Model` types such as `PromptPreset`, `WordReplacement`, and `VocabularyWord`.
- Depends on: SwiftData `ModelContext` / `ModelContainer`
- Used by: stores, `MainWindowController` via `.modelContainer(container)`, and app boot in `Pindrop/PindropApp.swift`

**Shared KMP policy/runtime layer:**
- Purpose: Centralize state transitions, startup model resolution, navigation helpers, and transcription/media policy outside Swift-only code.
- Location: `shared/core/`, `shared/feature-transcription/`, `shared/ui-shell/`, `shared/ui-settings/`, `shared/ui-theme/`, `shared/ui-workspace/`
- Contains: contracts in `shared/core/src/commonMain/kotlin/tech/watzon/pindrop/shared/core/TranscriptionContracts.kt` and orchestration logic in `shared/feature-transcription/src/commonMain/kotlin/tech/watzon/pindrop/shared/feature/transcription/SharedTranscriptionOrchestrator.kt`
- Depends on: Kotlin Multiplatform Gradle workspace declared in `shared/settings.gradle.kts`
- Used by: Swift bridges such as `Pindrop/Services/Transcription/KMPTranscriptionBridge.swift`, `Pindrop/Models/MediaTranscriptionTypes.swift`, and optional imports in `Pindrop/UI/Main/MainWindow.swift` / `Pindrop/UI/Settings/SettingsWindow.swift`

## Data Flow

**App startup flow:**

1. `Pindrop/PindropApp.swift` enters `AppDelegate.applicationDidFinishLaunching(_:)` and exits early for previews, unit tests, or UI fixture mode.
2. `SwiftDataStoreRepairService` in the same file prepares and, if needed, repairs the SwiftData store before `makeModelContainer()` builds a `ModelContainer` for `TranscriptionRecord`, `MediaFolder`, `WordReplacement`, `VocabularyWord`, `Note`, and `PromptPreset`.
3. `AppDelegate` creates `AppCoordinator(modelContext:modelContainer:)`, configures dock/menu behavior, then schedules `await coordinator.start()`.
4. `AppCoordinator.start()` chooses the onboarding path (`showOnboarding()`) or the normal path (`seedBuiltInPresetsIfNeeded()`, splash screen, `startNormalOperation()`).
5. `startNormalOperation()` synchronizes launch-at-login state, checks permissions, refreshes downloaded models, resolves the startup model through `KMPTranscriptionBridge.resolveStartupModel(...)`, loads or downloads the model through `ModelManager` and `TranscriptionService`, refreshes status-bar data, and reveals `MainWindowController` after splash dismissal.

**Live recording and transcription flow:**

1. User actions arrive from `StatusBarController` callbacks, global hotkeys managed in `Pindrop/Services/HotkeyManager.swift`, or floating-indicator presenters configured in `AppCoordinator`.
2. `AppCoordinator.startRecording(source:)` begins audio capture through `Pindrop/Services/AudioRecorder.swift`, optionally pauses media via `Pindrop/Services/MediaPauseService.swift`, captures clipboard/UI context using `ContextCaptureService` and `ContextEngineService`, and starts the active recording indicator.
3. Session policy is determined through helpers backed by `Pindrop/Services/Transcription/TranscriptionPolicy.swift` and `Pindrop/Services/Transcription/KMPTranscriptionBridge.swift`.
4. If streaming is allowed, `AppCoordinator.beginStreamingSessionIfAvailable()` prepares `TranscriptionService`, forwards live audio buffers, and streams direct insertion updates through `Pindrop/Services/OutputManager.swift`.
5. On stop, `AppCoordinator.stopRecordingAndFinalizeStreaming()` or `AppCoordinator.stopRecordingAndTranscribe()` finalizes the transcript, applies dictionary replacements from `Pindrop/Services/DictionaryStore.swift`, optionally enhances text, writes output via `OutputManager`, and persists history through `HistoryStore.save(...)`.

**Media transcription flow:**

1. `Pindrop/UI/Main/TranscribeView.swift` routes import/link actions through callbacks injected by `MainWindowController.configureTranscribeFeature(...)` in `Pindrop/UI/Main/MainWindow.swift`.
2. `AppCoordinator.handleImportMediaFiles(_:)` / `handleSubmitMediaLink(_:)` create a task that calls `performMediaTranscription(_:)`.
3. `MediaTranscriptionFeatureState` in `Pindrop/Models/MediaTranscriptionTypes.swift` tracks route, current job, setup issues, and library messages.
4. `Pindrop/Services/MediaIngestionService.swift` imports local files or downloads media into a managed library directory; `Pindrop/Services/MediaPreparationService.swift` converts media to 16 kHz mono float audio.
5. `TranscriptionService.transcribe(audioData:diarizationEnabled:options:)` runs transcription plus diarization, and `HistoryStore.save(...)` stores the resulting media-backed transcript and folder linkage.

**Workspace navigation flow:**

1. `MainWindowController.show(...)` creates the workspace window once and injects `SettingsStore`, optional media transcription state, and the shared `ModelContainer`.
2. `Pindrop/UI/Main/MainWindow.swift` renders sidebar + detail content and responds to NotificationCenter messages `navigateToMainNavItem` and `navigateToSettingsTab`.
3. When the optional KMP navigation frameworks are available, `MainWindow` and `SettingsWindow` delegate browse/navigation state to `PindropSharedNavigation`; otherwise they fall back to local `@State` properties.

**State Management:**
- Top-level mutable runtime state sits in `AppCoordinator`.
- Long-lived reactive stores use `@Observable` or `ObservableObject`, for example `TranscriptionService`, `HistoryStore`, `ModelManager`, `MediaTranscriptionFeatureState`, and `SettingsStore`.
- Cross-view navigation and store refreshes use `NotificationCenter` in a few places, notably `historyStoreDidChange`, `navigateToMainNavItem`, `navigateToSettingsTab`, `modelActiveChanged`, and `requestActiveModel`.

## Key Abstractions

**AppCoordinator:**
- Purpose: Central runtime orchestrator and composition root.
- Examples: `Pindrop/AppCoordinator.swift`
- Pattern: One coordinator owns services, controller objects, and session state instead of distributing startup logic across views.

**Window/menu controllers:**
- Purpose: Isolate AppKit window/status-item concerns from SwiftUI view code.
- Examples: `Pindrop/UI/StatusBarController.swift`, `Pindrop/UI/Main/MainWindow.swift`, `Pindrop/UI/Onboarding/OnboardingWindowController.swift`, `Pindrop/UI/SplashScreen.swift`, `Pindrop/UI/ToastWindowController.swift`
- Pattern: Controllers create/manage `NSWindow` or `NSStatusItem` objects and embed SwiftUI via `NSHostingController`.

**Store wrappers around SwiftData:**
- Purpose: Keep fetch/save/query behavior out of views and centralize model-context access.
- Examples: `Pindrop/Services/HistoryStore.swift`, `Pindrop/Services/NotesStore.swift`, `Pindrop/Services/DictionaryStore.swift`, `Pindrop/Services/PromptPresetStore.swift`
- Pattern: `@MainActor` stores accept `ModelContext` in their initializer and expose task-oriented methods such as `save`, `fetch`, `search`, `createFolder`, and `assign`.

**Port protocols around engines/system APIs:**
- Purpose: Decouple orchestration from engine implementations and make runtime switching/test seams possible.
- Examples: `Pindrop/Services/Transcription/TranscriptionPorts.swift`, `Pindrop/Services/ContextEngineService.swift` (`AXProviderProtocol`), `Pindrop/Services/MediaIngestionService.swift` (`ProcessRunning`, `MediaLibraryManaging`)
- Pattern: concrete engines/services conform to small protocols consumed by a higher-level service.

**Shared bridge adapters:**
- Purpose: Convert between Swift enums/models and Kotlin shared-policy types.
- Examples: `Pindrop/Services/Transcription/KMPTranscriptionBridge.swift`, `Pindrop/Models/MediaTranscriptionTypes.swift`
- Pattern: bridge functions call into KMP when the XCFramework is present and provide Swift fallback logic when it is not.

## Entry Points

**macOS app entry:**
- Location: `Pindrop/PindropApp.swift`
- Triggers: normal app launch
- Responsibilities: register `AppDelegate`, host the UI-test fixture window, and hand startup to the delegate

**Application delegate boot path:**
- Location: `Pindrop/PindropApp.swift`
- Triggers: `applicationDidFinishLaunching`
- Responsibilities: initialize logging, repair/open SwiftData, create `AppCoordinator`, set main menu and dock policy, then invoke `coordinator.start()`

**Runtime orchestration entry:**
- Location: `Pindrop/AppCoordinator.swift`
- Triggers: `AppDelegate`, status-bar callbacks, hotkeys, floating indicators, and media import callbacks
- Responsibilities: startup path selection, model loading, recording lifecycle, output, persistence, and media transcription

**Workspace window entry:**
- Location: `Pindrop/UI/Main/MainWindow.swift`
- Triggers: `MainWindowController.show*()`
- Responsibilities: render the main sidebar-driven workspace and route between dashboard/history/transcribe/models/notes/dictionary/settings pages

**Shared workspace entry points:**
- Location: `shared/settings.gradle.kts`
- Triggers: Gradle builds and XCFramework generation via `just shared-xcframework`
- Responsibilities: define `:core`, `:feature-transcription`, `:ui-shell`, `:ui-settings`, `:ui-theme`, and `:ui-workspace` modules

## Error Handling

**Strategy:** Domain services define local `Error` / `LocalizedError` enums, catch failures at coordinator or controller boundaries, log context, and surface user-visible alerts/toasts there.

**Patterns:**
- `Pindrop/PindropApp.swift` treats SwiftData initialization as fatal startup work and terminates after alerting when repair/retry fails.
- `Pindrop/AppCoordinator.swift` catches recording/transcription/media failures, writes log context, resets runtime state, and shows toast/alert feedback.
- Service types such as `TranscriptionService`, `HistoryStore`, `MediaIngestionService`, and `MediaPreparationService` convert low-level failures into domain-specific errors.

## Cross-Cutting Concerns

**Logging:** `Pindrop/Utils/Logger.swift` provides structured category loggers referenced across boot, model, transcription, output, UI, update, AI enhancement, and context flows.

**Validation:** Startup model selection, transcription state transitions, and runtime policy decisions are validated through `Pindrop/Services/Transcription/KMPTranscriptionBridge.swift` and KMP shared orchestrator code. Input-specific validation also appears inside service methods like `MediaPreparationService.prepareAudio(from:)` and `HistoryStore` folder name checks.

**Authentication:** No central app-session identity layer is detected. Secret storage appears to live in `Pindrop/Services/SettingsStore.swift` via Keychain-backed settings for API-based features. This analysis does not inspect secret values.

**Uncertainty:** The Xcode project wiring in `Pindrop.xcodeproj/` and exact XCFramework embedding settings were not inspected line-by-line, so build-phase relationships are inferred from imports, `justfile`, and files present under `shared/`.

---

*Architecture analysis: 2026-03-29*

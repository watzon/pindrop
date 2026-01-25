# Pindrop - macOS Dictation App

## Context

### Original Request

Build a native macOS menu bar dictation application that lives in the status bar, reacts to keyboard shortcuts (push-to-talk and toggle), uses open-source models (WhisperKit) locally with optional OpenAI API fallback, featuring a clean Apple-like design with Settings and History windows.

### Interview Summary

**Key Discussions**:

- **STT Engine**: WhisperKit (native Swift, Core ML optimized) as primary, OpenAI-compatible API as optional cloud enhancement
- **Model Management**: All Whisper sizes available, user downloads in Settings, starts with Tiny/Turbo
- **Keyboard Shortcuts**: Option+Space toggle (default), push-to-talk empty (user-configured)
- **Output Behavior**: Clipboard by default, optional direct text insertion (Accessibility API)
- **Visual Feedback**: Icon color change + animation + optional floating indicator
- **AI Enhancement**: Optional post-processing via any OpenAI-compatible API
- **History**: SQLite/SwiftData persistence with search and export
- **Language**: English only initially
- **Testing**: XCTest for core logic

**Research Findings**:

- WhisperKit: Native Swift, Core ML optimized, 5,500+ stars, actively maintained
- Audio: AVAudioEngine at 16kHz mono 16-bit PCM (Whisper requirement)
- Hotkeys: Carbon Event API for global registration
- Database: SwiftData (modern Core Data replacement for macOS 14+)

### Metis Review

**Identified Gaps** (addressed):

- Direct insertion mechanism: Accessibility API with clipboard fallback
- Permission handling: Graceful degradation with user prompts
- Latency targets: <500ms to recording start, <2s first transcription (Tiny model)
- Model storage: ~/Library/Application Support/Pindrop/Models/
- Offline behavior: Fully functional without network (AI enhancement disabled)
- Audio input: Default system mic, device selection in Settings (future)
- Hotkey conflicts: Fallback to menu toggle, log conflicts

---

## Work Objectives

### Core Objective

Build a native macOS 14+ menu bar dictation app using WhisperKit for local speech-to-text with optional cloud enhancement, focusing on privacy-first design and Apple-like simplicity.

### Concrete Deliverables

- `Pindrop.xcodeproj` - Xcode project with proper signing and entitlements
- Status bar application with dropdown menu
- Settings window (hotkeys, models, API config, output behavior)
- History window (searchable, exportable transcription history)
- WhisperKit integration with model download management
- Global keyboard shortcuts (toggle + push-to-talk)
- Optional OpenAI-compatible API enhancement

### Definition of Done

- [ ] App launches and appears in menu bar
- [ ] Option+Space toggles recording
- [ ] Audio is captured and transcribed via WhisperKit
- [ ] Transcribed text appears in clipboard
- [ ] History persists between app restarts
- [ ] All XCTests pass
- [ ] App is signed and notarized (or ready for)

### Must Have

- Menu bar icon with recording state indication
- Global hotkey support (toggle recording)
- Local WhisperKit transcription
- Clipboard output
- Settings persistence
- History persistence
- Permission request flows (Microphone)

### Must NOT Have (Guardrails)

- No batch file transcription (live dictation only)
- No meeting recorder features
- No multi-language support (English only for v1)
- No speaker diarization
- No sync/account system
- No telemetry without explicit consent
- No Intel/pre-Sonoma support
- No Shortcuts/automation integration (future scope)
- No per-app profiles or rules
- No system audio capture
- History window is read-only, not an editor

---

## Verification Strategy (MANDATORY)

### Test Decision

- **Infrastructure exists**: NO (greenfield)
- **User wants tests**: YES (XCTest)
- **Framework**: XCTest (built-in)

### TDD Approach

Each core component includes unit tests. UI components verified manually.

**Testable Units**:

- AudioRecorder: Mock AVAudioEngine, verify buffer handling
- TranscriptionService: Mock WhisperKit, verify text output
- HotkeyManager: Verify registration/unregistration
- HistoryStore: Verify CRUD operations on SwiftData
- SettingsStore: Verify persistence

**Manual Verification** (UI/Integration):

- Status bar icon states
- Settings window interactions
- History window search/export
- End-to-end dictation flow

---

## Task Flow

```
Setup (0-2) → Core Audio (3-4) → STT Integration (5-7) → Hotkeys (8-9)
                                                              ↓
Output (10-11) → History (12-13) → Settings UI (14-16) → History UI (17)
                                                              ↓
                                              Visual Polish (18-19) → Testing (20-21)
```

## Parallelization

| Group | Tasks  | Reason                                                |
| ----- | ------ | ----------------------------------------------------- |
| A     | 3, 8   | Audio capture and hotkey registration are independent |
| B     | 12, 14 | History store and Settings store are independent      |
| C     | 16, 17 | Settings window and History window are independent    |

| Task | Depends On | Reason                                |
| ---- | ---------- | ------------------------------------- |
| 5    | 3          | Transcription needs audio capture     |
| 10   | 5          | Output needs transcription            |
| 13   | 12         | History queries need store            |
| 15   | 14         | Settings UI needs store               |
| 18   | 10         | Visual feedback needs recording state |

---

## TODOs

- [x] 0. Initialize Xcode Project

  **What to do**:
  - Create new macOS App project in Xcode
  - Select Swift and SwiftUI as UI framework
  - Set deployment target to macOS 14.0
  - Configure bundle identifier: `com.yourname.pindrop`
  - Add WhisperKit package dependency
  - Configure app to be a menu bar only app (LSUIElement = YES)

  **Must NOT do**:
  - Do not add any other external dependencies
  - Do not configure for iOS/multiplatform

  **Parallelizable**: NO (must be first)

  **References**:
  - WhisperKit SPM: `https://github.com/argmaxinc/WhisperKit.git` (from: "0.9.0")
  - Apple docs: Menu bar apps - `LSUIElement` in Info.plist

  **Acceptance Criteria**:
  - [ ] Project opens in Xcode without errors
  - [ ] `xcodebuild -list` shows Pindrop scheme
  - [ ] WhisperKit appears in Package Dependencies
  - [ ] Info.plist contains `LSUIElement = YES`

  **Commit**: YES
  - Message: `chore: initialize Pindrop Xcode project with WhisperKit dependency`
  - Files: `Pindrop.xcodeproj/`, `Pindrop/`

---

- [x] 1. Configure Entitlements and Permissions

  **What to do**:
  - Create `Pindrop.entitlements` file
  - Add microphone entitlement: `com.apple.security.device.audio-input`
  - Add Info.plist usage descriptions:
    - `NSMicrophoneUsageDescription`: "Pindrop needs microphone access to transcribe your speech"
  - Configure App Sandbox appropriately

  **Must NOT do**:
  - Do not disable App Sandbox entirely
  - Do not add camera or network entitlements unnecessarily

  **Parallelizable**: NO (depends on 0)

  **References**:
  - Apple docs: Entitlements - https://developer.apple.com/documentation/bundleresources/entitlements

  **Acceptance Criteria**:
  - [ ] Entitlements file exists with correct keys
  - [ ] Info.plist has microphone usage description
  - [ ] Project builds without signing errors
  - [ ] `codesign -d --entitlements - Pindrop.app` shows expected entitlements

  **Commit**: YES
  - Message: `chore: configure entitlements and permission descriptions`
  - Files: `Pindrop/Pindrop.entitlements`, `Pindrop/Info.plist`

---

- [x] 2. Set Up XCTest Infrastructure

  **What to do**:
  - Create `PindropTests` test target (Xcode creates by default)
  - Create `PindropTests/TestHelpers/` directory for mocks
  - Write initial example test to verify setup
  - Configure test scheme to run tests

  **Must NOT do**:
  - Do not add third-party test frameworks

  **Parallelizable**: NO (depends on 0)

  **References**:
  - Apple docs: XCTest - https://developer.apple.com/documentation/xctest

  **Acceptance Criteria**:
  - [ ] Test target exists in project
  - [ ] `xcodebuild test -scheme Pindrop` runs successfully
  - [ ] Example test passes

  **Commit**: YES
  - Message: `test: set up XCTest infrastructure with example test`
  - Files: `PindropTests/`

---

- [x] 3. Implement AudioRecorder Service

  **What to do**:
  - Create `Pindrop/Services/AudioRecorder.swift`
  - Implement AVAudioEngine-based recording
  - Configure for 16kHz, mono, 16-bit PCM (WhisperKit requirement)
  - Implement `startRecording()` and `stopRecording()` methods
  - Return audio buffer/data for transcription
  - Handle microphone permission request

  **Must NOT do**:
  - Do not save audio to disk (in-memory only)
  - Do not implement noise reduction (Whisper handles this)

  **Parallelizable**: YES (with 8)

  **References**:
  - AVAudioEngine: https://developer.apple.com/documentation/avfaudio/avaudioengine
  - WhisperKit audio requirements: 16kHz mono PCM

  **Acceptance Criteria**:
  - [ ] AudioRecorder class compiles
  - [ ] Unit test: `testStartRecordingRequestsPermission` passes
  - [ ] Unit test: `testStopRecordingReturnsAudioData` passes
  - [ ] Manual: Microphone permission prompt appears on first use
  - [ ] Manual: Audio data is captured (verify buffer size > 0)

  **Commit**: YES
  - Message: `feat(audio): implement AudioRecorder service with AVAudioEngine`
  - Files: `Pindrop/Services/AudioRecorder.swift`, `PindropTests/AudioRecorderTests.swift`

---

- [x] 4. Implement Audio Permission Manager

  **What to do**:
  - Create `Pindrop/Services/PermissionManager.swift`
  - Check microphone permission status
  - Request permission with completion handler
  - Provide observable state for UI binding

  **Must NOT do**:
  - Do not auto-request on app launch (request on first use)

  **Parallelizable**: NO (depends on 3, used by 3)

  **References**:
  - AVAudioApplication.requestRecordPermission: https://developer.apple.com/documentation/avfaudio/avaudioapplication

  **Acceptance Criteria**:
  - [ ] PermissionManager class compiles
  - [ ] Unit test: `testCheckPermissionStatus` passes
  - [ ] Unit test: `testRequestPermission` passes (mocked)
  - [ ] Manual: Permission dialog appears when requested

  **Commit**: YES
  - Message: `feat(permissions): implement PermissionManager for microphone access`
  - Files: `Pindrop/Services/PermissionManager.swift`, `PindropTests/PermissionManagerTests.swift`

---

- [x] 5. Implement TranscriptionService with WhisperKit

  **What to do**:
  - Create `Pindrop/Services/TranscriptionService.swift`
  - Initialize WhisperKit with selected model
  - Implement `transcribe(audioData:) -> String` method
  - Handle model loading states (loading, ready, error)
  - Expose transcription progress/state

  **Must NOT do**:
  - Do not implement streaming transcription (batch only for v1)
  - Do not handle model downloads here (separate task)

  **Parallelizable**: NO (depends on 3)

  **References**:
  - WhisperKit usage: https://github.com/argmaxinc/WhisperKit#usage
  - WhisperKit API: `Whisper.transcribe(audioFrames:)`

  **Acceptance Criteria**:
  - [ ] TranscriptionService class compiles
  - [ ] Unit test: `testTranscribeWithMockWhisper` passes
  - [ ] Unit test: `testModelLoadingStates` passes
  - [ ] Manual: Transcription works with Tiny model

  **Commit**: YES
  - Message: `feat(stt): implement TranscriptionService with WhisperKit integration`
  - Files: `Pindrop/Services/TranscriptionService.swift`, `PindropTests/TranscriptionServiceTests.swift`

---

- [x] 6. Implement Model Manager

  **What to do**:
  - Create `Pindrop/Services/ModelManager.swift`
  - Define available models (tiny, base, small, medium, large)
  - Check which models are downloaded locally
  - Download models from WhisperKit/HuggingFace
  - Store models in `~/Library/Application Support/Pindrop/Models/`
  - Track download progress

  **Must NOT do**:
  - Do not auto-download models
  - Do not bundle models in app (too large)

  **Parallelizable**: NO (depends on 5)

  **References**:
  - WhisperKit model management: https://github.com/argmaxinc/WhisperKit#downloading-models
  - FileManager for Application Support: https://developer.apple.com/documentation/foundation/filemanager

  **Acceptance Criteria**:
  - [ ] ModelManager class compiles
  - [ ] Unit test: `testListAvailableModels` passes
  - [ ] Unit test: `testCheckDownloadedModels` passes
  - [ ] Manual: Model download works, progress is reported
  - [ ] Manual: Downloaded models persist between launches

  **Commit**: YES
  - Message: `feat(models): implement ModelManager for Whisper model downloads`
  - Files: `Pindrop/Services/ModelManager.swift`, `PindropTests/ModelManagerTests.swift`

---

- [x] 7. Implement AI Enhancement Service (Optional Feature)

  **What to do**:
  - Create `Pindrop/Services/AIEnhancementService.swift`
  - Accept OpenAI-compatible API endpoint and key
  - Send transcribed text for enhancement (grammar, formatting)
  - Return enhanced text or original on failure
  - Make feature toggleable

  **Must NOT do**:
  - Do not make AI enhancement required
  - Do not store API keys in plaintext (use Keychain)

  **Parallelizable**: YES (with 6)

  **References**:
  - OpenAI Chat API: https://platform.openai.com/docs/api-reference/chat
  - Keychain Services: https://developer.apple.com/documentation/security/keychain_services

  **Acceptance Criteria**:
  - [ ] AIEnhancementService class compiles
  - [ ] Unit test: `testEnhanceTextWithMockAPI` passes
  - [ ] Unit test: `testFallbackOnAPIError` passes
  - [ ] Manual: Enhancement works with real OpenAI API

  **Commit**: YES
  - Message: `feat(ai): implement AIEnhancementService for optional text post-processing`
  - Files: `Pindrop/Services/AIEnhancementService.swift`, `PindropTests/AIEnhancementServiceTests.swift`

---

- [x] 8. Implement Global Hotkey Manager

  **What to do**:
  - Create `Pindrop/Services/HotkeyManager.swift`
  - Use Carbon Event API for global hotkey registration
  - Support two hotkeys: toggle and push-to-talk
  - Implement register/unregister methods
  - Handle hotkey conflicts gracefully
  - Store hotkey configurations

  **Must NOT do**:
  - Do not use private APIs
  - Do not override system shortcuts without warning

  **Parallelizable**: YES (with 3)

  **References**:
  - Carbon Events: RegisterEventHotKey, UnregisterEventHotKey
  - Key codes: https://gist.github.com/swillits/df648e87016772c7f7e5

  **Acceptance Criteria**:
  - [ ] HotkeyManager class compiles
  - [ ] Unit test: `testRegisterHotkey` passes
  - [ ] Unit test: `testUnregisterHotkey` passes
  - [ ] Manual: Option+Space triggers callback globally
  - [ ] Manual: Hotkey works when app is not focused

  **Commit**: YES
  - Message: `feat(hotkeys): implement HotkeyManager with Carbon Event API`
  - Files: `Pindrop/Services/HotkeyManager.swift`, `PindropTests/HotkeyManagerTests.swift`

---

- [x] 9. Implement Push-to-Talk Logic

  **What to do**:
  - Extend HotkeyManager for push-to-talk behavior
  - Detect key down -> start recording
  - Detect key up -> stop recording and transcribe
  - Handle edge cases (key held too long, key released quickly)

  **Must NOT do**:
  - Do not implement voice activity detection (key-based only)

  **Parallelizable**: NO (depends on 8)

  **References**:
  - Carbon Events: kEventHotKeyPressed, kEventHotKeyReleased

  **Acceptance Criteria**:
  - [ ] Push-to-talk logic works in HotkeyManager
  - [ ] Unit test: `testPushToTalkKeyDown` passes
  - [ ] Unit test: `testPushToTalkKeyUp` passes
  - [ ] Manual: Hold key = record, release = transcribe

  **Commit**: YES
  - Message: `feat(hotkeys): add push-to-talk key down/up detection`
  - Files: `Pindrop/Services/HotkeyManager.swift`, `PindropTests/HotkeyManagerTests.swift`

---

- [x] 10. Implement Output Manager (Clipboard + Direct Insert)

  **What to do**:
  - Create `Pindrop/Services/OutputManager.swift`
  - Implement clipboard output via NSPasteboard
  - Implement direct text insertion via Accessibility API (CGEvent)
  - Fall back to clipboard if Accessibility permission denied
  - Make output mode configurable

  **Must NOT do**:
  - Do not require Accessibility permission for basic functionality

  **Parallelizable**: NO (depends on 5)

  **References**:
  - NSPasteboard: https://developer.apple.com/documentation/appkit/nspasteboard
  - CGEvent for key simulation: https://developer.apple.com/documentation/coregraphics/cgevent

  **Acceptance Criteria**:
  - [ ] OutputManager class compiles
  - [ ] Unit test: `testCopyToClipboard` passes
  - [ ] Unit test: `testDirectInsertFallback` passes
  - [ ] Manual: Text appears in clipboard after transcription
  - [ ] Manual: Text inserts directly when Accessibility enabled

  **Commit**: YES
  - Message: `feat(output): implement OutputManager with clipboard and direct insert`
  - Files: `Pindrop/Services/OutputManager.swift`, `PindropTests/OutputManagerTests.swift`

---

- [x] 11. Implement Accessibility Permission Handling

  **What to do**:
  - Extend PermissionManager for Accessibility permission
  - Check Accessibility permission status
  - Guide user to System Preferences if needed
  - Track permission state for UI

  **Must NOT do**:
  - Do not auto-enable Accessibility (requires user action)

  **Parallelizable**: NO (depends on 10)

  **References**:
  - AXIsProcessTrusted: https://developer.apple.com/documentation/applicationservices/1460720-axisprocesstrusted

  **Acceptance Criteria**:
  - [ ] Accessibility check added to PermissionManager
  - [ ] Unit test: `testAccessibilityPermissionCheck` passes
  - [ ] Manual: Opens System Preferences when permission needed

  **Commit**: YES
  - Message: `feat(permissions): add Accessibility permission handling`
  - Files: `Pindrop/Services/PermissionManager.swift`, `PindropTests/PermissionManagerTests.swift`

---

- [x] 12. Implement History Store with SwiftData

  **What to do**:
  - Create `Pindrop/Models/TranscriptionRecord.swift` (SwiftData model)
  - Define schema: id, text, timestamp, duration, modelUsed
  - Create `Pindrop/Services/HistoryStore.swift`
  - Implement CRUD operations
  - Implement search functionality

  **Must NOT do**:
  - Do not use Core Data directly (SwiftData only)
  - Do not implement edit functionality (read-only history)

  **Parallelizable**: YES (with 14)

  **References**:
  - SwiftData: https://developer.apple.com/documentation/swiftdata
  - @Model macro: https://developer.apple.com/documentation/swiftdata/model()

  **Acceptance Criteria**:
  - [ ] TranscriptionRecord model compiles
  - [ ] HistoryStore class compiles
  - [ ] Unit test: `testSaveTranscription` passes
  - [ ] Unit test: `testFetchTranscriptions` passes
  - [ ] Unit test: `testSearchTranscriptions` passes
  - [ ] Manual: History persists between app restarts

  **Commit**: YES
  - Message: `feat(history): implement HistoryStore with SwiftData`
  - Files: `Pindrop/Models/TranscriptionRecord.swift`, `Pindrop/Services/HistoryStore.swift`, `PindropTests/HistoryStoreTests.swift`

---

- [ ] 13. Implement History Export

  **What to do**:
  - Add export functionality to HistoryStore
  - Support export formats: plain text, JSON, CSV
  - Use NSSavePanel for file destination
  - Export selected or all records

  **Must NOT do**:
  - Do not implement cloud export (local files only)

  **Parallelizable**: NO (depends on 12)

  **References**:
  - NSSavePanel: https://developer.apple.com/documentation/appkit/nssavepanel

  **Acceptance Criteria**:
  - [ ] Export methods added to HistoryStore
  - [ ] Unit test: `testExportToJSON` passes
  - [ ] Unit test: `testExportToCSV` passes
  - [ ] Manual: Export dialog appears, file is saved correctly

  **Commit**: YES
  - Message: `feat(history): add export functionality (JSON, CSV, plain text)`
  - Files: `Pindrop/Services/HistoryStore.swift`, `PindropTests/HistoryStoreTests.swift`

---

- [x] 14. Implement Settings Store

  **What to do**:
  - Create `Pindrop/Services/SettingsStore.swift`
  - Use @AppStorage for simple settings
  - Store: selected model, hotkey configs, output mode, AI enhancement toggle
  - Store API endpoint and key in Keychain
  - Make observable for SwiftUI binding

  **Must NOT do**:
  - Do not store sensitive data in UserDefaults

  **Parallelizable**: YES (with 12)

  **References**:
  - @AppStorage: https://developer.apple.com/documentation/swiftui/appstorage
  - Keychain: https://developer.apple.com/documentation/security/keychain_services

  **Acceptance Criteria**:
  - [ ] SettingsStore class compiles
  - [ ] Unit test: `testSaveAndLoadSettings` passes
  - [ ] Unit test: `testKeychainStorage` passes
  - [ ] Manual: Settings persist between launches

  **Commit**: YES
  - Message: `feat(settings): implement SettingsStore with Keychain for sensitive data`
  - Files: `Pindrop/Services/SettingsStore.swift`, `PindropTests/SettingsStoreTests.swift`

---

- [x] 15. Implement Status Bar Controller

  **What to do**:
  - Create `Pindrop/UI/StatusBarController.swift`
  - Create NSStatusItem with SF Symbol icon (mic.fill)
  - Build dropdown menu with:
    - Recording status indicator
    - Start/Stop Recording toggle
    - Separator
    - Settings...
    - History...
    - Separator
    - Quit
  - Wire up menu actions to services

  **Must NOT do**:
  - Do not add too many menu items (keep it minimal)

  **Parallelizable**: NO (depends on 0)

  **References**:
  - NSStatusItem: https://developer.apple.com/documentation/appkit/nsstatusitem
  - SF Symbols: mic.fill, waveform, checkmark

  **Acceptance Criteria**:
  - [ ] StatusBarController class compiles
  - [ ] Manual: App icon appears in menu bar
  - [ ] Manual: Clicking icon shows menu
  - [ ] Manual: Menu items trigger correct actions

  **Commit**: YES
  - Message: `feat(ui): implement StatusBarController with dropdown menu`
  - Files: `Pindrop/UI/StatusBarController.swift`

---

- [x] 16. Implement Settings Window

  **What to do**:
  - Create `Pindrop/UI/SettingsWindow.swift` (SwiftUI)
  - Create tabs: General, Hotkeys, Models, AI Enhancement
  - General: Output mode, language (future)
  - Hotkeys: Configure toggle and push-to-talk shortcuts
  - Models: List available models, download/delete, select active
  - AI Enhancement: Enable/disable, API endpoint, API key

  **Must NOT do**:
  - Do not use AppKit for settings (SwiftUI only)
  - Do not add advanced/power-user settings

  **Parallelizable**: YES (with 17)

  **References**:
  - Settings/Preferences window: https://developer.apple.com/documentation/swiftui/settings
  - TabView: https://developer.apple.com/documentation/swiftui/tabview

  **Acceptance Criteria**:
  - [ ] SettingsWindow compiles and renders
  - [ ] Manual: Settings window opens from menu
  - [ ] Manual: All tabs display correctly
  - [ ] Manual: Changes persist after closing window

  **Commit**: YES
  - Message: `feat(ui): implement Settings window with General, Hotkeys, Models, AI tabs`
  - Files: `Pindrop/UI/SettingsWindow.swift`, `Pindrop/UI/Settings/`

---

- [x] 17. Implement History Window

  **What to do**:
  - Create `Pindrop/UI/HistoryWindow.swift` (SwiftUI)
  - Display list of transcriptions (newest first)
  - Show: text preview, timestamp, duration, model used
  - Implement search field
  - Add export button
  - Add copy-to-clipboard action per item

  **Must NOT do**:
  - Do not allow editing transcriptions
  - Do not implement deletion (future scope)

  **Parallelizable**: YES (with 16)

  **References**:
  - List with search: https://developer.apple.com/documentation/swiftui/list
  - Searchable modifier: https://developer.apple.com/documentation/swiftui/view/searchable(text:placement:prompt:)

  **Acceptance Criteria**:
  - [ ] HistoryWindow compiles and renders
  - [ ] Manual: History window opens from menu
  - [ ] Manual: Transcriptions display in list
  - [ ] Manual: Search filters results
  - [ ] Manual: Export saves file correctly

  **Commit**: YES
  - Message: `feat(ui): implement History window with search and export`
  - Files: `Pindrop/UI/HistoryWindow.swift`

---

- [x] 18. Implement Status Bar Visual Feedback

  **What to do**:
  - Update StatusBarController for recording states
  - Idle: mic.fill (monochrome)
  - Recording: mic.fill with red tint + animation
  - Processing: waveform animation
  - Use NSStatusItem button image updates

  **Must NOT do**:
  - Do not add sound effects

  **Parallelizable**: NO (depends on 15)

  **References**:
  - SF Symbols animation: https://developer.apple.com/documentation/symbols/

  **Acceptance Criteria**:
  - [ ] Icon changes based on recording state
  - [ ] Manual: Idle shows normal mic icon
  - [ ] Manual: Recording shows red/animated icon
  - [ ] Manual: Processing shows waveform

  **Commit**: YES
  - Message: `feat(ui): add visual feedback for recording states in status bar`
  - Files: `Pindrop/UI/StatusBarController.swift`

---

- [x] 19. Implement Optional Floating Indicator

  **What to do**:
  - Create `Pindrop/UI/FloatingIndicator.swift` (SwiftUI)
  - Small, always-on-top window showing recording status
  - Draggable position (remembers location)
  - Shows: recording duration, waveform visualization
  - Toggle in Settings

  **Must NOT do**:
  - Do not make floating indicator required
  - Do not add text/transcription preview to indicator

  **Parallelizable**: NO (depends on 18)

  **References**:
  - NSPanel for floating window: https://developer.apple.com/documentation/appkit/nspanel
  - Window level: .floating

  **Acceptance Criteria**:
  - [ ] FloatingIndicator compiles and renders
  - [ ] Manual: Indicator appears when enabled in Settings
  - [ ] Manual: Indicator shows during recording
  - [ ] Manual: Indicator position persists

  **Commit**: YES
  - Message: `feat(ui): implement optional floating recording indicator`
  - Files: `Pindrop/UI/FloatingIndicator.swift`

---

- [ ] 20. Wire Up App Coordinator

  **What to do**:
  - Create `Pindrop/App/AppCoordinator.swift`
  - Initialize all services on app launch
  - Wire up:
    - Hotkey events -> AudioRecorder -> TranscriptionService -> OutputManager
    - Transcription results -> HistoryStore
    - Settings changes -> Service configurations
  - Handle app lifecycle (launch, terminate, wake from sleep)

  **Must NOT do**:
  - Do not add complex state machines

  **Parallelizable**: NO (depends on most services)

  **References**:
  - App lifecycle: https://developer.apple.com/documentation/swiftui/app

  **Acceptance Criteria**:
  - [ ] AppCoordinator initializes without errors
  - [ ] Manual: Full flow works: hotkey -> record -> transcribe -> clipboard
  - [ ] Manual: History is saved after each transcription

  **Commit**: YES
  - Message: `feat(app): implement AppCoordinator to wire up all services`
  - Files: `Pindrop/App/AppCoordinator.swift`, `Pindrop/App/PindropApp.swift`

---

- [ ] 21. Final Integration Testing and Polish

  **What to do**:
  - Run full integration test suite
  - Test all user flows end-to-end
  - Fix any remaining bugs
  - Verify all acceptance criteria from above tasks
  - Create README with usage instructions

  **Must NOT do**:
  - Do not add new features
  - Do not refactor working code

  **Parallelizable**: NO (final task)

  **References**:
  - All previous task acceptance criteria

  **Acceptance Criteria**:
  - [ ] All XCTests pass: `xcodebuild test -scheme Pindrop`
  - [ ] Manual: Complete user flow works 5 times without error
  - [ ] Manual: App launches at login (if enabled)
  - [ ] Manual: Settings persist correctly
  - [ ] Manual: History persists correctly
  - [ ] README.md exists with basic usage

  **Commit**: YES
  - Message: `docs: add README and finalize v1.0`
  - Files: `README.md`

---

## Commit Strategy

| After Task | Message                                          | Files                                | Verification     |
| ---------- | ------------------------------------------------ | ------------------------------------ | ---------------- |
| 0          | `chore: initialize Pindrop Xcode project`        | Pindrop.xcodeproj/, Pindrop/         | xcodebuild -list |
| 1          | `chore: configure entitlements`                  | Pindrop.entitlements, Info.plist     | codesign check   |
| 2          | `test: set up XCTest infrastructure`             | PindropTests/                        | xcodebuild test  |
| 3          | `feat(audio): implement AudioRecorder`           | Services/AudioRecorder.swift         | Unit tests       |
| 4          | `feat(permissions): implement PermissionManager` | Services/PermissionManager.swift     | Unit tests       |
| 5          | `feat(stt): implement TranscriptionService`      | Services/TranscriptionService.swift  | Unit tests       |
| 6          | `feat(models): implement ModelManager`           | Services/ModelManager.swift          | Unit tests       |
| 7          | `feat(ai): implement AIEnhancementService`       | Services/AIEnhancementService.swift  | Unit tests       |
| 8          | `feat(hotkeys): implement HotkeyManager`         | Services/HotkeyManager.swift         | Unit tests       |
| 9          | `feat(hotkeys): add push-to-talk`                | Services/HotkeyManager.swift         | Unit tests       |
| 10         | `feat(output): implement OutputManager`          | Services/OutputManager.swift         | Unit tests       |
| 11         | `feat(permissions): add Accessibility`           | Services/PermissionManager.swift     | Unit tests       |
| 12         | `feat(history): implement HistoryStore`          | Models/, Services/HistoryStore.swift | Unit tests       |
| 13         | `feat(history): add export`                      | Services/HistoryStore.swift          | Unit tests       |
| 14         | `feat(settings): implement SettingsStore`        | Services/SettingsStore.swift         | Unit tests       |
| 15         | `feat(ui): implement StatusBarController`        | UI/StatusBarController.swift         | Manual           |
| 16         | `feat(ui): implement Settings window`            | UI/SettingsWindow.swift              | Manual           |
| 17         | `feat(ui): implement History window`             | UI/HistoryWindow.swift               | Manual           |
| 18         | `feat(ui): add visual feedback`                  | UI/StatusBarController.swift         | Manual           |
| 19         | `feat(ui): implement floating indicator`         | UI/FloatingIndicator.swift           | Manual           |
| 20         | `feat(app): implement AppCoordinator`            | App/AppCoordinator.swift             | Integration      |
| 21         | `docs: add README and finalize`                  | README.md                            | Full flow        |

---

## Success Criteria

### Verification Commands

```bash
# Build
xcodebuild -scheme Pindrop -configuration Debug build

# Test
xcodebuild test -scheme Pindrop -destination 'platform=macOS'

# Check signing
codesign -d --verbose=4 build/Debug/Pindrop.app
```

### Final Checklist

- [ ] App appears in menu bar on launch
- [ ] Option+Space toggles recording (global)
- [ ] Audio is captured and transcribed locally
- [ ] Transcribed text copies to clipboard
- [ ] Settings window opens and saves preferences
- [ ] History window shows past transcriptions
- [ ] History persists between restarts
- [ ] All unit tests pass
- [ ] No memory leaks during recording
- [ ] App uses < 200MB RAM during transcription

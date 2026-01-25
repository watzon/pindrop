# Learnings - Pindrop

## Conventions

(To be populated as we discover patterns)

## Patterns

(To be populated with code patterns)

## Xcode Project Initialization (2026-01-25)

### Manual Project Creation
- Created Xcode project manually without xcodegen (not installed)
- Used proper UUID-based object IDs (24-character hex strings) for all PBX objects
- Critical: XCBuildConfiguration objects must NOT have a `group` property - this causes "unrecognized selector" errors

### Project Structure
```
Pindrop.xcodeproj/
├── project.pbxproj                    # Main project file with PBX objects
├── project.xcworkspace/
│   ├── contents.xcworkspacedata       # Workspace definition
│   └── xcshareddata/swiftpm/          # Swift Package Manager cache
└── xcshareddata/xcschemes/
    └── Pindrop.xcscheme               # Shared build scheme
```

### WhisperKit Integration
- Added as XCRemoteSwiftPackageReference in project.pbxproj
- Minimum version: 0.9.0 (upToNextMajorVersion)
- Repository: https://github.com/argmaxinc/WhisperKit.git
- Package resolution happens on first `xcodebuild -list` (can take time)

### Menu Bar App Configuration
- Set `LSUIElement = YES` in Info.plist to hide dock icon
- Configured entitlements for:
  - App Sandbox (com.apple.security.app-sandbox)
  - Microphone access (com.apple.security.device.audio-input)
  - User-selected file read/write (com.apple.security.files.user-selected.read-write)

### Build Settings
- Deployment target: macOS 14.0 (MACOSX_DEPLOYMENT_TARGET)
- Bundle identifier: com.pindrop.app
- Swift version: 5.0
- SwiftUI previews enabled (ENABLE_PREVIEWS = YES)
- Asset catalog compiler configured for AppIcon and AccentColor

### Gotchas
- LSP errors about @main and ContentView are false positives when project context isn't loaded
- xcodebuild timeout during package resolution is normal for first run
- Standard Xcode file headers (comments) are conventional and should be kept

## XCTest Target Configuration (2026-01-25)

### Test Target Setup
- Created PindropTests target as `com.apple.product-type.bundle.unit-test`
- Test bundle identifier: `com.pindrop.app.tests`
- Test target requires dependency on main app target via PBXTargetDependency
- Test target requires PBXContainerItemProxy to reference main app

### Required PBX Objects for Test Target
1. PBXNativeTarget - The test target itself
2. PBXFileReference - The .xctest bundle product
3. PBXBuildFile - For test source files
4. PBXSourcesBuildPhase - To compile test files
5. PBXFrameworksBuildPhase - For linking (can be empty for basic tests)
6. PBXResourcesBuildPhase - For test resources (can be empty)
7. XCBuildConfiguration (Debug & Release) - Test-specific build settings
8. XCConfigurationList - To hold test configurations
9. PBXTargetDependency - Links test target to main app
10. PBXContainerItemProxy - Proxy for main app target reference

### Critical Build Settings for Test Target
```
BUNDLE_LOADER = "$(TEST_HOST)"
TEST_HOST = "$(BUILT_PRODUCTS_DIR)/Pindrop.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/Pindrop"
PRODUCT_BUNDLE_IDENTIFIER = com.pindrop.app.tests
GENERATE_INFOPLIST_FILE = YES
SWIFT_EMIT_LOC_STRINGS = NO
```

### Test Scheme Configuration
- Must add `<Testables>` section to TestAction in .xcscheme file
- TestableReference must include:
  - `BlueprintIdentifier` matching test target UUID
  - `BuildableName` as "PindropTests.xctest"
  - `parallelizable = "YES"` for parallel test execution
  - `skipped = "NO"` to enable tests

### Project Attributes
- Add test target to `TargetAttributes` in PBXProject
- Set `TestTargetID` to main app target UUID
- Set `CreatedOnToolsVersion` to match main target

### Gotchas
- Test scheme must be configured before `xcodebuild test` will work
- Without Testables section in scheme, get error: "Scheme X is not currently configured for the test action"
- Test target must be added to both `targets` array and Products group
- Standard Xcode test file comments are conventional and should be kept

## AudioRecorder Service Implementation (2026-01-25)

### AVAudioEngine Configuration for WhisperKit
- WhisperKit requires: 16kHz sample rate, mono (1 channel), 16-bit PCM format
- Created AVAudioFormat with: `AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000.0, channels: 1, interleaved: false)`
- Used AVAudioMixerNode to convert from input format to target format
- Input node provides hardware format, mixer handles conversion

### Audio Recording Pattern
- AVAudioEngine.inputNode provides microphone access
- installTap(onBus:bufferSize:format:) captures audio buffers
- Buffer size 2048 provides good balance between latency and efficiency
- Must convert buffers from input format to target format using AVAudioConverter

### Permission Handling
- Use AVCaptureDevice.requestAccess(for: .audio) for microphone permission
- Wrapped in async/await using withCheckedContinuation
- Permission prompt appears automatically on first request
- NSMicrophoneUsageDescription in Info.plist required (already configured)

### Buffer Management
- Store AVAudioPCMBuffer instances in array during recording
- Convert to Data on stopRecording() by extracting int16ChannelData
- Combine all buffers into single Data blob for transcription
- Clear buffer array after each recording session

### Testing Strategy
- Used @MainActor for AudioRecorder to ensure thread safety
- Tests handle permission denial gracefully (skip test if denied)
- Tests use Task {} for async/await in XCTest
- Brief sleep (0.5s) in tests to capture actual audio data
- Multiple recording sessions tested to verify cleanup

### Gotchas
- Must call audioEngine.prepare() before start()
- Must remove tap before stopping engine to avoid crashes
- Converter requires capacity calculation: `frameLength * outputRate / inputRate`
- int16ChannelData returns UnsafeMutablePointer, must iterate carefully
- @MainActor required for UI-related audio operations on macOS

## HotkeyManager Implementation (2026-01-25)

### Carbon Event API Usage
- Used `RegisterEventHotKey` and `UnregisterEventHotKey` for global hotkey registration
- Event handler installed via `InstallEventHandler` with `GetApplicationEventTarget()`
- EventHotKeyID signature uses 4-character code "PNDR" converted to OSType
- EventHotKeyID.id uses hash of identifier string for uniqueness

### Hotkey Registration Approach
- ModifierFlags as OptionSet wrapping Carbon's UInt32 modifier constants
- Store EventHotKeyRef for cleanup in deinit
- Callbacks dispatched to main queue for thread safety
- Event handler uses Unmanaged<HotkeyManager> for self reference in C callback

### Conflict Handling Strategies
- Check for duplicate identifiers before registration
- Log errors with os.log Logger subsystem
- Return Bool success/failure for all operations
- RegisterEventHotKey returns OSStatus - noErr (0) indicates success

### Testing Strategies for Global Hotkeys
- Unit tests for modifier flag conversion pass successfully
- Registration tests fail in test environment (expected - requires accessibility permissions)
- Tests verify API surface: register, unregister, configuration retrieval
- Manual testing required for actual hotkey triggering
- Test warning: unused variable 'callbackInvoked' is acceptable for callback verification tests

### Gotchas
- Global hotkeys require accessibility permissions at runtime
- Carbon Event API is C-based, requires careful memory management with Unmanaged
- EventHandlerUPP callback must use @convention(c) compatible signature
- Tests cannot verify actual hotkey triggering without accessibility permissions
- Import Carbon required in both implementation and test files

## PermissionManager Implementation (2026-01-25)

### Observable Pattern with @Observable Macro
- Used Swift's @Observable macro (macOS 14+) for reactive state management
- @Observable automatically makes properties observable without @Published
- Works seamlessly with SwiftUI views for automatic UI updates
- More modern and concise than Combine's @Published approach

### Permission Status Management
- AVCaptureDevice.authorizationStatus(for: .audio) checks current permission state
- Four states: .notDetermined, .restricted, .denied, .authorized
- .restricted indicates system-level restrictions (parental controls, MDM)
- .denied means user explicitly denied permission

### Permission Request Pattern
- AVCaptureDevice.requestAccess(for: .audio) requests permission
- Wrapped in async/await using withCheckedContinuation for clean API
- Permission dialog appears automatically on first request
- Subsequent calls return cached permission state without showing dialog
- Must refresh observable state after request completes

### Convenience Properties
- isAuthorized: true only when status == .authorized
- isDenied: true when status == .denied OR .restricted
- Computed properties provide cleaner API for UI binding

### Integration with AudioRecorder
- AudioRecorder now accepts PermissionManager via dependency injection
- Default parameter allows backward compatibility: init(permissionManager: PermissionManager = PermissionManager())
- Removed duplicate permission request logic from AudioRecorder
- Centralized permission handling in single service

### Testing Strategy
- Tests verify all permission states are handled correctly
- Tests check observable state updates after permission requests
- Tests validate convenience properties match underlying status
- Tests document behavior for restricted and denied states
- Permission dialog may appear during first test run (expected behavior)

### Gotchas
- @MainActor required for PermissionManager to ensure thread safety with UI
- Permission status should be refreshed after requestPermission() completes
- Tests cannot mock AVCaptureDevice, so they test against real system state
- LSP may show false positive errors for @Observable types in test files

## TranscriptionService Implementation (2026-01-25)

### WhisperKit API Usage
- WhisperKit initialization requires WhisperKitConfig with either modelFolder (path) or model (name)
- Model names like "tiny", "large-v3" trigger automatic download if not present
- WhisperKit.transcribe() accepts [Float] array (normalized -1.0 to 1.0) for audio data
- DecodingOptions configures transcription: task (.transcribe), language, timestamps
- TranscriptionResult array returned, typically use .first.text for simple transcription

### Audio Data Conversion for WhisperKit
- AudioRecorder outputs 16kHz mono 16-bit PCM as Data
- WhisperKit requires [Float] array with normalized samples
- Conversion: Int16 sample / Int16.max = Float in range [-1.0, 1.0]
- Use Data.withUnsafeBytes and bindMemory(to: Int16.self) for efficient conversion
- Reserve capacity on Float array for performance with large audio buffers

### State Management with @Observable
- Used @Observable macro for reactive state management (macOS 14+)
- State enum tracks: .unloaded, .loading, .ready, .transcribing, .error
- @MainActor required for TranscriptionService to ensure thread safety
- State transitions: unloaded → loading → ready → transcribing → ready (or error)
- Prevent concurrent transcriptions by checking state before starting

### Error Handling Patterns
- Custom TranscriptionError enum with LocalizedError conformance
- Specific errors: modelNotLoaded, invalidAudioData, transcriptionFailed, modelLoadFailed
- Catch and rethrow with context: catch generic Error, wrap in TranscriptionError
- Set state to .error and store error property for UI display
- Always reset state to .ready after transcription completes (success or failure)

### Testing Strategies for STT Services
- @MainActor required on test class for testing @MainActor services
- Tests verify state transitions without actual model (expected to fail in test env)
- Test audio data conversion separately from transcription
- Verify error handling: modelNotLoaded, invalidAudioData, concurrent transcription
- Use Task.sleep for async state transition verification
- Tests pass even when model loading fails (validates error handling)

### Dependency Injection for @MainActor Services
- AudioRecorder.init() changed from default parameter to explicit parameter
- Cannot use default parameter with @MainActor initializer (async context issue)
- Use nonisolated init for services that need to be created outside MainActor
- Tests must create PermissionManager and pass to AudioRecorder explicitly
- Pattern: nonisolated init(permissionManager: PermissionManager) for flexibility

### Gotchas
- LSP shows "No such module 'WhisperKit'" but xcodebuild succeeds (false positive)
- WhisperKit package must be added to project.pbxproj before use
- @Observable requires import Observation (implicit in some contexts)
- Cannot call @MainActor init from default parameter (use nonisolated or explicit param)
- TranscriptionResult is array, not single result - always check .first
- Empty audio data should be validated before conversion to avoid crashes

## ModelManager Implementation (2026-01-25)

### WhisperKit Model Management
- WhisperKit models hosted on HuggingFace: argmaxinc/whisperkit-coreml
- Model sizes: tiny (75MB), base (145MB), small (483MB), medium (1500MB), large-v3 (3100MB), turbo (809MB)
- English-only variants available for smaller models (.en suffix)
- Models stored in ~/Library/Application Support/Pindrop/Models/
- Each model gets its own subdirectory

### URLSession Download with Progress Tracking
- Use URLSession.shared.download(from:delegate:) for file downloads
- Custom URLSessionDownloadDelegate to track progress
- Progress calculated: totalBytesWritten / totalBytesExpectedToWrite
- Delegate must be class (not struct) to conform to NSObject
- Progress handler uses weak self and @MainActor Task to update UI state

### FileManager for Application Support
- Use FileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
- Create directory with createDirectory(atPath:withIntermediateDirectories:)
- withIntermediateDirectories: true creates parent directories automatically
- Check existence with fileExists(atPath:isDirectory:)
- Delete with removeItem(atPath:)

### @Observable State Management for Downloads
- @Published properties: downloadProgress, isDownloading, currentDownloadModel
- State updates must happen on @MainActor
- Use defer block to reset download state on completion/error
- Prevent concurrent downloads by checking isDownloading flag

### Async Filter Pattern
- Cannot use async closure in synchronous filter()
- Must iterate manually with for-in loop and await
- Pattern: var result = []; for item in items { if await check(item) { result.append(item) } }
- Alternative: use TaskGroup for parallel async filtering

### Testing Model Management
- Tests verify model listing, path generation, directory creation
- Tests check download progress state management
- Tests validate error handling for nonexistent models
- Cannot test actual downloads in unit tests (too slow, requires network)
- Manual testing required for download functionality

### Gotchas
- LSP shows "No such module 'XCTest'" in test files (false positive, tests compile)
- URLSessionDownloadDelegate requires NSObject inheritance
- Progress handler must use weak self to avoid retain cycles
- Download destination must be removed before moveItem if it exists
- HTTP response status codes 200-299 indicate success

## AI Enhancement Service Implementation (2026-01-25)

### OpenAI-Compatible API Integration
- **Request Structure**: POST to `/v1/chat/completions` with JSON body containing `model`, `messages`, `temperature`, `max_tokens`
- **Authentication**: Bearer token in `Authorization` header
- **Response Parsing**: Extract `choices[0].message.content` from JSON response
- **Error Handling**: Return original text on any failure (network, HTTP error, JSON parsing)

### Keychain Integration for API Keys
- **Service Identifier**: Use bundle identifier-based service name (`com.pindrop.ai-enhancement`)
- **Account Identifier**: Use API endpoint URL as account name for multi-endpoint support
- **Security Framework**: Use `SecItemAdd`, `SecItemCopyMatching`, `SecItemDelete` for CRUD operations
- **Error Handling**: Check for `errSecSuccess` and `errSecItemNotFound` status codes

### Testing Strategies for External APIs
- **Protocol Abstraction**: Create `URLSessionProtocol` to enable dependency injection
- **Mock Session**: Implement mock that captures requests and returns controlled responses
- **Test Coverage**: Success case, network errors, HTTP errors, JSON parsing errors, empty input
- **Request Verification**: Validate headers, body structure, and message format in tests

### Swift Service Architecture Patterns
- **@MainActor**: Mark service as `@MainActor` for UI integration safety
- **@Observable**: Use for SwiftUI state management integration
- **Error Types**: Define custom error enum conforming to `LocalizedError`
- **Fallback Strategy**: Always return original text on enhancement failure (graceful degradation)

### API Enhancement Prompt Engineering
- **System Message**: Clear instruction to improve grammar/punctuation while preserving meaning
- **Temperature**: Use low temperature (0.3) for consistent, conservative enhancements
- **Output Format**: Request only enhanced text without commentary
- **Token Limit**: Set reasonable max_tokens (2048) for typical transcription lengths


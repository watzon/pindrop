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


## Push-to-Talk Hotkey Implementation (2026-01-25)

### Carbon Event Key Down/Up Detection
- GetEventKind(event) returns event type: kEventHotKeyPressed or kEventHotKeyReleased
- Event handler receives both press and release events when registered for both EventTypeSpecs
- Must distinguish between key down and key up in handleHotkeyEvent using eventKind comparison
- EventTypeSpec array includes both kEventHotKeyPressed and kEventHotKeyReleased for full lifecycle

### Push-to-Talk Mode Architecture
- Added HotkeyMode enum with .toggle and .pushToTalk cases
- HotkeyConfiguration now has mode, onKeyDown, and onKeyUp optional closures
- Backward compatibility maintained with convenience init for toggle mode (single callback)
- Push-to-talk mode requires both onKeyDown and onKeyUp callbacks

### Edge Case Handling for Key Events
- Track isKeyCurrentlyPressed state per hotkey to prevent duplicate key down events
- Ignore repeated key down events when key is already pressed (OS key repeat)
- Update state on both key down and key up events
- State tracking prevents callback spam during key hold

### Testing Push-to-Talk Functionality
- testPushToTalkKeyDown: Verifies registration with mode, onKeyDown, onKeyUp
- testPushToTalkKeyUp: Validates configuration retrieval for push-to-talk mode
- testToggleModeBackwardCompatibility: Ensures old API still works with convenience init
- testPushToTalkModeConfiguration: Tests direct HotkeyConfiguration creation and callback invocation
- Tests verify mode, callback presence, and proper initialization

### API Design Patterns
- Default parameters for mode (.toggle), onKeyDown (nil), onKeyUp (nil) in registerHotkey
- Convenience initializer for toggle mode maintains backward compatibility
- Explicit initializer for push-to-talk mode requires all parameters
- Optional closures allow flexible callback configuration

### Gotchas
- Must update registeredHotkeys dictionary after modifying isKeyCurrentlyPressed (value type)
- GetEventKind returns UInt32, must compare with UInt32(kEventHotKeyPressed/Released)
- Switch statement on mode determines which callbacks to invoke
- Thread safety maintained with DispatchQueue.main.async for all callbacks

## OutputManager Implementation (2026-01-25)

### NSPasteboard for Clipboard Operations
- NSPasteboard.general provides access to system clipboard
- Must call clearContents() before writing to replace previous clipboard contents
- setString(_:forType:) writes text to clipboard, returns Bool for success/failure
- Use .string as the pasteboard type for plain text
- Unlike iOS UIPasteboard, macOS requires explicit clearing before writing

### CGEvent for Keyboard Simulation
- CGEvent.keyboardEventSource creates keyboard events for text insertion
- Requires two events per character: keyDown (true) and keyUp (false)
- Events posted via post(tap: .cgAnnotatedSessionEventTap) to system event stream
- CGEventFlags used for modifiers: .maskShift for uppercase/special chars
- Small delay (1ms) between characters improves reliability

### Character to KeyCode Mapping
- macOS uses hardware keycodes (CGKeyCode), not characters
- Mapping required for each character: (keyCode: CGKeyCode, modifiers: CGEventFlags)
- Example mappings: "a" = (0, []), "A" = (0, .maskShift), space = (49, [])
- Lowercase letters: keycodes 0-46, uppercase adds .maskShift modifier
- Numbers: keycodes 18-29, special chars require shift for symbols
- Unsupported characters (emoji, unicode) return nil from mapping

### Accessibility Permission for Direct Insert
- AXIsProcessTrustedWithOptions checks if app has accessibility permission
- kAXTrustedCheckOptionPrompt: false = silent check, true = show system prompt
- Permission required for CGEvent posting to work across applications
- System prompt can only appear once per app launch
- Must guide users to System Settings > Privacy & Security > Accessibility if denied

### Fallback Strategy Pattern
- OutputMode enum: .clipboard (always safe) vs .directInsert (requires permission)
- Check accessibility permission before attempting direct insert
- Automatically fall back to clipboard if permission denied
- Graceful degradation ensures functionality without blocking user

### Testing Strategies for Output Services
- @MainActor required on test class for testing @MainActor services
- Tests verify clipboard operations by reading NSPasteboard after write
- Tests verify fallback behavior when accessibility permission unavailable
- Character mapping tested separately from actual keyboard simulation
- Manual testing required for direct insert (needs accessibility permission)
- Extension pattern used to expose private methods for unit testing

### Error Handling for Output Operations
- Custom OutputManagerError enum with LocalizedError conformance
- Specific errors: emptyText, clipboardWriteFailed, textInsertionFailed, accessibilityPermissionDenied
- Throw errors for invalid input (empty text) before attempting operations
- Return Bool from clipboard operations to detect write failures
- Fallback to clipboard on any direct insert failure

### Gotchas
- LSP shows false positive errors for XCTest imports (tests compile successfully)
- CGEvent requires accessibility permission at runtime, not compile time
- Character mapping incomplete - production needs full Unicode support
- Direct insert types one character at a time (slower than paste for long text)
- Accessibility permission prompt only shows once per app launch
- Must add files to correct Services group in Xcode project (multiple groups exist)

## Accessibility Permission Handling (2026-01-25)

### AXIsProcessTrusted API Usage
- AXIsProcessTrusted() checks if app has Accessibility permission (returns Bool)
- AXIsProcessTrustedWithOptions() allows showing system prompt on first check
- kAXTrustedCheckOptionPrompt key controls whether to show system dialog
- System prompt can only appear once per app launch (subsequent calls return cached state)
- Permission check is synchronous (no async/await needed)

### Permission Request Pattern with Options
- Create CFDictionary with kAXTrustedCheckOptionPrompt key
- Use takeUnretainedValue() to convert CFString to Swift String for dictionary key
- showPrompt: false = silent check, showPrompt: true = show system prompt if not granted
- Always update observable state after checking permission
- Return Bool directly (no need for async/await like microphone permission)

### Opening System Preferences for Accessibility
- Use URL scheme: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
- NSWorkspace.shared.open(url) opens System Settings to Accessibility pane
- Requires AppKit framework import (NSWorkspace is part of AppKit)
- User must manually enable app in System Settings (cannot be automated)

### Observable State Management for Multiple Permissions
- Separate observable properties for each permission type (permissionStatus, accessibilityPermissionGranted)
- Convenience properties for UI binding (isAuthorized, isAccessibilityAuthorized)
- Initialize all permission states in init() for immediate UI availability
- Refresh methods update observable state for reactive UI updates

### Testing Accessibility Permissions
- Tests verify observable state updates after permission checks
- Tests verify convenience properties match underlying state
- Tests verify request with and without prompt parameter
- Tests verify refresh method updates observable state
- openAccessibilityPreferences() test just verifies method doesn't crash
- Actual permission state depends on system configuration (tests adapt to current state)

### Integration with Existing PermissionManager
- Added MARK comments to organize microphone vs accessibility sections
- Maintained existing @MainActor and @Observable patterns
- Followed same naming conventions (check, request, refresh methods)
- Kept backward compatibility with existing microphone permission API

### Gotchas
- ApplicationServices framework required for AX* functions
- AppKit framework required for NSWorkspace
- kAXTrustedCheckOptionPrompt is CFString, must use takeUnretainedValue()
- System prompt only shows once per app launch (by design)
- Permission cannot be granted programmatically (user must enable in System Settings)
- Tests pass regardless of actual permission state (validates API surface, not system state)

## SettingsStore Implementation (2026-01-25)

### @AppStorage for Simple Settings
- @AppStorage property wrapper provides automatic UserDefaults persistence
- Syntax: @AppStorage("key") var property: Type = defaultValue
- Works seamlessly with @Observable for reactive SwiftUI updates
- Supports String, Bool, Int, Double, and other basic types
- Settings persist automatically across app launches
- No manual UserDefaults.standard calls needed

### Keychain Integration for Sensitive Data
- Use Security framework for API keys and endpoints
- Service identifier pattern: bundle-based (e.g., "com.pindrop.settings")
- Account identifier: unique per value (e.g., "api-endpoint", "api-key")
- CRUD operations: SecItemAdd, SecItemCopyMatching, SecItemDelete
- Always delete existing item before adding (SecItemDelete before SecItemAdd)
- Check for errSecSuccess and errSecItemNotFound status codes

### Observable Settings Pattern
- Combine @Observable with @AppStorage for reactive settings
- Cache Keychain values in private properties for performance
- Update cached values after save/delete operations
- Load Keychain values in init() for immediate availability
- @MainActor required for UI integration safety

### Settings Architecture Best Practices
- Separate concerns: @AppStorage for preferences, Keychain for secrets
- Provide public read-only access to Keychain values (private(set))
- Expose save/delete methods for Keychain values
- Initialize Keychain cache in init() to avoid repeated Keychain queries
- Use custom error types conforming to LocalizedError

### Testing Settings Persistence
- Test @AppStorage by creating new instance and verifying values persist
- Test Keychain by saving, creating new instance, and verifying load
- Test Keychain updates by saving twice and verifying latest value
- Clean up Keychain in setUp() and tearDown() to avoid test pollution
- Test default values with fresh instance
- Test error handling for delete operations (should not throw on missing items)

### Gotchas
- @AppStorage values persist in UserDefaults between test runs (reset in tearDown)
- Keychain values persist system-wide (must explicitly delete in tests)
- SecItemDelete returns errSecItemNotFound if item doesn't exist (not an error)
- Must delete existing Keychain item before adding to avoid duplicate errors
- @Observable requires import Observation (implicit in some contexts)
- Cached Keychain values must be updated after save/delete operations


## HistoryStore with SwiftData Implementation (2026-01-25)

### SwiftData @Model Macro Usage
- @Model macro automatically generates SwiftData persistence code for classes
- @Attribute(.unique) ensures unique constraint on properties (e.g., id: UUID)
- Model classes must be final and use var (not let) for all properties
- Default values in init() work seamlessly with SwiftData
- No need for @Published or manual observation - SwiftData handles it

### ModelContext and ModelContainer Patterns
- ModelContext is the primary interface for database operations (insert, delete, save, fetch)
- ModelContainer created with Schema([ModelType.self]) defines available models
- ModelConfiguration(isStoredInMemoryOnly: true) perfect for unit tests (no persistence)
- ModelContext.insert() adds new records, must call save() to persist
- ModelContext.delete() removes records, must call save() to persist
- ModelContext.fetch(descriptor) retrieves records with sorting and filtering

### FetchDescriptor for Queries
- FetchDescriptor<T> defines how to fetch records of type T
- sortBy parameter accepts array of SortDescriptor for ordering
- SortDescriptor(\.property, order: .reverse) for descending order
- fetchLimit property limits number of results returned
- predicate parameter filters results using #Predicate macro

### #Predicate Macro for Search
- #Predicate<ModelType> { record in ... } creates type-safe predicates
- localizedStandardContains() provides case-insensitive search
- Predicates compile to efficient database queries (not in-memory filtering)
- Can combine multiple conditions with && and || operators
- Supports complex expressions with property access and comparisons

### SwiftData Error Handling
- Wrap ModelContext operations in do-catch blocks
- save() can throw errors (disk full, constraint violations, etc.)
- fetch() can throw errors (invalid descriptor, database corruption, etc.)
- delete() operations can fail if record doesn't exist or is referenced
- Custom error enums with LocalizedError provide user-friendly messages

### Testing SwiftData Services
- Use in-memory ModelContainer for fast, isolated tests
- Create fresh ModelContext in setUp(), nil in tearDown()
- @MainActor required on test class when testing @MainActor services
- Tests verify CRUD operations, search, ordering, and error handling
- async throws tests supported with async func test methods
- Task.sleep() useful for testing timestamp ordering

### Xcode Project Integration for SwiftData
- Must add Model files to Xcode project (not just filesystem)
- Create Models group in PBXGroup section of project.pbxproj
- Add PBXFileReference for each model file
- Add PBXBuildFile to link file to target
- Add file UUID to Sources build phase
- Python script useful for batch adding files to project

### Gotchas
- LSP shows "Cannot find 'ModelType' in scope" but xcodebuild succeeds (false positive)
- SwiftData requires macOS 14.0+ (already set in build settings)
- @Model classes cannot be structs (must be classes)
- ModelContext operations must be on same actor as ModelContext creation
- FetchDescriptor predicate errors only appear at runtime, not compile time
- Task.sleep() in tests requires async throws function signature


## History Export Implementation (2026-01-25)

### NSSavePanel for File Export
- NSSavePanel provides native macOS file save dialog
- Set allowedContentTypes using UTType (.plainText, .json, .commaSeparatedText)
- nameFieldStringValue sets default filename in dialog
- title and message customize dialog appearance
- runModal() returns .OK or .cancel (NSApplication.ModalResponse)
- url property contains selected file path after successful dialog
- Must check both response == .OK and url != nil before proceeding

### Export Format Strategies
- **Plain Text**: Human-readable format with headers, separators, formatted dates
- **JSON**: Structured data with ISO8601 timestamps, pretty-printed with sortedKeys
- **CSV**: Spreadsheet-compatible with proper escaping (quotes doubled, newlines removed)
- All formats use UTF-8 encoding for universal compatibility

### CSV Escaping Rules
- Double quotes in text must be escaped as "" (two double quotes)
- Newlines and carriage returns replaced with spaces to prevent row breaks
- All text fields wrapped in quotes to handle commas safely
- Format: "field with ""quotes"" and, commas" becomes valid CSV cell

### JSON Export Pattern
- Define nested Codable structs for export structure (ExportData, ExportRecord)
- Use ISO8601DateFormatter for consistent timestamp formatting
- JSONEncoder.outputFormatting = [.prettyPrinted, .sortedKeys] for readable output
- Include metadata: exportDate, totalRecords for context

### Testing File Export Without UI
- Create internal helper methods that accept URL parameter (bypass NSSavePanel)
- Use FileManager.default.temporaryDirectory for test files
- Clean up test files in both setUp and tearDown to prevent pollution
- Verify file existence, content structure, and proper escaping
- Test empty records case to ensure proper error handling

### Gotchas
- NSSavePanel requires @MainActor context (UI operation)
- Records from HistoryStore are in reverse chronological order (newest first)
- Test assertions must account for record ordering
- LSP shows false positive errors for TranscriptionRecord (tests compile and pass)
- FileManager operations can throw, must wrap in do-catch
- ISO8601DateFormatter produces consistent, parseable timestamps across platforms


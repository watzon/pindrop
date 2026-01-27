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


## StatusBarController Implementation (2026-01-25)

### NSStatusItem Usage Patterns
- Created status item with `NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)`
- Set button image using SF Symbols: `NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Pindrop")`
- Used `button.image?.isTemplate = true` to allow icon to adapt to menu bar theme (light/dark mode)
- Assigned NSMenu directly to statusItem.menu property for dropdown behavior

### Menu Bar App Best Practices
- Keep menu minimal and focused (7 items total including separators)
- Disabled status indicator item (isEnabled = false) for non-interactive display
- Used keyboard shortcuts for common actions (⌘R for recording, ⌘, for settings, ⌘H for history, ⌘Q for quit)
- Grouped related items with NSMenuItem.separator() for visual organization
- Made controller @MainActor since all AppKit UI must run on main thread

### SF Symbols Integration
- SF Symbols work seamlessly with NSImage(systemSymbolName:accessibilityDescription:)
- Template images automatically adapt to system appearance
- Used "mic.fill" for microphone icon (solid fill style)
- Accessibility descriptions improve VoiceOver support

### Menu Action Wiring
- Used @objc methods as action selectors for NSMenuItem
- Set target to self for proper action routing
- Wrapped async operations in Task {} for AudioRecorder integration
- Dynamic menu updates via updateMenuState() method that changes titles and icons based on recording state
- Used emoji (🔴) for visual recording indicator in menu

### Architecture Notes
- StatusBarController depends on AudioRecorder and SettingsStore services
- Placeholder print statements for Settings/History windows (to be implemented later)
- Clean separation: controller handles UI, delegates recording logic to AudioRecorder
- Public updateMenuState() method allows external state synchronization


## HistoryWindow SwiftUI Implementation (2026-01-25)

### SwiftUI List with Search
- .searchable(text:prompt:) modifier adds native macOS search field to window
- Search field automatically appears in toolbar area above list
- Filtering done manually in computed property (filteredTranscriptions)
- localizedStandardContains() provides case-insensitive search matching
- List automatically updates when filtered array changes

### SwiftUI Empty States Pattern
- Use conditional rendering with if-else for loading, error, and empty states
- Image(systemName:) with large font size creates visual empty state icons
- VStack with spacing and foregroundStyle(.secondary) for muted appearance
- Different empty states for "no data" vs "no search results"
- frame(maxWidth:maxHeight:) centers empty state content

### Context Menu on List Items
- .contextMenu modifier adds right-click menu to list rows
- Multiple Button actions in context menu for different operations
- Copy to clipboard uses NSPasteboard.general pattern
- Can provide multiple copy formats (plain text vs formatted with details)

### Export Menu Pattern
- Menu with Label creates dropdown button in toolbar
- Multiple Button actions for different export formats
- .disabled() modifier based on data availability (empty list)
- Export operations delegated to HistoryStore service
- Task { @MainActor in } wrapper for async export operations

### SwiftUI Preview with SwiftData
- @Previewable @State var for preview-only state management
- Closure with immediate invocation () for setup logic in preview
- ModelConfiguration(isStoredInMemoryOnly: true) for preview data
- Insert sample records into context before returning container
- .modelContainer() modifier passes container to view hierarchy

### Environment ModelContext Pattern
- @Environment(\.modelContext) injects SwiftData context into view
- Create HistoryStore lazily in onAppear with injected context
- @State private var for storing service instance
- Allows view to work with any ModelContext (production or preview)

### Gotchas
- LSP shows "Cannot find type" errors for SwiftData models (false positives)
- Build succeeds even when LSP shows errors (trust xcodebuild)
- #Preview macro requires @Previewable for state variables in closure
- Cannot use explicit return in #Preview body (ViewBuilder context)
- Must remove return keyword or use closure pattern for setup
- filteredTranscriptions computed property recalculates on every searchText change

## Settings Window Implementation (2026-01-25)

### @Observable vs ObservableObject with @AppStorage
- **Conflict**: @Observable macro conflicts with @AppStorage property wrapper
- **Error**: "property wrapper cannot be applied to a computed property"
- **Root Cause**: @Observable generates computed properties for observation tracking, incompatible with @AppStorage
- **Solution**: Use ObservableObject protocol with Combine instead of @Observable macro
- **Pattern**: `final class SettingsStore: ObservableObject` with `@AppStorage` properties
- **Views**: Use @ObservedObject (child views) or @StateObject (owner) instead of @Bindable

### SwiftUI Settings Window Architecture
- **TabView**: Native tab interface for settings categories
- **Form + .formStyle(.grouped)**: Apple-standard settings layout
- **Section with header**: Organized settings groups with headers
- **Picker with .radioGroup**: Radio button style for exclusive choices
- **SecureField**: Password-style input for API keys
- **TextField with .disabled(true)**: Display-only fields for future features

### Settings Persistence Patterns
- **@AppStorage**: Automatic UserDefaults persistence for simple types (String, Bool, Int)
- **Keychain**: Secure storage for sensitive data (API keys, endpoints)
- **Cached Values**: Load Keychain values once in init(), cache in properties
- **Reactive Updates**: @AppStorage automatically triggers view updates on change
- **ObservableObject**: Manual objectWillChange.send() not needed with @AppStorage

### Model Management UI Patterns
- **List with Selection**: `List(selection: $settings.selectedModel)` for model picker
- **Conditional Buttons**: Show Download/Delete based on model state
- **Progress Indicators**: ProgressView(value:) for download progress
- **Error Display**: Inline error messages with dismiss button
- **Task Modifier**: `.task { await refreshDownloadedModels() }` for async initialization
- **State Management**: @State for local UI state, @ObservedObject for shared state

### Form Validation and UX
- **Disabled States**: Disable controls when feature is off or data is invalid
- **Visual Feedback**: Success indicators (checkmark + green text) for save operations
- **Temporary Messages**: Use Task.sleep() to auto-dismiss success messages
- **Error Handling**: Display errors inline, allow user to dismiss
- **Placeholder Text**: Use .disabled(true) + placeholder for future features

### Xcode Project Integration for UI Files
- **Group Structure**: Create Settings group under UI group for organization
- **File References**: Add PBXFileReference for each .swift file
- **Build Files**: Add PBXBuildFile linking file reference to target
- **Sources Phase**: Add build file UUIDs to PBXSourcesBuildPhase
- **Group Children**: Add file references to parent PBXGroup children array
- **Nested Groups**: Create separate group for Settings subdirectory

### SwiftUI Preview Patterns
- **#Preview Macro**: Modern preview syntax for Xcode 15+
- **State Initialization**: Create fresh SettingsStore() for each preview
- **Isolated Previews**: Each view preview is independent, no shared state
- **Quick Iteration**: Previews enable rapid UI development without full app launch

### Gotchas
- **@Observable + @AppStorage**: Cannot be used together, use ObservableObject instead
- **@Bindable**: Only works with @Observable types, use @ObservedObject for ObservableObject
- **@StateObject**: Use in parent/owner view, @ObservedObject in child views
- **LSP Errors**: "Cannot find type" errors are false positives when project context not loaded
- **Xcode Project**: Must add files to project.pbxproj, not just filesystem
- **Build Success**: xcodebuild succeeds even when LSP shows errors (trust the build)

## Status Bar Visual Feedback Implementation (2026-01-25)

### NSStatusItem Icon State Management
- RecordingState enum tracks three states: idle, recording, processing
- didSet property observer automatically updates icon when state changes
- Eliminates manual icon updates scattered throughout code
- Single source of truth for visual state

### SF Symbols State-Based Icons
- **Idle**: mic.fill with isTemplate = true (adapts to menu bar theme)
- **Recording**: mic.fill with isTemplate = false + contentTintColor = .systemRed
- **Processing**: waveform symbol with template mode for theme adaptation
- Template mode allows automatic light/dark mode adaptation
- Non-template mode required for custom tint colors

### Core Animation for Status Bar Icons
- CABasicAnimation applied directly to button.layer
- **Pulse animation**: opacity 1.0 → 0.3, autoreverses, infinite repeat
- **Rotation animation**: transform.rotation 0 → 2π, infinite repeat
- Animation keys ("pulse", "rotation") allow removal when state changes
- Animations automatically removed when new state sets different animation

### State Transition Pattern
- Private updateStatusBarIcon() method handles all visual updates
- Public setProcessingState() and setIdleState() for external control
- updateMenuState() now only updates menu items, delegates icon to state system
- Clean separation: menu state vs icon state

### Accessibility Integration
- accessibilityDescription changes per state: "Pindrop", "Recording", "Processing"
- VoiceOver announces state changes automatically
- Template icons work with system accessibility settings (high contrast, etc.)

### Animation Performance
- Core Animation runs on GPU, minimal CPU impact
- Infinite animations don't block main thread
- Small duration values (0.8s, 2.0s) provide smooth visual feedback
- autoreverses creates natural pulse effect without manual keyframe management

### Gotchas
- Must set isTemplate = false before applying contentTintColor (red tint)
- Template mode and custom tint colors are mutually exclusive
- Animation keys must be unique per animation type to avoid conflicts
- Layer animations persist until explicitly removed or replaced
- LSP shows false positive errors for AudioRecorder/SettingsStore (build succeeds)


## Floating Indicator Window Implementation (2026-01-25)

### NSPanel for Floating Windows
- NSPanel is specialized NSWindow subclass for utility/accessory windows
- Set window level to .floating for always-on-top behavior
- collectionBehavior: [.canJoinAllSpaces, .fullSizeContentView] allows window on all desktops
- isFloatingPanel = true enables proper floating panel behavior
- isMovableByWindowBackground = true allows dragging from any part of window
- titlebarAppearsTransparent + .fullSizeContentView for modern borderless look

### Position Persistence with UserDefaults
- Store NSPoint coordinates (x, y) separately in UserDefaults
- Load saved position in init, use default if no saved position exists
- Default position: top-right corner calculated from NSScreen.main.visibleFrame
- Save position on NSWindow.didMoveNotification for automatic persistence
- NotificationCenter observer with weak self prevents retain cycles

### ObservableObject Pattern for Window Controllers
- Use ObservableObject instead of @Observable for AppKit integration
- @Published properties automatically trigger SwiftUI view updates
- NSHostingView wraps SwiftUI view for embedding in NSPanel
- Pass controller as @ObservedObject to SwiftUI view for reactive binding
- Eliminates need for manual Binding creation with $ syntax

### SwiftUI Waveform Visualization
- GeometryReader provides dynamic sizing for bar layout
- ForEach with index creates individual bars with unique heights
- Sine wave pattern: sin(normalizedIndex * .pi * 2) creates smooth wave
- Audio level multiplier scales wave amplitude (0.2 to 1.0 range)
- Color gradient based on bar position creates visual interest
- Minimal height (2pt) when not recording maintains visual presence

### @MainActor Isolation with NotificationCenter
- NotificationCenter observers run on specified queue (.main)
- Must wrap @MainActor method calls in Task { @MainActor in } from observer
- Prevents "synchronous nonisolated context" compiler warnings
- Pattern: NotificationCenter observer → Task wrapper → @MainActor method

### SwiftUI Preview with ObservableObject
- Create controller instance in preview closure
- Set published properties directly (no $ binding needed)
- Return view with controller passed as parameter
- Allows testing different states in preview

### Gotchas
- NSPanel requires explicit contentView assignment (not body like SwiftUI)
- Window level .floating higher than normal windows but below .statusBar
- Must call orderFrontRegardless() to show panel (orderFront insufficient)
- NSHostingView retains SwiftUI view, must nil out on hide() to prevent leaks
- @Published properties in @MainActor class require Task wrapper in non-isolated contexts
- Preview must use explicit return when setup logic precedes view creation


## AppCoordinator Implementation (2026-01-25)

### Service Coordination Patterns
- **Dependency Injection**: All services initialized in correct order in AppCoordinator init
- **@Observable**: Used for reactive state management across the app
- **@MainActor**: Ensures all UI-related operations run on main thread
- **Weak References**: Used in closures to prevent retain cycles

### Dependency Order
1. PermissionManager (no dependencies)
2. AudioRecorder (depends on PermissionManager)
3. TranscriptionService, ModelManager, AIEnhancementService (independent)
4. HotkeyManager, OutputManager (independent)
5. HistoryStore (depends on ModelContext)
6. SettingsStore (independent)
7. UI Controllers (depend on services)

### Hotkey Integration
- **Push-to-Talk Mode**: onKeyDown starts recording, onKeyUp stops and transcribes
- **Toggle Mode**: onKeyDown toggles recording state
- **Key Codes**: T=17, R=15 with Command+Shift modifiers
- **Async Handlers**: Wrapped in Task { @MainActor } for proper async execution

### Recording Flow
1. Hotkey pressed → startRecording()
2. Update UI (StatusBar, FloatingIndicator)
3. AudioRecorder.startRecording()
4. Hotkey released → stopRecordingAndTranscribe()
5. AudioRecorder.stopRecording() → audioData
6. TranscriptionService.transcribe() → text
7. Optional: AIEnhancementService.enhance() → enhanced text
8. OutputManager.output() → clipboard/direct insert
9. HistoryStore.save() → persist to SwiftData

### Settings Reactivity
- **Combine**: Used settingsStore.objectWillChange publisher
- **Sink**: Observes changes and updates services accordingly
- **Output Mode**: Dynamically switches between clipboard and direct insert
- **Floating Indicator**: Shows/hides based on settings

### Error Handling
- **Try-Catch**: Used throughout async operations
- **Error Property**: Stored on AppCoordinator for UI access
- **Fallbacks**: AI enhancement falls back to original text on failure
- **Print Statements**: Used for debugging (should be replaced with proper logging)

### App Lifecycle
- **ModelContainer**: Created as static property in PindropApp
- **onAppear**: Used to initialize AppCoordinator (avoids escaping closure issues)
- **MenuBarExtra**: Used instead of WindowGroup for menu bar app
- **Lazy Initialization**: Coordinator created on first appear

### Xcode Project Integration
- **xcodeproj gem**: Used to programmatically add files to Xcode project
- **File References**: Added AppCoordinator, StatusBarController, FloatingIndicator, AIEnhancementService
- **Build Success**: Verified with xcodebuild command

### Challenges Encountered
1. **Escaping Closure**: Initial attempt to initialize coordinator in init() failed
   - Solution: Moved to onAppear in body
2. **LSP Errors**: LSP doesn't understand Xcode project structure
   - Solution: Verified with actual build instead of LSP
3. **File Organization**: Wanted App/ directory but Xcode project needed updates
   - Solution: Kept files in main Pindrop/ directory for now

### Best Practices Applied
- Single responsibility: AppCoordinator only coordinates, doesn't implement logic
- Dependency injection: All dependencies passed explicitly
- Reactive programming: Settings changes propagate automatically
- Error handling: All async operations wrapped in try-catch
- Thread safety: @MainActor ensures UI updates on main thread

## Build System Implementation (2026-01-27)

### Justfile Build Automation
- Created comprehensive `justfile` with 30+ commands for common operations
- Commands organized by category: development, release, maintenance, distribution
- Default recipe shows available commands with `just --list`
- Variables defined at top for easy configuration (app_name, build_dir, etc.)

### DMG Creation Script
- `scripts/create-dmg.sh` automates DMG creation with custom layout
- Uses `create-dmg` tool (brew install create-dmg)
- Automatically detects version from Info.plist
- Creates DMG with app icon, window positioning, and Applications symlink
- Includes error checking and colored output for better UX

### Build Workflow Commands
- **Development**: `just build`, `just test`, `just dev` (clean + build + test)
- **Release**: `just build-release`, `just dmg`, `just release` (full workflow)
- **Maintenance**: `just clean`, `just lint`, `just format`
- **Distribution**: `just sign`, `just verify-signature`, `just notarize`, `just staple`
- **Version**: `just version`, `just bump-patch`, `just bump-minor`

### Export Options Template
- Created `scripts/ExportOptions.plist` for Xcode archive exports
- Configured for Developer ID distribution method
- Requires user to add their Team ID before use
- Supports code signing and notarization workflow

### Documentation
- `BUILD.md`: Complete build guide with workflows and troubleshooting
- `scripts/README.md`: Documentation for build scripts
- `.github/CONTRIBUTING.md`: Contributor guidelines with build instructions
- Updated main `README.md` with build system usage

### CI/CD Ready
- `just ci` command runs full CI workflow (clean, build, test, build-release)
- All commands designed for automation (no interactive prompts)
- Exit codes properly propagated for CI systems
- GitHub Actions example included in CONTRIBUTING.md

### Tool Dependencies
- **Required**: Xcode, xcodebuild (comes with Xcode)
- **Recommended**: just (brew install just)
- **Optional**: create-dmg (for DMG creation), swiftlint, swiftformat

### Gotchas
- DMG creation requires release build to exist first
- Notarization requires Apple Developer account and credentials setup
- Code signing requires valid Developer ID certificate
- `just` uses tabs for indentation in recipes (not spaces)
- Export options plist needs Team ID customization per developer


## Onboarding Improvements (2026-01-27)

### Issue 1: Coming Soon Models Shown in Onboarding

**Problem**: Onboarding "Choose a Model" step was showing ALL models including those marked as `availability: .comingSoon` (Parakeet, OpenAI API, Groq, ElevenLabs).

**Solution**: Filter models in `ModelSelectionStepView.swift` line 23:
```swift
// Before
ForEach(modelManager.availableModels) { model in

// After
ForEach(modelManager.availableModels.filter { $0.availability == .available }) { model in
```

**Result**: Only available WhisperKit models shown in onboarding. Coming soon models remain visible in Settings for future use.

### Issue 2: Unnecessary Model Downloads on Reinstall

**Problem**: During reinstall or interrupted onboarding, the app would re-download models that were already present on disk, wasting time and bandwidth.

**Solution**: Added check in `ModelDownloadStepView.swift` `startDownload()` function:
```swift
// Check if model is already downloaded
if modelManager.isModelDownloaded(modelName) {
    Log.model.info("Model \(modelName) already downloaded, skipping download step")
    Task.detached { @MainActor in
        try? await self.transcriptionService.loadModel(modelName: self.modelName)
    }
    try? await Task.sleep(for: .milliseconds(300))
    onComplete()
    return
}
```

**Result**: 
- Reinstalls skip download if model exists
- Interrupted onboarding resumes without re-downloading
- Better UX with faster onboarding for existing users

### Onboarding Flow Optimization

The onboarding now has two levels of download checking:
1. **Navigation level** (`OnboardingWindow.startModelDownload()`): Skips download step entirely if model exists
2. **Download step level** (`ModelDownloadStepView.startDownload()`): Double-check in case user navigates directly to download step

This redundancy ensures models are never unnecessarily downloaded.


## Complete Model Path Resolution (2026-01-27)

### The Problem Chain

A series of interconnected path issues prevented models from loading after download:

1. **Nested Directory Issue**: Models downloaded to `models/models/` instead of `models/`
2. **TranscriptionService Path Mismatch**: Service couldn't find downloaded models
3. **ModelManager Prewarm Failure**: Post-download prewarm used wrong path

### Root Cause Analysis

WhisperKit's architecture:
- `WhisperKit.download(downloadBase: URL)` downloads to: `{downloadBase}/models/argmaxinc/whisperkit-coreml/{modelName}/`
- `WhisperKitConfig(model:, downloadBase:)` looks in: `{downloadBase}/models/argmaxinc/whisperkit-coreml/{modelName}/`
- `WhisperKitConfig(modelFolder:)` looks in: `{modelFolder}/` (exact path, no additions)

### The Fixes

#### Fix 1: ModelManager Download Path (Line 257)
```swift
// Before
.appendingPathComponent("Pindrop/models", isDirectory: true)

// After
.appendingPathComponent("Pindrop", isDirectory: true)
```
**Why**: WhisperKit adds `/models/` automatically, so we only need base `Pindrop` directory.

#### Fix 2: TranscriptionService Load Path (Lines 49-52, 72)
```swift
// Added modelsBaseURL property
private var modelsBaseURL: URL {
    fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        .appendingPathComponent("Pindrop", isDirectory: true)
}

// Updated WhisperKitConfig
let config = WhisperKitConfig(
    model: modelName,
    downloadBase: modelsBaseURL,  // Added this parameter
    // ...
)
```
**Why**: TranscriptionService needs to know where models are stored.

#### Fix 3: ModelManager Prewarm Path (Line 343)
```swift
// Before
modelFolder: self.modelsBaseURL.appendingPathComponent(modelName).path,

// After
downloadBase: self.modelsBaseURL,
```
**Why**: Using `modelFolder` with manual path construction bypassed WhisperKit's path logic. Using `downloadBase` + `model` parameter lets WhisperKit find the model correctly.

### Final Path Structure

```
~/Library/Application Support/Pindrop/
└── models/                              ← WhisperKit creates this
    └── argmaxinc/                       ← WhisperKit creates this
        └── whisperkit-coreml/           ← WhisperKit creates this
            ├── openai_whisper-base/     ← Model files
            │   ├── AudioEncoder.mlmodelc
            │   ├── TextDecoder.mlmodelc
            │   └── ...
            ├── openai_whisper-tiny/
            └── ...
```

### Key Learnings

1. **Use `downloadBase` + `model` parameter**: This is the correct way to let WhisperKit manage paths
2. **Avoid `modelFolder` for downloaded models**: Only use `modelFolder` for custom/external model paths
3. **Don't duplicate WhisperKit's path logic**: Let WhisperKit handle the `models/argmaxinc/whisperkit-coreml/` structure
4. **Keep paths consistent**: Both ModelManager and TranscriptionService must use the same base path

### Pattern to Follow

```swift
// For downloading
WhisperKit.download(
    variant: modelName,
    downloadBase: modelsBaseURL  // Just the base, WhisperKit adds /models/...
)

// For loading
WhisperKitConfig(
    model: modelName,
    downloadBase: modelsBaseURL  // Same base, WhisperKit finds the model
)
```

### Anti-Pattern (What We Fixed)

```swift
// ❌ DON'T DO THIS
WhisperKitConfig(
    model: modelName,
    modelFolder: modelsBaseURL.appendingPathComponent(modelName).path  // Wrong!
)
```

This bypasses WhisperKit's path resolution and creates incorrect paths.


## Model Detection Fix (2026-01-27)

### The Problem
Downloaded models weren't being detected, causing:
- Models showing as "not downloaded" in Settings
- Transcription failing because model couldn't be loaded
- Log showing: `isModelDownloaded(openai_whisper-base): false, downloadedModels: []`

### Root Cause
`refreshDownloadedModels()` was looking in the wrong directory:
- **Looking in**: `~/Library/Application Support/Pindrop/`
- **Finding**: `["argmaxinc", "openai"]` (directory names, not model names)
- **Should look in**: `~/Library/Application Support/Pindrop/models/argmaxinc/whisperkit-coreml/`
- **Should find**: `["openai_whisper-base", "openai_whisper-tiny", ...]` (actual model names)

### The Fix
Updated `refreshDownloadedModels()` to use WhisperKit's standard directory structure:

```swift
// WhisperKit stores models in models/argmaxinc/whisperkit-coreml/
let whisperKitPath = modelsBaseURL
    .appendingPathComponent("models", isDirectory: true)
    .appendingPathComponent("argmaxinc", isDirectory: true)
    .appendingPathComponent("whisperkit-coreml", isDirectory: true)

let basePath = whisperKitPath.path
guard fileManager.fileExists(atPath: basePath) else {
    downloadedModelNames = []
    return
}

do {
    let contents = try fileManager.contentsOfDirectory(atPath: basePath)
    for folder in contents {
        // Skip hidden directories like .cache
        if folder.hasPrefix(".") { continue }
        
        let folderPath = whisperKitPath.appendingPathComponent(folder).path
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: folderPath, isDirectory: &isDirectory), isDirectory.boolValue {
            downloaded.insert(folder)
        }
    }
    Log.model.info("Found \(downloaded.count) downloaded models: \(downloaded)")
}
```

### Key Changes
1. **Correct path**: Now looks in `models/argmaxinc/whisperkit-coreml/` subdirectory
2. **Skip hidden dirs**: Filters out `.cache` and other hidden directories
3. **Better logging**: Shows count and list of found models

### Single Source of Truth
WhisperKit's directory structure is now the single source of truth:
- **Download**: `WhisperKit.download(downloadBase: modelsBaseURL)` → Creates `models/argmaxinc/whisperkit-coreml/{modelName}/`
- **Load**: `WhisperKitConfig(model:, downloadBase: modelsBaseURL)` → Looks in `models/argmaxinc/whisperkit-coreml/{modelName}/`
- **Detect**: `refreshDownloadedModels()` → Scans `models/argmaxinc/whisperkit-coreml/` for folders

All three operations now use the same path structure, ensuring consistency.


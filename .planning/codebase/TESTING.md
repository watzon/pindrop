# Testing Patterns

**Analysis Date:** 2026-03-29

## Test Framework

**Runner:**
- Swift Testing is the primary unit and integration test framework in `PindropTests/`. Evidence: `import Testing`, `@Suite`, and `@Test` in `PindropTests/AudioRecorderTests.swift`, `PindropTests/SettingsStoreTests.swift`, and `PindropTests/TranscriptionServiceTests.swift`.
- XCTest is used for UI automation in `PindropUITests/PindropUITests.swift`.
- Test plans are defined in `Pindrop.xcodeproj/xcshareddata/xctestplans/Unit.xctestplan`, `Pindrop.xcodeproj/xcshareddata/xctestplans/Integration.xctestplan`, and `Pindrop.xcodeproj/xcshareddata/xctestplans/UI.xctestplan`.

**Assertion Library:**
- Swift Testing macros: `#expect`, `#require`, and `Issue.record` in `PindropTests/AudioRecorderTests.swift`, `PindropTests/HistoryStoreTests.swift`, and `PindropTests/TranscriptionServiceTests.swift`.
- XCTest assertions in UI tests: `XCTAssertTrue` and `XCTSkip` in `PindropUITests/PindropUITests.swift`.

**Run Commands:**
```bash
just test                    # Run the Unit test plan
just test-integration        # Run the Integration test plan
just test-ui                 # Run the UI test plan
just test-all                # Run unit + integration + UI suites
just test-coverage           # Run the Unit test plan with code coverage enabled
```

Additional direct commands are encoded in `justfile`:

```bash
xcodebuild test -project Pindrop.xcodeproj -scheme Pindrop -testPlan Unit -destination 'platform=macOS'
xcodebuild test -project Pindrop.xcodeproj -scheme Pindrop -testPlan Integration -destination 'platform=macOS'
xcodebuild test -project Pindrop.xcodeproj -scheme Pindrop -testPlan UI -destination 'platform=macOS'
```

## Test File Organization

**Location:**
- Unit and integration tests live in `PindropTests/`.
- UI tests live in `PindropUITests/`.
- Test doubles and reusable mocks live in `PindropTests/TestHelpers/`.
- Shared utilities live in `PindropTests/TestSupport.swift`.

**Naming:**
- Use `*Tests.swift` for suites. Examples: `PindropTests/HistoryStoreTests.swift`, `PindropTests/AIEnhancementServiceTests.swift`.
- Mock helpers use `Mock*.swift`. Examples: `PindropTests/TestHelpers/MockPermissionProvider.swift`, `PindropTests/TestHelpers/MockAudioCaptureBackend.swift`.

**Structure:**
```text
PindropTests/
├── <Feature>Tests.swift
├── TestHelpers/
│   └── Mock<Dependency>.swift
└── TestSupport.swift

PindropUITests/
└── PindropUITests.swift
```

## Test Structure

**Suite Organization:**
```swift
@MainActor
@Suite
struct AudioRecorderTests {
    private typealias Fixture = (
        sut: AudioRecorder,
        mockPermission: MockPermissionProvider,
        mockBackend: MockAudioCaptureBackend
    )

    private func makeFixture() throws -> Fixture {
        let mockPermission = MockPermissionProvider()
        let mockBackend = MockAudioCaptureBackend()
        let sut = try AudioRecorder(permissionManager: mockPermission, captureBackend: mockBackend)
        return (sut, mockPermission, mockBackend)
    }

    @Test func startRecordingRequestsPermission() async throws {
        let fixture = try makeFixture()
        fixture.mockPermission.grantPermission = true

        try await fixture.sut.startRecording()

        #expect(fixture.mockPermission.requestPermissionCallCount == 1)
    }
}
```

Source: `PindropTests/AudioRecorderTests.swift`.

**Patterns:**
- Mark suites `@MainActor` when they exercise `@MainActor` services. Examples: `PindropTests/AudioRecorderTests.swift`, `PindropTests/SettingsStoreTests.swift`.
- Use `@Suite(.serialized)` when test isolation matters. Examples: `PindropTests/TranscriptionServiceTests.swift`, `PindropTests/HistoryStoreTests.swift`.
- Use local `makeFixture()` or `makeSUT()` helpers instead of global setup. Examples: `PindropTests/AudioRecorderTests.swift`, `PindropTests/AIEnhancementServiceTests.swift`.
- Use `defer { cleanup(...) }` when tests mutate persisted state. Example: `PindropTests/SettingsStoreTests.swift`.

## Mocking

**Framework:**
- Built-in protocol-based mocks; no third-party mocking library was detected.

**Patterns:**
```swift
final class MockPermissionProvider: PermissionProviding {
    var grantPermission: Bool = true
    var requestPermissionCallCount: Int = 0
    var delayNanoseconds: UInt64 = 0

    func requestPermission() async -> Bool {
        requestPermissionCallCount += 1
        if delayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: delayNanoseconds)
        }
        return grantPermission
    }
}
```

Source: `PindropTests/TestHelpers/MockPermissionProvider.swift`.

```swift
private func makeSUT() -> (service: AIEnhancementService, mockSession: MockURLSession) {
    let mockSession = MockURLSession()
    let service = AIEnhancementService(session: mockSession)
    return (service, mockSession)
}
```

Source: `PindropTests/AIEnhancementServiceTests.swift`.

**What to Mock:**
- Hardware and permission boundaries. Example: `MockPermissionProvider` and `MockAudioCaptureBackend` in `PindropTests/TestHelpers/`.
- Network boundaries. Example: `MockURLSession` in `PindropTests/AIEnhancementServiceTests.swift`.
- Transcription engines and diarizers when testing orchestration logic. Example: mock engine types inside `PindropTests/TranscriptionServiceTests.swift`.

**What NOT to Mock:**
- SwiftData store behavior when the test is validating persistence semantics; use in-memory or temporary backing stores instead. Example: `PindropTests/HistoryStoreTests.swift`.
- UI automation surfaces in `PindropUITests/PindropUITests.swift`; those tests launch the real app with deterministic environment fixtures.

## Fixtures and Factories

**Test Data:**
```swift
let modelContainer = try ModelContainer(
    for: TranscriptionRecord.self,
    MediaFolder.self,
    configurations: ModelConfiguration(isStoredInMemoryOnly: true)
)
let modelContext = ModelContext(modelContainer)
let historyStore = HistoryStore(modelContext: modelContext)
```

Source: `PindropTests/HistoryStoreTests.swift`.

```swift
let sampleBuffer = try #require(
    MockAudioCaptureBackend.makeSynthesizedBuffer(format: fixture.mockBackend.targetFormat),
    "Expected synthesized sample buffer"
)
```

Source: `PindropTests/AudioRecorderTests.swift`.

**Location:**
- Lightweight per-suite fixtures live inside the test file.
- Reusable task/time support lives in `PindropTests/TestSupport.swift`.
- Reusable protocol mocks live in `PindropTests/TestHelpers/`.

## Coverage

**Requirements:**
- Coverage collection is supported by `just test-coverage` in `justfile`.
- No explicit minimum coverage threshold was detected in the repository.

**View Coverage:**
```bash
just test-coverage
```

- Additional coverage reporting commands were not documented in checked-in files, so any post-processing workflow is not detectable from repository evidence.

## Test Types

**Unit Tests:**
- Default path is the `Unit` test plan in `Pindrop.xcodeproj/xcshareddata/xctestplans/Unit.xctestplan`.
- The `Unit` plan sets `PINDROP_TEST_MODE=1` and `PINDROP_RUN_INTEGRATION_TESTS=0`.
- `PermissionManagerTests` are skipped in the `Unit` plan, indicating they are treated as integration-style system tests.

**Integration Tests:**
- Gated by `PINDROP_RUN_INTEGRATION_TESTS=1` in `Pindrop.xcodeproj/xcshareddata/xctestplans/Integration.xctestplan`.
- The `Integration` plan selects `PermissionManagerTests` explicitly.
- Some suites self-gate with `@Suite(.enabled(if: ...))`. Examples: `PindropTests/PermissionManagerTests.swift`, `PindropTests/WhisperKitEngineTests.swift`, `PindropTests/ParakeetEngineTests.swift`.

**E2E Tests:**
- UI automation uses XCTest in `PindropUITests/PindropUITests.swift`.
- The `UI` test plan sets `PINDROP_TEST_MODE=1` and `PINDROP_UI_TEST_MODE=1` in `Pindrop.xcodeproj/xcshareddata/xctestplans/UI.xctestplan`.
- UI tests launch deterministic app surfaces through `Pindrop/AppTestMode.swift` and environment variables such as `PINDROP_UI_TEST_SURFACE` and `PINDROP_UI_TEST_SETTINGS_TAB`.

## Common Patterns

**Async Testing:**
```swift
Task {
    try? await service.loadModel(modelName: "tiny")
}

try await Task.sleep(nanoseconds: 100_000_000)

#expect(service.state == .loading)
```

Source: `PindropTests/TranscriptionServiceTests.swift`.

- Use `Task.sleep` and occasionally `Task.yield()` to observe in-flight state transitions. Examples: `PindropTests/TranscriptionServiceTests.swift`, `PindropTests/WhisperKitEngineTests.swift`.
- Use `async let` to verify concurrency behavior. Example: `PindropTests/AudioRecorderTests.swift` and `PindropTests/TranscriptionServiceTests.swift`.

**Error Testing:**
```swift
do {
    _ = try await fixture.sut.stopRecording()
    Issue.record("Should have thrown notRecording error")
} catch AudioRecorderError.notRecording {
} catch {
    Issue.record("Unexpected error: \(error.localizedDescription)")
}
```

Source: `PindropTests/AudioRecorderTests.swift`.

**Persistence Testing:**
- Use `ModelConfiguration(isStoredInMemoryOnly: true)` for isolated SwiftData tests. Examples: `PindropTests/HistoryStoreTests.swift`, `PindropTests/PromptPresetStoreTests.swift`.
- Use temporary on-disk stores only when validating migrations. Example: `diskBackedMigrationFromV3PreservesExistingTranscriptions()` in `PindropTests/HistoryStoreTests.swift`.

**UI Fixture Testing:**
```swift
let app = XCUIApplication()
app.launchEnvironment["PINDROP_TEST_MODE"] = "1"
app.launchEnvironment["PINDROP_UI_TEST_MODE"] = "1"
app.launchEnvironment["PINDROP_UI_TEST_SURFACE"] = "settings"
app.launch()
```

Source: `PindropUITests/PindropUITests.swift`.

## Prescriptive Guidance

- Add new unit and integration coverage in `PindropTests/<Feature>Tests.swift` using Swift Testing, not XCTest, unless the test is UI automation.
- Mark suites `@MainActor` whenever the subject type is `@MainActor`.
- Prefer local `makeFixture()` / `makeSUT()` helpers and explicit per-test setup over shared mutable suite state.
- Inject mocks through protocols for hardware, network, and engine seams; follow `AudioCaptureBackend` and `URLSessionProtocol`.
- Use in-memory SwiftData containers for store logic tests and temporary file-backed stores only for migration scenarios.
- Gate tests that touch real system permissions or installed model engines with suite-level environment checks, matching `PINDROP_RUN_INTEGRATION_TESTS` patterns in `PindropTests/PermissionManagerTests.swift` and `PindropTests/WhisperKitEngineTests.swift`.

---

*Testing analysis: 2026-03-29*

# Contributing to Pindrop

Thank you for your interest in contributing to Pindrop! Whether you're fixing a bug, adding a feature, or improving documentation, your help is welcome and appreciated.

Pindrop is a macOS menu bar dictation app that uses [WhisperKit](https://github.com/argmaxinc/WhisperKit) for fully local, on-device speech-to-text. It's built with Swift and SwiftUI, targets macOS 14+, and has a single external dependency.

## Table of Contents

- [Development Setup](#development-setup)
- [Development Workflow](#development-workflow)
- [Code Standards](#code-standards)
- [Testing Requirements](#testing-requirements)
- [Architecture Guidelines](#architecture-guidelines)
- [Pull Request Checklist](#pull-request-checklist)
- [Anti-Patterns to Avoid](#anti-patterns-to-avoid)
- [Getting Help](#getting-help)

## Development Setup

### Prerequisites

| Requirement   | Version      | Notes                                    |
| ------------- | ------------ | ---------------------------------------- |
| macOS         | 14+ (Sonoma) | Uses SwiftData, @Observable              |
| Xcode         | 15+          | With Command Line Tools                  |
| Apple Silicon | Required     | WhisperKit uses Core ML on Apple Silicon |
| `just`        | Any          | Command runner: `brew install just`      |

Optional tools for code quality:

```bash
brew install swiftlint swiftformat
```

### Clone and Build

1. **Fork the repository** on GitHub, then clone your fork:

   ```bash
   git clone https://github.com/YOUR_USERNAME/pindrop.git
   cd pindrop
   ```

2. **Build the project:**

   ```bash
   just build
   ```

3. **Run the test suite** to confirm everything works:

   ```bash
   just test
   ```

4. **Open in Xcode** (if you prefer the IDE):

   ```bash
   just xcode
   # Or: open Pindrop.xcodeproj
   ```

For the full build system reference (release builds, DMGs, code signing, notarization), see [BUILD.md](BUILD.md).

## Development Workflow

### Branch Naming

Use descriptive, prefixed branch names:

```
feature/add-volume-indicator
fix/hotkey-not-registering
docs/update-readme
refactor/extract-audio-pipeline
```

### Commit Messages

Write clear, imperative commit messages. Prefix with a type when helpful:

```
feat: add floating volume indicator during recording
fix: resolve hotkey conflict detection on Sequoia
docs: update build instructions for Xcode 16
refactor: extract audio format conversion to utility
test: add tests for push-to-talk key-up handling
```

### Pull Request Process

1. **Create a branch** from `main`:

   ```bash
   git checkout -b feature/your-feature
   ```

2. **Make your changes**, following the [code standards](#code-standards) below.

3. **Run the full dev cycle** before pushing:

   ```bash
   just dev    # clean + build + test
   ```

4. **Push and open a PR** against `main`:

   ```bash
   git push origin feature/your-feature
   ```

5. **In the PR description**, include:
   - What changed and why
   - How to test the changes
   - Screenshots for any UI changes
   - Related issue numbers

## Code Standards

All conventions here are drawn from the project's [AGENTS.md](AGENTS.md), which is the authoritative reference.

### File Headers

Every Swift file starts with:

```swift
//
//  FileName.swift
//  Pindrop
//
//  Created on YYYY-MM-DD.
//
```

### Import Order

Group imports in this order, separated by blank lines if you prefer:

```swift
import Foundation              // 1. Foundation always first
import SwiftUI                 // 2. Apple frameworks
import AVFoundation
import AppKit
import WhisperKit              // 3. External packages
import os.log                  // 4. Logging last
```

### Naming Conventions

| Element               | Convention     | Example                               |
| --------------------- | -------------- | ------------------------------------- |
| Types                 | PascalCase     | `AudioRecorder`, `TranscriptionError` |
| Variables / Functions | camelCase      | `isRecording`, `startRecording()`     |
| Local constants       | camelCase      | `let maxRetries = 3`                  |
| Static constants      | PascalCase     | `static let DefaultTimeout`           |
| Test files            | `*Tests.swift` | `AudioRecorderTests.swift`            |
| System Under Test     | `sut`          | `var sut: AudioRecorder!`             |

### Error Handling

Each service defines a nested error enum conforming to `Error` and `LocalizedError`:

```swift
enum AudioRecorderError: Error, LocalizedError {
    case permissionDenied
    case engineStartFailed(String)

    var errorDescription: String? {
        switch self {
        case .permissionDenied: return "Microphone permission denied"
        case .engineStartFailed(let msg): return "Audio engine failed: \(msg)"
        }
    }
}
```

**Never** use force unwrap (`!`) or force cast (`as!`). Use `guard let` or `if let`.

### Service Pattern

Services are `@MainActor`, `final` classes with async methods for I/O:

```swift
@MainActor
final class MyService {
    private(set) var isActive = false  // @Observable if reactive state needed

    func doWork() async throws {
        // Implementation
    }
}
```

- Use `@Observable` (not `ObservableObject`) for reactive state.
- Exception: `HotkeyManager` is not `@MainActor` (Carbon Events thread requirement).

### Logging

Use the project's `Log` enum with the appropriate category:

```swift
Log.audio.info("Starting recording")
Log.transcription.error("Transcription failed: \(error)")
```

Available categories: `audio`, `transcription`, `model`, `output`, `hotkey`, `app`, `ui`.

### Secrets

All API keys and secrets go through the Keychain via `SettingsStore.saveAPIKey()`. **Never** store secrets in `UserDefaults` or `@AppStorage`.

## Testing Requirements

### Running Tests

```bash
just test                 # Unit test suite (default)
just test-integration     # Integration suite only
just test-all             # Both suites

# Run a specific test class:
xcodebuild test -scheme Pindrop -destination 'platform=macOS' \
    -only-testing:PindropTests/AudioRecorderTests

# Run a single test:
xcodebuild test -scheme Pindrop -destination 'platform=macOS' \
    -only-testing:PindropTests/AudioRecorderTests/testStartRecordingRequestsPermission
```

### Test Isolation

Tests are isolated from user settings. The test plans set `PINDROP_TEST_MODE=1`, which causes `SettingsStore` to use test-only `@AppStorage` and Keychain backends. You don't need to do anything special; just make sure new settings-dependent code respects this flag.

### Writing Tests for New Features

1. **Add to the existing `*Tests.swift`** file for the service you changed, or create a new one following the same structure.

2. **Use the standard pattern:**

   ```swift
   @MainActor
   final class MyServiceTests: XCTestCase {
       var sut: MyService!

       override func setUpWithError() throws {
           sut = MyService()
       }

       func testFeature() async throws {
           let result = try await sut.doWork()
           XCTAssertEqual(result, expected)
       }
   }
   ```

3. **For hardware-dependent code** (microphone, permissions), use protocol-based dependency injection with mocks. See `TestHelpers/MockPermissionProvider.swift` and `TestHelpers/MockAudioCaptureBackend.swift` for examples.

4. **For SwiftData tests**, use in-memory containers:

   ```swift
   let config = ModelConfiguration(isStoredInMemoryOnly: true)
   modelContainer = try ModelContainer(for: schema, configurations: [config])
   ```

5. **For network-dependent code**, use `MockURLSession` (see `AIEnhancementServiceTests.swift`).

6. **Tests must pass on CI** (macOS runners with no microphone, no permission dialogs). Never depend on real hardware.

### Test Conventions

| Rule                      | Details                                                                |
| ------------------------- | ---------------------------------------------------------------------- |
| Variable naming           | Always use `sut` for the System Under Test                             |
| `@MainActor`              | Required on tests for `@MainActor` services                            |
| Cleanup                   | Clean up Keychain/file state in `setUp`; nil assignments in `tearDown` |
| Timeouts                  | 1-5s for unit tests, up to 10s for integration tests                   |
| No third-party frameworks | XCTest is sufficient                                                   |

## Architecture Guidelines

### Project Structure

```
Pindrop/
├── PindropApp.swift        # @main entry point + AppDelegate
├── AppCoordinator.swift    # Central service wiring + lifecycle
├── Services/               # 9 service modules (all non-UI logic)
├── UI/                     # StatusBar, Settings, History, FloatingIndicator
├── Models/                 # TranscriptionRecord (SwiftData)
└── Utils/                  # Log (os.log wrapper), AlertManager
```

### Service-Oriented Architecture

All business logic lives in `Services/`. Each service is a single-responsibility class. `AppCoordinator` wires them together and manages lifecycle. The recording flow is:

```
AppCoordinator.handleToggleRecording()
    → AudioRecorder (capture audio)
    → TranscriptionService (run WhisperKit)
    → OutputManager (clipboard / direct insert)
```

### Adding New Views

1. Create your view file in the appropriate `UI/` subdirectory.
2. Use existing design tokens: `AppTheme.Spacing.*`, `AppColors`, `AppTypography`.
3. Reuse shared components: `SettingsCard`, `IconView`.
4. **Add the file to the Xcode project** — update `PBXBuildFile`, `PBXFileReference`, `PBXGroup`, and `PBXSourcesBuildPhase` in the `.xcodeproj`.

### Adding New Services

1. Create the service file in `Services/`.
2. Follow the `@MainActor final class` pattern (unless threading constraints prevent it).
3. Define a nested error enum.
4. Wire it through `AppCoordinator`.
5. Add tests in `PindropTests/` using the existing patterns.
6. If the service depends on hardware, define a protocol and provide a mock in `TestHelpers/`.

## Pull Request Checklist

Before submitting, verify:

- [ ] Code builds without errors or warnings (`just build`)
- [ ] All tests pass (`just test`)
- [ ] Code is linted and formatted (`just lint`, `just format` — if tools are installed)
- [ ] New features have tests
- [ ] No force unwraps (`!`) or force casts (`as!`)
- [ ] No test-only methods added to production code
- [ ] Secrets use Keychain, not UserDefaults
- [ ] Permissions are requested on first use, not at launch
- [ ] Follows existing patterns (services, logging, error handling)
- [ ] Documentation updated if applicable (`README.md` for user-facing, `AGENTS.md` for architecture)
- [ ] Commit messages are clear and descriptive

## Anti-Patterns to Avoid

These are project-specific guardrails. Violating them will block your PR.

| Don't Do This                      | Why                                | Do This Instead                             |
| ---------------------------------- | ---------------------------------- | ------------------------------------------- |
| Store API keys in `UserDefaults`   | Security                           | Use `SettingsStore.saveAPIKey()` (Keychain) |
| Auto-request permissions on launch | Bad UX                             | Request on first use only                   |
| Use Core Data directly             | SwiftData only                     | See `HistoryStore`                          |
| Force unwrap (`!`) or `as!`        | Type safety                        | Use `guard let` or `if let`                 |
| Override system keyboard shortcuts | User confusion                     | Warn if conflict detected                   |
| Require Accessibility permission   | Breaks basic functionality         | Clipboard fallback must always work         |
| Edit history transcriptions in UI  | History is read-only by design     | —                                           |
| Add batch file transcription       | Out of scope (live dictation only) | —                                           |
| Add multi-language support         | Out of scope for v1 (English only) | —                                           |
| Add telemetry without consent      | Privacy                            | —                                           |
| Target Intel / pre-Sonoma          | Not supported                      | macOS 14+ Apple Silicon only                |

## Getting Help

### Questions

- **Architecture questions**: Read [AGENTS.md](AGENTS.md) first — it covers structure, conventions, and where to find things.
- **Build issues**: See [BUILD.md](BUILD.md) for the full build system reference.
- **Still stuck?** Open a [GitHub Discussion](https://github.com/watzon/pindrop/discussions) or ask in an issue.

### Reporting Bugs

Open a [GitHub Issue](https://github.com/watzon/pindrop/issues/new) with:

- macOS version and Mac model
- Steps to reproduce
- Expected vs. actual behavior
- Console logs if available (use the "Copy System Info" button in Settings)

### Feature Requests

Open a [GitHub Issue](https://github.com/watzon/pindrop/issues/new) describing:

- The problem you're trying to solve
- Your proposed solution
- Any alternatives you've considered

Check the [anti-patterns](#anti-patterns-to-avoid) and scope constraints above before proposing — some features are intentionally excluded from v1.

## License

By contributing to Pindrop, you agree that your contributions will be licensed under the [MIT License](LICENSE).

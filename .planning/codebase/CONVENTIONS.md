# Coding Conventions

**Analysis Date:** 2026-03-29

## Naming Patterns

**Files:**
- Use `PascalCase.swift` for app, service, model, and test files. Examples: `Pindrop/Services/AudioRecorder.swift`, `Pindrop/UI/Main/MainWindow.swift`, `PindropTests/AudioRecorderTests.swift`.
- Use `*Tests.swift` for test files in `PindropTests/` and `PindropUITests/`. Examples: `PindropTests/SettingsStoreTests.swift`, `PindropUITests/PindropUITests.swift`.

**Functions:**
- Use `lowerCamelCase` for methods and helpers. Examples: `startRecording()` in `Pindrop/Services/AudioRecorder.swift`, `makeFixture()` in `PindropTests/AudioRecorderTests.swift`, `configuredApplication(...)` in `PindropUITests/PindropUITests.swift`.
- Prefer verb-led names for actions and `make...` helpers for fixture construction. Examples: `makeSUT()` in `PindropTests/AIEnhancementServiceTests.swift`, `makeSettingsStore()` in `PindropTests/SettingsStoreTests.swift`.

**Variables:**
- Use `lowerCamelCase` for stored properties and locals. Examples: `selectedLanguage` in `Pindrop/Services/SettingsStore.swift`, `mockPermission` in `PindropTests/AudioRecorderTests.swift`.
- Use descriptive tuple labels in tests instead of positional returns. Example `Fixture` in `PindropTests/AudioRecorderTests.swift` exposes `sut`, `mockPermission`, and `mockBackend`.

**Types:**
- Use `PascalCase` for structs, classes, enums, and protocols. Examples: `SettingsStore`, `AppTestMode`, `AudioCaptureBackend`, `HistoryStoreTests`.
- Use nested error enums and state/helper structs inside the owning type when the concept is local. Examples: `AudioRecorderError` in `Pindrop/Services/AudioRecorder.swift`, `SettingsStore.SettingsError` in `Pindrop/Services/SettingsStore.swift`, `AppCoordinator.EventTapRecoveryDecision` in `Pindrop/AppCoordinator.swift`.

## Code Style

**Formatting:**
- No checked-in formatter config was detected at repository root; `.swiftformat` and `.swiftformat` variants were not found.
- `just format` runs `swiftformat .` if the tool is installed, so format with SwiftFormat when available. Source: `justfile`.
- Indentation is predominantly 4 spaces in files such as `Pindrop/Services/AudioRecorder.swift` and `Pindrop/AppCoordinator.swift`.
- File headers usually follow the pattern shown in `Pindrop/Services/AudioRecorder.swift` and `Pindrop/Services/SettingsStore.swift`:

```swift
//
//  AudioRecorder.swift
//  Pindrop
//
//  Created on 2026-01-25.
//
```

- Some UI files keep the same header shell but replace the creation line with a descriptive comment, so preserve the local file style when editing. Example: `Pindrop/UI/Main/MainWindow.swift`.

**Linting:**
- No checked-in SwiftLint config was detected at repository root; `.swiftlint.yml` was not found.
- `just lint` runs `swiftlint` only if installed locally. Source: `justfile`.
- Because no repo config is present, project-specific rule overrides are not detectable from the repository alone.

## Import Organization

**Order:**
1. Apple/system frameworks first, usually with `Foundation` near the top. Examples: `Pindrop/Services/AudioRecorder.swift`, `Pindrop/Services/HistoryStore.swift`.
2. Platform/framework modules next. Examples: `AVFoundation`, `SwiftData`, `AppKit`, `SwiftUI`.
3. Conditional shared-module imports behind `#if canImport(...)` when needed. Example: `Pindrop/UI/Main/MainWindow.swift`, `PindropTests/SettingsStoreTests.swift`.
4. `@testable import Pindrop` after framework imports in unit tests. Example: `PindropTests/AudioRecorderTests.swift`.

**Path Aliases:**
- Not applicable in current Swift source; import statements use module names, not alias paths.

## Error Handling

**Patterns:**
- Define domain errors as `Error, LocalizedError` with user-facing `errorDescription`. Examples: `AudioRecorderError` in `Pindrop/Services/AudioRecorder.swift`, `HistoryStore.HistoryStoreError` in `Pindrop/Services/HistoryStore.swift`.
- Wrap lower-level failures into typed domain errors instead of leaking raw errors. Example: `HistoryStore.save(...)` converts persistence failures into `.saveFailed(...)` in `Pindrop/Services/HistoryStore.swift`.
- In tests, use explicit typed `catch` branches and record unexpected cases with `Issue.record(...)`. Example: `PindropTests/AudioRecorderTests.swift`, `PindropTests/TranscriptionServiceTests.swift`.

## Logging

**Framework:** `os.log` via the `Log` facade in `Pindrop/Utils/Logger.swift`.

**Patterns:**
- Use category-based loggers such as `Log.audio`, `Log.transcription`, `Log.app`, and `Log.ui`. Source: `Pindrop/Utils/Logger.swift`.
- Prefer domain-specific logging at service boundaries. Example: `Pindrop/Services/AudioRecorder.swift` logs engine lifecycle and converter failures with `Log.audio`.
- Test and preview runs suppress on-disk log persistence via environment checks in `Pindrop/Utils/Logger.swift`.

## Comments

**When to Comment:**
- Use `// MARK:` to split large files into functional sections. This is heavily used in `Pindrop/AppCoordinator.swift`, `Pindrop/UI/Main/MainWindow.swift`, and `Pindrop/UI/Settings/PresetManagementSheet.swift`.
- Use short inline comments sparingly for local rationale. Example: the force-unwrap justification in `PindropTests/TestHelpers/MockAudioCaptureBackend.swift`.

**JSDoc/TSDoc:**
- Swift doc comments (`///`) are used for protocols, helpers, and non-obvious behavior, not for every member. Examples: `AudioCaptureBackend` in `Pindrop/Services/AudioRecorder.swift`, `TranscriptionEngine` in `Pindrop/Services/Transcription/TranscriptionEngine.swift`, screen helper docs in `Pindrop/UI/FloatingIndicatorShared.swift`.

## Function Design

**Size:**
- Service and coordinator files can be large, but they are segmented with `// MARK:` blocks. Examples: `Pindrop/AppCoordinator.swift`, `Pindrop/Services/SettingsStore.swift`.
- Tests favor many small `@Test` functions over shared setup-heavy suites. Example: `PindropTests/AudioRecorderTests.swift`.

**Parameters:**
- Prefer initializer injection for dependencies and seams. Examples: `AudioRecorder(permissionManager:captureBackend:)` exercised in `PindropTests/AudioRecorderTests.swift`, `AIEnhancementService(session:)` exercised in `PindropTests/AIEnhancementServiceTests.swift`.
- Prefer labeled parameters for clarity on service APIs. Examples: `HistoryStore.save(text:duration:modelUsed:...)`, `AIEnhancementService.enhance(text:apiEndpoint:apiKey:)`.

**Return Values:**
- Use typed returns instead of shared mutable out-parameters. Examples: `AudioRecorder.stopRecording()` returns `Data`, `HistoryStore.save(...)` returns `TranscriptionRecord` in `Pindrop/Services/HistoryStore.swift`.
- Use tuple-return helpers in tests for compact fixture assembly. Examples: `makeSUT()` in `PindropTests/AIEnhancementServiceTests.swift`, `makeFixture()` in `PindropTests/AudioRecorderTests.swift`.

## Module Design

**Exports:**
- Concrete implementations are commonly `final class` and actor-isolated with `@MainActor` when they own UI-facing state. Examples: `SettingsStore` in `Pindrop/Services/SettingsStore.swift`, `HistoryStore` in `Pindrop/Services/HistoryStore.swift`, `AIEnhancementService` in `Pindrop/Services/AIEnhancementService.swift`.
- Protocol seams are used around hardware, networking, and engine boundaries. Examples: `AudioCaptureBackend` in `Pindrop/Services/AudioRecorder.swift`, `URLSessionProtocol` in `Pindrop/Services/AIEnhancementService.swift`.

**Barrel Files:**
- Not detected. The codebase imports concrete files through the `Pindrop` module instead of using barrel-style export files.

## Prescriptive Guidance

- Match the local file header style before editing a file. Prefer the `Created on YYYY-MM-DD` header when adding new source files, because that is the dominant pattern in `Pindrop/Services/` and `PindropTests/`.
- Keep concrete service types `final` unless subclassing is required.
- Keep stateful app services on `@MainActor` unless system APIs require another model. `Pindrop/AppCoordinator.swift` and `Pindrop/Services/SettingsStore.swift` are the reference pattern.
- Add dependency seams as protocols when code touches hardware, network, persistence, or external engines. Follow `AudioCaptureBackend` and `URLSessionProtocol`.
- Add `LocalizedError.errorDescription` for new domain errors.
- Use `// MARK:` sections in large files instead of long comment prose.

---

*Convention analysis: 2026-03-29*

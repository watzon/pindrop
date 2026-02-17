# Repository Guidelines

Last updated: 2026-02-16

## Project Snapshot

- App: `Pindrop` (menu bar macOS app, `LSUIElement` behavior)
- Stack: Swift 5.9+, SwiftUI, SwiftData, XCTest
- Platform target: macOS 14+
- Main dependency path: `Pindrop.xcodeproj` + SwiftPM
- Entry points: `Pindrop/PindropApp.swift`, `Pindrop/AppCoordinator.swift`

## Source Layout

- App code: `Pindrop/`
- Services: `Pindrop/Services/`
- UI: `Pindrop/UI/`
- Persistence models: `Pindrop/Models/`
- Utilities/logging: `Pindrop/Utils/`
- Tests: `PindropTests/`
- Test doubles: `PindropTests/TestHelpers/`
- Build automation: `justfile`, `scripts/`, `.github/workflows/`

## Required Local Tooling

- Xcode with command-line tools (`xcodebuild`)
- `just` for all routine workflows: `brew install just`
- Optional: `swiftlint`, `swiftformat`, `create-dmg`

## Build and Run Commands

Prefer `just` recipes over ad-hoc shell commands.

```bash
just build                 # Debug build
just build-release         # Release build
just test                  # Unit test plan
just test-integration      # Integration test plan (opt-in)
just test-all              # Unit + integration
just test-coverage         # Unit tests with coverage
just dev                   # clean + build + test
just ci                    # clean + build + test + build-release
just run                   # open Xcode project
just xcode                 # open Xcode project
```

Direct focused test commands:

```bash
xcodebuild test -project Pindrop.xcodeproj -scheme Pindrop -testPlan Unit -destination 'platform=macOS'
xcodebuild test -project Pindrop.xcodeproj -scheme Pindrop -destination 'platform=macOS' -only-testing:PindropTests/AudioRecorderTests
xcodebuild test -project Pindrop.xcodeproj -scheme Pindrop -destination 'platform=macOS' -only-testing:PindropTests/AudioRecorderTests/testStartRecordingRequestsPermission
```

## Coding Conventions

- Follow existing file header style (`Created on YYYY-MM-DD`)
- Use `final class` for services and most concrete implementations
- Actor isolation pattern: services are usually `@MainActor`
- Known exception: hotkey internals with Carbon/event constraints
- Use `@Observable` for reactive services where compatible
- `SettingsStore` intentionally uses `ObservableObject` + `@AppStorage`
- Keep import groups consistent with existing files

## Service Patterns

- Dependency injection via initializer arguments (avoid hidden globals)
- Protocol abstractions for hardware/system boundaries
- Example protocol seam: `AudioCaptureBackend` in `Pindrop/Services/AudioRecorder.swift`
- Keep async boundaries explicit (`async` / `async throws`)
- Avoid fire-and-forget tasks unless they are UI/lifecycle orchestration

## Error Handling

- Define domain errors as `enum ...: Error, LocalizedError`
- Keep user-facing messaging in `errorDescription`
- Catch at boundaries, log with context, then rethrow typed errors when possible
- Do not swallow errors with empty catch blocks

## Logging

- Use `Log` categories from `Pindrop/Utils/Logger.swift`
- Categories include: `audio`, `transcription`, `model`, `output`, `hotkey`, `app`, `ui`, `update`, `aiEnhancement`, `context`
- Log intent and failure context; avoid noisy per-frame spam

## SwiftData and Persistence

- Models use SwiftData macros (`@Model`, `@Attribute(.unique)`)
- Keep schema-related changes coordinated with schema files under `Pindrop/Models/`
- Use in-memory model containers for unit tests when testing store logic

## Testing Conventions

- Test files: `*Tests.swift`
- Typical test class shape: `@MainActor final class XTests: XCTestCase`
- Standard naming: `sut` for system under test
- Use `setUp`/`tearDown` to build and nil shared state
- Use protocol mocks from `PindropTests/TestHelpers/` for hardware/system APIs
- Integration tests are gated (see `PINDROP_RUN_INTEGRATION_TESTS` pattern)
- Test mode signal exists in runtime (`PINDROP_TEST_MODE`)

## Change Scope Rules

- Keep fixes minimal and local; do not refactor unrelated code in bugfixes
- Preserve architecture boundaries (UI -> coordinator -> services -> models)
- Do not introduce alternate command systems when `just` recipes already exist
- Prefer extending existing services over adding parallel duplicate services

## Release and Distribution

- Local release helpers: `just build-release`, `just dmg`, `just dmg-self-signed`
- Version/tag flow automation exists in `just release <X.Y.Z>`
- CI workflows under `.github/workflows/` drive build/release pipeline
- Sparkle appcast generation is scripted via `just appcast <dmg-path>`

## Quick PR Checklist

- Build passes: `just build`
- Relevant tests pass: `just test` (and integration when touched)
- No new warnings from your change scope
- Docs/comments updated only when behavior changes
- Keep diffs focused; avoid opportunistic formatting-only churn

## Important Paths

- App lifecycle: `Pindrop/PindropApp.swift`
- Service composition: `Pindrop/AppCoordinator.swift`
- Settings and keychain: `Pindrop/Services/SettingsStore.swift`
- Audio capture core: `Pindrop/Services/AudioRecorder.swift`
- Transcription orchestration: `Pindrop/Services/TranscriptionService.swift`
- Logging facade: `Pindrop/Utils/Logger.swift`
- Build recipes: `justfile`
- Contributor docs: `README.md`, `CONTRIBUTING.md`, `BUILD.md`

## Notes for Agents

- Use `just` commands in examples unless a direct `xcodebuild` form is required
- When adding tests, mirror structure from the nearest existing test file first
- When touching settings, verify both app behavior and test-mode behavior
- When touching model or schema code, verify migration and read/write behavior

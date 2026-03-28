# Repository Guidelines

Last updated: 2026-03-28

## Project Snapshot

- App: `Pindrop` (menu bar macOS app, `LSUIElement` behavior)
- Stack: Swift 5.9+, SwiftUI, SwiftData, Swift Testing, XCTest UI tests, Kotlin Multiplatform shared modules
- Platform target: macOS 14+ for the shipped app; shared KMP code is intended to support future Windows/Linux targets
- Main dependency path: `Pindrop.xcodeproj`, SwiftPM, and the Gradle-based KMP workspace under `shared/`
- Entry points: `Pindrop/PindropApp.swift`, `Pindrop/AppCoordinator.swift`

## Source Layout

- App code: `Pindrop/`
- Services: `Pindrop/Services/`
- UI: `Pindrop/UI/`
- Persistence models: `Pindrop/Models/`
- Utilities/logging: `Pindrop/Utils/`
- Tests: `PindropTests/`
- Test doubles: `PindropTests/TestHelpers/`
- Shared KMP workspace: `shared/`
- Build automation: `justfile`, `scripts/`, `.github/workflows/`

## Required Local Tooling

- Xcode with command-line tools (`xcodebuild`)
- `just` for all routine workflows: `brew install just`
- JDK 21+ for the Gradle/Kotlin toolchain used by `shared/`
- Prefer the checked-in Gradle wrapper at `shared/gradlew` over a globally installed `gradle`
- Optional: `swiftlint`, `swiftformat`, `create-dmg`
- Apple Developer signing configured in Xcode for signed local/release builds; CI recipes use explicit unsigned overrides

## Build and Run Commands

Prefer `just` recipes over ad-hoc shell commands.

```bash
just build                 # Debug build
just build-release         # Release build
just export-app            # Developer ID export for distribution
just dmg                   # Signed DMG for distribution
just test                  # Unit test plan
just shared-test           # Kotlin shared-module tests
just shared-xcframework    # Build embedded KMP XCFrameworks
just test-integration      # Integration test plan (opt-in)
just test-ui               # UI test plan
just test-all              # Unit + integration + UI
just test-coverage         # Unit tests with coverage
just dev                   # clean + build + test
just ci                    # clean + unsigned build + unsigned test + unsigned release build
just run                   # open Xcode project
just xcode                 # open Xcode project
```

Direct focused test commands:

```bash
xcodebuild test -project Pindrop.xcodeproj -scheme Pindrop -testPlan Unit -destination 'platform=macOS'
xcodebuild test -project Pindrop.xcodeproj -scheme Pindrop -testPlan UI -destination 'platform=macOS'
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

## Localization

- **String Catalogs**: `Pindrop/Localization/Localizable.xcstrings` (in-app copy) and `Pindrop/Localization/InfoPlist.xcstrings` (privacy strings, bundle display name). Both are in the app target’s **Copy Bundle Resources**.
- **Runtime API**: `localized("English key", locale: locale)` in `Pindrop/AppLocalization.swift` resolves against `Bundle` for `SettingsStore.selectedAppLanguage` (see `MainWindow`, `SettingsWindow`, menu bar). The catalog **key is usually the English default string**; if you add UI text in Swift but **omit** the key from `Localizable.xcstrings`, every locale falls back to that English key and nothing appears translated.
- **New user-facing strings**: Add an entry to `Localizable.xcstrings` with **en** plus every shipped locale (**es**, **fr**, **de**, **zh-Hans**, **ja**, …). Xcode can export/import; hand-editing JSON is fine if you mirror an existing entry’s shape (`localizations` → `stringUnit` → `state` / `value`).
- **New language (locale)**: Add the locale to **Project → Info → Localizations** (or `knownRegions` in `Pindrop.xcodeproj/project.pbxproj`), add `localizations` blocks for that code in both `.xcstrings` files, and if it should appear in **Settings → General → Language**, set `AppLanguage.isSelectable` in `SettingsStore.swift` and ensure `AppLanguage` has a matching `locale` identifier.
- **Single “Language” setting**: The General settings picker drives **both** UI locale (`\.locale`) and transcription language (`TranscriptionOptions` / Whisper). Copy in that section should stay accurate when you change behavior.
- **AI enhancement prompts**: `AIEnhancementSettingsView` localizes default prompts for display; if the user saves without editing, the **localized** prompt text can be persisted and sent to the API—expect models to follow non-English system prompts, or keep defaults in English if you change that flow.
- **Machine translation helper** (optional, not CI): `scripts/translate_xcstrings.py` fills a target locale from English using `deep-translator` and preserves `%@`, `%lld`, `${transcription}`, etc. Examples: `just translate-xcstrings ja`, `just translate-xcstrings-missing ja`, `just translate-infoplist ja`. Always **review** MT output before release.

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
- Unit tests use Swift Testing with `@Suite` / `@Test`; macOS UI coverage stays in `PindropUITests/` with XCTest UI APIs
- Standard naming: `sut` for system under test
- Prefer local fixture builders over shared `setUp` / `tearDown`; use `PindropTests/TestSupport.swift` for reusable test helpers
- Use protocol mocks from `PindropTests/TestHelpers/` for hardware/system APIs
- Integration tests are gated (see `PINDROP_RUN_INTEGRATION_TESTS` pattern)
- Test mode signal exists in runtime (`PINDROP_TEST_MODE`)
- UI tests run through `PINDROP_UI_TEST_MODE` and deterministic fixture surfaces in `Pindrop/AppTestMode.swift`

## Change Scope Rules

- Keep fixes minimal and local; do not refactor unrelated code in bugfixes
- Preserve architecture boundaries (UI -> coordinator -> services -> models)
- Do not introduce alternate command systems when `just` recipes already exist
- Prefer extending existing services over adding parallel duplicate services

## Release and Distribution

- Local release helpers: `just build-release`, `just export-app`, `just dmg`, `just dmg-self-signed` (fallback only)
- macOS release builds embed the XCFrameworks produced from `shared/`; KMP is a build input, not a separate end-user artifact
- Manual release flow is `just release <X.Y.Z>` (local execution, not CI-driven)
  1. Create/edit contextual release notes (`release-notes/vX.Y.Z.md`)
  2. Run tests
  3. Build signed release DMG (`just dmg` exports a Developer ID-signed app first)
  4. Generate `appcast.xml`
  5. Create + push tag
  6. Create GitHub release via `gh` with notes + DMG + `appcast.xml`
- CI workflows under `.github/workflows/` are for build/test validation; release publishing is manual
- Sparkle appcast generation is scripted via `just appcast <dmg-path>`
- Keep `just build-self-signed` / `just dmg-self-signed` only as a fallback when Apple signing is unavailable

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
- Localization: `Pindrop/AppLocalization.swift`, `Pindrop/Localization/Localizable.xcstrings`, `Pindrop/Localization/InfoPlist.xcstrings`
- MT helper (optional): `scripts/translate_xcstrings.py`
- Build recipes: `justfile`
- Contributor docs: `README.md`, `CONTRIBUTING.md`, `BUILD.md`

## Notes for Agents

- Use `just` commands in examples unless a direct `xcodebuild` form is required
- When adding tests, mirror structure from the nearest existing test file first
- Prefer Swift Testing assertions (`#expect`, `#require`, `Issue.record`) for unit tests; keep XCTest only for UI automation
- When touching settings, verify both app behavior and test-mode behavior
- When touching model or schema code, verify migration and read/write behavior
- When adding or changing user-visible strings, update **both** Swift `localized(...)` keys and `Localizable.xcstrings` (and `InfoPlist.xcstrings` for permission / bundle strings) for all shipped locales

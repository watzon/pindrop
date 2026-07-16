# Repository Guidelines

Last updated: 2026-03-24

## Project Snapshot

- App: `Pindrop` (menu bar macOS app, `LSUIElement` behavior)
- Stack: Swift 5.9+, SwiftUI, SwiftData, Swift Testing, XCTest UI tests
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
- Apple Developer signing configured in Xcode for signed local/release builds; CI recipes use explicit unsigned overrides

## Build and Run Commands

Prefer `just` recipes over ad-hoc shell commands.

```bash
just build                 # Debug build (ALWAYS use this when testing builds)
just build-release         # Release build
just export-app            # Developer ID export for distribution
just dmg                   # Signed DMG for distribution
just test                  # Unit test plan
just test-integration      # Integration test plan (opt-in)
just test-ui               # UI test plan
just test-all              # Unit + integration + UI
just test-coverage         # Unit tests with coverage
just dev                   # clean + build + test
just ci                    # clean + unsigned build + unsigned test + unsigned release build
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

- **String Catalogs**: `Pindrop/Localization/Localizable.xcstrings` (in-app copy) and `Pindrop/Localization/InfoPlist.xcstrings` (privacy strings, bundle display name). Both are in the app target’s **Copy Bundle Resources**. The top-level `Localization/` tree is the source of truth for the YAML-first pipeline.
- **Runtime API**: `localized("English key", locale: locale)` in `Pindrop/AppLocalization.swift` now resolves through generated stable-key metadata before falling back to `Bundle`; `SettingsStore.selectedAppLocale` drives UI locale and `SettingsStore.selectedAppLanguage` drives dictation/transcription language.
- **New user-facing strings**: Add an entry to the YAML source tree under `Localization/`, then run `just l10n-sync` so the catalogs and generated Swift stay in sync.
- **New language (locale)**: Add the locale with `just l10n-add-locale <locale>` (or edit `Localization/locales.yml`), then populate the relevant `Localization/app/*.yml` and `Localization/infoplist/*.yml` files before syncing.
- **Interface vs dictation language**: The General settings UI now separates interface language from dictation language. Keep `AppLocale`-driven UI locale changes away from `AppLanguage`/transcription behavior.
- **AI enhancement prompts**: `AIEnhancementSettingsView` localizes default prompts for display; if the user saves without editing, the **localized** prompt text can be persisted and sent to the API—expect models to follow non-English system prompts, or keep defaults in English if you change that flow.
- **Localization tooling**: Use `just l10n-import-current`, `just l10n-sync`, and `just l10n-lint`. The old `scripts/translate_xcstrings.py` helper is obsolete.

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
- Manual release flow is `just release <X.Y.Z>` (local execution, not CI-driven)
  1. Create/edit contextual release notes (`release-notes/vX.Y.Z.md`)
  2. For feature releases (X.Y.0): update the in-app What's New announcement — `AnnouncementCatalog` in `Pindrop/Models/Announcement.swift` (new id + `Pindrop X.Y.0 · <Month Year>` header + feature items) plus the `whatsnew:` strings in `Localization/app/*.yml` for all locales, then `just l10n-sync` (`just release` enforces this)
  3. Run tests
  4. Build signed release DMG (`just dmg` exports a Developer ID-signed app first)
  5. Generate `appcast.xml`
  6. Create + push tag
  7. Create GitHub release via `gh` with notes + DMG + `appcast.xml`
  8. Sync release notes to the website changelog: `just sync-website-changelog <X.Y.Z>` runs automatically at the end of `just release` (best-effort). It copies `release-notes/vX.Y.Z.md` with version/date frontmatter into `../pindrop-website/src/content/changelog/` (override location with `PINDROP_WEBSITE_DIR`), commits that one file in the website repo, and pushes so the site redeploys. If it fails, run it manually after the release.
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
- Localization: `Pindrop/AppLocalization.swift`, `Pindrop/Generated/LocalizationMetadata.swift`, `Pindrop/Generated/L10nKeys.swift`, `Pindrop/Localization/Localizable.xcstrings`, `Pindrop/Localization/InfoPlist.xcstrings`, `Localization/`
- Localization tooling: `scripts/localization.py`, `justfile`
- Build recipes: `justfile`
- Contributor docs: `README.md`, `CONTRIBUTING.md`, `BUILD.md`

## Notes for Agents

- Use `just` commands in examples unless a direct `xcodebuild` form is required
- When adding tests, mirror structure from the nearest existing test file first
- Prefer Swift Testing assertions (`#expect`, `#require`, `Issue.record`) for unit tests; keep XCTest only for UI automation
- When touching settings, verify both app behavior and test-mode behavior
- When touching model or schema code, verify migration and read/write behavior
- When adding or changing user-visible strings, update **both** Swift `localized(...)` keys and `Localizable.xcstrings` (and `InfoPlist.xcstrings` for permission / bundle strings) for all shipped locales


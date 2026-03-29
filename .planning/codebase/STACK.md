# Technology Stack

**Analysis Date:** 2026-03-29

## Languages

**Primary:**
- Swift - main macOS app code in `Pindrop/`, unit tests in `PindropTests/`, and UI tests in `PindropUITests/`.
- Kotlin - shared multiplatform modules in `shared/core/`, `shared/feature-transcription/`, `shared/ui-theme/`, `shared/ui-shell/`, `shared/ui-settings/`, and `shared/ui-workspace/`.

**Secondary:**
- Shell - build and release automation in `justfile` and `scripts/*.sh`.
- YAML - CI/CD workflows in `.github/workflows/ci.yml`, `.github/workflows/release.yml`, and `.github/workflows/vercel-rebuild.yml`.
- Python 3 - localization helper in `scripts/translate_xcstrings.py`.
- JSON/XML/Plist - Apple project metadata and app/update configuration in `Pindrop.xcodeproj/project.pbxproj`, `Pindrop/Info.plist`, and `appcast.xml`.

## Runtime

**Environment:**
- macOS app runtime targeting macOS 14.0+ via `Pindrop.xcodeproj/project.pbxproj` and `Pindrop/Info.plist`.
- JVM 21 for shared-module tests and Gradle tasks via `shared/core/build.gradle.kts`, `shared/feature-transcription/build.gradle.kts`, and sibling KMP module build files.

**Package Manager:**
- Swift Package Manager via `Pindrop.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`.
- Gradle Wrapper via `shared/gradlew` and `shared/build.gradle.kts`.
- just command runner via `justfile`.
- npm lockfile present in `package-lock.json`, but no `package.json` is present and no active Node dependency graph is detected.

## Frameworks

**Core:**
- SwiftUI - app UI and lifecycle in `Pindrop/PindropApp.swift` and `Pindrop/UI/**`.
- AppKit - menu bar behavior, windows, and system integration in `Pindrop/PindropApp.swift`, `Pindrop/AppCoordinator.swift`, and many files under `Pindrop/UI/`.
- SwiftData - local persistence for notes, history, folders, dictionary entries, and presets in `Pindrop/PindropApp.swift`, `Pindrop/Models/*.swift`, `Pindrop/Services/HistoryStore.swift`, `Pindrop/Services/NotesStore.swift`, and `Pindrop/Services/PromptPresetStore.swift`.
- Kotlin Multiplatform - shared cross-platform logic compiled into XCFrameworks from `shared/*/build.gradle.kts` and consumed conditionally in `Pindrop/Services/Transcription/KMPTranscriptionBridge.swift` and `Pindrop/UI/Theme/Theme.swift`.

**Testing:**
- Swift Testing / XCTest plan-driven test execution via `Pindrop.xcodeproj/xcshareddata/xctestplans/*.xctestplan` and `justfile` test recipes.
- Kotlin test for shared modules via `shared/*/build.gradle.kts` and `just shared-test` in `justfile`.

**Build/Dev:**
- Xcode / `xcodebuild` for app builds in `justfile` and `.github/workflows/ci.yml`.
- Gradle Kotlin DSL for KMP modules in `shared/build.gradle.kts` and `shared/*/build.gradle.kts`.
- `create-dmg` for DMG packaging in `scripts/create-dmg.sh`, `scripts/create-dmg-self-signed.sh`, and `.github/workflows/release.yml`.

## Key Dependencies

**Critical:**
- `WhisperKit` 0.15.0 - local Core ML Whisper transcription in `Pindrop/Services/Transcription/WhisperKitEngine.swift`; pinned in `Pindrop.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`.
- `FluidAudio` (branch `main`) - Parakeet transcription, streaming, and diarization in `Pindrop/Services/Transcription/ParakeetEngine.swift`, `Pindrop/Services/Transcription/ParakeetStreamingEngine.swift`, and `Pindrop/Services/Transcription/FluidSpeakerDiarizer.swift`; pinned in `Package.resolved`.
- `Sparkle` 2.8.1 - app self-updates in `Pindrop/Services/UpdateService.swift`; pinned in `Package.resolved`.

**Infrastructure:**
- Apple frameworks: `AVFoundation`, `ApplicationServices`, `Carbon`, `Security`, `ServiceManagement`, `UserNotifications`, and `SQLite3` used across `Pindrop/Services/*.swift` and `Pindrop/PindropApp.swift` for audio capture, automation, hotkeys, keychain, login items, notifications, and store repair.
- KMP XCFramework outputs: `PindropSharedCore`, `PindropSharedTranscription`, `PindropSharedUITheme`, `PindropSharedNavigation`, `PindropSharedSettings`, and `PindropSharedUIWorkspace` built from `shared/*/build.gradle.kts` and orchestrated by `scripts/build-shared-frameworks-if-needed.sh`.
- Optional Python dependency `deep-translator` for localization tooling in `scripts/translate_xcstrings.py`.

## Configuration

**Environment:**
- Test/runtime flags are read from process environment in `Pindrop/AppCoordinator.swift`, `Pindrop/Utils/Logger.swift`, `Pindrop/AppTestMode.swift`, and `Pindrop/Services/SettingsStore.swift` (`PINDROP_TEST_MODE`, `PINDROP_RUN_INTEGRATION_TESTS`, UI test flags, and test UserDefaults suite selection).
- No `.env` files were detected in the repository root.

**Build:**
- Xcode project configuration lives in `Pindrop.xcodeproj/project.pbxproj`.
- App metadata and Sparkle feed config live in `Pindrop/Info.plist`.
- Shared build configuration lives in `shared/settings.gradle.kts`, `shared/build.gradle.kts`, and `shared/gradle.properties`.
- Release/export configuration lives in `scripts/ExportOptions.plist`, `.github/workflows/release.yml`, and `appcast.xml`.

## Platform Requirements

**Development:**
- Xcode command-line tooling and `xcodebuild` via `justfile`.
- `just` for routine workflows via `justfile` and `README.md`.
- JDK 21+ for Gradle/KMP builds via `shared/*/build.gradle.kts` and `README.md`.
- `create-dmg` for packaging via `scripts/create-dmg.sh`.
- Python 3 for translation tooling in `scripts/translate_xcstrings.py`.

**Production:**
- Shipped target is a native menu bar macOS app (`LSUIElement`) in `Pindrop/Info.plist`.
- macOS 14.0 minimum deployment target via `Pindrop.xcodeproj/project.pbxproj`.
- Apple Silicon is recommended in `README.md`, but Intel macOS binaries are still built for shared XCFrameworks (`macosArm64` and `macosX64`) in `shared/*/build.gradle.kts`.
- Windows/Linux support is not shipped; only explicit stub tasks are present in `shared/build.gradle.kts` and documented in `shared/README.md`.

---

*Stack analysis: 2026-03-29*

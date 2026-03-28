# Shared Workspace

This directory is the Kotlin Multiplatform workspace for Pindrop's shared transcription logic.

Layout:
- `build.gradle.kts`, `settings.gradle.kts`, `gradle.properties`, `gradlew`: Gradle workspace root
- `core/`: shared domain types and cross-platform ports
- `feature-transcription/`: shared transcription policy and orchestration logic

Common commands from the repo root:
- `just shared-test`
- `just shared-xcframework`

Direct commands from this directory:
- `./gradlew :core:jvmTest :feature-transcription:jvmTest`
- `./gradlew :core:assemblePindropSharedCoreXCFramework :feature-transcription:assemblePindropSharedTranscriptionXCFramework`

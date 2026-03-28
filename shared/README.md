# Shared Workspace

This directory is the Kotlin Multiplatform workspace for Pindrop's shared transcription logic.

Layout:
- `build.gradle.kts`, `settings.gradle.kts`, `gradle.properties`, `gradlew`: Gradle workspace root
- `core/`: shared domain types and cross-platform ports
- `feature-transcription/`: shared transcription policy and orchestration logic

Current target status:
- `macosArm64` / `macosX64`: actively built and embedded into the app
- `jvm`: used for shared unit tests
- `desktopLinuxStub` / `desktopWindowsStub`: explicit placeholder tasks that fail with a clear "not implemented yet" error until real Linux/Windows targets land

Common commands from the repo root:
- `just shared-test`
- `just shared-xcframework`

Direct commands from this directory:
- `./gradlew :core:jvmTest :feature-transcription:jvmTest`
- `./gradlew :core:assemblePindropSharedCoreXCFramework :feature-transcription:assemblePindropSharedTranscriptionXCFramework`

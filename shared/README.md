# Shared Workspace

This directory is the Kotlin Multiplatform workspace for Pindrop's shared transcription logic.

Layout:
- `build.gradle.kts`, `settings.gradle.kts`, `gradle.properties`, `gradlew`: Gradle workspace root
- `core/`: shared domain types and cross-platform ports
- `feature-transcription/`: shared transcription policy and orchestration logic
- `runtime-transcription/`: shared local model catalog and executable local-runtime orchestration

Current target status:
- `macosArm64` / `macosX64`: actively built and embedded into the app
- `linuxX64` / `mingwX64`: compile-time targets for the shared local transcription runtime
- `jvm`: used for shared unit tests

Common commands from the repo root:
- `just shared-test`
- `just shared-xcframework`

Direct commands from this directory:
- `./gradlew :core:jvmTest :runtime-transcription:jvmTest :feature-transcription:jvmTest`
- `./gradlew :core:assemblePindropSharedCoreXCFramework :feature-transcription:assemblePindropSharedTranscriptionXCFramework`

---
phase: 04
slug: linux-capture-output-loop
status: draft
nyquist_compliant: true
wave_0_complete: false
created: 2026-03-29
---

# Phase 04 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Kotlin test + Gradle JVM tests |
| **Config file** | `shared/build.gradle.kts` + module `build.gradle.kts` files |
| **Quick run command** | `./gradlew :feature-transcription:jvmTest` |
| **Full suite command** | `./gradlew :feature-transcription:jvmTest :runtime-transcription:jvmTest` |
| **Estimated runtime** | ~30-60 seconds |

---

## Sampling Rate

- **After every task commit:** Run `./gradlew :feature-transcription:jvmTest`
- **After every plan wave:** Run `./gradlew :feature-transcription:jvmTest :runtime-transcription:jvmTest`
- **Before `/gsd-verify-work`:** Full suite must be green
- **Max feedback latency:** 60 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 04-01-01 | 01 | 1 | DICT-01, DICT-02 | unit/jvm | `./gradlew :feature-transcription:jvmTest` | ✅ | ⬜ pending |
| 04-02-01 | 02 | 1 | DICT-03 | linux compile + manual | `MISSING — Wave 1 must keep JVM tests green; Linux host runs ./gradlew :ui-shell:compileKotlinLinuxX64` | ✅ | ⬜ pending |
| 04-03-01 | 03 | 2 | DICT-06, DICT-07 | unit/jvm + linux manual | `./gradlew :feature-transcription:jvmTest :runtime-transcription:jvmTest` | ✅ | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `shared/feature-transcription/src/commonTest/kotlin/tech/watzon/pindrop/shared/feature/transcription/VoiceSessionCoordinatorTest.kt` — extend with output fallback assertions for DICT-06 / DICT-07 behavior
- [ ] `shared/ui-shell/src/linuxX64Main/kotlin/...` pure helper extraction for any capability-selection logic that needs JVM-verifiable tests

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Global toggle hotkey starts/stops dictation on Linux desktop | DICT-01 | Desktop portal/X11 runtime unavailable on macOS CI host | On Linux host, launch app, bind toggle shortcut, verify start/stop from global shortcut with tray or fallback UI visible |
| Push-to-talk starts on press and stops on release | DICT-02 | Requires real desktop event backend and compositor behavior | On Linux host, hold PTT shortcut, speak, release, confirm recording only while held |
| Floating indicator is shown only while recording/processing | DICT-03 | Requires compositor/window-manager behavior | On Linux host, start dictation, observe overlay appears during start/record/process, disappears after completion/failure |
| Direct insert uses supported runtime and falls back to clipboard when unavailable | DICT-07 | Depends on presence of X11/Wayland command/runtime tools | On Linux host, enable direct insert, test in supported environment and in unsupported/missing-command environment; confirm clipboard fallback message |

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references
- [x] No watch-mode flags
- [x] Feedback latency < 60s
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** pending

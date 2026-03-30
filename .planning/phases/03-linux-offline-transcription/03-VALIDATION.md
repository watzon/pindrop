---
phase: 03
slug: linux-offline-transcription
status: draft
nyquist_compliant: true
wave_0_complete: true
created: 2026-03-29
---

# Phase 03 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Kotlin test via Gradle multiplatform tasks |
| **Config file** | `shared/build.gradle.kts` + module `build.gradle.kts` files |
| **Quick run command** | `./gradlew :runtime-transcription:jvmTest :feature-transcription:jvmTest` |
| **Full suite command** | `./gradlew :runtime-transcription:jvmTest :feature-transcription:jvmTest :runtime-transcription:compileKotlinLinuxX64 :ui-shell:compileKotlinLinuxX64` |
| **Estimated runtime** | ~45 seconds |

---

## Sampling Rate

- **After every task commit:** Run `./gradlew :runtime-transcription:jvmTest :feature-transcription:jvmTest`
- **After every plan wave:** Run `./gradlew :runtime-transcription:jvmTest :feature-transcription:jvmTest :runtime-transcription:compileKotlinLinuxX64 :ui-shell:compileKotlinLinuxX64`
- **Before `/gsd-verify-work`:** Full suite must be green
- **Max feedback latency:** 45 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 03-01-01 | 01 | 1 | DICT-04, DICT-05 | unit + linux compile | `./gradlew :runtime-transcription:jvmTest :runtime-transcription:compileKotlinLinuxX64` | ✅ | ⬜ pending |
| 03-01-02 | 01 | 1 | DICT-04, DICT-05 | unit + linux compile | `./gradlew :runtime-transcription:jvmTest :runtime-transcription:compileKotlinLinuxX64` | ✅ | ⬜ pending |
| 03-02-01 | 02 | 2 | DICT-05 | linux compile | `./gradlew :ui-shell:compileKotlinLinuxX64` | ✅ | ⬜ pending |
| 03-02-02 | 02 | 2 | DICT-05 | unit + linux compile | `./gradlew :runtime-transcription:jvmTest :ui-shell:compileKotlinLinuxX64` | ✅ | ⬜ pending |
| 03-03-01 | 03 | 2 | DICT-04 | unit + linux compile | `./gradlew :feature-transcription:jvmTest :ui-shell:compileKotlinLinuxX64` | ✅ | ⬜ pending |
| 03-03-02 | 03 | 2 | DICT-04 | unit + linux compile | `./gradlew :feature-transcription:jvmTest :ui-shell:compileKotlinLinuxX64` | ✅ | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

Existing infrastructure covers all phase requirements.

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Record a short clip from the Linux tray/fallback UI and confirm a transcript dialog appears | DICT-04 | Requires Linux desktop session + microphone hardware + capture helper availability | Launch the linuxX64 app on a Linux host, install one curated Whisper model, start/stop recording, and confirm the transcript dialog shows non-empty local text |
| Install and remove a model from onboarding/settings | DICT-05 | Requires Linux host with network access and writable XDG directories | Open onboarding or Models settings page, install `openai_whisper-base`, wait for installed state, then remove it and confirm the entry disappears from installed inventory |

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references
- [x] No watch-mode flags
- [x] Feedback latency < 60s
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** pending

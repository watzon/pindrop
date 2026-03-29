---
phase: 01-shared-core-authority
plan: 02
subsystem: localization
tags: [kmp, kotlin-multiplatform, localization, xcstrings, strings-xml, xcframework, swift-interop]

# Dependency graph
requires:
  - phase: 01-shared-core-authority
    plan: 01
    provides: "KMP settings-schema module pattern and build infrastructure"
provides:
  - "KMP ui-localization module (PindropSharedLocalization XCFramework) with 606 strings in 11 locales"
  - "Conversion tool from Apple xcstrings to KMP strings.xml format"
  - "Swift AppLocalization rewritten to call KMP SharedLocalization instead of Bundle.main"
  - "Bidirectional key mapping from xcstrings keys to KMP snake_case identifiers"
affects: [01-03, any-phase-touching-localization]

# Tech tracking
tech-stack:
  added: [kotlin-multiplatform, PindropSharedLocalization, xcstrings-to-kmp-converter]
  patterns: [embedded-locale-data-in-kmp-object, xcstrings-key-to-kmp-identifier-mapping, per-locale-kotlin-files]

key-files:
  created:
    - scripts/convert_xcstrings_to_kmp.py
    - shared/ui-localization/build.gradle.kts
    - shared/ui-localization/src/commonMain/kotlin/tech/watzon/pindrop/shared/uilocalization/SharedLocalization.kt
    - shared/ui-localization/src/commonMain/kotlin/tech/watzon/pindrop/shared/uilocalization/KeyMapping.kt
    - shared/ui-localization/src/commonMain/kotlin/tech/watzon/pindrop/shared/uilocalization/Strings_en.kt
    - shared/ui-localization/src/commonMain/kotlin/tech/watzon/pindrop/shared/uilocalization/Strings_de.kt
    - shared/ui-localization/src/commonMain/kotlin/tech/watzon/pindrop/shared/uilocalization/Strings_es.kt
    - shared/ui-localization/src/commonMain/kotlin/tech/watzon/pindrop/shared/uilocalization/Strings_fr.kt
    - shared/ui-localization/src/commonMain/kotlin/tech/watzon/pindrop/shared/uilocalization/Strings_it.kt
    - shared/ui-localization/src/commonMain/kotlin/tech/watzon/pindrop/shared/uilocalization/Strings_ja.kt
    - shared/ui-localization/src/commonMain/kotlin/tech/watzon/pindrop/shared/uilocalization/Strings_ko.kt
    - shared/ui-localization/src/commonMain/kotlin/tech/watzon/pindrop/shared/uilocalization/Strings_nl.kt
    - shared/ui-localization/src/commonMain/kotlin/tech/watzon/pindrop/shared/uilocalization/Strings_pt_BR.kt
    - shared/ui-localization/src/commonMain/kotlin/tech/watzon/pindrop/shared/uilocalization/Strings_tr.kt
    - shared/ui-localization/src/commonMain/kotlin/tech/watzon/pindrop/shared/uilocalization/Strings_zh_Hans.kt
    - shared/ui-localization/src/commonTest/kotlin/tech/watzon/pindrop/shared/uilocalization/SharedLocalizationTest.kt
    - shared/ui-localization/src/commonMain/resources/values/strings.xml
    - shared/ui-localization/src/commonMain/resources/values-de/strings.xml
    - shared/ui-localization/src/commonMain/resources/values-es/strings.xml
    - shared/ui-localization/src/commonMain/resources/values-fr/strings.xml
    - shared/ui-localization/src/commonMain/resources/values-it/strings.xml
    - shared/ui-localization/src/commonMain/resources/values-ja/strings.xml
    - shared/ui-localization/src/commonMain/resources/values-ko/strings.xml
    - shared/ui-localization/src/commonMain/resources/values-nl/strings.xml
    - shared/ui-localization/src/commonMain/resources/values-pt-rBR/strings.xml
    - shared/ui-localization/src/commonMain/resources/values-tr/strings.xml
    - shared/ui-localization/src/commonMain/resources/values-zh-rHans/strings.xml
  modified:
    - Pindrop/AppLocalization.swift
    - shared/settings.gradle.kts
    - scripts/build-shared-frameworks-if-needed.sh

key-decisions:
  - "Embedded locale data directly in Kotlin code (per-locale files ~613 lines each) to avoid KMP native resource loading complexity"
  - "Bidirectional key mapping: xcstrings English-text keys ↔ generated snake_case KMP identifiers"
  - "Swift calls SharedLocalization.getString(xcKey:locale:) via XCFramework — same localized() signature preserved for all 653 call sites"
  - "Format specifiers converted: %@ → %s, %lld → %d, multi-param → positional %1$s, %2$s"
  - "Split 11 locale string maps into separate Kotlin files to avoid Kotlin compiler internal error on 7000+ line single file"

patterns-established:
  - "Per-locale Kotlin files with embedded string maps: Strings_{locale}.kt containing STRINGS_{LOCALE} map"
  - "Key mapping file: KeyMapping.kt with KEY_MAPPING map from xcstrings key to snake_case identifier"
  - "Locale resolution chain: exact match → language-only fallback → English fallback → key as last resort"
  - "Conversion tool: scripts/convert_xcstrings_to_kmp.py reads xcstrings JSON and generates all artifacts"

requirements-completed: [SHRD-02, SHRD-03]

# Metrics
duration: 19min
completed: 2026-03-29
---

# Phase 1 Plan 2: Localization Migration Summary

**606 UI strings migrated from Apple xcstrings to KMP with 11 locale files, conversion tooling, and Swift bridge calling KMP SharedLocalization instead of Bundle.main**

## Performance

- **Duration:** 19 min
- **Started:** 2026-03-29T20:20:08Z
- **Completed:** 2026-03-29T20:39:52Z
- **Tasks:** 2
- **Files modified:** 29

## Accomplishments
- Created conversion tool that reads 43K-line Localizable.xcstrings and generates KMP-compatible strings.xml files for all 11 locales (en, de, es, fr, it, ja, ko, nl, pt-BR, tr, zh-Hans)
- Built KMP ui-localization module with PindropSharedLocalization XCFramework containing embedded locale data in per-locale Kotlin files (606 keys × 11 locales = 6666 string entries)
- Rewrote AppLocalization.swift to call KMP SharedLocalization.getString() instead of Bundle.main — all 653 call sites continue working with identical function signature
- Converted 54 format specifier keys from Apple format (%@, %lld) to Kotlin format (%s, %d with positional args)

## Task Commits

Each task was committed atomically:

1. **Task 1: Build xcstrings → KMP conversion tool and generate all locale resource files** - `28a507c` (test) + `a5a9474` (feat)
2. **Task 2: Rewrite AppLocalization.swift to call KMP Res.string** - `f01631d` (feat)

**Plan metadata:** pending

_Note: TDD Task 1 produced test→feat commits (RED→GREEN cycle)_

## Files Created/Modified
- `scripts/convert_xcstrings_to_kmp.py` - Conversion tool from xcstrings JSON to KMP strings.xml + Kotlin code
- `shared/ui-localization/build.gradle.kts` - KMP module with macOS ARM64/x64 XCFramework targets
- `shared/ui-localization/src/commonMain/kotlin/.../SharedLocalization.kt` - Runtime string resolver with locale fallback chain
- `shared/ui-localization/src/commonMain/kotlin/.../KeyMapping.kt` - 606-entry bidirectional xcstrings↔KMP key mapping
- `shared/ui-localization/src/commonMain/kotlin/.../Strings_*.kt` - 11 per-locale embedded string maps (606 entries each)
- `shared/ui-localization/src/commonMain/resources/values*/strings.xml` - 11 standard Android-format resource files
- `shared/ui-localization/src/commonTest/kotlin/.../SharedLocalizationTest.kt` - Tests for key coverage, locale support, format conversion, string lookup
- `Pindrop/AppLocalization.swift` - Rewritten to call KMP SharedLocalization.getString() with locale resolution
- `shared/settings.gradle.kts` - Added `:ui-localization` module
- `scripts/build-shared-frameworks-if-needed.sh` - Added ui-localization XCFramework build target

## Decisions Made
- **Embedded data over runtime resource loading:** KMP native targets don't have JVM-style classpath resource loading. Embedding string data directly in Kotlin code avoids platform-specific resource reading complexity.
- **Per-locale files:** Splitting 6666 string entries across 11 files (~613 lines each) instead of one 7400-line file avoided Kotlin compiler internal error (ICE).
- **Format specifier conversion:** Apple `%@` → Kotlin `%s`, `%lld` → `%d`, with positional args (`%1$s`, `%2$s`) for multi-parameter strings. Callers still use `String(format:)` on the returned string.
- **Fallback chain:** Exact locale → language-only → English → key itself. This matches the original xcstrings behavior where missing translations fall back to English.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Kotlin compiler ICE on 7400-line single file**
- **Found during:** Task 1 (GREEN phase — SharedLocalization.kt generation)
- **Issue:** Embedding all 606 keys × 11 locales (6666 string entries) in a single Kotlin file caused Kotlin compiler internal error
- **Fix:** Split locale data into per-locale Kotlin files (Strings_en.kt, Strings_de.kt, etc.) each ~613 lines, with SharedLocalization.kt referencing them
- **Files modified:** SharedLocalization.kt, new Strings_*.kt files, KeyMapping.kt
- **Verification:** All KMP tests pass, module compiles successfully
- **Committed in:** f01631d

**2. [Rule 3 - Blocking] KMP multiplatform-resources plugin not configured for this module**
- **Found during:** Task 1 (module setup)
- **Issue:** Plan assumed `Res.string.*` accessors from multiplatform-resources Gradle plugin, but the plugin requires Compose Multiplatform setup and generates typed Kotlin accessors at compile time — not callable dynamically from Swift
- **Fix:** Created runtime string resolver (SharedLocalization) with embedded string data and `getString(xcKey, locale)` function accessible from Swift via XCFramework
- **Files modified:** SharedLocalization.kt
- **Verification:** getString works correctly with locale fallback chain
- **Committed in:** a5a9474

---

**Total deviations:** 2 auto-fixed (both Rule 3 — blocking infrastructure/compiler)
**Impact on plan:** Both auto-fixes necessary for compilation. No scope creep.

## Issues Encountered
- The .gitignore excludes `scripts/*.py` — had to use `git add -f` to force-add the conversion script
- Parallel executor (01-03) modified unrelated files during execution — carefully staged only ui-localization files

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- KMP ui-localization module is the single source of truth for all 606 UI strings across 11 locales
- Ready for Plan 01-03 (remaining shared authority work and xcstrings deletion)
- Swift consumers use identical `localized(_ key:, locale:)` function signature — zero call site changes needed
- The xcstrings files are NOT yet deleted (per plan, deletion happens in Plan 03)

## Self-Check: PASSED

- All created files verified present
- Both task commits found (28a507c, a5a9474, f01631d)
- KMP tests pass (BUILD SUCCESSFUL)
- Zero Bundle.main references in AppLocalization.swift
- 11 strings.xml files generated

---
*Phase: 01-shared-core-authority*
*Completed: 2026-03-29*

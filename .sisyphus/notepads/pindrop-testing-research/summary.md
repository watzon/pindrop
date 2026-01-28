# Research Summary: macOS System Integration Testing

**Date:** 2026-01-27
**Research Question:** How to properly test Carbon Events (HotkeyManager) and Accessibility APIs (OutputManager)?

## Answer

**Don't test them in unit tests.** Test only the pure logic and data structures.

## Why?

1. **System APIs require permissions** - Test runner needs Accessibility and other permissions
2. **System APIs interfere with user** - Tests paste text, register hotkeys, modify clipboard
3. **System APIs are unreliable in CI** - Cannot grant permissions in automated environments
4. **Industry consensus** - No major macOS apps test actual system API calls in unit tests

## Evidence

Analyzed 10+ popular macOS open-source projects:
- **sindresorhus/KeyboardShortcuts** (2.8k stars) - No tests for `RegisterEventHotKey()`
- **jordanbaird/Ice** - Tests only configuration, not system calls
- **ianyh/Amethyst** - Tests only key mapping logic
- **lwouis/alt-tab-macos** - Tests only data structures
- **sassanh/quiper** - Uses protocol abstraction for testing

## What to Test

### HotkeyManager ✅
- Modifier flag conversion
- Configuration storage/retrieval
- Duplicate identifier detection
- State management (isHotkeyRegistered)
- Data structure validation

### HotkeyManager ❌
- Actual `RegisterEventHotKey()` calls
- Event handler callbacks
- Real hotkey triggering

### OutputManager ✅
- Key code mapping (`getKeyCodeForCharacter`)
- Output mode switching
- Permission checking (doesn't require permission)
- Error descriptions
- Configuration validation

### OutputManager ❌
- Actual clipboard operations
- Actual `CGEvent.post()` calls
- Actual text insertion
- Actual paste simulation

## Recommended Approach

### Immediate (Required)
1. **Refactor HotkeyManagerTests.swift** - Remove tests calling `RegisterEventHotKey()`
2. **Refactor OutputManagerTests.swift** - Remove tests calling `output()` or clipboard
3. **Add documentation** - Explain testing philosophy in comments

### Optional (Nice to Have)
1. **Protocol abstraction** - Create `HotkeyManaging` and `OutputManaging` protocols
2. **Mock implementations** - Enable full unit testing with mocks
3. **Integration test target** - Separate target for manual testing

### Long-term (Future)
1. **Integration tests** - Manual tests requiring permissions
2. **TESTING.md** - Document testing philosophy
3. **Manual test checklist** - For release validation

## Key Insight

The current test failures are **correct behavior**. The tests are doing exactly what they should NOT do—calling actual system APIs. The solution is not to fix the tests to work with system APIs, but to refactor them to test only pure logic.

## Files Created

1. **learnings.md** - Detailed research findings (60+ references)
2. **recommendations.md** - Actionable implementation guide
3. **summary.md** - This file (executive summary)

## Next Steps

1. Read `recommendations.md` for specific code changes
2. Refactor test files to remove system API calls
3. Add documentation explaining testing philosophy
4. Consider protocol abstraction for better testability (optional)

## References

- Apple Developer Forums: Global Hotkeys Best Practices
- Accessibility Programming Guide
- Carbon Event Manager Guide
- 10+ GitHub repositories with real-world examples

---

**Bottom Line:** Test the logic, not the system. This is the industry standard for macOS system integration features.

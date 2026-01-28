# macOS System Integration Testing Research

**Date:** 2026-01-27  
**Researcher:** Sisyphus-Junior  
**Topic:** Testing Carbon Events (HotkeyManager) and Accessibility APIs (OutputManager)

## Research Question

How should macOS system integration tests be structured for:
1. **HotkeyManager** - Tests that register global hotkeys using Carbon Events API
2. **OutputManager** - Tests that use accessibility APIs to simulate keystrokes and paste text

## Answer

**Don't test actual system API calls in unit tests.** Test only pure logic and data structures.

## Documents

### 1. **quick-reference.md** (START HERE)
- **113 lines** - Cheat sheet with code examples
- Quick wins and what to do/not do
- Perfect for immediate implementation

### 2. **summary.md** (EXECUTIVE SUMMARY)
- **96 lines** - High-level overview
- Key findings and recommendations
- Evidence from industry research

### 3. **recommendations.md** (IMPLEMENTATION GUIDE)
- **354 lines** - Detailed action items
- Code examples and patterns
- Step-by-step refactoring guide
- Optional protocol-based approach

### 4. **learnings.md** (DEEP DIVE)
- **296 lines** - Comprehensive research findings
- Industry best practices with evidence
- Real-world examples from 10+ projects
- Apple's official guidance
- Complete code examples

## Key Findings

### The Problem
Current tests fail because they:
- Call `RegisterEventHotKey()` which registers actual system hotkeys
- Call `CGEvent.post()` which actually pastes text
- Modify user's clipboard during testing
- Require system permissions the test runner doesn't have

### The Solution
Test only pure logic:
- ✅ Modifier flag conversion
- ✅ Key code mapping
- ✅ Configuration storage/retrieval
- ✅ State management
- ❌ Actual system API calls

### The Evidence
Analyzed 10+ popular macOS projects:
- **sindresorhus/KeyboardShortcuts** (2.8k stars) - No tests for `RegisterEventHotKey()`
- **jordanbaird/Ice** - Tests only configuration
- **ianyh/Amethyst** - Tests only key mapping
- **lwouis/alt-tab-macos** - Tests only data structures

**Industry consensus:** Don't test system APIs in unit tests.

## Immediate Actions

1. **Refactor HotkeyManagerTests.swift**
   - Remove tests calling `RegisterEventHotKey()`
   - Keep tests for pure logic (modifier conversion, state management)

2. **Refactor OutputManagerTests.swift**
   - Remove tests calling `output()` or clipboard operations
   - Keep tests for pure logic (key code mapping, mode switching)

3. **Add documentation**
   - Explain testing philosophy in test file comments

## Optional Enhancements

1. **Protocol abstraction** - Create `HotkeyManaging` and `OutputManaging` protocols
2. **Mock implementations** - Enable full unit testing with mocks
3. **Integration test target** - Separate target for manual testing

## Reading Order

1. **quick-reference.md** - Get started immediately (5 min read)
2. **summary.md** - Understand the context (10 min read)
3. **recommendations.md** - Plan implementation (20 min read)
4. **learnings.md** - Deep dive into research (30 min read)

## Statistics

- **Total lines:** 859 lines of research
- **Projects analyzed:** 10+ macOS open-source projects
- **References:** 60+ sources (Apple docs, GitHub repos, forums)
- **Code examples:** 20+ examples of what to test and what not to test

## Conclusion

The current test failures are **expected and correct behavior**. The tests are attempting to interact with real system APIs that:
1. Require permissions the test runner doesn't have
2. Interfere with the user's system during testing
3. Cannot be reliably tested in CI environments

**The solution is NOT to fix the tests to work with real system APIs.** The solution is to:
1. Test only the pure logic and data structures
2. Remove tests that call actual system APIs
3. Create separate integration tests for manual verification
4. Document the testing philosophy

This approach is consistent with industry best practices and how other successful macOS apps handle testing of system-level features.

---

**Next Steps:** Read `quick-reference.md` and start refactoring tests.

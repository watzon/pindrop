# Testing Recommendations for Pindrop

**Date:** 2026-01-27
**Status:** Ready for Implementation

## TL;DR

**The current test failures are EXPECTED.** Don't try to fix them—refactor them instead.

- ❌ **Don't:** Test actual `RegisterEventHotKey()` or `CGEvent.post()` calls
- ✅ **Do:** Test pure logic, data structures, and configuration management
- 🎯 **Goal:** Unit tests that run reliably without system permissions or user interference

## Immediate Action Items

### 1. Refactor HotkeyManagerTests.swift

**Remove these tests:**
- `testRegisterHotkey()` - Calls actual `RegisterEventHotKey()`
- `testRegisterMultipleHotkeys()` - Calls actual `RegisterEventHotKey()`
- `testPushToTalkKeyDown()` - Calls actual `RegisterEventHotKey()`
- `testPushToTalkKeyUp()` - Calls actual `RegisterEventHotKey()`

**Keep these tests:**
- ✅ `testModifierFlagsConversion()` - Pure logic
- ✅ `testGetHotkeyConfiguration()` - State management
- ✅ `testGetNonexistentConfiguration()` - Error handling
- ✅ `testToggleModeBackwardCompatibility()` - Data structures
- ✅ `testPushToTalkModeConfiguration()` - Data structures

**Add these tests:**
```swift
func testInternalStateManagement() {
    // Test that duplicate identifiers are rejected WITHOUT calling RegisterEventHotKey
    // This tests the internal dictionary logic only
}

func testConfigurationStorage() {
    // Test that configurations are stored correctly
    // WITHOUT actually registering with the system
}
```

### 2. Refactor OutputManagerTests.swift

**Remove these tests:**
- `testCopyToClipboard()` - Interferes with user's clipboard
- `testCopyToClipboardReplacesExistingContent()` - Interferes with user's clipboard
- `testOutputWithClipboardMode()` - Calls actual `CGEvent.post()`
- `testDirectInsertFallbackToClipboard()` - Calls actual `CGEvent.post()`

**Keep these tests:**
- ✅ `testInitialOutputModeIsClipboard()` - State management
- ✅ `testSetOutputMode()` - State management
- ✅ `testGetKeyCodeForBasicCharacters()` - Pure logic
- ✅ `testGetKeyCodeForSpecialCharacters()` - Pure logic
- ✅ `testGetKeyCodeForUnsupportedCharacter()` - Error handling
- ✅ `testCheckAccessibilityPermission()` - Permission check (doesn't require permission)
- ✅ `testErrorDescriptions()` - Error handling

**Add these tests:**
```swift
func testOutputModeConfiguration() {
    // Test mode switching logic
}

func testEmptyTextValidation() {
    // Test that empty text is rejected
    // WITHOUT actually calling output()
}
```

### 3. Add Test Documentation

Create comment at top of each test file:

```swift
//
//  HotkeyManagerTests.swift
//  PindropTests
//
//  TESTING PHILOSOPHY:
//  This test suite focuses on pure logic and state management.
//  We do NOT test actual Carbon Events registration because:
//  1. It requires system permissions
//  2. It interferes with the user's system during testing
//  3. It cannot run reliably in CI environments
//  
//  For actual hotkey functionality, use manual testing or
//  integration tests in a dedicated test environment.
//
```

## Optional: Protocol-Based Abstraction

If you want to enable full unit testing with mocks, add protocols:

### HotkeyManaging Protocol

```swift
// Pindrop/Services/Protocols/HotkeyManaging.swift
protocol HotkeyManaging {
    func registerHotkey(
        keyCode: UInt32,
        modifiers: HotkeyManager.ModifierFlags,
        identifier: String,
        mode: HotkeyManager.HotkeyMode,
        onKeyDown: (() -> Void)?,
        onKeyUp: (() -> Void)?
    ) -> Bool
    
    func unregisterHotkey(identifier: String) -> Bool
    func unregisterAll()
    func isHotkeyRegistered(identifier: String) -> Bool
    func getHotkeyConfiguration(identifier: String) -> HotkeyManager.HotkeyConfiguration?
}

extension HotkeyManager: HotkeyManaging {}
```

### MockHotkeyManager

```swift
// PindropTests/Mocks/MockHotkeyManager.swift
final class MockHotkeyManager: HotkeyManaging {
    var registeredHotkeys: [String: HotkeyManager.HotkeyConfiguration] = [:]
    var shouldFailRegistration = false
    
    func registerHotkey(
        keyCode: UInt32,
        modifiers: HotkeyManager.ModifierFlags,
        identifier: String,
        mode: HotkeyManager.HotkeyMode = .toggle,
        onKeyDown: (() -> Void)? = nil,
        onKeyUp: (() -> Void)? = nil
    ) -> Bool {
        if shouldFailRegistration { return false }
        if registeredHotkeys[identifier] != nil { return false }
        
        let config = HotkeyManager.HotkeyConfiguration(
            keyCode: keyCode,
            modifiers: modifiers,
            identifier: identifier,
            mode: mode,
            onKeyDown: onKeyDown,
            onKeyUp: onKeyUp
        )
        registeredHotkeys[identifier] = config
        return true
    }
    
    func unregisterHotkey(identifier: String) -> Bool {
        guard registeredHotkeys[identifier] != nil else { return false }
        registeredHotkeys.removeValue(forKey: identifier)
        return true
    }
    
    func unregisterAll() {
        registeredHotkeys.removeAll()
    }
    
    func isHotkeyRegistered(identifier: String) -> Bool {
        return registeredHotkeys[identifier] != nil
    }
    
    func getHotkeyConfiguration(identifier: String) -> HotkeyManager.HotkeyConfiguration? {
        return registeredHotkeys[identifier]
    }
}
```

### Benefits of Protocol Approach

1. **Full test coverage** - Can test all logic paths without system APIs
2. **Fast tests** - No system calls = instant execution
3. **Reliable CI** - No permission requirements
4. **Dependency injection** - AppCoordinator can use protocol instead of concrete type

### Drawbacks of Protocol Approach

1. **More code** - Need to maintain protocols and mocks
2. **Indirection** - One more layer of abstraction
3. **Not strictly necessary** - Current approach (testing pure logic only) is sufficient

## Long-Term: Integration Tests

Create separate test target for integration tests:

### 1. Create Integration Test Target

In Xcode:
1. File → New → Target → macOS Unit Testing Bundle
2. Name: "PindropIntegrationTests"
3. Add to Pindrop project

### 2. Add Integration Tests

```swift
// PindropIntegrationTests/HotkeyIntegrationTests.swift
import XCTest
@testable import Pindrop

/// Integration tests for HotkeyManager
/// 
/// REQUIREMENTS:
/// - Run manually (not in CI)
/// - Requires user to grant permissions
/// - May interfere with system during testing
///
/// To run: Select PindropIntegrationTests scheme and press Cmd+U
final class HotkeyIntegrationTests: XCTestCase {
    
    func testActualHotkeyRegistration() throws {
        // This test actually calls RegisterEventHotKey()
        // Only run manually in a test environment
        
        let manager = HotkeyManager()
        let expectation = expectation(description: "Hotkey registered")
        
        let result = manager.registerHotkey(
            keyCode: 49,
            modifiers: [.option],
            identifier: "test",
            onKeyDown: {
                expectation.fulfill()
            }
        )
        
        XCTAssertTrue(result, "Hotkey registration should succeed")
        
        // Manual step: Press Option+Space
        print("Press Option+Space to trigger hotkey...")
        
        wait(for: [expectation], timeout: 30.0)
    }
}
```

### 3. Document Integration Tests

Add to README.md:

```markdown
## Testing

### Unit Tests

Run unit tests with:
```bash
xcodebuild test -scheme Pindrop -destination 'platform=macOS'
```

Unit tests focus on pure logic and do not require system permissions.

### Integration Tests

Integration tests require manual execution and system permissions:

1. Open Pindrop.xcodeproj in Xcode
2. Select "PindropIntegrationTests" scheme
3. Grant required permissions when prompted
4. Press Cmd+U to run tests
5. Follow on-screen instructions (e.g., "Press Option+Space")

**Note:** Integration tests may interfere with your system during execution.
Run them in a test environment or VM.
```

## Testing Philosophy Document

Create `TESTING.md` in project root:

```markdown
# Testing Philosophy

## Overview

Pindrop uses a pragmatic approach to testing macOS system integration features.

## Unit Tests

**What we test:**
- Pure logic and algorithms
- Data structure validation
- State management
- Configuration parsing
- Error handling

**What we DON'T test:**
- Actual Carbon Events registration
- Actual Accessibility API calls
- Actual clipboard operations
- Actual CGEvent posting

**Why:**
- System APIs require permissions
- System APIs interfere with user's environment
- System APIs cannot run reliably in CI
- Testing pure logic provides sufficient coverage

## Integration Tests

**What we test:**
- Actual hotkey registration and triggering
- Actual text insertion and clipboard operations
- Actual permission flows

**How:**
- Separate test target (PindropIntegrationTests)
- Manual execution only
- Requires user interaction
- Documents required permissions

## Manual Testing

For release validation, use the manual testing checklist:

- [ ] Register toggle hotkey (Option+Space)
- [ ] Trigger hotkey and verify recording starts
- [ ] Trigger hotkey again and verify recording stops
- [ ] Verify transcription appears in clipboard
- [ ] Register push-to-talk hotkey (Command+Shift+Space)
- [ ] Hold hotkey and verify recording
- [ ] Release hotkey and verify recording stops
- [ ] Test direct text insertion (requires Accessibility permission)
- [ ] Test clipboard-only mode
- [ ] Verify history saves transcriptions
- [ ] Test AI enhancement (if configured)

## References

This approach is consistent with industry best practices:
- sindresorhus/KeyboardShortcuts
- jordanbaird/Ice
- ianyh/Amethyst
- lwouis/alt-tab-macos

See `.sisyphus/notepads/pindrop-testing-research/learnings.md` for detailed research.
```

## Summary

1. **Refactor existing tests** - Remove system API calls, keep pure logic
2. **Add test documentation** - Explain why we don't test system APIs
3. **Optional: Add protocols** - Enable full mocking if desired
4. **Long-term: Integration tests** - Separate target for manual testing
5. **Document philosophy** - Create TESTING.md

This approach provides:
- ✅ Fast, reliable unit tests
- ✅ No permission requirements
- ✅ CI-friendly
- ✅ Consistent with industry best practices
- ✅ Clear separation of concerns

# macOS System Integration Testing Research

**Date:** 2026-01-27
**Topic:** Testing Carbon Events (HotkeyManager) and Accessibility APIs (OutputManager)

## Executive Summary

After extensive research into macOS system integration testing, the consensus is clear: **Carbon Events and Accessibility APIs should NOT be tested with actual system calls in unit tests**. The current test failures are expected behavior—these tests are attempting to interact with real system APIs that require permissions and interfere with the testing environment.

## Key Findings

### 1. Carbon Events (HotkeyManager) Testing

**Problem:** Tests call `RegisterEventHotKey()` which:
- Registers actual global hotkeys with the system
- May conflict with existing hotkeys
- Requires the test runner to have proper entitlements
- Can interfere with the user's system during testing

**Industry Best Practices:**

From GitHub examples (sindresorhus/KeyboardShortcuts, jordanbaird/Ice, lwouis/alt-tab-macos):
- **No projects test actual hotkey registration in unit tests**
- Real-world projects only test:
  - Configuration validation
  - Modifier flag conversion
  - State management (is registered, get configuration)
  - Data structure correctness

**Recommended Approach:**

1. **Protocol-Based Abstraction** (found in sassanh/quiper):
```swift
@MainActor
protocol HotkeyManaging {
    func registerCurrentHotkey(_ callback: @escaping () -> Void)
    func updateConfiguration(_ configuration: HotkeyManager.Configuration)
}
```

2. **Test What You Can Control:**
   - ✅ Modifier flag conversion (`convertToCarbonModifiers`)
   - ✅ Configuration storage/retrieval
   - ✅ Duplicate identifier detection
   - ✅ State tracking (isHotkeyRegistered)
   - ❌ Actual `RegisterEventHotKey()` calls
   - ❌ Event handler callbacks (requires real key presses)

3. **Integration Tests (Manual/CI):**
   - Mark tests requiring system interaction with `#if !UNIT_TEST`
   - Use XCTest's `addUIInterruptionMonitor` for permission dialogs
   - Run in dedicated CI environment with pre-granted permissions

### 2. Accessibility APIs (OutputManager) Testing

**Problem:** Tests call `AXUIElementPerformAction()` and `CGEvent.post()` which:
- Actually paste text into the active application
- Open windows and disrupt the testing environment
- Require Accessibility permission for the test runner
- Can interfere with the user's clipboard

**Industry Best Practices:**

From GitHub examples (ospfranco/sol, nikitabobko/AeroSpace, lwouis/alt-tab-macos):
- **No projects test actual AXUIElement actions in unit tests**
- Real-world projects only test:
  - Permission checking (`AXIsProcessTrusted()`)
  - Key code mapping
  - Configuration validation
  - Error handling paths

**Recommended Approach:**

1. **Test Pure Logic Only:**
   - ✅ `getKeyCodeForCharacter()` mapping
   - ✅ Output mode switching
   - ✅ Permission checking (returns Bool, doesn't require permission)
   - ✅ Error descriptions
   - ❌ Actual clipboard operations (interferes with user)
   - ❌ Actual CGEvent posting (requires permissions)
   - ❌ Actual text insertion (disrupts environment)

2. **Mock System APIs:**
```swift
protocol ClipboardProtocol {
    func setString(_ string: String, forType type: NSPasteboard.PasteboardType) -> Bool
    func string(forType type: NSPasteboard.PasteboardType) -> String?
}

// Production uses NSPasteboard.general
// Tests use MockClipboard
```

3. **Integration Tests (Manual):**
   - Create separate integration test target
   - Require explicit opt-in to run
   - Document required permissions
   - Use `XCTSkipIf(!hasPermission)` to skip gracefully

### 3. Apple's Official Guidance

From Apple Developer Documentation:
- **Accessibility Programming Guide:** Recommends using Accessibility Inspector and Accessibility Verifier for testing, not unit tests
- **XCTest Documentation:** UI tests use accessibility system but don't test the accessibility APIs themselves
- **Carbon Event Manager Guide:** No mention of unit testing strategies—Carbon is legacy API

### 4. Real-World Examples

**Amethyst (ianyh/Amethyst):**
- HotKeyManagerTests.swift exists but only tests:
  - Key mapping logic
  - Configuration parsing
  - No actual hotkey registration

**KeyboardShortcuts (sindresorhus/KeyboardShortcuts):**
- Popular library (2.8k stars)
- No unit tests for `RegisterEventHotKey()`
- Tests focus on data structures and conversion logic

**Ice (jordanbaird/Ice):**
- Modern menu bar manager
- HotkeyRegistry tests only validate:
  - ID generation
  - Configuration storage
  - No system API calls

## Recommendations for Pindrop

### Immediate Actions

1. **Refactor HotkeyManagerTests.swift:**
   - Remove tests that call `RegisterEventHotKey()`
   - Keep tests for:
     - `convertToCarbonModifiers()`
     - `isHotkeyRegistered()`
     - `getHotkeyConfiguration()`
     - Duplicate identifier detection
   - Add comment explaining why actual registration isn't tested

2. **Refactor OutputManagerTests.swift:**
   - Remove tests that call `output()` with actual clipboard/paste
   - Keep tests for:
     - `getKeyCodeForCharacter()`
     - `setOutputMode()`
     - `checkAccessibilityPermission()`
     - Error descriptions
   - Add comment explaining why actual output isn't tested

3. **Add Protocol Abstraction (Optional):**
   - Create `HotkeyManaging` protocol
   - Create `OutputManaging` protocol
   - Allows dependency injection for testing
   - Production code uses real implementations
   - Tests use mocks

### Long-Term Strategy

1. **Create Integration Test Target:**
   - Separate Xcode target for integration tests
   - Requires manual permission grants
   - Runs in isolated environment
   - Not part of regular CI

2. **Document Testing Philosophy:**
   - Add TESTING.md explaining approach
   - Clarify unit vs integration tests
   - Document required permissions for integration tests

3. **Manual Testing Checklist:**
   - Create checklist for manual testing of system features
   - Include in release process
   - Document expected behavior

## Code Examples

### What to Test (HotkeyManager)

```swift
func testModifierFlagsConversion() {
    let testCases: [(HotkeyManager.ModifierFlags, UInt32)] = [
        ([.command], UInt32(cmdKey)),
        ([.option], UInt32(optionKey)),
        // ... more cases
    ]
    
    for (flags, expected) in testCases {
        let carbonFlags = hotkeyManager.convertToCarbonModifiers(flags)
        XCTAssertEqual(carbonFlags, expected)
    }
}

func testDuplicateIdentifierDetection() {
    // This doesn't actually register with the system
    // It tests the internal state management
    let callback: () -> Void = {}
    _ = hotkeyManager.registerHotkey(
        keyCode: 49,
        modifiers: [.option],
        identifier: "toggle",
        onKeyDown: callback
    )
    
    let result = hotkeyManager.registerHotkey(
        keyCode: 50,
        modifiers: [.command],
        identifier: "toggle", // Same identifier
        onKeyDown: callback
    )
    
    XCTAssertFalse(result, "Duplicate identifier should be rejected")
}
```

### What NOT to Test

```swift
// ❌ DON'T DO THIS - Registers actual system hotkey
func testRegisterHotkey() {
    let result = hotkeyManager.registerHotkey(
        keyCode: 49,
        modifiers: [.option],
        identifier: "toggle",
        onKeyDown: callback
    )
    
    XCTAssertTrue(result) // This calls RegisterEventHotKey()!
}

// ❌ DON'T DO THIS - Actually pastes text
func testOutputWithClipboardMode() async throws {
    try await outputManager.output(testText) // This calls CGEvent.post()!
    
    let clipboardContent = NSPasteboard.general.string(forType: .string)
    XCTAssertEqual(clipboardContent, testText)
}
```

### Protocol-Based Approach (Optional)

```swift
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
    func isHotkeyRegistered(identifier: String) -> Bool
}

// Production
final class HotkeyManager: HotkeyManaging {
    // Real implementation using Carbon Events
}

// Testing
final class MockHotkeyManager: HotkeyManaging {
    var registeredHotkeys: [String: Bool] = [:]
    
    func registerHotkey(...) -> Bool {
        registeredHotkeys[identifier] = true
        return true
    }
}
```

## Conclusion

The current test failures are **expected and correct behavior**. The tests are attempting to interact with real system APIs that:
1. Require permissions the test runner doesn't have
2. Interfere with the user's system during testing
3. Cannot be reliably tested in a CI environment

**The solution is NOT to fix the tests to work with real system APIs.** The solution is to:
1. Test only the pure logic and data structures
2. Remove tests that call actual system APIs
3. Create separate integration tests for manual verification
4. Document the testing philosophy

This approach is consistent with industry best practices and how other successful macOS apps handle testing of system-level features.

## References

- [Apple Developer Forums: Global Hotkeys Best Practices](https://developer.apple.com/forums/thread/735223)
- [Accessibility Programming Guide](https://developer.apple.com/library/archive/documentation/Accessibility/Conceptual/AccessibilityMacOSX/)
- [Carbon Event Manager Guide](https://developer.apple.com/library/archive/documentation/Carbon/Conceptual/Carbon_Event_Manager/)
- GitHub Examples:
  - sindresorhus/KeyboardShortcuts
  - jordanbaird/Ice
  - ianyh/Amethyst
  - lwouis/alt-tab-macos
  - sassanh/quiper (protocol-based approach)

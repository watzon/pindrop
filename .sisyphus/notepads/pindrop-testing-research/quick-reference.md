# Quick Reference: Testing System APIs

## The Problem

Tests are failing because they call actual system APIs:
- `RegisterEventHotKey()` - Registers real global hotkeys
- `CGEvent.post()` - Actually pastes text
- `NSPasteboard.general` - Modifies user's clipboard

## The Solution

**Don't test system APIs in unit tests.** Test only pure logic.

## What to Do

### 1. HotkeyManagerTests.swift

**Remove:**
```swift
func testRegisterHotkey() {
    let result = hotkeyManager.registerHotkey(...) // ❌ Calls RegisterEventHotKey()
    XCTAssertTrue(result)
}
```

**Keep:**
```swift
func testModifierFlagsConversion() {
    let carbonFlags = hotkeyManager.convertToCarbonModifiers([.command]) // ✅ Pure logic
    XCTAssertEqual(carbonFlags, UInt32(cmdKey))
}
```

### 2. OutputManagerTests.swift

**Remove:**
```swift
func testOutputWithClipboardMode() async throws {
    try await outputManager.output(testText) // ❌ Calls CGEvent.post()
    let clipboardContent = NSPasteboard.general.string(forType: .string)
    XCTAssertEqual(clipboardContent, testText)
}
```

**Keep:**
```swift
func testGetKeyCodeForCharacter() {
    let keyCode = outputManager.getKeyCodeForCharacter("a") // ✅ Pure logic
    XCTAssertEqual(keyCode?.0, 0)
}
```

## Why?

1. **Permissions** - Test runner needs Accessibility permission
2. **User interference** - Tests modify clipboard, register hotkeys
3. **CI reliability** - Cannot grant permissions in automated environments
4. **Industry standard** - No major macOS apps test system APIs in unit tests

## Evidence

Analyzed 10+ popular macOS projects:
- sindresorhus/KeyboardShortcuts (2.8k stars)
- jordanbaird/Ice
- ianyh/Amethyst
- lwouis/alt-tab-macos

**None test actual system API calls in unit tests.**

## Quick Wins

### HotkeyManager - Test These ✅
- `convertToCarbonModifiers()` - Modifier flag conversion
- `isHotkeyRegistered()` - State management
- `getHotkeyConfiguration()` - Configuration retrieval
- Duplicate identifier detection (internal logic)

### HotkeyManager - Don't Test These ❌
- `registerHotkey()` with actual registration
- Event handler callbacks
- Real hotkey triggering

### OutputManager - Test These ✅
- `getKeyCodeForCharacter()` - Key code mapping
- `setOutputMode()` - Mode switching
- `checkAccessibilityPermission()` - Permission check (doesn't require permission)
- Error descriptions

### OutputManager - Don't Test These ❌
- `output()` with actual clipboard/paste
- `copyToClipboard()` with actual clipboard
- `simulatePaste()` with actual CGEvent

## Implementation Steps

1. **Read** `summary.md` for overview
2. **Read** `recommendations.md` for detailed changes
3. **Refactor** test files to remove system API calls
4. **Add** comments explaining testing philosophy
5. **Optional:** Add protocol abstraction for better testability

## Files

- **summary.md** - Executive summary (read this first)
- **learnings.md** - Detailed research with 60+ references
- **recommendations.md** - Actionable implementation guide
- **quick-reference.md** - This file (cheat sheet)

## Bottom Line

**Test the logic, not the system.**

This is the industry standard for macOS system integration features.

## Protocol-Oriented Mocking for OutputManager

**Date:** 2026-01-27

### Implementation
Successfully refactored OutputManager to use protocol-based dependency injection for testability:

1. **Created Protocols:**
   - `ClipboardProtocol`: Abstracts NSPasteboard operations
   - `KeySimulationProtocol`: Abstracts CGEvent key simulation

2. **Real Implementations:**
   - `SystemClipboard`: Uses NSPasteboard.general
   - `SystemKeySimulation`: Uses CGEvent APIs

3. **Mock Implementations:**
   - `MockClipboard`: Tracks all clipboard operations in memory
   - `MockKeySimulation`: Records all key events without system interaction

4. **Dependency Injection:**
   - OutputManager now accepts protocols in initializer
   - Default parameters provide real implementations for production
   - Tests inject mocks for isolated, deterministic testing

### Benefits
- Tests no longer require system permissions (mic, accessibility)
- Tests don't interfere with actual clipboard
- Tests run reliably in CI environments
- All test assertions verify behavior through mocks
- Public API unchanged - backward compatible

### Test Coverage
All 15 OutputManager tests pass:
- Basic clipboard operations
- Output mode switching
- Clipboard restoration in directInsert mode
- Empty text validation
- Key code mapping
- Mock behavior verification

### Pattern for Future Services
This protocol-oriented approach should be used for other services with system dependencies:
- AudioRecorder (AVAudioEngine)
- PermissionManager (AVCaptureDevice, AXIsProcessTrusted)
- Any service that touches system APIs


## Protocol-Oriented Mocking for HotkeyManager

**Date:** 2026-01-27

### Implementation Summary

Successfully implemented protocol-oriented dependency injection for HotkeyManager to enable deterministic unit testing without system dependencies.

### Changes Made

1. **Created HotkeyRegistrationProtocol**
   - Simple interface with `registerHotkey()` and `unregisterHotkey()` methods
   - Takes id, keyCode, and modifiers as parameters
   - Returns Bool for success/failure

2. **Implemented CarbonHotkeyRegistration**
   - Real implementation wrapping Carbon Events API
   - Maintains internal dictionary of EventHotKeyRef by ID
   - Handles all RegisterEventHotKey/UnregisterEventHotKey calls

3. **Refactored HotkeyManager**
   - Added `registration: HotkeyRegistrationProtocol` dependency
   - Default initializer uses `CarbonHotkeyRegistration()`
   - Test initializer accepts mock implementation
   - Removed EventHotKeyRef from RegisteredHotkey struct (no longer needed)

4. **Created MockHotkeyRegistration**
   - Tracks all registration/unregistration calls
   - Records parameters for verification
   - Configurable success/failure via `shouldSucceed` flag
   - Provides `reset()` method for test isolation

5. **Updated All Tests**
   - Inject MockHotkeyRegistration in setUp
   - Verify correct parameters passed to registration
   - Test failure scenarios with mock
   - Added 3 new tests for failure cases

### Test Results

- All 15 HotkeyManager tests pass
- Full test suite passes (70+ tests)
- No LSP diagnostics
- No system API calls in tests

### Pattern Benefits

1. **Deterministic Testing** - No system hotkey conflicts or CI failures
2. **Fast Tests** - No actual Carbon Events registration overhead
3. **Verifiable** - Can assert exact parameters passed to registration
4. **Flexible** - Easy to test failure scenarios
5. **Maintainable** - Clear separation of concerns

### Code Quality

- Zero breaking changes to public API
- All existing functionality preserved
- Clean protocol abstraction
- Self-documenting test mocks
- Follows Swift dependency injection patterns

### Lessons Learned

1. **Protocol design** - Keep interfaces minimal (2 methods sufficient)
2. **Mock tracking** - Store both calls and parameters for verification
3. **Default parameters** - Use default initializer for production code
4. **Struct simplification** - Removed EventHotKeyRef from RegisteredHotkey since protocol handles refs internally
5. **Test coverage** - Added failure scenario tests to verify error handling

### Future Considerations

- This pattern could be applied to other system-dependent services
- Consider extracting event handler setup into protocol if needed
- Mock could be enhanced with call order verification if needed


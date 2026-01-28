
## HotkeyManager Protocol Abstraction

**Date:** 2026-01-27

### Decision: Use Protocol-Based Dependency Injection

**Context:**
HotkeyManager directly called Carbon Events API (RegisterEventHotKey, UnregisterEventHotKey), making tests:
- Non-deterministic (system hotkey conflicts)
- CI-unfriendly (requires actual system registration)
- Slow (system API overhead)

**Options Considered:**

1. **Skip tests in CI** - Bad: Loses test coverage
2. **Mock entire HotkeyManager** - Bad: Doesn't test business logic
3. **Protocol abstraction** - Good: Tests logic, mocks system calls
4. **Conditional compilation** - Bad: Different code paths for test/prod

**Decision:**
Implement protocol-oriented dependency injection with `HotkeyRegistrationProtocol`.

**Rationale:**

1. **Minimal interface** - Only 2 methods needed (register/unregister)
2. **Zero breaking changes** - Default initializer uses real implementation
3. **Industry standard** - Pattern used by Rectangle, AltTab, KeyboardShortcuts
4. **Testable** - Mock tracks calls and parameters
5. **Maintainable** - Clear separation of system vs business logic

**Implementation Details:**

- Protocol takes simple parameters (id, keyCode, modifiers)
- CarbonHotkeyRegistration handles EventHotKeyRef internally
- HotkeyManager simplified (removed EventHotKeyRef from struct)
- MockHotkeyRegistration provides comprehensive tracking

**Trade-offs:**

✅ **Pros:**
- Deterministic tests
- Fast test execution
- Verifiable parameters
- Easy failure scenario testing
- No system dependencies in tests

❌ **Cons:**
- Slightly more code (protocol + implementation)
- One extra level of indirection
- Real Carbon Events integration not tested (acceptable - system API)

**Validation:**
- All 15 tests pass
- Full suite passes (70+ tests)
- No performance impact
- No API changes

**Status:** ✅ Implemented and verified


//
//  HotkeyManagerTests.swift
//  PindropTests
//
//  Created on 2026-01-25.
//

import Carbon
import CoreGraphics
import Testing
@testable import Pindrop

// MARK: - Mock Hotkey Registration

final class MockHotkeyRegistration: HotkeyRegistrationProtocol {
    var registeredHotkeys: [(id: UInt32, keyCode: UInt32, modifiers: UInt32)] = []
    var unregisteredIds: [UInt32] = []
    var shouldSucceed = true
    var registerCallCount = 0
    var unregisterCallCount = 0

    func registerHotkey(id: UInt32, keyCode: UInt32, modifiers: UInt32) -> Bool {
        registerCallCount += 1
        guard shouldSucceed else { return false }
        registeredHotkeys.append((id, keyCode, modifiers))
        return true
    }

    func unregisterHotkey(id: UInt32) -> Bool {
        unregisterCallCount += 1
        guard shouldSucceed else { return false }
        unregisteredIds.append(id)
        registeredHotkeys.removeAll { $0.id == id }
        return true
    }

    func reset() {
        registeredHotkeys.removeAll()
        unregisteredIds.removeAll()
        shouldSucceed = true
        registerCallCount = 0
        unregisterCallCount = 0
    }
}

@Suite(.serialized)
struct HotkeyManagerTests {
    private typealias Fixture = (hotkeyManager: HotkeyManager, mockRegistration: MockHotkeyRegistration)

    private func makeFixture() -> Fixture {
        let mockRegistration = MockHotkeyRegistration()
        let hotkeyManager = HotkeyManager(registration: mockRegistration)
        return (hotkeyManager, mockRegistration)
    }

    private func waitUntil(_ condition: @escaping @autoclosure () -> Bool) async {
        for _ in 0..<20 {
            if condition() {
                return
            }
            await Task.yield()
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    @Test func registerHotkey() {
        let fixture = makeFixture()
        let callback: () -> Void = {}

        let result = fixture.hotkeyManager.registerHotkey(
            keyCode: 49,
            modifiers: [.option],
            identifier: "toggle",
            onKeyDown: callback
        )

        #expect(result)
        #expect(fixture.hotkeyManager.isHotkeyRegistered(identifier: "toggle"))
        #expect(fixture.mockRegistration.registerCallCount == 1)
        #expect(fixture.mockRegistration.registeredHotkeys.count == 1)
        #expect(fixture.mockRegistration.registeredHotkeys[0].keyCode == 49)
        #expect(fixture.mockRegistration.registeredHotkeys[0].modifiers == UInt32(optionKey))
    }

    @Test func registerMultipleHotkeys() {
        let fixture = makeFixture()
        let callback1: () -> Void = {}
        let callback2: () -> Void = {}

        let result1 = fixture.hotkeyManager.registerHotkey(
            keyCode: 49,
            modifiers: [.option],
            identifier: "toggle",
            onKeyDown: callback1
        )

        let result2 = fixture.hotkeyManager.registerHotkey(
            keyCode: 50,
            modifiers: [.command, .shift],
            identifier: "pushToTalk",
            mode: .pushToTalk,
            onKeyDown: callback2,
            onKeyUp: callback2
        )

        #expect(result1)
        #expect(result2)
        #expect(fixture.hotkeyManager.isHotkeyRegistered(identifier: "toggle"))
        #expect(fixture.hotkeyManager.isHotkeyRegistered(identifier: "pushToTalk"))
    }

    @Test func registerDuplicateIdentifier() {
        let fixture = makeFixture()
        let callback: () -> Void = {}

        _ = fixture.hotkeyManager.registerHotkey(
            keyCode: 49,
            modifiers: [.option],
            identifier: "toggle",
            onKeyDown: callback
        )

        let result = fixture.hotkeyManager.registerHotkey(
            keyCode: 50,
            modifiers: [.command],
            identifier: "toggle",
            onKeyDown: callback
        )

        #expect(!result)
        #expect(fixture.mockRegistration.registerCallCount == 1)
    }

    @Test func registerHotkeyFailure() {
        let fixture = makeFixture()
        fixture.mockRegistration.shouldSucceed = false
        let callback: () -> Void = {}

        let result = fixture.hotkeyManager.registerHotkey(
            keyCode: 49,
            modifiers: [.option],
            identifier: "toggle",
            onKeyDown: callback
        )

        #expect(!result)
        #expect(!fixture.hotkeyManager.isHotkeyRegistered(identifier: "toggle"))
        #expect(fixture.mockRegistration.registerCallCount == 1)
    }

    @Test func unregisterHotkeyFailure() {
        let fixture = makeFixture()
        let callback: () -> Void = {}

        _ = fixture.hotkeyManager.registerHotkey(
            keyCode: 49,
            modifiers: [.option],
            identifier: "toggle",
            onKeyDown: callback
        )

        fixture.mockRegistration.shouldSucceed = false
        let result = fixture.hotkeyManager.unregisterHotkey(identifier: "toggle")

        #expect(!result)
        #expect(fixture.hotkeyManager.isHotkeyRegistered(identifier: "toggle"))
    }

    @Test func unregisterHotkey() {
        let fixture = makeFixture()
        let callback: () -> Void = {}

        _ = fixture.hotkeyManager.registerHotkey(
            keyCode: 49,
            modifiers: [.option],
            identifier: "toggle",
            onKeyDown: callback
        )

        let result = fixture.hotkeyManager.unregisterHotkey(identifier: "toggle")

        #expect(result)
        #expect(!fixture.hotkeyManager.isHotkeyRegistered(identifier: "toggle"))
        #expect(fixture.mockRegistration.unregisterCallCount == 1)
        #expect(fixture.mockRegistration.unregisteredIds.count == 1)
    }

    @Test func unregisterNonexistentHotkey() {
        let fixture = makeFixture()
        let result = fixture.hotkeyManager.unregisterHotkey(identifier: "nonexistent")

        #expect(!result)
        #expect(fixture.mockRegistration.unregisterCallCount == 0)
    }

    @Test func unregisterAll() {
        let fixture = makeFixture()
        let callback: () -> Void = {}

        _ = fixture.hotkeyManager.registerHotkey(keyCode: 49, modifiers: [.option], identifier: "toggle", onKeyDown: callback)
        _ = fixture.hotkeyManager.registerHotkey(keyCode: 50, modifiers: [.command], identifier: "pushToTalk", onKeyDown: callback)

        fixture.hotkeyManager.unregisterAll()

        #expect(!fixture.hotkeyManager.isHotkeyRegistered(identifier: "toggle"))
        #expect(!fixture.hotkeyManager.isHotkeyRegistered(identifier: "pushToTalk"))
        #expect(fixture.mockRegistration.unregisterCallCount == 2)
        #expect(fixture.mockRegistration.unregisteredIds.count == 2)
    }

    @Test func getHotkeyConfiguration() {
        let fixture = makeFixture()
        let callback: () -> Void = {}

        _ = fixture.hotkeyManager.registerHotkey(
            keyCode: 49,
            modifiers: [.option],
            identifier: "toggle",
            onKeyDown: callback
        )

        let config = fixture.hotkeyManager.getHotkeyConfiguration(identifier: "toggle")

        #expect(config != nil)
        #expect(config?.keyCode == 49)
        #expect(config?.modifiers == [.option])
        #expect(config?.identifier == "toggle")
    }

    @Test func getNonexistentConfiguration() {
        let fixture = makeFixture()
        let config = fixture.hotkeyManager.getHotkeyConfiguration(identifier: "nonexistent")
        #expect(config == nil)
    }

    @Test func modifierFlagsConversion() {
        let fixture = makeFixture()
        let testCases: [(HotkeyManager.ModifierFlags, UInt32)] = [
            ([.command], UInt32(cmdKey)),
            ([.option], UInt32(optionKey)),
            ([.shift], UInt32(shiftKey)),
            ([.control], UInt32(controlKey)),
            ([.command, .option], UInt32(cmdKey | optionKey)),
            ([.command, .shift, .option], UInt32(cmdKey | shiftKey | optionKey))
        ]

        for (flags, expected) in testCases {
            let carbonFlags = fixture.hotkeyManager.convertToCarbonModifiers(flags)
            #expect(carbonFlags == expected, "Modifier conversion failed for \(flags)")
        }
    }

    @Test func pushToTalkKeyDown() {
        let fixture = makeFixture()
        var keyDownCalled = false
        var keyUpCalled = false

        let result = fixture.hotkeyManager.registerHotkey(
            keyCode: 50,
            modifiers: [.command],
            identifier: "pushToTalk",
            mode: .pushToTalk,
            onKeyDown: { keyDownCalled = true },
            onKeyUp: { keyUpCalled = true }
        )

        #expect(result)
        #expect(fixture.hotkeyManager.isHotkeyRegistered(identifier: "pushToTalk"))

        let config = fixture.hotkeyManager.getHotkeyConfiguration(identifier: "pushToTalk")
        #expect(config != nil)
        #expect(config?.mode == .pushToTalk)
        #expect(config?.onKeyDown != nil)
        #expect(config?.onKeyUp != nil)
        #expect(!keyDownCalled)
        #expect(!keyUpCalled)
    }

    @Test func pushToTalkKeyUp() {
        let fixture = makeFixture()
        var keyDownCount = 0
        var keyUpCount = 0

        let result = fixture.hotkeyManager.registerHotkey(
            keyCode: 50,
            modifiers: [.command],
            identifier: "pushToTalk",
            mode: .pushToTalk,
            onKeyDown: { keyDownCount += 1 },
            onKeyUp: { keyUpCount += 1 }
        )

        #expect(result)

        let config = fixture.hotkeyManager.getHotkeyConfiguration(identifier: "pushToTalk")
        #expect(config != nil)
        #expect(config?.mode == .pushToTalk)
        #expect(keyDownCount == 0)
        #expect(keyUpCount == 0)
    }

    @Test func toggleModeBackwardCompatibility() {
        var callbackInvoked = false

        let callback: () -> Void = {
            callbackInvoked = true
        }

        let config = HotkeyManager.HotkeyConfiguration(
            keyCode: 49,
            modifiers: [.option],
            identifier: "toggle",
            callback: callback
        )

        #expect(config.mode == .toggle)
        #expect(config.onKeyDown != nil)
        #expect(config.onKeyUp == nil)
        #expect(!callbackInvoked)
    }

    @Test func pushToTalkModeConfiguration() {
        var keyDownCalled = false
        var keyUpCalled = false

        let config = HotkeyManager.HotkeyConfiguration(
            keyCode: 50,
            modifiers: [.command],
            identifier: "pushToTalk",
            mode: .pushToTalk,
            onKeyDown: { keyDownCalled = true },
            onKeyUp: { keyUpCalled = true }
        )

        #expect(config.mode == .pushToTalk)
        #expect(config.onKeyDown != nil)
        #expect(config.onKeyUp != nil)

        config.onKeyDown?()
        #expect(keyDownCalled)

        config.onKeyUp?()
        #expect(keyUpCalled)
    }

    @Test func registerModifierOnlyHotkeySkipsCarbonRegistration() {
        let fixture = makeFixture()

        let result = fixture.hotkeyManager.registerHotkey(
            keyCode: 54,
            modifiers: [.command],
            identifier: "rightCommand",
            mode: .pushToTalk,
            onKeyDown: nil,
            onKeyUp: nil
        )

        #expect(result)
        #expect(fixture.mockRegistration.registerCallCount == 0)
    }

    @Test func registerFnModifierOnlyHotkeySkipsCarbonRegistration() {
        let fixture = makeFixture()

        let result = fixture.hotkeyManager.registerHotkey(
            keyCode: UInt32(kVK_Function),
            modifiers: [.function],
            identifier: "fnOnly",
            mode: .pushToTalk,
            onKeyDown: nil,
            onKeyUp: nil
        )

        #expect(result)
        #expect(fixture.mockRegistration.registerCallCount == 0)
    }

    @Test func modifierOnlyPushToTalkKeyDownAndUp() async throws {
        let fixture = makeFixture()
        var keyDownCount = 0
        var keyUpCount = 0

        let result = fixture.hotkeyManager.registerHotkey(
            keyCode: 54,
            modifiers: [.command],
            identifier: "rightCommandPTT",
            mode: .pushToTalk,
            onKeyDown: { keyDownCount += 1 },
            onKeyUp: { keyUpCount += 1 }
        )

        #expect(result)

        let source = try #require(CGEventSource(stateID: .hidSystemState), "Failed to create CGEventSource")
        let keyDownEvent = try #require(
            CGEvent(keyboardEventSource: source, virtualKey: 54, keyDown: true),
            "Failed to create keyDown CGEvent"
        )
        keyDownEvent.flags = .maskCommand
        fixture.hotkeyManager.handleModifierFlagsChanged(event: keyDownEvent)

        let keyUpEvent = try #require(
            CGEvent(keyboardEventSource: source, virtualKey: 54, keyDown: false),
            "Failed to create keyUp CGEvent"
        )
        keyUpEvent.flags = []
        fixture.hotkeyManager.handleModifierFlagsChanged(event: keyUpEvent)
        await waitUntil(keyDownCount == 1 && keyUpCount == 1)

        #expect(keyDownCount == 1)
        #expect(keyUpCount == 1)
    }

    @Test func fnOnlyPushToTalkKeyDownAndUp() async throws {
        let fixture = makeFixture()
        var keyDownCount = 0
        var keyUpCount = 0

        let result = fixture.hotkeyManager.registerHotkey(
            keyCode: UInt32(kVK_Function),
            modifiers: [.function],
            identifier: "fnPTT",
            mode: .pushToTalk,
            onKeyDown: { keyDownCount += 1 },
            onKeyUp: { keyUpCount += 1 }
        )

        #expect(result)

        let source = try #require(CGEventSource(stateID: .hidSystemState), "Failed to create CGEventSource")
        let keyDownEvent = try #require(
            CGEvent(
                keyboardEventSource: source,
                virtualKey: CGKeyCode(kVK_Function),
                keyDown: true
            ),
            "Failed to create Fn keyDown CGEvent"
        )
        keyDownEvent.flags = .maskSecondaryFn
        fixture.hotkeyManager.handleModifierFlagsChanged(event: keyDownEvent)

        let keyUpEvent = try #require(
            CGEvent(
                keyboardEventSource: source,
                virtualKey: CGKeyCode(kVK_Function),
                keyDown: false
            ),
            "Failed to create Fn keyUp CGEvent"
        )
        keyUpEvent.flags = []
        fixture.hotkeyManager.handleModifierFlagsChanged(event: keyUpEvent)
        await waitUntil(keyDownCount == 1 && keyUpCount == 1)

        #expect(keyDownCount == 1)
        #expect(keyUpCount == 1)
    }

    @Test func suppressedDispatchSkipsModifierOnlyCallbacks() async throws {
        let fixture = makeFixture()

        let result = fixture.hotkeyManager.registerHotkey(
            keyCode: 54,
            modifiers: [.command],
            identifier: "suppressedModifierPTT",
            mode: .pushToTalk,
            onKeyDown: nil,
            onKeyUp: nil
        )

        #expect(result)
        fixture.hotkeyManager.setEventDispatchSuppressed(true)

        let source = try #require(CGEventSource(stateID: .hidSystemState), "Failed to create CGEventSource")

        await confirmation("Modifier key down should be suppressed", expectedCount: 0) { unexpectedKeyDown in
            await confirmation("Modifier key up should be suppressed", expectedCount: 0) { unexpectedKeyUp in
                _ = fixture.hotkeyManager.unregisterHotkey(identifier: "suppressedModifierPTT")
                _ = fixture.hotkeyManager.registerHotkey(
                    keyCode: 54,
                    modifiers: [.command],
                    identifier: "suppressedModifierPTT",
                    mode: .pushToTalk,
                    onKeyDown: { unexpectedKeyDown() },
                    onKeyUp: { unexpectedKeyUp() }
                )

                guard let keyDownEvent = CGEvent(keyboardEventSource: source, virtualKey: 54, keyDown: true),
                      let keyUpEvent = CGEvent(keyboardEventSource: source, virtualKey: 54, keyDown: false) else {
                    Issue.record("Failed to create modifier CGEvents")
                    return
                }
                keyDownEvent.flags = .maskCommand
                keyUpEvent.flags = []
                fixture.hotkeyManager.handleModifierFlagsChanged(event: keyDownEvent)
                fixture.hotkeyManager.handleModifierFlagsChanged(event: keyUpEvent)
            }
        }
    }

    @Test func suppressingDispatchReleasesPressedPushToTalkHotkey() async throws {
        let fixture = makeFixture()
        var keyDownCount = 0
        var keyUpCount = 0

        let result = fixture.hotkeyManager.registerHotkey(
            keyCode: 54,
            modifiers: [.command],
            identifier: "suppressionReleasePTT",
            mode: .pushToTalk,
            onKeyDown: { keyDownCount += 1 },
            onKeyUp: { keyUpCount += 1 }
        )

        #expect(result)

        let source = try #require(CGEventSource(stateID: .hidSystemState), "Failed to create CGEventSource")
        let keyDownEvent = try #require(
            CGEvent(keyboardEventSource: source, virtualKey: 54, keyDown: true),
            "Failed to create keyDown CGEvent"
        )
        keyDownEvent.flags = .maskCommand
        fixture.hotkeyManager.handleModifierFlagsChanged(event: keyDownEvent)
        await waitUntil(keyDownCount == 1)
        fixture.hotkeyManager.setEventDispatchSuppressed(true)
        await waitUntil(keyUpCount == 1)

        #expect(keyDownCount == 1)
        #expect(keyUpCount == 1)
    }

    @Test func hotkeyRegistrationStateRequiresOnboardingCompletion() {
        #expect(!HotkeyRegistrationState.shouldRegisterHotkeys(hasCompletedOnboarding: false))
        #expect(HotkeyRegistrationState.shouldRegisterHotkeys(hasCompletedOnboarding: true))
    }

    @Test func hotkeyRegistrationStateRegistersUniqueCombinations() {
        var state = HotkeyRegistrationState()

        let firstConflict = state.register(
            identifier: "push-to-talk",
            keyCode: 54,
            modifiers: UInt32(cmdKey)
        )
        let secondConflict = state.register(
            identifier: "toggle-recording",
            keyCode: 55,
            modifiers: UInt32(cmdKey)
        )

        #expect(firstConflict == nil)
        #expect(secondConflict == nil)
        #expect(state.registeredIdentifiersByCombination.count == 2)
    }

    @Test func hotkeyRegistrationStateDetectsCombinationConflicts() {
        var state = HotkeyRegistrationState()
        _ = state.register(
            identifier: "push-to-talk",
            keyCode: 54,
            modifiers: UInt32(cmdKey)
        )

        let conflict = state.register(
            identifier: "toggle-recording",
            keyCode: 54,
            modifiers: UInt32(cmdKey)
        )

        #expect(conflict?.existingIdentifier == "push-to-talk")
        #expect(conflict?.incomingIdentifier == "toggle-recording")
        #expect(conflict?.combination == HotkeyRegistrationState.Combination(keyCode: 54, modifiers: UInt32(cmdKey)))
        #expect(state.registeredIdentifiersByCombination.count == 1)
    }

    @Test func hotkeyConflictKeyIsStableAcrossIdentifierOrder() {
        let combination = HotkeyRegistrationState.Combination(
            keyCode: 54,
            modifiers: UInt32(cmdKey)
        )
        let first = HotkeyConflict(
            existingIdentifier: "push-to-talk",
            incomingIdentifier: "toggle-recording",
            combination: combination
        )
        let second = HotkeyConflict(
            existingIdentifier: "toggle-recording",
            incomingIdentifier: "push-to-talk",
            combination: combination
        )

        #expect(first.conflictKey == second.conflictKey)
        #expect(first.conflictKey == "push-to-talk|toggle-recording|54|256")
    }
}

//
//  InputMuteMonitorTests.swift
//  PindropTests
//
//  Created on 2026-07-09.
//

import CoreAudio
import Foundation
import Testing
@testable import Pindrop

@MainActor
private final class MockInputDeviceMuteReader: InputDeviceMuteReading {
    var resolvedDeviceID: AudioDeviceID? = 42
    /// `nil` means the device does not support mute/volume observation.
    var muteResult: Bool? = false
    private(set) var preferredUIDsRequested: [String?] = []
    private(set) var addedMuteListeners = 0
    private(set) var removedMuteListeners = 0
    private(set) var addedDefaultListeners = 0
    private(set) var removedDefaultListeners = 0

    private var muteBlock: AudioObjectPropertyListenerBlock?
    private var defaultBlock: AudioObjectPropertyListenerBlock?

    func resolveDeviceID(preferredUID: String?) -> AudioDeviceID? {
        preferredUIDsRequested.append(preferredUID)
        return resolvedDeviceID
    }

    func readIsMuted(deviceID: AudioDeviceID) -> Bool? {
        _ = deviceID
        return muteResult
    }

    func addMuteListener(
        deviceID: AudioDeviceID,
        queue: DispatchQueue,
        block: @escaping AudioObjectPropertyListenerBlock
    ) -> OSStatus {
        _ = deviceID
        _ = queue
        addedMuteListeners += 1
        muteBlock = block
        return noErr
    }

    func removeMuteListener(
        deviceID: AudioDeviceID,
        queue: DispatchQueue,
        block: AudioObjectPropertyListenerBlock
    ) {
        _ = deviceID
        _ = queue
        _ = block
        removedMuteListeners += 1
        muteBlock = nil
    }

    func addDefaultInputListener(
        queue: DispatchQueue,
        block: @escaping AudioObjectPropertyListenerBlock
    ) -> OSStatus {
        _ = queue
        addedDefaultListeners += 1
        defaultBlock = block
        return noErr
    }

    func removeDefaultInputListener(
        queue: DispatchQueue,
        block: AudioObjectPropertyListenerBlock
    ) {
        _ = queue
        _ = block
        removedDefaultListeners += 1
        defaultBlock = nil
    }

    func simulateMuteChange(muted: Bool?) {
        muteResult = muted
        var address = AudioObjectPropertyAddress(
            mSelector: AudioObjectPropertySelector(kAudioDevicePropertyMute),
            mScope: AudioObjectPropertyScope(kAudioDevicePropertyScopeInput),
            mElement: AudioObjectPropertyElement(kAudioObjectPropertyElementMain)
        )
        withUnsafePointer(to: &address) { pointer in
            muteBlock?(1, pointer)
        }
    }

    func simulateDefaultInputChange() {
        var address = AudioObjectPropertyAddress(
            mSelector: AudioObjectPropertySelector(kAudioHardwarePropertyDefaultInputDevice),
            mScope: AudioObjectPropertyScope(kAudioObjectPropertyScopeGlobal),
            mElement: AudioObjectPropertyElement(kAudioObjectPropertyElementMain)
        )
        withUnsafePointer(to: &address) { pointer in
            defaultBlock?(1, pointer)
        }
    }
}

@MainActor
@Suite
struct InputMuteMonitorTests {

    @Test func startReadsInitialMuteStateAndPublishesChanges() async {
        let reader = MockInputDeviceMuteReader()
        reader.muteResult = false
        let sut = InputMuteMonitor(preferredDeviceUID: "mic-1", reader: reader)
        var published: [Bool] = []
        sut.onMuteStateChange = { published.append($0) }

        sut.start()
        #expect(sut.isMuted == false)
        #expect(reader.addedMuteListeners == 1)
        #expect(reader.addedDefaultListeners == 1)

        reader.simulateMuteChange(muted: true)
        await waitUntil { sut.isMuted }

        #expect(sut.isMuted == true)
        #expect(published == [true])
    }

    @Test func unsupportedMutePropertyTreatsAsUnmuted() {
        let reader = MockInputDeviceMuteReader()
        reader.muteResult = nil
        let sut = InputMuteMonitor(preferredDeviceUID: nil, reader: reader)

        var published: [Bool] = []
        sut.onMuteStateChange = { published.append($0) }
        sut.start()

        #expect(sut.isMuted == false)
        // Initial state is already false; no change is published.
        #expect(published.isEmpty)
    }

    @Test func setPreferredDeviceUIDRebinds() async {
        let reader = MockInputDeviceMuteReader()
        reader.muteResult = false
        let sut = InputMuteMonitor(preferredDeviceUID: "a", reader: reader)
        sut.start()

        reader.resolvedDeviceID = 7
        reader.muteResult = true
        sut.setPreferredDeviceUID("b")

        #expect(reader.removedMuteListeners >= 1)
        #expect(sut.isMuted == true)
        #expect(reader.preferredUIDsRequested.contains("b"))
    }

    @Test func stopRemovesListeners() {
        let reader = MockInputDeviceMuteReader()
        let sut = InputMuteMonitor(reader: reader)
        sut.start()
        sut.stop()

        #expect(reader.removedMuteListeners >= 1)
        #expect(reader.removedDefaultListeners >= 1)
        #expect(sut.isMuted == false)
    }

    private func waitUntil(
        timeoutMs: Int = 500,
        condition: @MainActor () -> Bool
    ) async {
        let steps = max(timeoutMs / 10, 1)
        for _ in 0..<steps {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
    }
}

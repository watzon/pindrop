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
    private(set) var muteReadCount = 0
    private(set) var addedMuteListeners = 0
    private(set) var removedMuteListeners = 0
    private(set) var addedDefaultListeners = 0
    private(set) var removedDefaultListeners = 0

    private var muteBlock: AudioObjectPropertyListenerBlock?
    private var defaultBlock: AudioObjectPropertyListenerBlock?

    /// One-shot stream continuation resumed the next time `resolveDeviceID` is entered.
    private var nextResolveContinuation: AsyncStream<String?>.Continuation?

    func resolveDeviceID(preferredUID: String?) -> AudioDeviceID? {
        preferredUIDsRequested.append(preferredUID)
        if let continuation = nextResolveContinuation {
            nextResolveContinuation = nil
            continuation.yield(preferredUID)
            continuation.finish()
        }
        return resolvedDeviceID
    }

    /// Returns a one-shot stream whose continuation is installed *before* return,
    /// so a later same-actor `resolveDeviceID` cannot race past an unarmed waiter.
    func nextDeviceResolveStream() -> AsyncStream<String?> {
        let (stream, continuation) = AsyncStream<String?>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
        precondition(nextResolveContinuation == nil, "only one resolve waiter is supported")
        nextResolveContinuation = continuation
        return stream
    }

    func readIsMuted(deviceID: AudioDeviceID) -> Bool? {
        _ = deviceID
        muteReadCount += 1
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

    @Test func setPreferredDeviceUIDNormalizesEmptyAndNilWithoutChurn() {
        let reader = MockInputDeviceMuteReader()
        reader.muteResult = false
        let sut = InputMuteMonitor(preferredDeviceUID: "mic-1", reader: reader)
        sut.start()

        #expect(reader.preferredUIDsRequested == ["mic-1"])
        let addedMuteAfterStart = reader.addedMuteListeners
        let removedMuteAfterStart = reader.removedMuteListeners
        let readsAfterStart = reader.muteReadCount

        // Empty normalizes to nil and rebinds once away from "mic-1".
        // Assert the full sequence so an empty array cannot pass as "last == nil".
        sut.setPreferredDeviceUID("")
        #expect(reader.preferredUIDsRequested == ["mic-1", nil])
        #expect(reader.removedMuteListeners == removedMuteAfterStart + 1)
        #expect(reader.addedMuteListeners == addedMuteAfterStart + 1)
        #expect(reader.muteReadCount == readsAfterStart + 1)

        let resolveAfterEmpty = reader.preferredUIDsRequested.count
        let addedMuteAfterEmpty = reader.addedMuteListeners
        let removedMuteAfterEmpty = reader.removedMuteListeners
        let readsAfterEmpty = reader.muteReadCount

        // Same logical UID (nil / empty) must not tear down, reinstall, or re-read.
        sut.setPreferredDeviceUID(nil)
        sut.setPreferredDeviceUID("")
        sut.setPreferredDeviceUID(nil)

        #expect(reader.preferredUIDsRequested.count == resolveAfterEmpty)
        #expect(reader.addedMuteListeners == addedMuteAfterEmpty)
        #expect(reader.removedMuteListeners == removedMuteAfterEmpty)
        #expect(reader.muteReadCount == readsAfterEmpty)
    }

    @Test func setPreferredDeviceUIDSameUIDPerformsZeroListenerChurn() {
        let reader = MockInputDeviceMuteReader()
        reader.muteResult = true
        let sut = InputMuteMonitor(preferredDeviceUID: "built-in", reader: reader)
        sut.start()

        let resolveAfterStart = reader.preferredUIDsRequested.count
        let addedMuteAfterStart = reader.addedMuteListeners
        let removedMuteAfterStart = reader.removedMuteListeners
        let addedDefaultAfterStart = reader.addedDefaultListeners
        let removedDefaultAfterStart = reader.removedDefaultListeners
        let readsAfterStart = reader.muteReadCount
        #expect(sut.isMuted == true)

        sut.setPreferredDeviceUID("built-in")
        sut.setPreferredDeviceUID("built-in")

        #expect(reader.preferredUIDsRequested.count == resolveAfterStart)
        #expect(reader.addedMuteListeners == addedMuteAfterStart)
        #expect(reader.removedMuteListeners == removedMuteAfterStart)
        #expect(reader.addedDefaultListeners == addedDefaultAfterStart)
        #expect(reader.removedDefaultListeners == removedDefaultAfterStart)
        #expect(reader.muteReadCount == readsAfterStart)
        #expect(sut.isMuted == true)
    }

    @Test func emptyPreferredUIDOnInitNormalizesToNil() {
        let reader = MockInputDeviceMuteReader()
        let sut = InputMuteMonitor(preferredDeviceUID: "", reader: reader)

        sut.start()

        #expect(reader.preferredUIDsRequested == [nil])

        let resolveAfterStart = reader.preferredUIDsRequested.count
        let addedMuteAfterStart = reader.addedMuteListeners
        let removedMuteAfterStart = reader.removedMuteListeners
        let readsAfterStart = reader.muteReadCount

        // Empty and nil remain the same logical preference after init normalization.
        sut.setPreferredDeviceUID("")
        sut.setPreferredDeviceUID(nil)

        #expect(reader.preferredUIDsRequested.count == resolveAfterStart)
        #expect(reader.addedMuteListeners == addedMuteAfterStart)
        #expect(reader.removedMuteListeners == removedMuteAfterStart)
        #expect(reader.muteReadCount == readsAfterStart)
    }

    @Test
    func defaultInputChangeStillRebindsDespiteUIDNoOp() async {
        let reader = MockInputDeviceMuteReader()
        reader.muteResult = false
        let sut = InputMuteMonitor(preferredDeviceUID: "mic-1", reader: reader)
        sut.start()

        // Same logical UID is a no-op — hardware/default callbacks must still rebind.
        sut.setPreferredDeviceUID("mic-1")

        let resolveAfterStart = reader.preferredUIDsRequested.count
        let addedMuteAfterStart = reader.addedMuteListeners
        let removedMuteAfterStart = reader.removedMuteListeners
        let readsAfterStart = reader.muteReadCount

        reader.resolvedDeviceID = 99
        reader.muteResult = true

        // Default-input listener hops via Task { @MainActor }. Arm the one-shot
        // resolve stream *synchronously* (`makeStream` installs the continuation
        // before return) so the rebind event cannot be lost, then await one yield.
        var resolveEvents = reader.nextDeviceResolveStream().makeAsyncIterator()
        reader.simulateDefaultInputChange()
        // `next()` is `String??` because the stream element is already optional.
        let preferredUID = await resolveEvents.next() ?? nil

        #expect(preferredUID == "mic-1")
        #expect(reader.preferredUIDsRequested.count == resolveAfterStart + 1)
        #expect(reader.preferredUIDsRequested.last == "mic-1")
        #expect(reader.removedMuteListeners == removedMuteAfterStart + 1)
        #expect(reader.addedMuteListeners == addedMuteAfterStart + 1)
        #expect(reader.muteReadCount == readsAfterStart + 1)
        #expect(sut.isMuted == true)
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

    @Test func deinitRemovesListenersWithoutExplicitStop() async {
        let reader = MockInputDeviceMuteReader()
        do {
            let sut = InputMuteMonitor(reader: reader)
            sut.start()
            #expect(reader.addedMuteListeners == 1)
            #expect(reader.addedDefaultListeners == 1)
            // Leave scope without stop() — deinit must tear down listeners.
            _ = sut
        }
        // Mock remove is notified via a MainActor Task hop from nonisolated tearDown.
        await waitUntil {
            reader.removedMuteListeners >= 1 && reader.removedDefaultListeners >= 1
        }
        #expect(reader.removedMuteListeners >= 1)
        #expect(reader.removedDefaultListeners >= 1)
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

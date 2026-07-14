//
//  AudioRecorderTests.swift
//  PindropTests
//
//  Created on 2026-01-25.
//

import AVFoundation
import Testing
@testable import Pindrop

@MainActor
@Suite
struct AudioRecorderTests {
    private typealias Fixture = (
        sut: AudioRecorder,
        mockPermission: MockPermissionProvider,
        mockBackend: MockAudioCaptureBackend,
        mockSystemBackend: MockAudioCaptureBackend
    )

    private func makeFixture() throws -> Fixture {
        let mockPermission = MockPermissionProvider()
        let mockBackend = MockAudioCaptureBackend(identifier: "microphone")
        let mockSystemBackend = MockAudioCaptureBackend(identifier: "system")
        let sut = try AudioRecorder(
            permissionManager: mockPermission,
            captureBackend: mockBackend,
            systemAudioCaptureBackend: mockSystemBackend
        )
        return (sut, mockPermission, mockBackend, mockSystemBackend)
    }

    @Test func audioRecorderInitialization() throws {
        let fixture = try makeFixture()
        #expect(fixture.sut.isRecording == false)
    }

    @Test func startRecordingRequestsPermission() async throws {
        let fixture = try makeFixture()
        fixture.mockPermission.grantPermission = true

        try await fixture.sut.startRecording()

        #expect(fixture.mockPermission.requestPermissionCallCount == 1)
    }

    @Test func startSystemAudioRecordingRequestsSystemPermissionOnly() async throws {
        let fixture = try makeFixture()

        try await fixture.sut.startRecording(configuration: AudioRecordingConfiguration(mode: .systemAudio))

        #expect(fixture.mockPermission.requestPermissionCallCount == 0)
        #expect(fixture.mockPermission.requestSystemAudioPermissionCallCount == 1)
        #expect(fixture.mockSystemBackend.startCaptureCallCount == 1)
    }

    @Test func startMixedRecordingRequestsBothPermissions() async throws {
        let fixture = try makeFixture()

        try await fixture.sut.startRecording(configuration: AudioRecordingConfiguration(mode: .microphoneAndSystemAudio))

        #expect(fixture.mockPermission.requestPermissionCallCount == 1)
        #expect(fixture.mockPermission.requestSystemAudioPermissionCallCount == 1)
        #expect(fixture.mockBackend.startCaptureCallCount == 1)
        #expect(fixture.mockSystemBackend.startCaptureCallCount == 1)
    }

    @Test func startRecordingSetsIsRecordingFlag() async throws {
        let fixture = try makeFixture()
        fixture.mockPermission.grantPermission = true

        #expect(fixture.sut.isRecording == false)

        try await fixture.sut.startRecording()

        #expect(fixture.sut.isRecording)
        #expect(fixture.mockBackend.startCaptureCallCount == 1)
    }

    @Test func startRecordingForwardsAudioBufferCallback() async throws {
        let fixture = try makeFixture()
        fixture.mockPermission.grantPermission = true
        let sampleBuffer = try #require(
            MockAudioCaptureBackend.makeSynthesizedBuffer(format: fixture.mockBackend.targetFormat),
            "Expected synthesized sample buffer"
        )
        var receivedFrameLength: AVAudioFrameCount?

        fixture.sut.onAudioBuffer = { buffer in
            receivedFrameLength = buffer.frameLength
        }

        try await fixture.sut.startRecording()
        fixture.mockBackend.capturedOnBuffer?(sampleBuffer)
        await Task.yield()
        await Task.yield()

        #expect(receivedFrameLength == sampleBuffer.frameLength)
    }

    @Test func concurrentStartRecordingOnlyRequestsPermissionOnce() async throws {
        let fixture = try makeFixture()
        fixture.mockPermission.grantPermission = true
        fixture.mockPermission.delayNanoseconds = 50_000_000

        async let firstStartResult = fixture.sut.startRecording()
        async let secondStartResult = fixture.sut.startRecording()

        let firstResult = try await firstStartResult
        let secondResult = try await secondStartResult

        let successfulStarts = [firstResult, secondResult].filter { $0 }.count
        #expect(successfulStarts == 1)
        #expect(fixture.mockPermission.requestPermissionCallCount == 1)
        #expect(fixture.mockBackend.startCaptureCallCount == 1)
        #expect(fixture.sut.isRecording)
    }

    @Test func stopRecordingReturnsAudioData() async throws {
        let fixture = try makeFixture()
        fixture.mockPermission.grantPermission = true
        let buffer = try #require(
            MockAudioCaptureBackend.makeSynthesizedBuffer(format: fixture.mockBackend.targetFormat),
            "Expected synthesized audio buffer"
        )
        fixture.mockBackend.simulatedBuffers = [buffer]

        try await fixture.sut.startRecording()
        let audioData = try await fixture.sut.stopRecording()

        #expect(audioData.count > 0)
        #expect(fixture.sut.isRecording == false)
        #expect(fixture.mockBackend.stopCaptureCallCount == 1)
    }

    @Test func stopRecordingPreservesAllPCMBytesAcrossBuffers() async throws {
        let fixture = try makeFixture()
        fixture.mockPermission.grantPermission = true
        let firstBuffer = try #require(
            MockAudioCaptureBackend.makeSynthesizedBuffer(
                format: fixture.mockBackend.targetFormat,
                frameCount: 8,
                frequency: 100
            )
        )
        let secondBuffer = try #require(
            MockAudioCaptureBackend.makeSynthesizedBuffer(
                format: fixture.mockBackend.targetFormat,
                frameCount: 8,
                frequency: 200
            )
        )
        fixture.mockBackend.simulatedBuffers = [firstBuffer, secondBuffer]

        try await fixture.sut.startRecording()
        let data = try await fixture.sut.stopRecording()

        let expected = [firstBuffer, secondBuffer].reduce(into: Data()) { data, buffer in
            data.append(contentsOf:
                UnsafeRawBufferPointer(
                    start: buffer.floatChannelData![0],
                    count: Int(buffer.frameLength) * MemoryLayout<Float>.size
                )
            )
        }
        #expect(data == expected)
    }

    @Test func stopRecordingWithoutStartingThrowsError() async throws {
        let fixture = try makeFixture()

        do {
            _ = try await fixture.sut.stopRecording()
            Issue.record("Should have thrown notRecording error")
        } catch AudioRecorderError.notRecording {
        } catch {
            Issue.record("Unexpected error: \(error.localizedDescription)")
        }
    }

    @Test func audioFormatConfiguration() throws {
        let fixture = try makeFixture()
        let format = fixture.sut.targetFormat

        #expect(format.sampleRate == 16000.0)
        #expect(format.channelCount == 1)
        #expect(format.commonFormat == .pcmFormatFloat32)
    }

    @Test func multipleRecordingSessions() async throws {
        let fixture = try makeFixture()
        fixture.mockPermission.grantPermission = true
        let buffer = try #require(
            MockAudioCaptureBackend.makeSynthesizedBuffer(format: fixture.mockBackend.targetFormat),
            "Expected synthesized audio buffer"
        )
        fixture.mockBackend.simulatedBuffers = [buffer]

        try await fixture.sut.startRecording()
        let firstData = try await fixture.sut.stopRecording()
        #expect(firstData.count > 0)

        fixture.mockBackend.simulatedBuffers = [buffer]

        try await fixture.sut.startRecording()
        let secondData = try await fixture.sut.stopRecording()
        #expect(secondData.count > 0)

        #expect(fixture.mockBackend.startCaptureCallCount == 2)
        #expect(fixture.mockBackend.stopCaptureCallCount == 2)
    }

    @Test func startRecordingThrowsWhenPermissionDenied() async throws {
        let fixture = try makeFixture()
        fixture.mockPermission.grantPermission = false

        do {
            try await fixture.sut.startRecording()
            Issue.record("Should have thrown permissionDenied")
        } catch AudioRecorderError.permissionDenied {
        } catch {
            Issue.record("Unexpected error: \(error.localizedDescription)")
        }

        #expect(fixture.sut.isRecording == false)
        #expect(fixture.mockBackend.startCaptureCallCount == 0)
    }

    @Test func startRecordingThrowsWhenSystemAudioPermissionDenied() async throws {
        let fixture = try makeFixture()
        fixture.mockPermission.grantSystemAudioPermission = false

        do {
            try await fixture.sut.startRecording(configuration: AudioRecordingConfiguration(mode: .systemAudio))
            Issue.record("Should have thrown systemAudioPermissionDenied")
        } catch AudioRecorderError.systemAudioPermissionDenied {
        } catch {
            Issue.record("Unexpected error: \(error.localizedDescription)")
        }

        #expect(fixture.mockSystemBackend.startCaptureCallCount == 0)
    }

    @Test func startRecordingThrowsWhenBackendFails() async throws {
        let fixture = try makeFixture()
        fixture.mockPermission.grantPermission = true
        fixture.mockBackend.shouldThrowOnStart = AudioRecorderError.engineStartFailed("Mock engine failure")

        do {
            try await fixture.sut.startRecording()
            Issue.record("Should have thrown engineStartFailed")
        } catch AudioRecorderError.engineStartFailed {
        } catch {
            Issue.record("Unexpected error: \(error.localizedDescription)")
        }

        #expect(fixture.sut.isRecording == false)
    }

    @Test func cancelRecording() async throws {
        let fixture = try makeFixture()
        fixture.mockPermission.grantPermission = true

        try await fixture.sut.startRecording()
        #expect(fixture.sut.isRecording)

        fixture.sut.cancelRecording()

        #expect(fixture.sut.isRecording == false)
        #expect(fixture.mockBackend.cancelCaptureCallCount == 1)
    }

    @Test func resetAudioEngine() async throws {
        let fixture = try makeFixture()
        fixture.mockPermission.grantPermission = true

        try await fixture.sut.startRecording()
        fixture.sut.resetAudioEngine()

        #expect(fixture.sut.isRecording == false)
        #expect(fixture.mockBackend.resetCallCount == 2)
    }

    @Test func setPreferredInputDeviceUIDForwardsSelectionToCaptureBackend() throws {
        let fixture = try makeFixture()

        try fixture.sut.setPreferredInputDeviceUID("usb-mic")

        #expect(fixture.mockBackend.setPreferredInputDeviceUIDCallCount == 1)
        #expect(fixture.mockBackend.lastPreferredInputDeviceUID == "usb-mic")
    }

    @Test func setPreferredInputDeviceUIDCanUpdateActiveCaptureBackend() async throws {
        let fixture = try makeFixture()
        fixture.mockPermission.grantPermission = true

        try await fixture.sut.startRecording()
        try fixture.sut.setPreferredInputDeviceUID("usb-mic")

        #expect(fixture.mockBackend.startCaptureCallCount == 1)
        #expect(fixture.mockBackend.setPreferredInputDeviceUIDCallCount == 1)
        #expect(fixture.mockBackend.lastPreferredInputDeviceUID == "usb-mic")
    }

    @Test func setPreferredInputDeviceUIDIgnoresDuplicateSelection() throws {
        let fixture = try makeFixture()

        try fixture.sut.setPreferredInputDeviceUID("usb-mic")
        try fixture.sut.setPreferredInputDeviceUID("usb-mic")

        #expect(fixture.mockBackend.setPreferredInputDeviceUIDCallCount == 1)
        #expect(fixture.mockBackend.lastPreferredInputDeviceUID == "usb-mic")
    }

    @Test func setPreferredInputDeviceUIDFailurePreservesActiveRecording() async throws {
        let fixture = try makeFixture()
        fixture.mockPermission.grantPermission = true

        try await fixture.sut.startRecording()
        fixture.mockBackend.shouldThrowOnSetPreferredInputDeviceUID = AudioRecorderError.engineStartFailed("switch failed")

        var caughtError: Error?
        do {
            try fixture.sut.setPreferredInputDeviceUID("missing-mic")
        } catch {
            caughtError = error
        }

        #expect(caughtError != nil)
        #expect(fixture.sut.isRecording)
        #expect(fixture.mockBackend.isCapturing)
        #expect(fixture.mockBackend.startCaptureCallCount == 1)
        #expect(fixture.mockBackend.setPreferredInputDeviceUIDCallCount == 1)
    }

    @Test func captureBackendFailureClearsRecordingState() async throws {
        let fixture = try makeFixture()
        fixture.mockPermission.grantPermission = true

        var reportedError: Error?
        fixture.sut.onCaptureError = { error in
            reportedError = error
        }

        try await fixture.sut.startRecording()
        fixture.mockBackend.capturedOnError?(AudioRecorderError.engineStartFailed("device disappeared"))
        await Task.yield()

        #expect(fixture.sut.isRecording == false)
        #expect(fixture.mockBackend.cancelCaptureCallCount == 1)
        #expect(reportedError != nil)
    }

    @Test func captureLimitKeepsRecorderActiveForControlledFinalization() async throws {
        let fixture = try makeFixture()
        fixture.mockPermission.grantPermission = true
        var receivedLimitSignal = false
        fixture.sut.onCaptureError = { error in
            if case .recordingLimitReached = error as? AudioRecorderError {
                receivedLimitSignal = true
            }
        }

        try await fixture.sut.startRecording()
        fixture.mockBackend.capturedOnError?(
            AudioRecorderError.recordingLimitReached(maximumDuration: 600)
        )
        await Task.yield()

        #expect(receivedLimitSignal)
        #expect(fixture.sut.isRecording)
        #expect(fixture.mockBackend.cancelCaptureCallCount == 0)
    }

    @Test func stopRecordingYieldsMainActorWhileBackendFinalizes() async throws {
        let mockPermission = MockPermissionProvider()
        mockPermission.grantPermission = true
        let mockBackend = DelayedMockAudioCaptureBackend()
        let mockSystemBackend = MockAudioCaptureBackend(identifier: "system")
        let sut = try AudioRecorder(
            permissionManager: mockPermission,
            captureBackend: mockBackend,
            systemAudioCaptureBackend: mockSystemBackend
        )

        let buffer = try #require(
            MockAudioCaptureBackend.makeSynthesizedBuffer(format: mockBackend.targetFormat),
            "Expected synthesized audio buffer"
        )
        mockBackend.simulatedBuffers = [buffer]

        try await sut.startRecording()
        #expect(sut.isRecording)

        let stopTask = Task { try await sut.stopRecording() }

        // Stop clears isRecording before the detached backend finalization returns.
        // Wait for the backend's explicit start signal rather than inferring it from elapsed time.
        await mockBackend.waitUntilStopCaptureStarts()
        defer { mockBackend.allowStopCaptureToFinish() }
        #expect(mockBackend.hasStartedStopCapture)
        #expect(sut.isRecording == false)

        var concurrentMainActorTicks = 0
        for _ in 0..<20 {
            await Task { @MainActor in
                concurrentMainActorTicks += 1
            }.value
        }
        #expect(concurrentMainActorTicks == 20)

        mockBackend.allowStopCaptureToFinish()
        let data = try await stopTask.value

        #expect(data.count > 0)
        #expect(sut.isRecording == false)
        #expect(mockBackend.stopCaptureCallCount == 1)
    }

    @Test func startRecordingWaitsForFinalizationBeforeReusingBackend() async throws {
        let mockPermission = MockPermissionProvider()
        mockPermission.grantPermission = true
        let mockBackend = DelayedMockAudioCaptureBackend()
        let mockSystemBackend = MockAudioCaptureBackend(identifier: "system")
        let sut = try AudioRecorder(
            permissionManager: mockPermission,
            captureBackend: mockBackend,
            systemAudioCaptureBackend: mockSystemBackend
        )

        let buffer = try #require(
            MockAudioCaptureBackend.makeSynthesizedBuffer(format: mockBackend.targetFormat),
            "Expected synthesized audio buffer"
        )
        mockBackend.simulatedBuffers = [buffer]

        try await sut.startRecording()
        #expect(mockBackend.startCaptureCallCount == 1)

        let stopTask = Task { try await sut.stopRecording() }
        await mockBackend.waitUntilStopCaptureStarts()
        defer { mockBackend.allowStopCaptureToFinish() }

        // Finalization owns the backend off the main actor. A concurrent start must
        // not call startCapture/reset on that same instance until ownership returns.
        let startTask = Task { try await sut.startRecording() }

        for _ in 0..<30 {
            await Task.yield()
        }

        #expect(mockBackend.startCaptureCallCount == 1)
        #expect(mockBackend.stopCaptureCallCount == 1)

        sut.resetAudioEngine()
        #expect(
            mockBackend.resetCallCount == 0,
            "reset must not touch a backend still owned by detached finalization"
        )

        mockBackend.allowStopCaptureToFinish()
        let data = try await stopTask.value
        #expect(data.count > 0)

        let started = try await startTask.value
        #expect(started)
        #expect(
            mockBackend.startCaptureCallCount == 2,
            "start may reuse the backend only after finalization releases ownership"
        )
    }


    @Test(.timeLimit(.minutes(1)))
    func meterDeliveryCoalescesLatestOverallAndBandsPreservingCallbackOrder() async throws {
        let fixture = try makeFixture()
        fixture.mockPermission.grantPermission = true

        var deliveredLevels: [Float] = []
        var deliveredBands: [AudioBandLevels] = []
        var deliveryOrder: [String] = []

        try await fixture.sut.startRecording()

        let buffer = try #require(
            MockAudioCaptureBackend.makeSynthesizedBuffer(
                format: fixture.mockBackend.targetFormat,
                frameCount: 320,
                frequency: 440
            ),
            "Expected synthesized sample buffer"
        )

        let emissionCount = 48
        let latestSourceLevel: Float = 0
        let burst = AudioCaptureCallbackBurst(
            buffer: buffer,
            emissionCount: emissionCount,
            onBuffer: fixture.mockBackend.capturedOnBuffer,
            onAudioLevel: fixture.mockBackend.capturedOnAudioLevel
        )
        let (latestPairDelivered, latestPairContinuation) = AsyncStream.makeStream(
            of: Void.self,
            bufferingPolicy: .bufferingNewest(1)
        )

        await confirmation(
            "A current level and bands snapshot is delivered in level-before-bands order"
        ) { confirm in
            var didConfirmLatestPair = false

            func confirmLatestDeliveredPairIfReady() {
                guard !didConfirmLatestPair, deliveredLevels.last == latestSourceLevel else {
                    return
                }

                let latestSnapshotIsOrderedPair =
                    deliveryOrder.suffix(2).elementsEqual(["level", "bands"])
                guard latestSnapshotIsOrderedPair else { return }

                didConfirmLatestPair = true
                confirm()
                latestPairContinuation.yield()
            }

            fixture.sut.onAudioLevel = { level in
                deliveredLevels.append(level)
                deliveryOrder.append("level")
                confirmLatestDeliveredPairIfReady()
            }
            fixture.sut.onAudioBandLevels = { bands in
                deliveredBands.append(bands)
                deliveryOrder.append("bands")
                confirmLatestDeliveredPairIfReady()
            }

            await Task.detached(priority: .userInitiated) {
                burst.run()
                // A distinct final value makes the coalescer's contractually retained
                // latest level observable even when every stale burst value is dropped.
                burst.onBuffer?(burst.buffer)
                burst.onAudioLevel?(latestSourceLevel)
            }.value
            let receivedLatestPair = await withTaskGroup(of: Bool.self) { group in
                group.addTask {
                    for await _ in latestPairDelivered {
                        return true
                    }
                    return false
                }
                group.addTask {
                    do {
                        try await Task.sleep(for: .seconds(1))
                        return false
                    } catch {
                        return false
                    }
                }

                let firstResult = await group.next() ?? false
                group.cancelAll()
                return firstResult
            }

            fixture.sut.onAudioLevel = nil
            fixture.sut.onAudioBandLevels = nil
            latestPairContinuation.finish()
            #expect(
                receivedLatestPair,
                "Timed out waiting for the coalescer's latest level and a delivered level/bands pair"
            )
        }

        let lastLevel = try #require(deliveredLevels.last)
        _ = try #require(deliveredBands.last)

        // The coalescer may supersede any stale source sample, but it must retain
        // and eventually deliver the distinct latest overall level.
        #expect(lastLevel == latestSourceLevel)
        #expect(deliveredLevels.count <= emissionCount + 1)
        #expect(deliveredBands.count <= emissionCount + 1)
        // Only the delivered snapshot containing the current values is ordered;
        // stale source samples may have been superseded before any callback.
        #expect(deliveryOrder.suffix(2).elementsEqual(["level", "bands"]))
    }

    @Test func coreAudioInputFormatUsesInputStreamVirtualFormat() throws {
        let expectedStreamID = AudioStreamID(42)
        var requestedStreamID: AudioStreamID?

        let sourceStream = try CoreAudioInputFormatResolver.resolve(
            streamIDs: [expectedStreamID]
        ) { streamID in
            requestedStreamID = streamID
            return Self.makeFloatStreamDescription(sampleRate: 48_000)
        }

        #expect(requestedStreamID == expectedStreamID)
        #expect(sourceStream.streamID == expectedStreamID)
        #expect(sourceStream.bufferIndex == 0)
        #expect(sourceStream.format.sampleRate == 48_000)
        #expect(sourceStream.format.channelCount == 1)
    }

    @Test func coreAudioInputFormatTracksSelectedStreamBufferIndex() throws {
        let sourceStream = try CoreAudioInputFormatResolver.resolve(
            streamIDs: [AudioStreamID(10), AudioStreamID(20)]
        ) { streamID in
            if streamID == 10 {
                return AudioStreamBasicDescription()
            }
            return Self.makeFloatStreamDescription(sampleRate: 44_100)
        }

        #expect(sourceStream.streamID == 20)
        #expect(sourceStream.bufferIndex == 1)
        #expect(sourceStream.format.sampleRate == 44_100)
    }

    @Test func coreAudioInputFormatRejectsMissingInputStreams() {
        do {
            _ = try CoreAudioInputFormatResolver.resolve(streamIDs: []) { _ in
                AudioStreamBasicDescription()
            }
            Issue.record("Expected missing input streams to fail")
        } catch AudioRecorderError.engineStartFailed(let message) {
            #expect(message == "No microphone input stream is available")
        } catch {
            Issue.record("Unexpected error: \(error.localizedDescription)")
        }
    }

    private static func makeFloatStreamDescription(
        sampleRate: Double
    ) -> AudioStreamBasicDescription {
        AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kLinearPCMFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 4,
            mFramesPerPacket: 1,
            mBytesPerFrame: 4,
            mChannelsPerFrame: 1,
            mBitsPerChannel: 32,
            mReserved: 0
        )
    }

}

/// Backend that blocks inside `stopCapture` so stop finalization can be observed
/// yielding the main actor. Lives only in this test file (production mocks stay lean).
private final class DelayedMockAudioCaptureBackend: AudioCaptureBackend, @unchecked Sendable {
    let identifier: String
    private let stateLock = NSLock()
    private var isCapturingStorage = false
    var isCapturing: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return isCapturingStorage
    }
    let targetFormat: AVAudioFormat

    var simulatedBuffers: [AVAudioPCMBuffer] = []
    private let stopMayFinish = DispatchSemaphore(value: 0)
    private var stopStartedStorage = false
    private var stopStartWaiters: [CheckedContinuation<Void, Never>] = []

    private(set) var startCaptureCallCount = 0
    private(set) var stopCaptureCallCount = 0
    private(set) var cancelCaptureCallCount = 0
    private(set) var resetCallCount = 0

    var capturedOnBuffer: ((AVAudioPCMBuffer) -> Void)?
    var capturedOnAudioLevel: ((Float) -> Void)?
    var capturedOnError: ((Error) -> Void)?

    var hasStartedStopCapture: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return stopStartedStorage
    }

    init(identifier: String = "delayed-microphone") {
        self.identifier = identifier
        var streamDescription = AudioStreamBasicDescription(
            mSampleRate: 16000.0,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kLinearPCMFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 4,
            mFramesPerPacket: 1,
            mBytesPerFrame: 4,
            mChannelsPerFrame: 1,
            mBitsPerChannel: 32,
            mReserved: 0
        )
        self.targetFormat = AVAudioFormat(streamDescription: &streamDescription)!
    }

    func startCapture(
        onBuffer: @escaping (AVAudioPCMBuffer) -> Void,
        onAudioLevel: @escaping (Float) -> Void,
        onError: @escaping (Error) -> Void
    ) throws {
        startCaptureCallCount += 1
        capturedOnBuffer = onBuffer
        capturedOnAudioLevel = onAudioLevel
        capturedOnError = onError
        stateLock.lock()
        isCapturingStorage = true
        stateLock.unlock()
    }

    func stopCapture() throws -> AudioPCMFile {
        stateLock.lock()
        stopCaptureCallCount += 1
        stopStartedStorage = true
        let waiters = stopStartWaiters
        stopStartWaiters.removeAll()
        stateLock.unlock()
        for waiter in waiters {
            waiter.resume()
        }
        stopMayFinish.wait()
        stateLock.lock()
        isCapturingStorage = false
        stateLock.unlock()
        let data = simulatedBuffers.reduce(into: Data()) { data, buffer in
            guard let channelData = buffer.floatChannelData else { return }
            data.append(contentsOf:
                UnsafeRawBufferPointer(
                    start: channelData[0],
                    count: Int(buffer.frameLength) * MemoryLayout<Float>.size
                )
            )
        }
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("pindrop-test-delayed-audio-\(UUID().uuidString).pcm")
        try data.write(to: fileURL)
        return AudioPCMFile(
            fileURL: fileURL,
            byteCount: data.count,
            sampleRate: targetFormat.sampleRate
        )
    }

    func cancelCapture() {
        stateLock.lock()
        cancelCaptureCallCount += 1
        isCapturingStorage = false
        stateLock.unlock()
    }

    func reset() {
        stateLock.lock()
        resetCallCount += 1
        isCapturingStorage = false
        stateLock.unlock()
    }

    func waitUntilStopCaptureStarts() async {
        await withCheckedContinuation { continuation in
            stateLock.lock()
            if stopStartedStorage {
                stateLock.unlock()
                continuation.resume()
            } else {
                stopStartWaiters.append(continuation)
                stateLock.unlock()
            }
        }
    }

    func allowStopCaptureToFinish() {
        stopMayFinish.signal()
    }

    func setPreferredInputDeviceUID(_ uid: String) throws {}
}

/// Immutable capture-thread work item. The callbacks are supplied by AudioRecorder and are
/// specifically required to accept backend-thread delivery; the audio buffer is read-only here.
private final class AudioCaptureCallbackBurst: @unchecked Sendable {
    let buffer: AVAudioPCMBuffer
    let emissionCount: Int
    let onBuffer: ((AVAudioPCMBuffer) -> Void)?
    let onAudioLevel: ((Float) -> Void)?

    init(
        buffer: AVAudioPCMBuffer,
        emissionCount: Int,
        onBuffer: ((AVAudioPCMBuffer) -> Void)?,
        onAudioLevel: ((Float) -> Void)?
    ) {
        self.buffer = buffer
        self.emissionCount = emissionCount
        self.onBuffer = onBuffer
        self.onAudioLevel = onAudioLevel
    }

    func run() {
        for index in 0..<emissionCount {
            onBuffer?(buffer)
            onAudioLevel?(Float(index + 1) / Float(emissionCount))
        }
    }
}


@Suite
struct AudioPCMFileStorageTests {
    @Test func spoolsPCMBuffersAndReturnsFinalDataInOrder() throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
        let first = try #require(MockAudioCaptureBackend.makeSynthesizedBuffer(format: format, frameCount: 4, frequency: 100))
        let second = try #require(MockAudioCaptureBackend.makeSynthesizedBuffer(format: format, frameCount: 4, frequency: 200))
        let storage = AudioPCMFileStorage()

        try storage.start()
        #expect(storage.enqueue(first))
        #expect(storage.enqueue(second))
        let completed = try storage.finish()
        let result = try #require(completed)
        let data = try result.consumeData(maximumByteCount: 1024)

        #expect(result.sampleRate == 16_000)
        #expect(data.count == 8 * MemoryLayout<Float>.size)
        let samples = data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        #expect(samples == [
            first.floatChannelData![0][0], first.floatChannelData![0][1], first.floatChannelData![0][2], first.floatChannelData![0][3],
            second.floatChannelData![0][0], second.floatChannelData![0][1], second.floatChannelData![0][2], second.floatChannelData![0][3],
        ])
    }

    @Test func slowWriterUsesBoundedHandoffAndRejectsOverflow() throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
        let buffer = try #require(MockAudioCaptureBackend.makeSynthesizedBuffer(format: format, frameCount: 4))
        let storage = AudioPCMFileStorage(pendingWriteLimit: 1, writerDelayNanoseconds: 100_000_000)

        try storage.start()
        #expect(storage.enqueue(buffer))
        #expect(storage.enqueue(buffer) == false)
        let completed = try storage.finish()
        let result = try #require(completed)
        result.discard()
    }

    @Test func materializationRejectsDataOverConfiguredLimit() throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
        let buffer = try #require(MockAudioCaptureBackend.makeSynthesizedBuffer(format: format, frameCount: 8))
        let storage = AudioPCMFileStorage()

        try storage.start()
        #expect(storage.enqueue(buffer))
        let completed = try storage.finish()
        let result = try #require(completed)
        defer { result.discard() }

        #expect(throws: AudioRecorderError.self) {
            _ = try result.consumeData(maximumByteCount: 4)
        }
    }

    @Test func limitPreservesAlreadyWrittenPCMForControlledFinalization() throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
        let first = try #require(MockAudioCaptureBackend.makeSynthesizedBuffer(format: format, frameCount: 4, frequency: 100))
        let second = try #require(MockAudioCaptureBackend.makeSynthesizedBuffer(format: format, frameCount: 4, frequency: 200))
        let overLimit = try #require(MockAudioCaptureBackend.makeSynthesizedBuffer(format: format, frameCount: 4, frequency: 300))
        var reachedLimit = false
        let storage = AudioPCMFileStorage(maximumByteCount: 8 * MemoryLayout<Float>.size)

        try storage.start(onLimitReached: { _ in reachedLimit = true })
        #expect(storage.enqueue(first))
        #expect(storage.enqueue(second))
        #expect(storage.enqueue(overLimit))

        let finished = try storage.finish()
        let completed = try #require(finished)
        let data = try completed.consumeData(maximumByteCount: 1024)
        #expect(reachedLimit)
        #expect(data.count == 8 * MemoryLayout<Float>.size)
    }

    @Test func enqueueSnapshotsSamplesBeforeBorrowedSourceCanMutate() throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
        let source = try #require(MockAudioCaptureBackend.makeSynthesizedBuffer(format: format, frameCount: 4))
        let expected = Array(UnsafeBufferPointer(start: source.floatChannelData![0], count: 4))
        let storage = AudioPCMFileStorage(writerDelayNanoseconds: 100_000_000)

        try storage.start()
        #expect(storage.enqueue(source))
        for index in 0..<4 { source.floatChannelData![0][index] = -1 }

        let finished = try storage.finish()
        let completed = try #require(finished)
        let data = try completed.consumeData(maximumByteCount: 1024)
        let actual = data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        #expect(actual == expected)
    }

    @Test func exhaustedSlabPoolRejectsThenRecyclesInWriteOrder() throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
        let first = try #require(MockAudioCaptureBackend.makeSynthesizedBuffer(format: format, frameCount: 4, frequency: 100))
        let second = try #require(MockAudioCaptureBackend.makeSynthesizedBuffer(format: format, frameCount: 4, frequency: 200))
        let storage = AudioPCMFileStorage(pendingWriteLimit: 1, writerDelayNanoseconds: 30_000_000)

        try storage.start()
        #expect(storage.enqueue(first))
        #expect(storage.enqueue(second) == false)
        Thread.sleep(forTimeInterval: 0.06) // Writer returns the sole slab off callback.
        #expect(storage.enqueue(second))

        let finished = try storage.finish()
        let completed = try #require(finished)
        let data = try completed.consumeData(maximumByteCount: 1024)
        let samples = data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        #expect(samples == [
            first.floatChannelData![0][0], first.floatChannelData![0][1], first.floatChannelData![0][2], first.floatChannelData![0][3],
            second.floatChannelData![0][0], second.floatChannelData![0][1], second.floatChannelData![0][2], second.floatChannelData![0][3],
        ])
    }

    @Test func multiSlabFIFOPreservesCaptureOrderAcrossOneWriterWakeup() throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
        var buffers: [AVAudioPCMBuffer] = []
        for frequency: Float in [100, 200, 300, 400] {
            let buffer = try #require(
                MockAudioCaptureBackend.makeSynthesizedBuffer(
                    format: format,
                    frameCount: 4,
                    frequency: frequency
                )
            )
            buffers.append(buffer)
        }
        let storage = AudioPCMFileStorage(pendingWriteLimit: 4, writerDelayNanoseconds: 20_000_000)

        try storage.start()
        for buffer in buffers { #expect(storage.enqueue(buffer)) }

        let finished = try storage.finish()
        let completed = try #require(finished)
        let data = try completed.consumeData(maximumByteCount: 1024)
        let samples = data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        var expected: [Float] = []
        for buffer in buffers {
            expected.append(contentsOf: (0..<4).map { buffer.floatChannelData![0][$0] })
        }
        #expect(samples == expected)
    }

    @Test func discardIsIdempotentAndStorageCanRestartAfterPendingSlabs() throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
        let first = try #require(MockAudioCaptureBackend.makeSynthesizedBuffer(format: format, frameCount: 4, frequency: 100))
        let second = try #require(MockAudioCaptureBackend.makeSynthesizedBuffer(format: format, frameCount: 4, frequency: 200))
        let storage = AudioPCMFileStorage(pendingWriteLimit: 2, writerDelayNanoseconds: 20_000_000)

        try storage.start()
        #expect(storage.enqueue(first))
        #expect(storage.enqueue(second))
        storage.discard()
        storage.discard()

        try storage.start()
        #expect(storage.enqueue(second))
        let finished = try storage.finish()
        let completed = try #require(finished)
        let data = try completed.consumeData(maximumByteCount: 1024)
        let samples = data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        #expect(samples == (0..<4).map { second.floatChannelData![0][$0] })
    }

    @Test func repeatedFinishRestartMaintainsFIFOSequences() throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
        let storage = AudioPCMFileStorage(pendingWriteLimit: 3)

        for frequency: Float in [100, 200, 300, 400, 500, 600] {
            let buffer = try #require(
                MockAudioCaptureBackend.makeSynthesizedBuffer(
                    format: format,
                    frameCount: 4,
                    frequency: frequency
                )
            )
            try storage.start()
            #expect(storage.enqueue(buffer))
            let finished = try storage.finish()
            let completed = try #require(finished)
            let data = try completed.consumeData(maximumByteCount: 1024)
            let samples = data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
            #expect(samples == (0..<4).map { buffer.floatChannelData![0][$0] })
        }
    }
}

@Suite
struct AudioLevelNormalizerTests {
    @Test func quietSourceIsBoostedToVisualRange() {
        let sut = AudioLevelNormalizer()

        // A soft mic whose speech peaks sit around 0.15 raw: after a few updates
        // the envelope tracks 0.15 and peaks land near full scale.
        var last: Float = 0
        for _ in 0..<5 {
            last = sut.normalize(0.15)
        }

        #expect(last > 0.85)
        #expect(last <= 1.0)
    }

    @Test func loudSourceIsNotAmplifiedPastFullScale() {
        let sut = AudioLevelNormalizer()

        let normalized = sut.normalize(0.9)

        #expect(normalized <= 1.0)
        #expect(normalized > 0.85)
    }

    @Test func silenceIsNotBoostedToFullScale() {
        let sut = AudioLevelNormalizer()

        // Room noise well under the envelope floor must stay visually quiet even
        // though nothing louder has been heard.
        let normalized = sut.normalize(0.01)

        #expect(normalized < 0.2)
    }

    @Test func gainRelaxesSlowlyAfterLoudPassage() {
        let sut = AudioLevelNormalizer()

        _ = sut.normalize(0.9)
        let gainAfterLoud = sut.currentGain
        // A handful of quiet updates should barely move the gain (slow release).
        for _ in 0..<10 {
            _ = sut.normalize(0.01)
        }

        #expect(sut.currentGain < gainAfterLoud * 1.2)
    }

    @Test func bandsScaleByASharedGain() {
        let sut = AudioLevelNormalizer()
        _ = sut.normalize(0.15)

        let bands = sut.scaled(AudioBandLevels(low: 0.12, mid: 0.06, high: 0.03))

        // Relative structure preserved: low > mid > high with the same ratios.
        #expect(bands.low > bands.mid)
        #expect(bands.mid > bands.high)
        #expect(abs(bands.mid / bands.low - 0.5) < 0.01)
        #expect(bands.low <= 1.0)
    }

    @Test func resetClearsTheEnvelope() {
        let sut = AudioLevelNormalizer()
        _ = sut.normalize(0.9)
        let adaptedGain = sut.currentGain

        sut.reset()

        #expect(sut.currentGain > adaptedGain)
    }
}

@Suite
struct OrbWaveformResponseTests {
    @Test func inputAtOrBelowBaselineKeepsEveryTraceFlat() {
        let loudBands = AudioBandLevels(low: 1, mid: 1, high: 1)

        let below = OrbWaveformResponse.levels(
            bands: loudBands,
            overall: OrbWaveformResponse.baselineLevel - 0.001
        )
        let atBaseline = OrbWaveformResponse.levels(
            bands: loudBands,
            overall: OrbWaveformResponse.baselineLevel
        )

        #expect(below == .zero)
        #expect(atBaseline == .zero)
    }

    @Test func individualBandsRemainFlatBelowTheirFloor() {
        let response = OrbWaveformResponse.levels(
            bands: AudioBandLevels(
                low: OrbWaveformResponse.bandFloor,
                mid: 0.5,
                high: OrbWaveformResponse.bandFloor - 0.001
            ),
            overall: 1
        )

        #expect(response.low == 0)
        #expect(response.mid > 0)
        #expect(response.high == 0)
    }

    @Test func responsePreservesBandOrderingAndCapsPeakMotion() {
        let response = OrbWaveformResponse.levels(
            bands: AudioBandLevels(low: 1, mid: 0.6, high: 0.25),
            overall: 1
        )

        #expect(response.low > response.mid)
        #expect(response.mid > response.high)
        #expect(response.low <= OrbWaveformResponse.maximumResponse)
        #expect(response.mid <= OrbWaveformResponse.maximumResponse)
        #expect(response.high <= OrbWaveformResponse.maximumResponse)
    }

    @Test func ordinarySpeechLevelsProduceVisibleMotion() {
        let response = OrbWaveformResponse.levels(
            bands: AudioBandLevels(low: 0.3, mid: 0.25, high: 0.18),
            overall: 0.2
        )

        #expect(response.low > 0.18)
        #expect(response.mid > 0.12)
        #expect(response.high > 0.05)
    }
}

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

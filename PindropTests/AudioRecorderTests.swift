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
        mockBackend: MockAudioCaptureBackend
    )

    private func makeFixture() throws -> Fixture {
        let mockPermission = MockPermissionProvider()
        let mockBackend = MockAudioCaptureBackend()
        let sut = try AudioRecorder(permissionManager: mockPermission, captureBackend: mockBackend)
        return (sut, mockPermission, mockBackend)
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
        #expect(fixture.mockBackend.resetCallCount == 1)
    }
}

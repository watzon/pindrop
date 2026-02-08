//
//  AudioRecorderTests.swift
//  PindropTests
//
//  Created on 2026-01-25.
//

import XCTest
import AVFoundation
@testable import Pindrop

@MainActor
final class AudioRecorderTests: XCTestCase {
    
    var sut: AudioRecorder!
    var mockPermission: MockPermissionProvider!
    var mockBackend: MockAudioCaptureBackend!
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        mockPermission = MockPermissionProvider()
        mockBackend = MockAudioCaptureBackend()
        sut = try AudioRecorder(permissionManager: mockPermission, captureBackend: mockBackend)
    }
    
    override func tearDownWithError() throws {
        sut = nil
        mockPermission = nil
        mockBackend = nil
        try super.tearDownWithError()
    }
    
    // MARK: - Initialization
    
    func testAudioRecorderInitialization() throws {
        XCTAssertNotNil(sut)
        XCTAssertFalse(sut.isRecording)
    }
    
    // MARK: - Recording
    
    func testStartRecordingRequestsPermission() async throws {
        mockPermission.grantPermission = true
        try await sut.startRecording()
        XCTAssertEqual(mockPermission.requestPermissionCallCount, 1)
    }
    
    func testStartRecordingSetsIsRecordingFlag() async throws {
        mockPermission.grantPermission = true
        XCTAssertFalse(sut.isRecording)
        try await sut.startRecording()
        XCTAssertTrue(sut.isRecording)
        XCTAssertEqual(mockBackend.startCaptureCallCount, 1)
    }
    
    func testStopRecordingReturnsAudioData() async throws {
        mockPermission.grantPermission = true
        let buffer = MockAudioCaptureBackend.makeSynthesizedBuffer(format: mockBackend.targetFormat)!
        mockBackend.simulatedBuffers = [buffer]
        
        try await sut.startRecording()
        let audioData = try await sut.stopRecording()
        
        XCTAssertGreaterThan(audioData.count, 0)
        XCTAssertFalse(sut.isRecording)
        XCTAssertEqual(mockBackend.stopCaptureCallCount, 1)
    }
    
    func testStopRecordingWithoutStartingThrowsError() async throws {
        do {
            _ = try await sut.stopRecording()
            XCTFail("Should have thrown notRecording error")
        } catch AudioRecorderError.notRecording {
            // Expected
        }
    }
    
    // MARK: - Audio Format
    
    func testAudioFormatConfiguration() throws {
        let format = sut.targetFormat
        XCTAssertEqual(format.sampleRate, 16000.0)
        XCTAssertEqual(format.channelCount, 1)
        XCTAssertEqual(format.commonFormat, .pcmFormatFloat32)
    }
    
    // MARK: - Multiple Sessions
    
    func testMultipleRecordingSessions() async throws {
        mockPermission.grantPermission = true
        let buffer = MockAudioCaptureBackend.makeSynthesizedBuffer(format: mockBackend.targetFormat)!
        mockBackend.simulatedBuffers = [buffer]
        
        // First session
        try await sut.startRecording()
        let firstData = try await sut.stopRecording()
        XCTAssertGreaterThan(firstData.count, 0)
        
        mockBackend.simulatedBuffers = [buffer]
        
        // Second session
        try await sut.startRecording()
        let secondData = try await sut.stopRecording()
        XCTAssertGreaterThan(secondData.count, 0)
        
        XCTAssertEqual(mockBackend.startCaptureCallCount, 2)
        XCTAssertEqual(mockBackend.stopCaptureCallCount, 2)
    }
    
    // MARK: - Error Handling
    
    func testStartRecordingThrowsWhenPermissionDenied() async throws {
        mockPermission.grantPermission = false
        do {
            try await sut.startRecording()
            XCTFail("Should have thrown permissionDenied")
        } catch AudioRecorderError.permissionDenied {
            // Expected
        }
        XCTAssertFalse(sut.isRecording)
        XCTAssertEqual(mockBackend.startCaptureCallCount, 0, "Backend should not start when permission denied")
    }
    
    func testStartRecordingThrowsWhenBackendFails() async throws {
        mockPermission.grantPermission = true
        mockBackend.shouldThrowOnStart = AudioRecorderError.engineStartFailed("Mock engine failure")
        
        do {
            try await sut.startRecording()
            XCTFail("Should have thrown engineStartFailed")
        } catch AudioRecorderError.engineStartFailed {
            // Expected
        }
        XCTAssertFalse(sut.isRecording)
    }
    
    func testCancelRecording() async throws {
        mockPermission.grantPermission = true
        try await sut.startRecording()
        XCTAssertTrue(sut.isRecording)
        
        sut.cancelRecording()
        XCTAssertFalse(sut.isRecording)
        XCTAssertEqual(mockBackend.cancelCaptureCallCount, 1)
    }
    
    func testResetAudioEngine() async throws {
        mockPermission.grantPermission = true
        try await sut.startRecording()
        
        sut.resetAudioEngine()
        XCTAssertFalse(sut.isRecording)
        XCTAssertEqual(mockBackend.resetCallCount, 1)
    }
}

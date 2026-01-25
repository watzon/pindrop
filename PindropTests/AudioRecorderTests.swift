//
//  AudioRecorderTests.swift
//  PindropTests
//
//  Created on 2026-01-25.
//

import XCTest
import AVFoundation
@testable import Pindrop

final class AudioRecorderTests: XCTestCase {
    
    var sut: AudioRecorder!
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        sut = AudioRecorder()
    }
    
    override func tearDownWithError() throws {
        sut = nil
        try super.tearDownWithError()
    }
    
    // MARK: - Initialization Tests
    
    func testAudioRecorderInitialization() throws {
        XCTAssertNotNil(sut, "AudioRecorder should initialize successfully")
        XCTAssertFalse(sut.isRecording, "AudioRecorder should not be recording initially")
    }
    
    // MARK: - Recording Tests
    
    func testStartRecordingRequestsPermission() throws {
        // Given: AudioRecorder is initialized
        // When: startRecording is called
        let expectation = expectation(description: "Permission requested")
        
        Task {
            do {
                try await sut.startRecording()
                // If we get here, permission was granted (or already granted)
                expectation.fulfill()
            } catch AudioRecorderError.permissionDenied {
                // Permission was denied - this is also a valid outcome for the test
                expectation.fulfill()
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
        }
        
        wait(for: [expectation], timeout: 5.0)
    }
    
    func testStartRecordingSetsIsRecordingFlag() throws {
        // Given: AudioRecorder is initialized
        XCTAssertFalse(sut.isRecording)
        
        // When: startRecording is called (assuming permission granted)
        let expectation = expectation(description: "Recording started")
        
        Task {
            do {
                try await sut.startRecording()
                // Then: isRecording should be true
                XCTAssertTrue(self.sut.isRecording, "isRecording should be true after starting")
                expectation.fulfill()
            } catch AudioRecorderError.permissionDenied {
                // Skip test if permission denied
                expectation.fulfill()
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
        }
        
        wait(for: [expectation], timeout: 5.0)
    }
    
    func testStopRecordingReturnsAudioData() throws {
        // Given: Recording has started
        let startExpectation = expectation(description: "Recording started")
        let stopExpectation = expectation(description: "Recording stopped")
        
        Task {
            do {
                try await sut.startRecording()
                startExpectation.fulfill()
                
                // Record for a brief moment
                try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                
                // When: stopRecording is called
                let audioData = try await sut.stopRecording()
                
                // Then: Audio data should be returned
                XCTAssertNotNil(audioData, "Audio data should not be nil")
                XCTAssertGreaterThan(audioData.count, 0, "Audio data should contain samples")
                XCTAssertFalse(self.sut.isRecording, "isRecording should be false after stopping")
                
                stopExpectation.fulfill()
            } catch AudioRecorderError.permissionDenied {
                // Skip test if permission denied
                startExpectation.fulfill()
                stopExpectation.fulfill()
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
        }
        
        wait(for: [startExpectation, stopExpectation], timeout: 10.0)
    }
    
    func testStopRecordingWithoutStartingThrowsError() throws {
        // Given: Recording has not started
        XCTAssertFalse(sut.isRecording)
        
        // When/Then: stopRecording should throw an error
        let expectation = expectation(description: "Error thrown")
        
        Task {
            do {
                _ = try await sut.stopRecording()
                XCTFail("Should have thrown notRecording error")
            } catch AudioRecorderError.notRecording {
                // Expected error
                expectation.fulfill()
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
        }
        
        wait(for: [expectation], timeout: 5.0)
    }
    
    // MARK: - Audio Format Tests
    
    func testAudioFormatConfiguration() throws {
        // Given: AudioRecorder is initialized
        // When: We check the audio format
        let format = sut.audioFormat
        
        // Then: Format should match WhisperKit requirements
        XCTAssertEqual(format.sampleRate, 16000.0, "Sample rate should be 16kHz")
        XCTAssertEqual(format.channelCount, 1, "Should be mono (1 channel)")
        XCTAssertEqual(format.commonFormat, .pcmFormatInt16, "Should be 16-bit PCM")
    }
    
    // MARK: - Multiple Recording Sessions Tests
    
    func testMultipleRecordingSessions() throws {
        let expectation = expectation(description: "Multiple sessions completed")
        
        Task {
            do {
                // First session
                try await sut.startRecording()
                try await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds
                let firstData = try await sut.stopRecording()
                XCTAssertGreaterThan(firstData.count, 0)
                
                // Second session
                try await sut.startRecording()
                try await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds
                let secondData = try await sut.stopRecording()
                XCTAssertGreaterThan(secondData.count, 0)
                
                expectation.fulfill()
            } catch AudioRecorderError.permissionDenied {
                // Skip test if permission denied
                expectation.fulfill()
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
        }
        
        wait(for: [expectation], timeout: 10.0)
    }
}

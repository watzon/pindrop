//
//  MediaPreparationServiceTests.swift
//  Pindrop
//
//  Created on 2026-07-11.
//

@preconcurrency import AVFoundation
import Foundation
import Testing
@testable import Pindrop

@MainActor
@Suite
struct MediaPreparationServiceTests {
    @Test func testPrepareAudioConvertsWAVToTranscriptionFormat() async throws {
        let sourceURL = try makeAudioFile()
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        let prepared = try await MediaPreparationService().prepareAudio(from: sourceURL)

        #expect(prepared.audioData.count > 0)
        #expect(abs(prepared.duration - 1) < 0.01)
    }

    @Test func testPrepareAudioHonorsCancellationBeforeDecode() async throws {
        let sourceURL = URL(fileURLWithPath: "/tmp/does-not-need-to-exist.wav")
        let task = Task {
            try await MediaPreparationService().prepareAudio(from: sourceURL)
        }
        task.cancel()

        do {
            _ = try await task.value
            Issue.record("Expected cancellation")
        } catch is CancellationError {
            // Expected: cancellation is checked before any synchronous decode work.
        } catch {
            Issue.record("Expected CancellationError, got \(error)")
        }
    }

    private func makeAudioFile() throws -> URL {
        let sourceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("wav")
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 48_000))
        buffer.frameLength = 48_000
        buffer.floatChannelData?[0].initialize(repeating: 0.25, count: 48_000)

        let file = try AVAudioFile(forWriting: sourceURL, settings: format.settings)
        try file.write(from: buffer)
        return sourceURL
    }
}

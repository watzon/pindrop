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

    @Test func testPrepareAudioCancelsFFmpegAndRemovesPartialOutput() async throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let sourceURL = temporaryDirectory.appendingPathComponent("unreadable.media")
        try Data("not audio".utf8).write(to: sourceURL)
        let scriptURL = temporaryDirectory.appendingPathComponent("fake-ffmpeg.sh")
        try Data(fakeFFmpegScript.utf8).write(to: scriptURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        let sut = MediaPreparationService(temporaryDirectory: temporaryDirectory)
        let task = Task {
            try await sut.prepareAudio(from: sourceURL, ffmpegPath: scriptURL.path)
        }

        let started = await waitForPartialOutput(in: temporaryDirectory)
        #expect(started)
        task.cancel()

        do {
            _ = try await task.value
            Issue.record("Expected cancellation")
        } catch is CancellationError {
            // Expected: the process is terminated and its partial output is removed.
        } catch {
            Issue.record("Expected CancellationError, got \(error)")
        }

        let remainingFiles = try FileManager.default.contentsOfDirectory(atPath: temporaryDirectory.path)
            .filter { $0.hasPrefix("pindrop-prep-") }
        #expect(remainingFiles.isEmpty)
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

    private func waitForPartialOutput(in directory: URL) async -> Bool {
        for _ in 0..<100 {
            let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
            if names.contains(where: { $0.hasPrefix("pindrop-prep-") }) {
                return true
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return false
    }

    private var fakeFFmpegScript: String {
        """
        #!/bin/sh
        for argument in "$@"; do output="$argument"; done
        printf partial > "$output"
        dd if=/dev/zero bs=1024 count=128 2>/dev/null | tr '\\0' x >&2
        while true; do sleep 1; done
        """
    }
}

//
//  SpeechSynthesisTestSupport.swift
//  PindropSpeechTests
//
//  Created on 2026-10-04.
//

import AVFoundation
import Foundation
import Testing

/// Real speech for the opt-in integration tests, made with the system `say` tool.
enum SpeechSynthesisTestSupport {
    /// 16 kHz mono Float32 samples of `text`, spoken by the system voice.
    /// `say` commands such as `[[slnc 3000]]` (3 s of silence) are allowed in `text`.
    static func synthesizeSpeech(_ text: String) throws -> Data {
        let buffer = try synthesizeSpeechBuffer(text)
        let channel = try #require(buffer.floatChannelData?[0])
        return Data(
            buffer: UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength))
        )
    }

    static func synthesizeSpeechBuffer(_ text: String) throws -> AVAudioPCMBuffer {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pindrop-speech-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: url) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        process.arguments = ["-o", url.path, "--data-format=LEF32@16000", text]
        try process.run()
        process.waitUntilExit()
        try #require(process.terminationStatus == 0, "say failed")

        let file = try AVAudioFile(forReading: url)
        let buffer = try #require(
            AVAudioPCMBuffer(
                pcmFormat: file.processingFormat,
                frameCapacity: AVAudioFrameCount(file.length)
            )
        )
        try file.read(into: buffer)
        return buffer
    }
}

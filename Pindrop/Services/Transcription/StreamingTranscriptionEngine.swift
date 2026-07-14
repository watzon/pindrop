//
//  StreamingTranscriptionEngine.swift
//  Pindrop
//
//  Created on 2026-01-30.
//

import Foundation
import AVFoundation

public struct StreamingTranscriptionResult: Sendable {
    public let text: String
    public let isFinal: Bool
    public let confidence: Float?
    public let timestamp: TimeInterval
    
    public init(text: String, isFinal: Bool, confidence: Float? = nil, timestamp: TimeInterval = 0) {
        self.text = text
        self.isFinal = isFinal
        self.confidence = confidence
        self.timestamp = timestamp
    }
}

public enum StreamingTranscriptionState: Equatable, Sendable {
    case unloaded
    case loading
    case ready
    case streaming
    case paused
    case error
}

public typealias StreamingTranscriptionCallback = @Sendable (StreamingTranscriptionResult) -> Void
public typealias EndOfUtteranceCallback = @Sendable (String) -> Void

// Deliberately NOT @MainActor: per-buffer decode must never queue behind UI work.
// A busy render loop (the orb animates at 30fps) starves main-actor hops to ~10/sec
// while audio arrives at ~50/sec, so partials pile up and burst out only at stop.
// Async requirements throughout let each conformer pick its isolation: Nemotron is
// an actor; the Apple engine stays @MainActor (isolated witnesses satisfy async
// requirements via a hop).
public protocol StreamingTranscriptionEngine: AnyObject {
    var state: StreamingTranscriptionState { get async }

    func loadModel(name: String) async throws
    /// Releases the model and ends callback production for the current session.
    /// Once this method returns, no callback originating before the unload may
    /// ever be invoked, even if this concrete instance is loaded again later.
    func unloadModel() async

    func startStreaming() async throws
    func stopStreaming() async throws -> String
    func pauseStreaming() async
    func resumeStreaming() async throws

    func processAudioChunk(_ samples: [Float]) async throws
    func processAudioBuffer(_ buffer: AVAudioPCMBuffer) async throws

    func setTranscriptionCallback(_ callback: @escaping StreamingTranscriptionCallback) async
    func setEndOfUtteranceCallback(_ callback: @escaping EndOfUtteranceCallback) async

    /// Ends the current streaming session and drains its callback production.
    /// Once this method returns, callbacks originating in any prior session must
    /// never be invoked. A subsequent `startStreaming()` begins a fresh session.
    func reset() async
}

extension StreamingTranscriptionEngine {
    public func processAudioChunk(_ data: Data) async throws {
        let samples = data.withUnsafeBytes { bytes in
            Array(bytes.bindMemory(to: Float.self))
        }
        try await processAudioChunk(samples)
    }
}

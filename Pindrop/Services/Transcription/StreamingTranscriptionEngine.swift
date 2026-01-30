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

@MainActor
public protocol StreamingTranscriptionEngine: AnyObject {
    var state: StreamingTranscriptionState { get }
    
    func loadModel(name: String) async throws
    func unloadModel() async
    
    func startStreaming() async throws
    func stopStreaming() async throws -> String
    func pauseStreaming() async
    func resumeStreaming() async throws
    
    func processAudioChunk(_ samples: [Float]) async throws
    func processAudioBuffer(_ buffer: AVAudioPCMBuffer) async throws
    
    func setTranscriptionCallback(_ callback: @escaping StreamingTranscriptionCallback)
    func setEndOfUtteranceCallback(_ callback: @escaping EndOfUtteranceCallback)
    
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

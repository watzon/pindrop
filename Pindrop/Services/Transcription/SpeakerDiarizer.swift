//
//  SpeakerDiarizer.swift
//  Pindrop
//
//  Created on 2026-01-30.
//

import Foundation

public struct Speaker: Identifiable, Sendable, Equatable {
    public let id: String
    public let label: String
    public let embedding: [Float]?

    public init(id: String, label: String, embedding: [Float]? = nil) {
        self.id = id
        self.label = label
        self.embedding = embedding
    }
}

public struct SpeakerSegment: Sendable, Equatable {
    public let speaker: Speaker
    public let startTime: TimeInterval
    public let endTime: TimeInterval
    public let confidence: Float

    public init(speaker: Speaker, startTime: TimeInterval, endTime: TimeInterval, confidence: Float) {
        self.speaker = speaker
        self.startTime = startTime
        self.endTime = endTime
        self.confidence = confidence
    }

    public var duration: TimeInterval {
        endTime - startTime
    }
}

public struct DiarizationResult: Sendable, Equatable {
    public let segments: [SpeakerSegment]
    public let speakers: [Speaker]
    public let audioDuration: TimeInterval

    public init(segments: [SpeakerSegment], speakers: [Speaker], audioDuration: TimeInterval) {
        self.segments = segments
        self.speakers = speakers
        self.audioDuration = audioDuration
    }

    public var speakerCount: Int {
        speakers.count
    }
}

public struct DiarizedTranscriptSegment: Codable, Sendable, Equatable {
    public let speakerId: String
    public let speakerLabel: String
    public let speakerProfileID: UUID?
    public let speakerEmbedding: [Float]?
    public let startTime: TimeInterval
    public let endTime: TimeInterval
    public let confidence: Float
    public let text: String

    public init(
        speakerId: String,
        speakerLabel: String,
        speakerProfileID: UUID? = nil,
        speakerEmbedding: [Float]? = nil,
        startTime: TimeInterval,
        endTime: TimeInterval,
        confidence: Float,
        text: String
    ) {
        self.speakerId = speakerId
        self.speakerLabel = speakerLabel
        self.speakerProfileID = speakerProfileID
        self.speakerEmbedding = speakerEmbedding
        self.startTime = startTime
        self.endTime = endTime
        self.confidence = confidence
        self.text = text
    }
}

public struct TranscriptionOutput: Sendable, Equatable {
    public let text: String
    public let diarizedSegments: [DiarizedTranscriptSegment]?

    public init(text: String, diarizedSegments: [DiarizedTranscriptSegment]? = nil) {
        self.text = text
        self.diarizedSegments = diarizedSegments
    }
}

public enum SpeakerDiarizerState: Equatable, Sendable {
    case unloaded
    case loading
    case ready
    case processing
    case error
}

public enum DiarizationMode: Sendable {
    case offline
    case online
}

/// Per-call options for anonymous offline speaker clustering.
public struct DiarizationOptions: Sendable, Equatable {
    /// Exact speaker count constraint. `nil` selects automatic detection.
    public let expectedSpeakerCount: Int?

    public init(expectedSpeakerCount: Int? = nil) {
        self.expectedSpeakerCount = expectedSpeakerCount
    }
}

@MainActor
public protocol SpeakerDiarizer: AnyObject {
    var state: SpeakerDiarizerState { get }
    var mode: DiarizationMode { get }

    func loadModels() async throws
    func unloadModels() async

    func diarize(audioData: Data) async throws -> DiarizationResult
    func diarize(samples: [Float], sampleRate: Int, options: DiarizationOptions) async throws -> DiarizationResult
}

extension SpeakerDiarizer {
    public func diarize(samples: [Float], sampleRate: Int) async throws -> DiarizationResult {
        try await diarize(samples: samples, sampleRate: sampleRate, options: .init())
    }

    public func diarize(audioData: Data) async throws -> DiarizationResult {
        let samples = audioData.withUnsafeBytes { bytes in
            Array(bytes.bindMemory(to: Float.self))
        }
        return try await diarize(samples: samples, sampleRate: 16000, options: .init())
    }
}

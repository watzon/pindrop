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

public struct SpeakerSegment: Sendable {
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

public struct DiarizationResult: Sendable {
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

@MainActor
public protocol SpeakerDiarizer: AnyObject {
    var state: SpeakerDiarizerState { get }
    var mode: DiarizationMode { get }
    
    func loadModels() async throws
    func unloadModels() async
    
    func diarize(audioData: Data) async throws -> DiarizationResult
    func diarize(samples: [Float], sampleRate: Int) async throws -> DiarizationResult
    
    func compareSpeakers(audio1: [Float], audio2: [Float]) async throws -> Float
    
    func registerKnownSpeaker(_ speaker: Speaker) async throws
    func clearKnownSpeakers() async
}

extension SpeakerDiarizer {
    public func diarize(audioData: Data) async throws -> DiarizationResult {
        let samples = audioData.withUnsafeBytes { bytes in
            Array(bytes.bindMemory(to: Float.self))
        }
        return try await diarize(samples: samples, sampleRate: 16000)
    }
}

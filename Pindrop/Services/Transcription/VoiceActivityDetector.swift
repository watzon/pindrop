//
//  VoiceActivityDetector.swift
//  Pindrop
//
//  Created on 2026-01-30.
//

import Foundation
import AVFoundation

public struct VoiceActivityResult: Sendable {
    public let startTime: TimeInterval
    public let endTime: TimeInterval
    public let probability: Float
    
    public init(startTime: TimeInterval, endTime: TimeInterval, probability: Float) {
        self.startTime = startTime
        self.endTime = endTime
        self.probability = probability
    }
    
    public var duration: TimeInterval {
        endTime - startTime
    }
}

public struct VoiceSegment: Sendable {
    public let startTime: TimeInterval
    public let endTime: TimeInterval
    public let samples: [Float]
    
    public init(startTime: TimeInterval, endTime: TimeInterval, samples: [Float]) {
        self.startTime = startTime
        self.endTime = endTime
        self.samples = samples
    }
    
    public var duration: TimeInterval {
        endTime - startTime
    }
}

public enum VoiceActivityDetectorState: Equatable, Sendable {
    case unloaded
    case loading
    case ready
    case processing
    case error
}

@MainActor
public protocol VoiceActivityDetector: AnyObject {
    var state: VoiceActivityDetectorState { get }
    
    func loadModel() async throws
    func unloadModel() async
    
    func detectVoiceActivity(in audioData: Data) async throws -> [VoiceActivityResult]
    func detectVoiceActivity(in samples: [Float], sampleRate: Int) async throws -> [VoiceActivityResult]
    
    func segmentSpeech(in audioData: Data) async throws -> [VoiceSegment]
    func segmentSpeech(in samples: [Float], sampleRate: Int) async throws -> [VoiceSegment]
}

extension VoiceActivityDetector {
    public func detectVoiceActivity(in audioData: Data) async throws -> [VoiceActivityResult] {
        let samples = audioData.withUnsafeBytes { bytes in
            Array(bytes.bindMemory(to: Float.self))
        }
        return try await detectVoiceActivity(in: samples, sampleRate: 16000)
    }
    
    public func segmentSpeech(in audioData: Data) async throws -> [VoiceSegment] {
        let samples = audioData.withUnsafeBytes { bytes in
            Array(bytes.bindMemory(to: Float.self))
        }
        return try await segmentSpeech(in: samples, sampleRate: 16000)
    }
}

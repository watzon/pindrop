//
//  AudioEngineCapabilities.swift
//  Pindrop
//
//  Created on 2026-01-30.
//

import Foundation

/// Capabilities that an audio engine may support
public struct AudioEngineCapabilities: OptionSet, Sendable {
    public let rawValue: Int
    
    public init(rawValue: Int) {
        self.rawValue = rawValue
    }
    
    /// Basic batch transcription (speech-to-text)
    public static let transcription = AudioEngineCapabilities(rawValue: 1 << 0)
    
    /// Real-time streaming transcription
    public static let streamingTranscription = AudioEngineCapabilities(rawValue: 1 << 1)
    
    /// Voice activity detection (speech vs silence)
    public static let voiceActivityDetection = AudioEngineCapabilities(rawValue: 1 << 2)
    
    /// Speaker diarization (who spoke when)
    public static let speakerDiarization = AudioEngineCapabilities(rawValue: 1 << 3)
    
    /// Text-to-speech synthesis
    public static let textToSpeech = AudioEngineCapabilities(rawValue: 1 << 4)
    
    /// Word-level timestamps
    public static let wordTimestamps = AudioEngineCapabilities(rawValue: 1 << 5)
    
    /// Language detection
    public static let languageDetection = AudioEngineCapabilities(rawValue: 1 << 6)
    
    /// All capabilities
    public static let all: AudioEngineCapabilities = [
        .transcription,
        .streamingTranscription,
        .voiceActivityDetection,
        .speakerDiarization,
        .textToSpeech,
        .wordTimestamps,
        .languageDetection
    ]
}

/// Protocol for engines that can report their capabilities
public protocol CapabilityReporting {
    /// The capabilities this engine supports
    static var capabilities: AudioEngineCapabilities { get }
    
    /// Check if this engine supports a specific capability
    static func supports(_ capability: AudioEngineCapabilities) -> Bool
}

extension CapabilityReporting {
    public static func supports(_ capability: AudioEngineCapabilities) -> Bool {
        capabilities.contains(capability)
    }
}

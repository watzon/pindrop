//
//  FeatureModelType.swift
//  Pindrop
//
//  Created on 2026-01-30.
//

import Foundation

/// Optional feature models separate from transcription models, downloaded on-demand.
enum FeatureModelType: String, CaseIterable, Identifiable, Codable {
    case vad = "vad"
    case diarization = "diarization"
    case streaming = "streaming"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .vad:
            return "Voice Activity Detection"
        case .diarization:
            return "Speaker Diarization"
        case .streaming:
            return "Streaming Transcription"
        }
    }
    
    var description: String {
        switch self {
        case .vad:
            return "Detects when you stop speaking for smarter recording cutoffs"
        case .diarization:
            return "Identifies different speakers in recordings"
        case .streaming:
            return "Real-time transcription as you speak"
        }
    }
    
    var sizeInMB: Int {
        switch self {
        case .vad:
            return 3
        case .diarization:
            return 100
        case .streaming:
            return 150
        }
    }
    
    var formattedSize: String {
        if sizeInMB >= 1000 {
            return String(format: "%.1f GB", Double(sizeInMB) / 1000.0)
        } else {
            return "\(sizeInMB) MB"
        }
    }
    
    var isAutoEnabled: Bool {
        self == .vad
    }
    
    var iconName: String {
        switch self {
        case .vad:
            return "waveform.badge.mic"
        case .diarization:
            return "person.2.wave.2"
        case .streaming:
            return "text.bubble"
        }
    }
    
    var repoFolderName: String {
        switch self {
        case .vad:
            return "silero-vad-coreml"
        case .diarization:
            return "speaker-diarization-coreml"
        case .streaming:
            return "parakeet-realtime-eou-120m-coreml"
        }
    }
}

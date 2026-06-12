//
//  FeatureModelType.swift
//  Pindrop
//
//  Created on 2026-01-30.
//

import Foundation
import FluidAudio

/// Streaming chunk size variants for the Nemotron Speech Streaming 0.6B model. The two
/// variants ship as separate CoreML exports under distinct subfolders; both punctuate
/// and capitalize natively (~2-3.5% WER on LibriSpeech test-clean) — picking between
/// them trades partial-text cadence against per-chunk compute.
public enum StreamingChunkProfile: String, Sendable {
    /// 1120ms chunks. Default — NVIDIA's original export, best accuracy.
    case standard = "standard"

    /// 560ms chunks. Snappier partial text at comparable accuracy, at the cost of
    /// running the encoder twice as often.
    case lowLatency = "lowLatency"

    public var nemotronChunkSize: NemotronChunkSize {
        switch self {
        case .standard: return .ms1120
        case .lowLatency: return .ms560
        }
    }

    public var modelSubdirectory: String {
        switch self {
        case .standard: return "1120ms"
        case .lowLatency: return "560ms"
        }
    }

    /// Full relative folder name under `Application Support/FluidAudio/Models/` where
    /// the CoreML variant lives once downloaded. Matches FluidAudio's
    /// `Repo.nemotronStreaming*` folder names.
    public var repoFolderName: String {
        "nemotron-streaming/\(modelSubdirectory)"
    }
}

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
            // Nemotron 0.6B per chunk variant (int8-quantized encoder).
            return 650
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

    /// Primary on-disk folder name for the feature. For streaming, this is the default
    /// (non-low-latency) variant; callers that need a specific chunk profile should use
    /// `streamingRepoFolderName(for:)` below.
    var repoFolderName: String {
        switch self {
        case .vad:
            return "silero-vad-coreml"
        case .diarization:
            return "speaker-diarization-coreml"
        case .streaming:
            return StreamingChunkProfile.standard.repoFolderName
        }
    }

    /// Resolve the streaming variant folder matching a given chunk profile. Undefined for
    /// non-streaming features — callers should only pass `.streaming` here.
    static func streamingRepoFolderName(for profile: StreamingChunkProfile) -> String {
        profile.repoFolderName
    }
}

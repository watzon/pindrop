//
//  FeatureModelType.swift
//  PindropSpeech
//
//  Created on 2026-01-30.
//

import Foundation
import FluidAudio

/// Streaming chunk size variants for the Nemotron Speech Streaming 0.6B model. The two
/// variants ship as separate CoreML exports under distinct subfolders; both punctuate
/// and capitalize natively (~2-3.5% WER on LibriSpeech test-clean). Picking between
/// them trades partial-text cadence against per-chunk compute.
public enum StreamingChunkProfile: String, Sendable {
    /// 1120ms chunks. Default: NVIDIA's original export, best accuracy.
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

    /// The chunk the streaming engine decodes, in seconds.
    ///
    /// `NemotronChunkSize` carries milliseconds and belongs to FluidAudio, which
    /// the app target deliberately does not import. Callers that time their work
    /// against the decode boundary read this instead.
    public var nemotronChunkSeconds: TimeInterval {
        TimeInterval(nemotronChunkSize.rawValue) / 1000
    }

    public var modelSubdirectory: String {
        switch self {
        case .standard: return "1120ms"
        case .lowLatency: return "560ms"
        }
    }

    /// Full relative folder name under the injected FluidAudio models root where
    /// the CoreML variant lives once downloaded. Matches FluidAudio's
    /// `Repo.nemotronStreaming*` folder names.
    public var repoFolderName: String {
        "nemotron-streaming/\(modelSubdirectory)"
    }
}

/// Feature models separate from transcription models.
///
/// Some are required and are fetched on first run; the rest are downloaded when
/// a person asks for them. See `isRequired`.
///
/// Presentation (display name, description, formatted size, icon) lives in the host app.
public enum FeatureModelType: String, CaseIterable, Identifiable, Codable, Sendable {
    case vad = "vad"
    case diarization = "diarization"
    case liveDiarization = "liveDiarization"
    case streaming = "streaming"

    public var id: String { rawValue }

    /// The models every install needs.
    ///
    /// Live transcription is what a person sees while they talk, and voice
    /// activity detection is what puts paragraph breaks in what they said.
    /// Neither is a setting anybody would think to turn on, so both are part of
    /// setting the app up rather than an extra a person has to find. Speaker
    /// diarization stays optional: it only matters when a recording has more
    /// than one voice in it. Live speaker labels are optional the same way, and
    /// they must never block a first run.
    public static let required: [FeatureModelType] = [.vad, .streaming]

    public var isRequired: Bool {
        Self.required.contains(self)
    }

    public var sizeInMB: Int {
        switch self {
        case .vad:
            return 3
        case .diarization:
            return 100
        case .liveDiarization:
            // Measured on 2026-08-31: the sum of every file under
            // SortformerNvidiaLow_v2.1.mlmodelc in
            // FluidInference/diar-streaming-sortformer-coreml is 246,280,141 bytes.
            return 246
        case .streaming:
            // Nemotron 0.6B per chunk variant (int8-quantized encoder).
            return 650
        }
    }

    /// Primary on-disk folder name for the feature. For streaming, this is the default
    /// (non-low-latency) variant; callers that need a specific chunk profile should use
    /// `streamingRepoFolderName(for:)` below.
    public var repoFolderName: String {
        switch self {
        case .vad:
            // `Repo.vad.folderName` ("silero-vad"): FluidAudio strips the "-coreml"
            // suffix from the repo name when it picks the cache folder. Readiness
            // pointed at the repo name stays false after a good download.
            return Repo.vad.folderName
        case .diarization:
            // `Repo.diarizer.folderName` ("speaker-diarization"), for the same
            // reason as `.vad` above. The offline diarizer reads and writes here.
            return Repo.diarizer.folderName
        case .liveDiarization:
            // `Repo.sortformer.folderName`, which is where DownloadUtils
            // materializes the streaming Sortformer bundle and where
            // SortformerModels reads it back. It is not the HuggingFace repo
            // name ("diar-streaming-sortformer-coreml"): readiness pointed at
            // the repo name stays false after a good download, so the download
            // reports itself incomplete and live labels never turn on.
            return "sortformer"
        case .streaming:
            return StreamingChunkProfile.standard.repoFolderName
        }
    }

    /// Resolve the streaming variant folder matching a given chunk profile. Undefined for
    /// non-streaming features: callers should only pass `.streaming` here.
    public static func streamingRepoFolderName(for profile: StreamingChunkProfile) -> String {
        profile.repoFolderName
    }
}

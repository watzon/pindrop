//
//  TranscriptionDetailAccess.swift
//  Pindrop
//
//  Created on 2026-07-09.
//

import Foundation

/// Pure helpers for Library/Dashboard detail presentation (B7 un-gating).
enum TranscriptionDetailAccess {
    /// Any transcription record can open the detail view (voice, meeting, media).
    static func canOpenDetail(for record: TranscriptionRecord) -> Bool {
        true
    }

    /// Playback chrome is shown only when a managed media file path is present.
    static func shouldShowPlayback(for record: TranscriptionRecord) -> Bool {
        record.managedMediaURL != nil
    }
}

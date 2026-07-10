//
//  NoteAppendListeningState.swift
//  Pindrop
//
//  Created on 2026-07-09.
//

import Foundation
import Combine

/// Published listening state for speak-to-append in the note editor.
/// Mirrors the FloatingIndicatorState recording/elapsed pattern without driving the global indicator UI.
@MainActor
final class NoteAppendListeningState: ObservableObject {
    @Published private(set) var isListening = false
    @Published private(set) var isProcessing = false
    @Published private(set) var elapsed: TimeInterval = 0
    /// Editor instance that started the session; transcripts are delivered only to this id.
    @Published private(set) var activeEditorID: UUID?

    private var listeningStartTime: Date?
    private var durationTimer: Timer?

    func startListening(editorID: UUID) {
        activeEditorID = editorID
        isListening = true
        isProcessing = false
        listeningStartTime = Date()
        elapsed = 0
        startDurationTimer()
    }

    func transitionToProcessing() {
        isListening = false
        isProcessing = true
        stopDurationTimer()
    }

    func finishSession() {
        isListening = false
        isProcessing = false
        elapsed = 0
        activeEditorID = nil
        listeningStartTime = nil
        stopDurationTimer()
    }

    private func startDurationTimer() {
        stopDurationTimer()
        durationTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let start = self.listeningStartTime else { return }
                self.elapsed = Date().timeIntervalSince(start)
            }
        }
    }

    private func stopDurationTimer() {
        durationTimer?.invalidate()
        durationTimer = nil
    }
}

extension Notification.Name {
    /// Posted by the note editor to request start/stop of speak-to-append.
    /// `userInfo`: `editorID` (UUID), `action` ("start" | "stop")
    static let noteSpeakToAppendRequest = Notification.Name("noteSpeakToAppendRequest")
    /// Posted by AppCoordinator when a speak-to-append transcript is ready.
    /// `userInfo`: `editorID` (UUID), `text` (String)
    static let noteSpeakToAppendTranscript = Notification.Name("noteSpeakToAppendTranscript")
}

//
//  MediaSourceKind.swift
//  Pindrop
//
//  Created on 2026-03-07.
//

import Foundation

enum MediaSourceKind: String, Codable, CaseIterable, Sendable {
    case voiceRecording
    case manualCapture
    case importedFile
    case webLink

    var isMediaBacked: Bool {
        switch self {
        case .voiceRecording:
            return false
        case .manualCapture, .importedFile, .webLink:
            return true
        }
    }
}

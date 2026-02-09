//
//  Logger.swift
//  Pindrop
//
//  Created on 2026-01-25.
//

import Foundation
import os.log

enum Log {
    private static var isPreview: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }
    
    private static let subsystem: String = {
        if isPreview {
            return "com.pindrop.preview"
        }
        return Bundle.main.bundleIdentifier ?? "com.pindrop"
    }()
    
    // Log categories
    static let audio = Logger(subsystem: subsystem, category: "Audio")
    static let transcription = Logger(subsystem: subsystem, category: "Transcription")
    static let model = Logger(subsystem: subsystem, category: "Model")
    static let output = Logger(subsystem: subsystem, category: "Output")
    static let hotkey = Logger(subsystem: subsystem, category: "Hotkey")
    static let app = Logger(subsystem: subsystem, category: "App")
    static let ui = Logger(subsystem: subsystem, category: "UI")
    static let update = Logger(subsystem: subsystem, category: "Update")
    static let aiEnhancement = Logger(subsystem: subsystem, category: "AIEnhancement")
    static let context = Logger(subsystem: subsystem, category: "Context")
}

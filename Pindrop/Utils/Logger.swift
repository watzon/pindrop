//
//  Logger.swift
//  Pindrop
//
//  Created on 2026-01-25.
//

import Foundation
import os.log

/// Centralized logging utility for Pindrop
enum Log {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.pindrop"
    
    // Log categories
    static let audio = Logger(subsystem: subsystem, category: "Audio")
    static let transcription = Logger(subsystem: subsystem, category: "Transcription")
    static let model = Logger(subsystem: subsystem, category: "Model")
    static let output = Logger(subsystem: subsystem, category: "Output")
    static let hotkey = Logger(subsystem: subsystem, category: "Hotkey")
    static let app = Logger(subsystem: subsystem, category: "App")
    static let ui = Logger(subsystem: subsystem, category: "UI")
}

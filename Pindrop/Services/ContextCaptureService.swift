//
//  ContextCaptureService.swift
//  Pindrop
//
//  Created on 2026-02-02.
//

import AppKit
import Foundation

struct CapturedContext {
    let clipboardText: String?
    let clipboardImage: NSImage?
}

@MainActor
final class ContextCaptureService {
    
    static let maxClipboardTextLength = 8192
    
    // MARK: - Clipboard Capture

    func captureClipboardText() -> String? {
        guard let text = NSPasteboard.general.string(forType: .string) else { return nil }
        return Self.truncateText(text, maxLength: Self.maxClipboardTextLength)
    }
    
    static func truncateText(_ text: String, maxLength: Int) -> String {
        guard text.count > maxLength else { return text }
        let truncated = String(text.prefix(maxLength))
        return truncated + "\n\n[Content truncated - \(text.count - maxLength) characters omitted]"
    }

    func captureClipboardImage() -> NSImage? {
        let pasteboard = NSPasteboard.general

        if let data = pasteboard.data(forType: .png),
           let image = NSImage(data: data) {
            return ImageResizer.resize(image)
        }

        if let data = pasteboard.data(forType: .tiff),
           let image = NSImage(data: data) {
            return ImageResizer.resize(image)
        }

        return nil
    }

}

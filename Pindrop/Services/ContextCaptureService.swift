//
//  ContextCaptureService.swift
//  Pindrop
//
//  Created on 2026-02-02.
//

import AppKit
import CoreGraphics
import Foundation

struct CapturedContext {
    let clipboardText: String?
    let clipboardImage: NSImage?
    let screenshot: NSImage?
}

enum ScreenshotMode: Equatable {
    case activeWindow
    case fullScreen
    case display(id: CGDirectDisplayID)
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

    // MARK: - Screenshot Capture

    func captureScreenshot(mode: ScreenshotMode) -> NSImage? {
        guard CGPreflightScreenCaptureAccess() else {
            Log.app.warning("Screen recording permission not granted, skipping screenshot capture")
            return nil
        }
        
        let cgImage: CGImage?

        switch mode {
        case .activeWindow:
            cgImage = captureActiveWindow()
        case .fullScreen:
            cgImage = captureFullScreen()
        case .display(let displayID):
            cgImage = createDisplayImage(displayID)
        }

        guard let cgImage else { return nil }

        let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        return ImageResizer.resize(image)
    }

    // MARK: - Private

    private func captureActiveWindow() -> CGImage? {
        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[CFString: Any]] else {
            return nil
        }

        // Layer 0 = normal windows (not menu bar or system UI)
        let frontmostWindow = windowList.first { windowInfo in
            guard let layer = windowInfo[kCGWindowLayer] as? Int,
                  let _ = windowInfo[kCGWindowOwnerName] as? String else {
                return false
            }
            return layer == 0
        }

        guard let windowInfo = frontmostWindow,
              let windowID = windowInfo[kCGWindowNumber] as? CGWindowID else {
            return nil
        }

        return createWindowImage(windowID)
    }

    private func captureFullScreen() -> CGImage? {
        createDisplayImage(CGMainDisplayID())
    }

    // Using deprecated APIs as ScreenCaptureKit is async-only
    // Returns nil if Screen Recording permission is denied

    @available(macOS, deprecated: 14.0, message: "ScreenCaptureKit is async-only; using legacy API")
    private func createDisplayImage(_ displayID: CGDirectDisplayID) -> CGImage? {
        CGDisplayCreateImage(displayID)
    }

    @available(macOS, deprecated: 14.0, message: "ScreenCaptureKit is async-only; using legacy API")
    private func createWindowImage(_ windowID: CGWindowID) -> CGImage? {
        CGWindowListCreateImage(
            .null,
            .optionIncludingWindow,
            windowID,
            [.boundsIgnoreFraming, .nominalResolution]
        )
    }
}

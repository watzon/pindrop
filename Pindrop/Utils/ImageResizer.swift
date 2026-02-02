//
// ImageResizer.swift
// Pindrop
//
// Created on 2026-02-02.
//

import AppKit
import Foundation

enum ImageResizer {
    /// Resizes an image to fit within a maximum dimension while preserving aspect ratio.
    /// Only resizes if the image is larger than the max dimension.
    /// - Parameters:
    ///   - image: The NSImage to resize
    ///   - maxDimension: The maximum width or height (default: 1024)
    /// - Returns: The resized NSImage, or the original if no resize was needed
    static func resize(_ image: NSImage, maxDimension: Int = 1024) -> NSImage {
        let maxDim = CGFloat(maxDimension)
        let originalSize = image.size

        // If both dimensions are within bounds, return original
        if originalSize.width <= maxDim && originalSize.height <= maxDim {
            return image
        }

        // Calculate scale factor based on the larger dimension
        let scaleFactor: CGFloat
        if originalSize.width > originalSize.height {
            scaleFactor = maxDim / originalSize.width
        } else {
            scaleFactor = maxDim / originalSize.height
        }

        let newSize = NSSize(
            width: originalSize.width * scaleFactor,
            height: originalSize.height * scaleFactor
        )

        // Create new image with calculated size
        let resizedImage = NSImage(size: newSize)

        resizedImage.lockFocus()
        defer { resizedImage.unlockFocus() }

        // Draw the original image scaled to the new size
        image.draw(
            in: NSRect(origin: .zero, size: newSize),
            from: NSRect(origin: .zero, size: originalSize),
            operation: .copy,
            fraction: 1.0
        )

        return resizedImage
    }

    /// Converts an NSImage to a base64-encoded PNG string.
    /// - Parameter image: The NSImage to convert
    /// - Returns: Base64-encoded PNG string, or nil if conversion fails
    static func toBase64PNG(_ image: NSImage) -> String? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
        bitmapRep.size = image.size

        guard let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
            return nil
        }

        return pngData.base64EncodedString()
    }
}

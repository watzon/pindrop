//
//  ModelsPresentation.swift
//  Pindrop
//
//  Created on 2026-07-10.
//
//  Pure helpers for Models page presentation (U7). No SwiftUI side effects.
//

import Foundation

// MARK: - Disk total

enum ModelsDiskTotal {
    /// Sum of installed model sizes in MB (STT + feature helpers).
    static func totalMegabytes(
        speechModels: [(isInstalled: Bool, sizeInMB: Int)],
        featureModels: [(isInstalled: Bool, sizeInMB: Int)]
    ) -> Int {
        let speech = speechModels
            .filter(\.isInstalled)
            .map(\.sizeInMB)
            .reduce(0, +)
        let features = featureModels
            .filter(\.isInstalled)
            .map(\.sizeInMB)
            .reduce(0, +)
        return speech + features
    }

    /// Formats a megabyte total for the header, e.g. "3.2 GB", "450 MB", "0 MB".
    static func formatted(megabytes: Int) -> String {
        let mb = max(0, megabytes)
        if mb >= 1000 {
            let gb = Double(mb) / 1000.0
            // One decimal when not whole, else strip trailing .0
            if abs(gb.rounded() - gb) < 0.05 {
                return "\(Int(gb.rounded())) GB"
            }
            return String(format: "%.1f GB", gb)
        }
        return "\(mb) MB"
    }

    /// Convenience: total megabytes → display string.
    static func formattedTotal(
        speechModels: [(isInstalled: Bool, sizeInMB: Int)],
        featureModels: [(isInstalled: Bool, sizeInMB: Int)]
    ) -> String {
        formatted(
            megabytes: totalMegabytes(
                speechModels: speechModels,
                featureModels: featureModels
            )
        )
    }
}

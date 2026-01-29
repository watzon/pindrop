//
//  FloatingIndicatorType.swift
//  Pindrop
//
//  Created on 2026-01-29.
//

import Foundation

enum FloatingIndicatorType: String, CaseIterable, Identifiable {
    case notch = "notch"
    case pill = "pill"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .notch:
            return "Notch"
        case .pill:
            return "Pill"
        }
    }

    var description: String {
        switch self {
        case .notch:
            return "Shows in the menu bar/notch area"
        case .pill:
            return "Shows as a pill at the bottom of the screen"
        }
    }
}

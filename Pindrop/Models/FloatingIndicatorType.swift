//
//  FloatingIndicatorType.swift
//  Pindrop
//
//  Created on 2026-01-29.
//

import Foundation

enum FloatingIndicatorType: String, CaseIterable, Identifiable {
    case pill = "pill"
    case orb = "orb"

    var id: String { rawValue }

    var displayName: String {
        displayName(locale: .autoupdatingCurrent)
    }

    func displayName(locale: Locale) -> String {
        switch self {
        case .pill:
            return localized("Pill", locale: locale)
        case .orb:
            return localized("Orb", locale: locale)
        }
    }

    var description: String {
        description(locale: .autoupdatingCurrent)
    }

    func description(locale: Locale) -> String {
        switch self {
        case .pill:
            return localized("Shows as a pill at the bottom of the screen", locale: locale)
        case .orb:
            return localized("Shows as a liquid glass orb in the corner of the screen", locale: locale)
        }
    }
}

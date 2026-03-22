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
    case bubble = "bubble"

    var id: String { rawValue }

    var displayName: String {
        displayName(locale: .autoupdatingCurrent)
    }

    func displayName(locale: Locale) -> String {
        switch self {
        case .notch:
            return localized("Notch", locale: locale)
        case .pill:
            return localized("Pill", locale: locale)
        case .bubble:
            return localized("Bubble", locale: locale)
        }
    }

    var description: String {
        description(locale: .autoupdatingCurrent)
    }

    func description(locale: Locale) -> String {
        switch self {
        case .notch:
            return localized("Shows in the menu bar/notch area", locale: locale)
        case .pill:
            return localized("Shows as a pill at the bottom of the screen", locale: locale)
        case .bubble:
            return localized("Shows beside the focused text field/caret", locale: locale)
        }
    }
}

//
//  FloatingIndicatorType.swift
//  Pindrop
//
//  Created on 2026-01-29.
//

import Foundation

enum FloatingIndicatorType: String, CaseIterable, Identifiable {
    /// Transient top-of-screen notch/menu-bar indicator (invisible while idle).
    case notch = "notch"
    /// Always-on pill at the bottom of the screen.
    case pill = "pill"
    /// Transient caret-adjacent bubble (invisible while idle).
    case bubble = "bubble"
    /// Always-on liquid-glass orb in the corner of the screen (default; successor to Dot).
    case orb = "orb"

    var id: String { rawValue }

    /// Always-on styles keep a window/visual footprint while idle.
    /// Transient styles only appear during recording/processing.
    var isAlwaysOn: Bool {
        switch self {
        case .pill, .orb:
            return true
        case .notch, .bubble:
            return false
        }
    }

    /// Bubble toasts remain screen-corner notifications because the bubble follows
    /// the focused caret. Every stable indicator location can anchor its own toasts.
    var anchorsToastsToIndicator: Bool {
        self != .bubble
    }

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
        case .orb:
            return localized("Orb", locale: locale)
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
        case .orb:
            return localized("Shows as a liquid glass orb in the corner of the screen", locale: locale)
        }
    }
}

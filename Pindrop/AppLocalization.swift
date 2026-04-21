//
//  AppLocalization.swift
//  Pindrop
//
//  Created on 2026-03-22.
//

import AppKit
import Foundation
import SwiftUI

nonisolated func localized(_ key: String, locale: Locale) -> String {
    let resolvedKey = LocalizationMetadata.stableKey(for: key)
    let bundle = localizationBundle(for: locale)
    let localizedValue = bundle.localizedString(forKey: resolvedKey, value: nil, table: nil)

    if bundle == Bundle.main {
        Log.ui.warningVisible(
            "No localization bundle found for locale=\(locale.identifier); key=\(resolvedKey)"
        )
        return Bundle.main.localizedString(forKey: resolvedKey, value: key, table: nil)
    }

    if localizedValue == resolvedKey {
        Log.ui.warningVisible(
            "Missing localized string for key=\(resolvedKey) locale=\(locale.identifier)"
        )
        return Bundle.main.localizedString(forKey: resolvedKey, value: key, table: nil)
    }

    return localizedValue
}

private nonisolated func localizationBundle(for locale: Locale) -> Bundle {
    for identifier in localizationIdentifiers(for: locale) {
        if let path = Bundle.main.path(forResource: identifier, ofType: "lproj"),
           let bundle = Bundle(path: path) {
            return bundle
        }
    }

    return Bundle.main
}

private nonisolated func localizationIdentifiers(for locale: Locale) -> [String] {
    var identifiers: [String] = []
    let normalizedIdentifier = locale.identifier.replacingOccurrences(of: "_", with: "-")

    if !normalizedIdentifier.isEmpty {
        identifiers.append(normalizedIdentifier)

        if let languageIdentifier = normalizedIdentifier.split(separator: "-").first {
            identifiers.append(String(languageIdentifier))
        }
    }

    return Array(NSOrderedSet(array: identifiers)) as? [String] ?? identifiers
}

private let selectedAppLocaleDefaultsKey = "selectedAppLocale"

extension AppLocale {
    static func currentSelection(from defaults: UserDefaults = .standard) -> AppLocale {
        let rawValue = defaults.string(forKey: selectedAppLocaleDefaultsKey) ?? AppLocale.automatic.rawValue
        return AppLocale(rawValue: rawValue) ?? .automatic
    }

    var layoutDirection: LayoutDirection {
        locale.interfaceLayoutDirection
    }
}

extension Locale {
    var interfaceLayoutDirection: LayoutDirection {
        appKitLayoutDirection == .rightToLeft ? .rightToLeft : .leftToRight
    }

    var appKitLayoutDirection: NSUserInterfaceLayoutDirection {
        let languageCode = language.languageCode?.identifier
            ?? identifier.replacingOccurrences(of: "_", with: "-").split(separator: "-").first.map(String.init)
            ?? identifier
        let direction = Locale.characterDirection(forLanguage: languageCode)
        return direction == .rightToLeft ? .rightToLeft : .leftToRight
    }
}

@MainActor
func applyInterfaceLayoutDirection(to menu: NSMenu, locale: Locale) {
    menu.userInterfaceLayoutDirection = locale.appKitLayoutDirection

    for item in menu.items {
        if let submenu = item.submenu {
            applyInterfaceLayoutDirection(to: submenu, locale: locale)
        }
    }
}

@MainActor
func applyInterfaceLayoutDirection(to view: NSView, locale: Locale) {
    view.userInterfaceLayoutDirection = locale.appKitLayoutDirection
}

@MainActor
func applyInterfaceLayoutDirection(to window: NSWindow, locale: Locale) {
    if let contentView = window.contentView {
        applyInterfaceLayoutDirection(to: contentView, locale: locale)
    }

    if let contentView = window.contentViewController?.view {
        applyInterfaceLayoutDirection(to: contentView, locale: locale)
    }
}

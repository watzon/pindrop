//
//  AppLocalization.swift
//  Pindrop
//
//  Created on 2026-03-22.
//

import Foundation

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

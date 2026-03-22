//
//  AppLocalization.swift
//  Pindrop
//
//  Created on 2026-03-22.
//

import Foundation

nonisolated func localized(_ key: String, locale: Locale) -> String {
    let bundle = localizationBundle(for: locale)
    let localizedValue = bundle.localizedString(forKey: key, value: nil, table: nil)

    if localizedValue != key || bundle == Bundle.main {
        return localizedValue
    }

    return Bundle.main.localizedString(forKey: key, value: key, table: nil)
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

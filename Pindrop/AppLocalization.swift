//
//  AppLocalization.swift
//  Pindrop
//
//  Created on 2026-03-22.
//

import Foundation

/// Resolves copy from the app String Catalog for a specific locale (Settings → Language).
/// Uses the catalog-aware API so languages ship from `Localizable.xcstrings` without requiring
/// hand-maintained `.lproj` folders in source control.
nonisolated func localized(_ key: String, locale: Locale) -> String {
    String(localized: String.LocalizationValue(key), bundle: .main, locale: locale)
}

//
//  AppLocalization.swift
//  Pindrop
//
//  Created on 2026-03-22.
//

import Foundation
import PindropSharedLocalization

nonisolated func localized(_ key: String, locale: Locale) -> String {
    let localeCode = localeIdentifierForKMP(locale)
    let value = SharedLocalization.shared.getString(xcKey: key, locale: localeCode)
    return normalizedFoundationFormatString(value)
}

private nonisolated func normalizedFoundationFormatString(_ value: String) -> String {
    guard value.contains("%s") || value.contains("$s") else {
        return value
    }

    let pattern = "%((?:\\d+\\$)?)s"
    guard let regex = try? NSRegularExpression(pattern: pattern) else {
        return value
    }

    let range = NSRange(value.startIndex..., in: value)
    return regex.stringByReplacingMatches(in: value, options: [], range: range, withTemplate: "%$1@")
}

/// Convert a Swift Locale to a KMP-compatible locale identifier.
/// Maps SwiftUI Locale identifiers to the locale codes used in the KMP strings bundle.
private nonisolated func localeIdentifierForKMP(_ locale: Locale) -> String {
    // Try the full identifier first (e.g., "pt-BR", "zh-Hans")
    let identifier = locale.identifier.replacingOccurrences(of: "_", with: "-")

    // Check for known multi-part locale codes
    let knownMultiPart: Set<String> = [
        "pt-BR", "zh-Hans", "zh-Hant", "zh-Hans-CN", "zh-Hant-TW",
        "en-US", "en-GB", "en-AU", "en-CA",
        "de-DE", "de-AT", "de-CH",
        "es-ES", "es-MX", "es-AR",
        "fr-FR", "fr-CA", "fr-BE",
        "it-IT", "it-CH",
        "nl-NL", "nl-BE",
        "ko-KR",
        "ja-JP",
        "tr-TR",
    ]

    if knownMultiPart.contains(identifier) {
        // Map to our supported locale codes
        if identifier.hasPrefix("pt") { return "pt-BR" }
        if identifier.hasPrefix("zh-Hans") { return "zh-Hans" }
        // For other multi-part codes, fall through to language-only mapping
    }

    // Extract the language code
    let languageCode: String
    if let lang = locale.language.languageCode?.identifier {
        languageCode = lang
    } else {
        let parts = identifier.split(separator: "-")
        languageCode = parts.first.map(String.init) ?? identifier
    }

    // Map language codes to our supported locales
    switch languageCode {
    case "de": return "de"
    case "es": return "es"
    case "fr": return "fr"
    case "it": return "it"
    case "ja": return "ja"
    case "ko": return "ko"
    case "nl": return "nl"
    case "pt": return "pt-BR"
    case "tr": return "tr"
    case "zh":
        // Determine simplified vs traditional
        if identifier.hasPrefix("zh-Hans") || identifier.hasPrefix("zh-CN") {
            return "zh-Hans"
        }
        // Default to simplified for any zh variant
        return "zh-Hans"
    default: return "en"
    }
}

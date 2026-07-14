//
//  TrainingTextRedactor.swift
//  Pindrop
//
//  Created on 2026-07-14.
//
//  Redacts structured PII from transcript text before it is stored as an opt-in
//  training contribution. Patterns are ported from LogRedactor (Logger.swift) and
//  extended for natural-language dictation: long digit runs (phone/card/account
//  numbers) and @handles.
//
//  LIMITATION (v1): this redactor removes STRUCTURED identifiers only. Free-form
//  personal names in dictated text are NOT detected — that requires on-device NER
//  we don't ship yet, and it is the primary reason ContributionUploader stays
//  NoOp: contributions must not leave the device until name-level redaction
//  exists. Bump `version` whenever patterns change so stored rows record which
//  redactor produced them.
//

import Foundation

struct TrainingTextRedactor {
    /// Persisted on each TrainingContribution as `redactionVersion`.
    static let version = 1

    private static let emailRegex = try! NSRegularExpression(
        pattern: #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#,
        options: [.caseInsensitive]
    )
    private static let uuidRegex = try! NSRegularExpression(
        pattern: #"\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\b"#
    )
    private static let urlRegex = try! NSRegularExpression(
        pattern: #"https?://[^\s,;]+"#,
        options: [.caseInsensitive]
    )
    private static let pathRegex = try! NSRegularExpression(
        pattern: #"(?<![A-Za-z0-9])/(?:Users|Volumes|private|var|tmp|Applications|System|Library|opt)[^\s,;)]*"#
    )
    private static let bearerRegex = try! NSRegularExpression(
        pattern: #"(?i)Bearer\s+[A-Za-z0-9._\-]{12,}"#
    )
    private static let secretValueRegex = try! NSRegularExpression(
        pattern: #"(?i)(api[_-]?key|token|secret|password)\s*[=:]\s*[^\s,;]+"#
    )
    /// Six or more consecutive digits (allowing common separators) — phone, card,
    /// and account numbers as dictated ("call me at 555 0123 4567").
    private static let longDigitRunRegex = try! NSRegularExpression(
        pattern: #"\b\d(?:[\d \-()]{4,}\d)\b"#
    )
    /// Social-style @handles.
    private static let handleRegex = try! NSRegularExpression(
        pattern: #"(?<![A-Za-z0-9])@[A-Za-z0-9_.]{2,}"#
    )

    func redact(_ text: String) -> String {
        guard !text.isEmpty else { return text }

        var output = text
        output = Self.replacingMatches(in: output, regex: Self.emailRegex, template: "<email>")
        output = Self.replacingMatches(in: output, regex: Self.urlRegex, template: "<url>")
        output = Self.replacingMatches(in: output, regex: Self.bearerRegex, template: "Bearer <redacted>")
        output = Self.replacingMatches(in: output, regex: Self.secretValueRegex, template: "$1=<redacted>")
        output = Self.replacingMatches(in: output, regex: Self.pathRegex, template: "<path>")
        output = Self.replacingMatches(in: output, regex: Self.uuidRegex, template: "<uuid>")
        output = Self.replacingMatches(in: output, regex: Self.longDigitRunRegex, template: "<number>")
        output = Self.replacingMatches(in: output, regex: Self.handleRegex, template: "<handle>")
        return output
    }

    private static func replacingMatches(
        in text: String,
        regex: NSRegularExpression,
        template: String
    ) -> String {
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: template)
    }
}

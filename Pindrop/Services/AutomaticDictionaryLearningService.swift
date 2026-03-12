//
//  AutomaticDictionaryLearningService.swift
//  Pindrop
//
//  Created on 2026-03-11.
//

import AppKit
import ApplicationServices
import Foundation

enum FocusedTextObservationEvent {
    case textMayHaveChanged(source: String)
    case focusedElementChanged
    case frontmostApplicationChanged(bundleIdentifier: String?, localizedName: String?, processIdentifier: pid_t)
}

@MainActor
protocol FocusedTextObservationSession: AnyObject {
    var supportsChangeNotifications: Bool { get }
    func invalidate()
}

@MainActor
protocol FocusedTextChangeObserving: AnyObject {
    func beginObservation(
        handler: @escaping @MainActor (FocusedTextObservationEvent) -> Void
    ) -> (any FocusedTextObservationSession)?
}

@MainActor
final class FocusedTextObservationService: FocusedTextChangeObserving {
    private let axProvider: AXProviderProtocol
    private let workspaceNotificationCenter: NotificationCenter

    init(
        axProvider: AXProviderProtocol = SystemAXProvider(),
        workspaceNotificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter
    ) {
        self.axProvider = axProvider
        self.workspaceNotificationCenter = workspaceNotificationCenter
    }

    func beginObservation(
        handler: @escaping @MainActor (FocusedTextObservationEvent) -> Void
    ) -> (any FocusedTextObservationSession)? {
        AXFocusedTextObservationSession(
            axProvider: axProvider,
            workspaceNotificationCenter: workspaceNotificationCenter,
            handler: handler
        )
    }
}

private final class AXFocusedTextObservationSession: FocusedTextObservationSession {
    private let appPID: pid_t
    private let appElement: AXUIElement
    private let focusedElement: AXUIElement
    private let workspaceNotificationCenter: NotificationCenter
    private let handler: @MainActor (FocusedTextObservationEvent) -> Void

    private var observer: AXObserver?
    private var workspaceObserverToken: NSObjectProtocol?
    private var registeredNotifications: [(element: AXUIElement, name: String)] = []
    private(set) var supportsChangeNotifications = false
    private var isInvalidated = false

    init?(
        axProvider: AXProviderProtocol,
        workspaceNotificationCenter: NotificationCenter,
        handler: @escaping @MainActor (FocusedTextObservationEvent) -> Void
    ) {
        guard let appPID = axProvider.frontmostAppPID(),
              let appElement = axProvider.copyFrontmostApplication(),
              let focusedElement = axProvider.elementAttribute(kAXFocusedUIElementAttribute, of: appElement) else {
            return nil
        }

        self.appPID = appPID
        self.appElement = appElement
        self.focusedElement = focusedElement
        self.workspaceNotificationCenter = workspaceNotificationCenter
        self.handler = handler

        var createdObserver: AXObserver?
        let callback: AXObserverCallback = { _, element, notification, refcon in
            guard let refcon else { return }
            let session = Unmanaged<AXFocusedTextObservationSession>.fromOpaque(refcon).takeUnretainedValue()
            session.handleAXNotification(notification as String, element: element)
        }

        guard AXObserverCreate(appPID, callback, &createdObserver) == .success,
              let observer = createdObserver else {
            return nil
        }

        self.observer = observer

        CFRunLoopAddSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(observer),
            .defaultMode
        )

        registerNotification(kAXFocusedUIElementChangedNotification as String, on: appElement)
        registerNotification(kAXValueChangedNotification as String, on: focusedElement)
        registerNotification(kAXSelectedTextChangedNotification as String, on: focusedElement)

        workspaceObserverToken = workspaceNotificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            guard let self else { return }
            Task { @MainActor in
                self.handleWorkspaceNotification(notification)
            }
        }
    }

    deinit {
        if let workspaceObserverToken {
            workspaceNotificationCenter.removeObserver(workspaceObserverToken)
        }

        if let observer {
            for registration in registeredNotifications {
                AXObserverRemoveNotification(observer, registration.element, registration.name as CFString)
            }
            CFRunLoopRemoveSource(
                CFRunLoopGetMain(),
                AXObserverGetRunLoopSource(observer),
                .defaultMode
            )
        }
    }

    func invalidate() {
        guard !isInvalidated else { return }
        isInvalidated = true

        if let workspaceObserverToken {
            workspaceNotificationCenter.removeObserver(workspaceObserverToken)
            self.workspaceObserverToken = nil
        }

        if let observer {
            for registration in registeredNotifications {
                AXObserverRemoveNotification(observer, registration.element, registration.name as CFString)
            }
            CFRunLoopRemoveSource(
                CFRunLoopGetMain(),
                AXObserverGetRunLoopSource(observer),
                .defaultMode
            )
        }

        registeredNotifications.removeAll()
        observer = nil
    }

    private func registerNotification(_ name: String, on element: AXUIElement) {
        guard let observer else { return }

        let result = AXObserverAddNotification(
            observer,
            element,
            name as CFString,
            UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        )

        guard result == .success else { return }
        registeredNotifications.append((element, name))

        if name == kAXValueChangedNotification as String || name == kAXSelectedTextChangedNotification as String {
            supportsChangeNotifications = true
        }
    }

    private func handleAXNotification(_ notification: String, element: AXUIElement) {
        guard !isInvalidated else { return }

        let event: FocusedTextObservationEvent
        switch notification {
        case kAXValueChangedNotification:
            event = .textMayHaveChanged(source: "ax-value-changed")
        case kAXSelectedTextChangedNotification:
            event = .textMayHaveChanged(source: "ax-selected-text-changed")
        case kAXFocusedUIElementChangedNotification:
            if CFEqual(element, appElement) {
                event = .focusedElementChanged
            } else {
                event = .textMayHaveChanged(source: "ax-focused-element-updated")
            }
        default:
            event = .textMayHaveChanged(source: "ax-\(notification)")
        }

        Task { @MainActor in
            self.handler(event)
        }
    }

    private func handleWorkspaceNotification(_ notification: Notification) {
        guard !isInvalidated else { return }
        guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
            return
        }
        guard application.processIdentifier != appPID else { return }

        handler(
            .frontmostApplicationChanged(
                bundleIdentifier: application.bundleIdentifier,
                localizedName: application.localizedName,
                processIdentifier: application.processIdentifier
            )
        )
    }
}

struct AutomaticDictionaryLearningConfiguration {
    let pollInterval: Duration
    let stabilityWindow: Duration
    let observationTimeout: Duration

    init(
        pollInterval: Duration = .milliseconds(500),
        stabilityWindow: Duration = .milliseconds(600),
        observationTimeout: Duration = .seconds(60)
    ) {
        self.pollInterval = pollInterval
        self.stabilityWindow = stabilityWindow
        self.observationTimeout = observationTimeout
    }
}

struct LearnedCorrectionCandidate: Equatable {
    let original: String
    let replacement: String
}

struct LearnedCorrectionMatch: Equatable {
    let candidate: LearnedCorrectionCandidate
    let observedInsertedSegment: String
}

enum AutomaticDictionaryLearningDetectionOutcome: Equatable {
    case learned(LearnedCorrectionMatch)
    case skipped(AutomaticDictionaryLearningSkipReason)
}

enum AutomaticDictionaryLearningSkipReason: Equatable {
    case editingContextChanged
    case invalidSelectedRange
    case noObservedDifference
    case unableToResolveObservedInsertedSegment
    case expectedTokenExtractionFailed
    case observedTokenExtractionFailed
    case expectedSideWasNotLearnableSpan
    case observedSideWasNotSingleToken
    case unchangedToken
    case ambiguousInsertedTokenOccurrence(count: Int)
    case mergedOriginalDidNotMatchReplacement
    case mergedOriginalContainedNonWhitespaceSeparators

    var logDescription: String {
        switch self {
        case .editingContextChanged:
            return "editing-context-changed"
        case .invalidSelectedRange:
            return "invalid-selected-range"
        case .noObservedDifference:
            return "no-observed-difference"
        case .unableToResolveObservedInsertedSegment:
            return "unable-to-resolve-observed-inserted-segment"
        case .expectedTokenExtractionFailed:
            return "expected-token-extraction-failed"
        case .observedTokenExtractionFailed:
            return "observed-token-extraction-failed"
        case .expectedSideWasNotLearnableSpan:
            return "expected-side-not-learnable-span"
        case .observedSideWasNotSingleToken:
            return "observed-side-not-single-token"
        case .unchangedToken:
            return "unchanged-token"
        case .ambiguousInsertedTokenOccurrence(let count):
            return "ambiguous-inserted-token-occurrence-\(count)"
        case .mergedOriginalDidNotMatchReplacement:
            return "merged-original-did-not-match-replacement"
        case .mergedOriginalContainedNonWhitespaceSeparators:
            return "merged-original-contained-non-whitespace-separators"
        }
    }
}

struct AutomaticDictionaryLearningDetector {
    static func detectCorrection(
        preInsertSnapshot: FocusedTextSnapshot,
        insertedText: String,
        observedSnapshot: FocusedTextSnapshot
    ) -> LearnedCorrectionCandidate? {
        switch detectCorrectionOutcome(
            preInsertSnapshot: preInsertSnapshot,
            insertedText: insertedText,
            observedSnapshot: observedSnapshot
        ) {
        case .learned(let match):
            return match.candidate
        case .skipped:
            return nil
        }
    }

    static func detectCorrectionOutcome(
        preInsertSnapshot: FocusedTextSnapshot,
        insertedText: String,
        observedSnapshot: FocusedTextSnapshot
    ) -> AutomaticDictionaryLearningDetectionOutcome {
        guard let expectedInsertedSegment = expectedInsertedSegment(
            preInsertSnapshot: preInsertSnapshot,
            insertedText: insertedText
        ) else {
            return .skipped(.invalidSelectedRange)
        }

        return detectCorrectionOutcome(
            referenceSnapshot: preInsertSnapshot,
            expectedInsertedSegment: expectedInsertedSegment,
            observedSnapshot: observedSnapshot
        )
    }

    static func detectCorrectionOutcome(
        referenceSnapshot: FocusedTextSnapshot,
        expectedInsertedSegment: String,
        observedSnapshot: FocusedTextSnapshot
    ) -> AutomaticDictionaryLearningDetectionOutcome {
        guard isSameEditingContext(referenceSnapshot, observedSnapshot) else {
            return .skipped(.editingContextChanged)
        }

        guard expectedInsertedSegment != observedSnapshot.text else {
            return .skipped(.noObservedDifference)
        }

        let selectedRange = NSRange(
            location: referenceSnapshot.selectedRange.location,
            length: referenceSnapshot.selectedRange.length
        )
        let observedSelectionRange = NSRange(
            location: observedSnapshot.selectedRange.location,
            length: observedSnapshot.selectedRange.length
        )

        guard let observedInsertedRange = resolveObservedInsertedRange(
            originalText: referenceSnapshot.text,
            selectedRange: selectedRange,
            expectedInsertedSegment: expectedInsertedSegment,
            observedText: observedSnapshot.text,
            observedSelectionRange: observedSelectionRange
        ) else {
            return .skipped(.unableToResolveObservedInsertedSegment)
        }

        let observedNSString = observedSnapshot.text as NSString
        let observedInsertedSegment = observedNSString.substring(with: observedInsertedRange)
        guard expectedInsertedSegment != observedInsertedSegment else {
            return .skipped(.noObservedDifference)
        }

        let expectedTokens = tokenMatches(in: expectedInsertedSegment)
        let observedTokens = tokenMatches(in: observedInsertedSegment)
        guard !expectedTokens.isEmpty else {
            return .skipped(.expectedTokenExtractionFailed)
        }
        guard !observedTokens.isEmpty else {
            return .skipped(.observedTokenExtractionFailed)
        }

        let tokenDiff = differingTokenSpans(expected: expectedTokens, observed: observedTokens)
        guard let tokenDiff else { return .skipped(.noObservedDifference) }

        let expectedChangedTokens = Array(expectedTokens[tokenDiff.expectedRange])
        let observedChangedTokens = Array(observedTokens[tokenDiff.observedRange])

        guard observedChangedTokens.count == 1 else {
            return .skipped(.observedSideWasNotSingleToken)
        }

        let observedDiff = observedChangedTokens[0].text
        let expectedDiff: String

        switch expectedChangedTokens.count {
        case 1:
            expectedDiff = expectedChangedTokens[0].text
        case 2...4:
            guard separatorsBetweenTokensAreWhitespaceOnly(
                expectedChangedTokens,
                in: expectedInsertedSegment
            ) else {
                return .skipped(.mergedOriginalContainedNonWhitespaceSeparators)
            }

            let expectedMerged = normalizedMergedTokenCandidate(
                expectedChangedTokens.map(\.text).joined()
            )
            let observedMerged = normalizedMergedTokenCandidate(observedDiff)
            guard !expectedMerged.isEmpty, expectedMerged == observedMerged else {
                return .skipped(.mergedOriginalDidNotMatchReplacement)
            }

            expectedDiff = expectedChangedTokens.map(\.text).joined(separator: " ")
        default:
            return .skipped(.expectedSideWasNotLearnableSpan)
        }

        guard expectedDiff != observedDiff else {
            return .skipped(.unchangedToken)
        }

        let occurrenceCount: Int
        if expectedChangedTokens.count == 1 {
            occurrenceCount = tokenOccurrenceCount(expectedDiff, in: expectedInsertedSegment)
        } else {
            occurrenceCount = tokenSequenceOccurrenceCount(
                expectedChangedTokens.map(\.text),
                in: expectedTokens
            )
        }
        guard occurrenceCount == 1 else {
            return .skipped(.ambiguousInsertedTokenOccurrence(count: occurrenceCount))
        }

        return .learned(
            LearnedCorrectionMatch(
                candidate: LearnedCorrectionCandidate(
                    original: expectedDiff,
                    replacement: observedDiff
                ),
                observedInsertedSegment: observedInsertedSegment
            )
        )
    }

    static func expectedInsertedSegment(
        preInsertSnapshot: FocusedTextSnapshot,
        insertedText: String
    ) -> String? {
        let insertedNSString = insertedText as NSString
        let originalNSString = preInsertSnapshot.text as NSString
        let originalLength = originalNSString.length
        let selectedRange = NSRange(
            location: preInsertSnapshot.selectedRange.location,
            length: preInsertSnapshot.selectedRange.length
        )

        guard selectedRange.location >= 0,
              selectedRange.length >= 0,
              selectedRange.upperBound <= originalLength else {
            return nil
        }

        let expectedText = originalNSString.replacingCharacters(in: selectedRange, with: insertedText)
        let expectedNSString = expectedText as NSString
        let expectedInsertedRange = NSRange(location: selectedRange.location, length: insertedNSString.length)
        guard expectedInsertedRange.upperBound <= expectedNSString.length else {
            return nil
        }

        return expectedNSString.substring(with: expectedInsertedRange)
    }

    static func debugDescription(
        for reason: AutomaticDictionaryLearningSkipReason,
        preInsertSnapshot: FocusedTextSnapshot,
        insertedText: String,
        observedSnapshot: FocusedTextSnapshot
    ) -> String {
        guard let expectedInsertedSegment = expectedInsertedSegment(
            preInsertSnapshot: preInsertSnapshot,
            insertedText: insertedText
        ) else {
            return "preRange=\(preInsertSnapshot.selectedRange.location):\(preInsertSnapshot.selectedRange.length), observedRange=\(observedSnapshot.selectedRange.location):\(observedSnapshot.selectedRange.length), invalidExpectedInsertedSegment=true"
        }

        return debugDescription(
            for: reason,
            referenceSnapshot: preInsertSnapshot,
            expectedInsertedSegment: expectedInsertedSegment,
            observedSnapshot: observedSnapshot
        )
    }

    static func debugDescription(
        for reason: AutomaticDictionaryLearningSkipReason,
        referenceSnapshot: FocusedTextSnapshot,
        expectedInsertedSegment: String,
        observedSnapshot: FocusedTextSnapshot
    ) -> String {
        let selectedRange = NSRange(
            location: referenceSnapshot.selectedRange.location,
            length: referenceSnapshot.selectedRange.length
        )
        let observedSelectionRange = NSRange(
            location: observedSnapshot.selectedRange.location,
            length: observedSnapshot.selectedRange.length
        )
        let expectedInsertedPreview = previewText(expectedInsertedSegment)
        let observedSelectionPreview = previewAroundCaret(
            in: observedSnapshot.text,
            caretLocation: observedSelectionRange.location
        )
        let commonPrefix = commonPrefixLength(expectedInsertedSegment as NSString, observedSnapshot.text as NSString)
        let commonSuffix = commonSuffixLength(
            expectedInsertedSegment as NSString,
            observedSnapshot.text as NSString,
            prefixLength: commonPrefix
        )
        let insertedComparison = "expectedInsertedLength=\((expectedInsertedSegment as NSString).length), observedTextLength=\((observedSnapshot.text as NSString).length), sharedPrefix=\(commonPrefix), sharedSuffix=\(commonSuffix)"

        switch reason {
        case .unableToResolveObservedInsertedSegment:
            let diagnostics = resolveObservedInsertedRangeDiagnostics(
                originalText: referenceSnapshot.text,
                selectedRange: selectedRange,
                expectedInsertedSegment: expectedInsertedSegment,
                observedText: observedSnapshot.text,
                observedSelectionRange: observedSelectionRange
            )
            return "preRange=\(selectedRange.location):\(selectedRange.length), observedRange=\(observedSelectionRange.location):\(observedSelectionRange.length), expectedInserted=\(expectedInsertedPreview), observedAroundCaret=\(observedSelectionPreview), \(insertedComparison), resolver=\(diagnostics)"
        case .noObservedDifference:
            return "preRange=\(selectedRange.location):\(selectedRange.length), observedRange=\(observedSelectionRange.location):\(observedSelectionRange.length), expectedInserted=\(expectedInsertedPreview), observedAroundCaret=\(observedSelectionPreview), \(insertedComparison)"
        default:
            return "preRange=\(selectedRange.location):\(selectedRange.length), observedRange=\(observedSelectionRange.location):\(observedSelectionRange.length), expectedInserted=\(expectedInsertedPreview), observedAroundCaret=\(observedSelectionPreview), \(insertedComparison)"
        }
    }

    private static func resolveObservedInsertedRange(
        originalText: String,
        selectedRange: NSRange,
        expectedInsertedSegment: String,
        observedText: String,
        observedSelectionRange: NSRange
    ) -> NSRange? {
        let originalNSString = originalText as NSString
        let observedNSString = observedText as NSString
        let observedLength = observedNSString.length
        let observedCaretLocation = min(max(0, observedSelectionRange.location), observedLength)

        let prefix = originalNSString.substring(with: NSRange(location: 0, length: selectedRange.location))
        let suffix = originalNSString.substring(with: NSRange(location: selectedRange.upperBound, length: originalNSString.length - selectedRange.upperBound))

        if prefix.isEmpty && suffix.isEmpty {
            return NSRange(location: 0, length: observedLength)
        }

        if isLikelyObservedWholeInsertedSegment(expected: expectedInsertedSegment, observed: observedText) {
            return NSRange(location: 0, length: observedLength)
        }

        let prefixAnchor = trailingAnchor(in: prefix)
        let suffixAnchor = leadingAnchor(in: suffix)

        let startLocation: Int
        if prefixAnchor.isEmpty {
            startLocation = 0
        } else {
            let prefixMatches = allOccurrences(of: prefixAnchor, in: observedText)
            guard let prefixMatch = prefixMatches
                .filter({ $0.upperBound <= observedCaretLocation })
                .max(by: { $0.upperBound < $1.upperBound }) else {
                return nil
            }
            startLocation = prefixMatch.upperBound
        }

        let endLocation: Int
        if suffixAnchor.isEmpty {
            endLocation = observedLength
        } else {
            let suffixMatches = allOccurrences(of: suffixAnchor, in: observedText)
            guard let suffixMatch = suffixMatches
                .filter({ $0.location >= startLocation })
                .min(by: { $0.location < $1.location }) else {
                return nil
            }
            endLocation = suffixMatch.location
        }

        guard endLocation >= startLocation else { return nil }
        return NSRange(location: startLocation, length: endLocation - startLocation)
    }

    private static func resolveObservedInsertedRangeDiagnostics(
        originalText: String,
        selectedRange: NSRange,
        expectedInsertedSegment: String,
        observedText: String,
        observedSelectionRange: NSRange
    ) -> String {
        let originalNSString = originalText as NSString
        let observedNSString = observedText as NSString
        let observedLength = observedNSString.length
        let observedCaretLocation = min(max(0, observedSelectionRange.location), observedLength)

        let prefix = originalNSString.substring(with: NSRange(location: 0, length: selectedRange.location))
        let suffix = originalNSString.substring(with: NSRange(location: selectedRange.upperBound, length: originalNSString.length - selectedRange.upperBound))
        let prefixAnchor = trailingAnchor(in: prefix)
        let suffixAnchor = leadingAnchor(in: suffix)
        let prefixMatches = prefixAnchor.isEmpty ? [] : allOccurrences(of: prefixAnchor, in: observedText)
        let suffixMatches = suffixAnchor.isEmpty ? [] : allOccurrences(of: suffixAnchor, in: observedText)
        let prefixMatchesBeforeCaret = prefixMatches.filter { $0.upperBound <= observedCaretLocation }.count
        let usedWholeObservedFallback = isLikelyObservedWholeInsertedSegment(expected: expectedInsertedSegment, observed: observedText)

        let approximateRange = approximateObservedInsertedRange(
            selectedRange: selectedRange,
            observedText: observedText,
            observedSelectionRange: observedSelectionRange,
            expectedInsertedLength: max(1, (expectedInsertedSegment as NSString).length)
        )
        let approximatePreview = approximateRange.map { preview(in: observedText, range: $0) } ?? "nil"

        return "prefixAnchor=\(previewText(prefixAnchor)), suffixAnchor=\(previewText(suffixAnchor)), prefixMatchesBeforeCaret=\(prefixMatchesBeforeCaret), suffixMatchesTotal=\(suffixMatches.count), observedLength=\(observedLength), wholeObservedFallback=\(usedWholeObservedFallback), approximateRange=\(approximateRange?.location ?? -1):\(approximateRange?.length ?? -1), approximatePreview=\(approximatePreview)"
    }

    private static func approximateObservedInsertedRange(
        selectedRange: NSRange,
        observedText: String,
        observedSelectionRange: NSRange,
        expectedInsertedLength: Int
    ) -> NSRange? {
        let observedNSString = observedText as NSString
        let observedLength = observedNSString.length
        guard observedLength > 0 else { return nil }

        let caretLocation = min(max(0, observedSelectionRange.location), observedLength)
        let baseLength = max(1, expectedInsertedLength)
        let lowerBound = max(0, min(selectedRange.location, caretLocation) - 12)
        let upperBound = min(observedLength, max(selectedRange.location, caretLocation) + baseLength + 12)
        guard upperBound >= lowerBound else { return nil }

        return NSRange(location: lowerBound, length: upperBound - lowerBound)
    }

    private static func trailingAnchor(in text: String, maxLength: Int = 24) -> String {
        let nsText = text as NSString
        guard nsText.length > maxLength else { return text }
        return nsText.substring(with: NSRange(location: nsText.length - maxLength, length: maxLength))
    }

    private static func leadingAnchor(in text: String, maxLength: Int = 24) -> String {
        let nsText = text as NSString
        guard nsText.length > maxLength else { return text }
        return nsText.substring(with: NSRange(location: 0, length: maxLength))
    }

    private static func allOccurrences(of needle: String, in haystack: String) -> [NSRange] {
        guard !needle.isEmpty else { return [] }

        let regex = try? NSRegularExpression(
            pattern: NSRegularExpression.escapedPattern(for: needle),
            options: []
        )
        return regex?.matches(
            in: haystack,
            options: [],
            range: NSRange(location: 0, length: (haystack as NSString).length)
        ).map(\.range) ?? []
    }

    private static func isLikelyObservedWholeInsertedSegment(expected: String, observed: String) -> Bool {
        let expectedNSString = expected as NSString
        let observedNSString = observed as NSString

        guard expectedNSString.length > 0, observedNSString.length > 0 else {
            return false
        }

        let prefixLength = commonPrefixLength(expectedNSString, observedNSString)
        let suffixLength = commonSuffixLength(
            expectedNSString,
            observedNSString,
            prefixLength: prefixLength
        )
        let sharedLength = prefixLength + suffixLength
        let shorterLength = min(expectedNSString.length, observedNSString.length)
        let lengthDelta = abs(expectedNSString.length - observedNSString.length)
        let maxLengthDelta = min(24, max(2, expectedNSString.length / 3))
        let requiredSharedLength = max(
            1,
            shorterLength - min(8, max(2, shorterLength / 4))
        )

        guard lengthDelta <= maxLengthDelta else {
            return false
        }

        return sharedLength >= requiredSharedLength
    }

    private static func preview(in text: String, range: NSRange, radius: Int = 12) -> String {
        let nsText = text as NSString
        guard nsText.length > 0 else { return "\"\"" }
        let lowerBound = max(0, range.location - radius)
        let upperBound = min(nsText.length, range.upperBound + radius)
        let previewRange = NSRange(location: lowerBound, length: upperBound - lowerBound)
        return previewText(nsText.substring(with: previewRange))
    }

    private static func previewAroundCaret(in text: String, caretLocation: Int, radius: Int = 18) -> String {
        let nsText = text as NSString
        guard nsText.length > 0 else { return "\"\"" }
        let clampedCaret = min(max(0, caretLocation), nsText.length)
        let lowerBound = max(0, clampedCaret - radius)
        let upperBound = min(nsText.length, clampedCaret + radius)
        let previewRange = NSRange(location: lowerBound, length: upperBound - lowerBound)
        return previewText(nsText.substring(with: previewRange))
    }

    private static func previewText(_ text: String, maxLength: Int = 60) -> String {
        let normalized = text
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\t", with: "\\t")
        let nsText = normalized as NSString
        let truncated = nsText.length > maxLength
            ? nsText.substring(with: NSRange(location: 0, length: maxLength)) + "..."
            : normalized
        return "\"\(truncated)\""
    }

    static func logToken(_ text: String) -> String {
        previewText(text, maxLength: 24)
    }

    private static func isSameEditingContext(_ lhs: FocusedTextSnapshot, _ rhs: FocusedTextSnapshot) -> Bool {
        lhs.appBundleIdentifier == rhs.appBundleIdentifier &&
            lhs.windowTitle == rhs.windowTitle &&
            lhs.focusedElementRole == rhs.focusedElementRole
    }

    private static func differingRanges(expected: String, observed: String) -> (expectedRange: NSRange, observedRange: NSRange)? {
        let expectedNSString = expected as NSString
        let observedNSString = observed as NSString
        let expectedLength = expectedNSString.length
        let observedLength = observedNSString.length

        let prefixLength = commonPrefixLength(expectedNSString, observedNSString)
        let suffixLength = commonSuffixLength(
            expectedNSString,
            observedNSString,
            prefixLength: prefixLength
        )

        let expectedDiffRange = NSRange(
            location: prefixLength,
            length: max(0, expectedLength - prefixLength - suffixLength)
        )
        let observedDiffRange = NSRange(
            location: prefixLength,
            length: max(0, observedLength - prefixLength - suffixLength)
        )

        guard expectedDiffRange.length > 0 || observedDiffRange.length > 0 else {
            return nil
        }

        return (expectedDiffRange, observedDiffRange)
    }

    private static func commonPrefixLength(_ lhs: NSString, _ rhs: NSString) -> Int {
        let sharedLength = min(lhs.length, rhs.length)
        var prefixLength = 0
        while prefixLength < sharedLength && lhs.character(at: prefixLength) == rhs.character(at: prefixLength) {
            prefixLength += 1
        }
        return prefixLength
    }

    private static func commonSuffixLength(_ lhs: NSString, _ rhs: NSString, prefixLength: Int) -> Int {
        let lhsRemaining = lhs.length - prefixLength
        let rhsRemaining = rhs.length - prefixLength
        let sharedLength = min(lhsRemaining, rhsRemaining)
        guard sharedLength > 0 else { return 0 }

        var suffixLength = 0
        while suffixLength < sharedLength {
            let lhsIndex = lhs.length - suffixLength - 1
            let rhsIndex = rhs.length - suffixLength - 1
            guard lhs.character(at: lhsIndex) == rhs.character(at: rhsIndex) else { break }
            suffixLength += 1
        }
        return suffixLength
    }

    private struct TokenMatch: Equatable {
        let text: String
        let range: NSRange
    }

    private static func tokenMatches(in text: String) -> [TokenMatch] {
        guard let regex = try? NSRegularExpression(
            pattern: #"[[:alnum:]][[:alnum:]'’-]*"#,
            options: []
        ) else {
            return []
        }

        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        return regex.matches(in: text, options: [], range: range).map { match in
            TokenMatch(text: nsText.substring(with: match.range), range: match.range)
        }
    }

    private static func differingTokenSpans(
        expected: [TokenMatch],
        observed: [TokenMatch]
    ) -> (expectedRange: Range<Int>, observedRange: Range<Int>)? {
        let prefixCount = commonTokenPrefixCount(expected, observed)
        let suffixCount = commonTokenSuffixCount(expected, observed, prefixCount: prefixCount)

        let expectedUpperBound = expected.count - suffixCount
        let observedUpperBound = observed.count - suffixCount
        guard expectedUpperBound >= prefixCount, observedUpperBound >= prefixCount else {
            return nil
        }

        let expectedRange = prefixCount..<expectedUpperBound
        let observedRange = prefixCount..<observedUpperBound
        guard !expectedRange.isEmpty || !observedRange.isEmpty else {
            return nil
        }

        return (expectedRange, observedRange)
    }

    private static func commonTokenPrefixCount(
        _ lhs: [TokenMatch],
        _ rhs: [TokenMatch]
    ) -> Int {
        let sharedCount = min(lhs.count, rhs.count)
        var prefixCount = 0
        while prefixCount < sharedCount && lhs[prefixCount].text == rhs[prefixCount].text {
            prefixCount += 1
        }
        return prefixCount
    }

    private static func commonTokenSuffixCount(
        _ lhs: [TokenMatch],
        _ rhs: [TokenMatch],
        prefixCount: Int
    ) -> Int {
        let lhsRemaining = lhs.count - prefixCount
        let rhsRemaining = rhs.count - prefixCount
        let sharedCount = min(lhsRemaining, rhsRemaining)
        guard sharedCount > 0 else { return 0 }

        var suffixCount = 0
        while suffixCount < sharedCount {
            let lhsIndex = lhs.count - suffixCount - 1
            let rhsIndex = rhs.count - suffixCount - 1
            guard lhsIndex >= prefixCount, rhsIndex >= prefixCount else { break }
            guard lhs[lhsIndex].text == rhs[rhsIndex].text else { break }
            suffixCount += 1
        }
        return suffixCount
    }

    private static func separatorsBetweenTokensAreWhitespaceOnly(
        _ tokens: [TokenMatch],
        in text: String
    ) -> Bool {
        guard tokens.count >= 2 else { return true }
        let nsText = text as NSString

        for index in 0..<(tokens.count - 1) {
            let current = tokens[index]
            let next = tokens[index + 1]
            let separatorRange = NSRange(
                location: current.range.upperBound,
                length: next.range.location - current.range.upperBound
            )
            guard separatorRange.length >= 0 else { return false }
            let separator = nsText.substring(with: separatorRange)
            guard separator.unicodeScalars.allSatisfy(CharacterSet.whitespacesAndNewlines.contains) else {
                return false
            }
        }

        return true
    }

    private static func normalizedMergedTokenCandidate(_ text: String) -> String {
        text.unicodeScalars
            .filter(CharacterSet.alphanumerics.contains)
            .map { Character($0).lowercased() }
            .joined()
    }

    private static func expandToTokenRange(
        in text: String,
        around range: NSRange,
        limitingTo limitingRange: NSRange?
    ) -> NSRange? {
        guard range.length > 0 else { return nil }

        let nsText = text as NSString
        let limitLowerBound = limitingRange?.location ?? 0
        let limitUpperBound = limitingRange?.upperBound ?? nsText.length

        var lowerBound = range.location
        var upperBound = range.upperBound

        while lowerBound > limitLowerBound && isTokenCharacter(nsText.character(at: lowerBound - 1)) {
            lowerBound -= 1
        }

        while upperBound < limitUpperBound && isTokenCharacter(nsText.character(at: upperBound)) {
            upperBound += 1
        }

        guard upperBound > lowerBound else { return nil }
        let tokenRange = NSRange(location: lowerBound, length: upperBound - lowerBound)
        let token = nsText.substring(with: tokenRange)

        return isSingleToken(token) ? tokenRange : nil
    }

    private static func isSingleToken(_ text: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: #"[[:alnum:]][[:alnum:]'’-]*"#, options: []) else {
            return false
        }

        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        let matches = regex.matches(in: text, options: [], range: range)
        guard matches.count == 1, let match = matches.first else {
            return false
        }

        return NSEqualRanges(match.range, range)
    }

    private static func isTokenCharacter(_ character: unichar) -> Bool {
        switch character {
        case 39, 45, 8217, 8211, 8212:
            return true
        default:
            guard let scalar = UnicodeScalar(Int(character)) else { return false }
            return CharacterSet.alphanumerics.contains(scalar)
        }
    }

    private static func tokenOccurrenceCount(_ token: String, in text: String) -> Int {
        guard let regex = try? NSRegularExpression(
            pattern: "\\b" + NSRegularExpression.escapedPattern(for: token) + "\\b",
            options: [.caseInsensitive]
        ) else {
            return 0
        }

        return regex.numberOfMatches(
            in: text,
            options: [],
            range: NSRange(location: 0, length: (text as NSString).length)
        )
    }

    private static func tokenSequenceOccurrenceCount(_ tokens: [String], in matches: [TokenMatch]) -> Int {
        guard !tokens.isEmpty, tokens.count <= matches.count else { return 0 }

        let normalizedTokens = tokens.map { $0.localizedLowercase }
        var occurrenceCount = 0
        let maxStart = matches.count - tokens.count

        for start in 0...maxStart {
            let candidate = matches[start..<(start + tokens.count)].map(\.text.localizedLowercase)
            if candidate == normalizedTokens {
                occurrenceCount += 1
            }
        }

        return occurrenceCount
    }
}

@MainActor
final class AutomaticDictionaryLearningService {
    private let snapshotProvider: any FocusedTextSnapshotCapturing
    private let changeObserver: any FocusedTextChangeObserving
    private let dictionaryStore: any LearnedReplacementPersisting
    private let toastService: any ToastShowing
    private let configuration: AutomaticDictionaryLearningConfiguration
    private let clock = ContinuousClock()

    private var pollingTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var observationSession: (any FocusedTextObservationSession)?
    private var sessionState: SessionState?

    private struct SessionState {
        let referenceSnapshot: FocusedTextSnapshot
        var expectedInsertedSegment: String
        var stableMatch: LearnedCorrectionMatch?
        var stableSince: ContinuousClock.Instant?
        var evaluationCount = 0
        var notificationCount = 0
    }

    init(
        snapshotProvider: any FocusedTextSnapshotCapturing,
        changeObserver: (any FocusedTextChangeObserving)? = nil,
        dictionaryStore: any LearnedReplacementPersisting,
        toastService: any ToastShowing,
        configuration: AutomaticDictionaryLearningConfiguration = AutomaticDictionaryLearningConfiguration()
    ) {
        self.snapshotProvider = snapshotProvider
        self.changeObserver = changeObserver ?? FocusedTextObservationService()
        self.dictionaryStore = dictionaryStore
        self.toastService = toastService
        self.configuration = configuration
    }

    convenience init(
        snapshotProvider: any FocusedTextSnapshotCapturing,
        dictionaryStore: any LearnedReplacementPersisting,
        toastService: any ToastShowing,
        configuration: AutomaticDictionaryLearningConfiguration = AutomaticDictionaryLearningConfiguration()
    ) {
        self.init(
            snapshotProvider: snapshotProvider,
            changeObserver: nil,
            dictionaryStore: dictionaryStore,
            toastService: toastService,
            configuration: configuration
        )
    }

    func cancelObservation() {
        if sessionState != nil || pollingTask != nil || observationSession != nil {
            Log.app.infoVisible("Automatic dictionary learning cancelled: starting a new recording or session")
        }
        stopObservation(logMessage: nil)
    }

    func beginObservation(preInsertSnapshot: FocusedTextSnapshot?, insertedText: String) {
        cancelObservation()

        guard let preInsertSnapshot else {
            Log.app.infoVisible("Automatic dictionary learning skipped: no pre-insert focused text snapshot was available")
            return
        }

        let normalizedInsertedText = insertedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedInsertedText.isEmpty else {
            Log.app.infoVisible("Automatic dictionary learning skipped: inserted text was empty after trimming")
            return
        }

        guard let expectedInsertedSegment = AutomaticDictionaryLearningDetector.expectedInsertedSegment(
            preInsertSnapshot: preInsertSnapshot,
            insertedText: insertedText
        ) else {
            Log.app.infoVisible("Automatic dictionary learning skipped: unable to derive the inserted segment from the pre-insert snapshot")
            return
        }

        Log.app.infoVisible(
            "Automatic dictionary learning started: app=\(preInsertSnapshot.appBundleIdentifier ?? "unknown"), role=\(preInsertSnapshot.focusedElementRole ?? "unknown"), insertedLength=\(insertedText.count), selectedRange=\(preInsertSnapshot.selectedRange.location):\(preInsertSnapshot.selectedRange.length)"
        )

        sessionState = SessionState(
            referenceSnapshot: preInsertSnapshot,
            expectedInsertedSegment: expectedInsertedSegment
        )

        observationSession = changeObserver.beginObservation { [weak self] event in
            self?.handleObservationEvent(event)
        }

        if let observationSession {
            if observationSession.supportsChangeNotifications {
                Log.app.infoVisible("Automatic dictionary learning observation mode: AX edit notifications enabled")
            } else {
                Log.app.infoVisible(
                    "Automatic dictionary learning observation mode: AX edit notifications unavailable, using polling fallback"
                )
                startPollingFallback()
            }
        } else {
            Log.app.infoVisible("Automatic dictionary learning observation mode: observer unavailable, using polling fallback")
            startPollingFallback()
        }

        startTimeoutTask()
    }

    private func startPollingFallback() {
        pollingTask?.cancel()
        pollingTask = Task { @MainActor [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                self.evaluateCurrentSnapshot(trigger: "poll")

                do {
                    try await Task.sleep(for: configuration.pollInterval)
                } catch {
                    return
                }
            }
        }
    }

    private func startTimeoutTask() {
        timeoutTask?.cancel()
        timeoutTask = Task { @MainActor [weak self] in
            guard let self else { return }

            do {
                try await Task.sleep(for: configuration.observationTimeout)
            } catch {
                return
            }

            self.stopObservation(
                logMessage: "Automatic dictionary learning timed out after \(self.sessionState?.evaluationCount ?? 0) evaluation(s)"
            )
        }
    }

    private func handleObservationEvent(_ event: FocusedTextObservationEvent) {
        switch event {
        case .textMayHaveChanged(let source):
            sessionState?.notificationCount += 1
            evaluateCurrentSnapshot(trigger: "notification:\(source)")
        case .focusedElementChanged:
            stopObservation(logMessage: "Automatic dictionary learning stopped: focused element changed")
        case .frontmostApplicationChanged(let bundleIdentifier, let localizedName, let processIdentifier):
            Log.app.debugVisible(
                "Automatic dictionary learning received frontmost app activation notification: pid=\(processIdentifier), bundle=\(bundleIdentifier ?? "unknown"), name=\(localizedName ?? "unknown")"
            )
            evaluateCurrentSnapshot(trigger: "notification:frontmost-app-activated")
        }
    }

    private func evaluateCurrentSnapshot(trigger: String) {
        guard var sessionState else { return }

        sessionState.evaluationCount += 1
        let evaluationCount = sessionState.evaluationCount
        self.sessionState = sessionState

        guard let observedSnapshot = snapshotProvider.captureFocusedTextSnapshot() else {
            stopObservation(logMessage: "Automatic dictionary learning stopped: focused text snapshot became unavailable during observation")
            return
        }

        guard observedSnapshot.appBundleIdentifier == sessionState.referenceSnapshot.appBundleIdentifier,
              observedSnapshot.windowTitle == sessionState.referenceSnapshot.windowTitle else {
            stopObservation(
                logMessage: "Automatic dictionary learning stopped: editing context changed to app=\(observedSnapshot.appBundleIdentifier ?? "unknown"), window=\(observedSnapshot.windowTitle ?? "unknown")"
            )
            return
        }

        if observedSnapshot.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            stopObservation(logMessage: "Automatic dictionary learning stopped: observed field was cleared")
            return
        }

        let detectionOutcome = AutomaticDictionaryLearningDetector.detectCorrectionOutcome(
            referenceSnapshot: sessionState.referenceSnapshot,
            expectedInsertedSegment: sessionState.expectedInsertedSegment,
            observedSnapshot: observedSnapshot
        )

        switch detectionOutcome {
        case .learned(let match):
            Log.app.debugVisible(
                "Automatic dictionary learning \(trigger) \(evaluationCount): candidate detected original=\(AutomaticDictionaryLearningDetector.logToken(match.candidate.original)), replacement=\(AutomaticDictionaryLearningDetector.logToken(match.candidate.replacement))"
            )

            if match == sessionState.stableMatch {
                if let stableSince = sessionState.stableSince,
                   stableSince.duration(to: clock.now) >= configuration.stabilityWindow {
                    let shouldAdvanceBaseline = commit(
                        candidate: match.candidate,
                        screenHintRect: observedSnapshot.anchorRect
                    )
                    if shouldAdvanceBaseline {
                        sessionState.expectedInsertedSegment = match.observedInsertedSegment
                    }
                    sessionState.stableMatch = nil
                    sessionState.stableSince = nil
                    self.sessionState = sessionState
                    Log.app.debugVisible(
                        "Automatic dictionary learning \(trigger) \(evaluationCount): advanced baseline insertedLength=\((match.observedInsertedSegment as NSString).length)"
                    )
                }
            } else {
                sessionState.stableMatch = match
                sessionState.stableSince = clock.now
                self.sessionState = sessionState
                Log.app.debugVisible(
                    "Automatic dictionary learning \(trigger) \(evaluationCount): candidate entered stability window original=\(AutomaticDictionaryLearningDetector.logToken(match.candidate.original)), replacement=\(AutomaticDictionaryLearningDetector.logToken(match.candidate.replacement))"
                )
            }
        case .skipped(let reason):
            Log.app.debugVisible(
                "Automatic dictionary learning \(trigger) \(evaluationCount): no learnable correction (\(reason.logDescription)) | \(AutomaticDictionaryLearningDetector.debugDescription(for: reason, referenceSnapshot: sessionState.referenceSnapshot, expectedInsertedSegment: sessionState.expectedInsertedSegment, observedSnapshot: observedSnapshot))"
            )
            if sessionState.stableMatch != nil {
                Log.app.debugVisible("Automatic dictionary learning \(trigger) \(evaluationCount): cleared pending candidate")
            }
            sessionState.stableMatch = nil
            sessionState.stableSince = nil
            self.sessionState = sessionState
        }
    }

    private func stopObservation(logMessage: String?) {
        if let logMessage {
            Log.app.infoVisible(logMessage)
        }

        pollingTask?.cancel()
        pollingTask = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        observationSession?.invalidate()
        observationSession = nil
        sessionState = nil
    }

    private func commit(candidate: LearnedCorrectionCandidate, screenHintRect: CGRect?) -> Bool {
        do {
            guard let change = try dictionaryStore.upsertLearnedReplacement(
                original: candidate.original,
                replacement: candidate.replacement
            ) else {
                Log.app.infoVisible(
                    "Automatic dictionary learning no-op: replacement was already present or could not be persisted original=\(AutomaticDictionaryLearningDetector.logToken(candidate.original)), replacement=\(AutomaticDictionaryLearningDetector.logToken(candidate.replacement))"
                )
                return true
            }

            Log.app.infoVisible(
                "Automatic dictionary learning committed: originalLength=\(candidate.original.count), replacementLength=\(candidate.replacement.count), createdReplacement=\(change.createdReplacement)"
            )
            toastService.show(
                ToastPayload(
                    message: "Added '\(candidate.replacement)' to dictionary",
                    actions: [
                        ToastAction(title: "Undo", role: .primary) { [weak self] in
                            self?.undo(change)
                        }
                    ],
                    screenHintRect: screenHintRect
                )
            )
            return true
        } catch {
            Log.app.errorVisible("Automatic dictionary learning persist failed: \(error.localizedDescription)")
            return false
        }
    }

    private func undo(_ change: LearnedReplacementChange) {
        do {
            try dictionaryStore.undoLearnedReplacement(change)
            Log.app.infoVisible(
                "Automatic dictionary learning undo completed: learnedOriginalLength=\(change.learnedOriginal.count)"
            )
        } catch {
            Log.app.errorVisible("Automatic dictionary learning undo failed: \(error.localizedDescription)")
        }
    }
}

private extension NSRange {
    var upperBound: Int {
        location + length
    }
}

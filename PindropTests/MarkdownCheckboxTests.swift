//
//  MarkdownCheckboxTests.swift
//  Pindrop
//
//  Created on 2026-07-09.
//

import Foundation
import Testing
@testable import Pindrop

@Suite("MarkdownCheckbox")
struct MarkdownCheckboxTests {
    @Test func parsesUncheckedAndCheckedItems() {
        let text = """
        # Tasks
        - [ ] Buy milk
        - [x] Write tests
        - normal bullet
        """

        let matches = MarkdownCheckbox.matches(in: text)
        #expect(matches.count == 2)
        #expect(matches[0].isChecked == false)
        #expect(matches[1].isChecked == true)

        let nsText = text as NSString
        #expect(nsText.substring(with: matches[0].contentRange) == "Buy milk")
        #expect(nsText.substring(with: matches[1].contentRange) == "Write tests")
    }

    @Test func toggleRoundTrip() {
        let original = "- [ ] Open task\n- [x] Done task"
        let matches = MarkdownCheckbox.matches(in: original)
        #expect(matches.count == 2)

        let afterFirst = MarkdownCheckbox.applyingToggle(to: original, match: matches[0])
        #expect(afterFirst.contains("- [x] Open task"))
        #expect(afterFirst.contains("- [x] Done task"))

        let rematched = MarkdownCheckbox.matches(in: afterFirst)
        #expect(rematched.count == 2)
        let afterSecond = MarkdownCheckbox.applyingToggle(to: afterFirst, match: rematched[1])
        #expect(afterSecond.contains("- [x] Open task"))
        #expect(afterSecond.contains("- [ ] Done task"))
    }

    @Test func toggleByUtf16OffsetOnMarker() throws {
        let text = "Intro\n- [ ] Click me"
        let matches = MarkdownCheckbox.matches(in: text)
        try #require(!matches.isEmpty)
        let offset = matches[0].markerRange.location
        let toggled = MarkdownCheckbox.toggle(in: text, utf16Offset: offset)
        #expect(toggled == "Intro\n- [x] Click me")
    }

    @Test func toggleLineByIndex() {
        let text = "line0\n- [ ] line1\nline2"
        let toggled = MarkdownCheckbox.toggleLine(in: text, lineIndex: 1)
        #expect(toggled == "line0\n- [x] line1\nline2")
        #expect(MarkdownCheckbox.toggleLine(in: text, lineIndex: 0) == nil)
    }

    @Test func ignoresNonTaskListLines() {
        let text = """
        [ ] not a list
        * [ ] star bullet
        1. [ ] numbered
        """
        #expect(MarkdownCheckbox.matches(in: text).isEmpty)
    }

    @Test func supportsIndentedTaskItems() {
        let text = "  - [X] Nested"
        let matches = MarkdownCheckbox.matches(in: text)
        #expect(matches.count == 1)
        #expect(matches[0].isChecked)
    }
}

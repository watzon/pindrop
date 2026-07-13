//
//  NotchPanelLayoutTests.swift
//  PindropTests
//
//  Created on 2026-07-13.
//

import Foundation
import Testing

@testable import Pindrop

@Suite
struct NotchPanelLayoutTests {

    /// 16" MacBook Pro-ish geometry: menu bar occupies the strip between
    /// visibleFrame.maxY and frame.maxY.
    private let screenFrame = CGRect(x: 0, y: 0, width: 1728, height: 1117)
    private let visibleFrame = CGRect(x: 0, y: 0, width: 1728, height: 1079)

    private func layout(transcriptActive: Bool, rowHeight: CGFloat = 38) -> NotchPanelLayoutMath.Layout {
        NotchPanelLayoutMath.compute(
            screenFrame: screenFrame,
            visibleFrame: visibleFrame,
            notchWidth: NotchPanelMetrics.fallbackNotchWidth,
            rowHeight: rowHeight,
            transcriptDropActive: transcriptActive
        )
    }

    @Test func panelTopEdgeStaysPinnedToScreenTop() {
        let collapsed = layout(transcriptActive: false)
        let expanded = layout(transcriptActive: true)

        #expect(collapsed.frame.maxY == screenFrame.maxY)
        #expect(expanded.frame.maxY == screenFrame.maxY)
    }

    @Test func transcriptDropExtendsPanelDownwardOnly() {
        let collapsed = layout(transcriptActive: false)
        let expanded = layout(transcriptActive: true)

        #expect(collapsed.frame.height == collapsed.rowHeight)
        #expect(expanded.frame.height == expanded.rowHeight + NotchPanelMetrics.transcriptDropHeight)
        #expect(expanded.frame.width == collapsed.frame.width)
        #expect(expanded.frame.minX == collapsed.frame.minX)
    }

    @Test func panelIsCenteredOnWideScreens() {
        let result = layout(transcriptActive: false)

        #expect(abs(result.frame.midX - visibleFrame.midX) < 0.5)
        #expect(result.frame.width == result.notchWidth + result.sideWidth * 2)
    }

    @Test func sideWidthStaysWithinConfiguredBounds() {
        let wide = layout(transcriptActive: false)
        #expect(wide.sideWidth >= NotchPanelMetrics.minimumSideWidth)
        #expect(wide.sideWidth <= NotchPanelMetrics.maximumSideWidth)

        let narrowVisible = CGRect(x: 0, y: 0, width: 400, height: 700)
        let narrow = NotchPanelLayoutMath.compute(
            screenFrame: CGRect(x: 0, y: 0, width: 400, height: 738),
            visibleFrame: narrowVisible,
            notchWidth: NotchPanelMetrics.fallbackNotchWidth,
            rowHeight: 30,
            transcriptDropActive: false
        )
        #expect(narrow.sideWidth >= NotchPanelMetrics.minimumSideWidth)
        #expect(narrow.sideWidth <= NotchPanelMetrics.maximumSideWidth)
    }

    @Test func narrowScreenClampsPanelInsideVisibleFrame() {
        let narrowVisible = CGRect(x: 0, y: 0, width: 360, height: 700)
        let result = NotchPanelLayoutMath.compute(
            screenFrame: CGRect(x: 0, y: 0, width: 360, height: 738),
            visibleFrame: narrowVisible,
            notchWidth: NotchPanelMetrics.fallbackNotchWidth,
            rowHeight: 30,
            transcriptDropActive: false
        )

        #expect(result.frame.width <= narrowVisible.width - NotchPanelMetrics.horizontalInset * 2)
        #expect(result.frame.minX >= narrowVisible.minX + NotchPanelMetrics.horizontalInset)
    }

    @Test func secondaryDisplayOffsetKeepsPanelOnThatDisplay() {
        // A display positioned to the right of the primary, with its own origin.
        let offsetScreen = CGRect(x: 1728, y: 200, width: 1920, height: 1080)
        let offsetVisible = CGRect(x: 1728, y: 200, width: 1920, height: 1055)
        let result = NotchPanelLayoutMath.compute(
            screenFrame: offsetScreen,
            visibleFrame: offsetVisible,
            notchWidth: NotchPanelMetrics.fallbackNotchWidth,
            rowHeight: 25,
            transcriptDropActive: true
        )

        #expect(result.frame.maxY == offsetScreen.maxY)
        #expect(abs(result.frame.midX - offsetVisible.midX) < 0.5)
        #expect(offsetVisible.minX...offsetVisible.maxX ~= result.frame.minX)
    }
}

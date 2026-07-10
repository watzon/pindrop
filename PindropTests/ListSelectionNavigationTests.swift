//
//  ListSelectionNavigationTests.swift
//  PindropTests
//
//  Created on 2026-07-09.
//

import Testing
@testable import Pindrop

@Suite("ListSelectionNavigation")
struct ListSelectionNavigationTests {

    @Test("empty list returns nil")
    func emptyList() {
        #expect(ListSelectionNavigation.moveIndex(current: nil, count: 0, delta: 1) == nil)
        #expect(ListSelectionNavigation.moveIndex(current: 0, count: 0, delta: -1) == nil)
    }

    @Test("no selection: down selects first, up selects last")
    func noSelectionDefaults() {
        #expect(ListSelectionNavigation.moveIndex(current: nil, count: 5, delta: 1) == 0)
        #expect(ListSelectionNavigation.moveIndex(current: nil, count: 5, delta: -1) == 4)
    }

    @Test("moves within bounds and clamps at ends")
    func moveAndClamp() {
        #expect(ListSelectionNavigation.moveIndex(current: 2, count: 5, delta: 1) == 3)
        #expect(ListSelectionNavigation.moveIndex(current: 2, count: 5, delta: -1) == 1)
        #expect(ListSelectionNavigation.moveIndex(current: 0, count: 5, delta: -1) == 0)
        #expect(ListSelectionNavigation.moveIndex(current: 4, count: 5, delta: 1) == 4)
    }

    @Test("zero delta keeps current selection")
    func zeroDelta() {
        #expect(ListSelectionNavigation.moveIndex(current: 2, count: 5, delta: 0) == 2)
        #expect(ListSelectionNavigation.moveIndex(current: nil, count: 5, delta: 0) == nil)
    }

    @Test("single item list")
    func singleItem() {
        #expect(ListSelectionNavigation.moveIndex(current: nil, count: 1, delta: 1) == 0)
        #expect(ListSelectionNavigation.moveIndex(current: 0, count: 1, delta: 1) == 0)
        #expect(ListSelectionNavigation.moveIndex(current: 0, count: 1, delta: -1) == 0)
    }
}

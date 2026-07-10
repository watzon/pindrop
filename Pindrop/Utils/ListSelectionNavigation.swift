//
//  ListSelectionNavigation.swift
//  Pindrop
//
//  Created on 2026-07-09.
//

import Foundation

/// Pure helpers for keyboard-driven list selection (↑/↓).
enum ListSelectionNavigation {
    /// Moves a selection index within `0..<count`.
    /// - If nothing is selected, a positive delta selects the first item and a
    ///   negative delta selects the last item.
    /// - Movement clamps at the ends (no wrap).
    /// - Returns `nil` when the list is empty.
    static func moveIndex(current: Int?, count: Int, delta: Int) -> Int? {
        guard count > 0 else { return nil }
        guard delta != 0 else { return current }

        guard let current else {
            return delta > 0 ? 0 : count - 1
        }

        let next = current + delta
        if next < 0 { return 0 }
        if next >= count { return count - 1 }
        return next
    }
}

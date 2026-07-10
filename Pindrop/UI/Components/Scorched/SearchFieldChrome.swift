//
//  SearchFieldChrome.swift
//  Pindrop
//
//  Created on 2026-07-09.
//

import SwiftUI

/// Scorched search field chrome: ground bg, line border, magnifier, optional ⌘F hint (spec §4).
struct SearchFieldChrome: View {
    @Binding var text: String
    var placeholder: String = "Search"
    var showsKeyboardHint: Bool = true
    var keyboardHint: String = "⌘F"

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(AppColors.textTertiary)

            TextField(placeholder, text: $text)
                .font(AppTypography.body)
                .foregroundStyle(AppColors.textPrimary)
                .textFieldStyle(.plain)

            if showsKeyboardHint, text.isEmpty {
                Text(keyboardHint)
                    .font(AppTypography.monoSmall)
                    .foregroundStyle(AppColors.textTertiary)
            }
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(AppColors.windowBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(AppColors.border, lineWidth: 1)
        )
    }
}

#Preview("SearchFieldChrome") {
    SearchFieldChrome(text: .constant(""), placeholder: "Search library")
        .frame(width: 240)
        .padding()
        .background(AppColors.contentBackground)
        .themeRefresh()
}

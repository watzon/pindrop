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
    /// Optional external focus binding (⌘F → Library search).
    var isFocused: FocusState<Bool>.Binding? = nil

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(AppColors.textTertiary)

            // Prompt styled as ink-3 (native TextField placeholder is not theme-aware).
            ZStack(alignment: .leading) {
                if text.isEmpty {
                    Text(placeholder)
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.textTertiary)
                        .allowsHitTesting(false)
                }
                textField
            }

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

    @ViewBuilder
    private var textField: some View {
        let field = TextField("", text: $text)
            .font(AppTypography.body)
            .foregroundStyle(AppColors.textPrimary)
            .textFieldStyle(.plain)
        if let isFocused {
            field.focused(isFocused)
        } else {
            field
        }
    }
}

#Preview("SearchFieldChrome") {
    SearchFieldChrome(text: .constant(""), placeholder: "Search library")
        .frame(width: 240)
        .padding()
        .background(AppColors.contentBackground)
        .themeRefresh()
}

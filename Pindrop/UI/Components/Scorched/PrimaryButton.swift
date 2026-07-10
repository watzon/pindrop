//
//  PrimaryButton.swift
//  Pindrop
//
//  Created on 2026-07-10.
//

import SwiftUI

/// Filled-accent primary action button — the one solid accent CTA in the app (spec §10).
/// Radius 8, ~32 pt tall, accent fill, page-color label.
struct PrimaryButton: View {
    let title: String
    var systemImage: String? = nil
    var keyboardHint: String? = nil
    var isEnabled: Bool = true
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 12, weight: .semibold))
                }
                Text(title)
                    .font(AppTypography.label)
                if let keyboardHint, !keyboardHint.isEmpty {
                    Text(keyboardHint)
                        .font(AppTypography.monoSmall)
                        .opacity(0.85)
                }
            }
            .foregroundStyle(AppColors.contentBackground)
            .padding(.horizontal, 12)
            .frame(minHeight: 32)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isEnabled ? AppColors.accent : AppColors.accent.opacity(0.4))
            )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }
}

#Preview("PrimaryButton") {
    HStack(spacing: 12) {
        PrimaryButton(title: "New note", systemImage: "plus", keyboardHint: "⌘N", action: {})
        PrimaryButton(title: "Add word", systemImage: "plus", action: {})
    }
    .padding()
    .background(AppColors.contentBackground)
    .themeRefresh()
}

//
//  DestructiveGhostButton.swift
//  Pindrop
//
//  Created on 2026-07-09.
//

import SwiftUI

/// Destructive ghost button: no fill/border, record-colored icon + label (spec §6).
struct DestructiveGhostButton: View {
    let title: String
    var systemImage: String? = "trash"
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 12, weight: .medium))
                }
                Text(title)
                    .font(AppTypography.label)
            }
            .foregroundStyle(AppColors.error)
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview("DestructiveGhostButton") {
    DestructiveGhostButton(title: "Delete", action: {})
        .padding()
        .background(AppColors.windowBackground)
        .themeRefresh()
}

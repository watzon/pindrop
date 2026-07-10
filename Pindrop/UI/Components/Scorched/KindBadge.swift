//
//  KindBadge.swift
//  Pindrop
//
//  Created on 2026-07-09.
//

import SwiftUI

/// Kind badge pill (spec §6): accent-soft bg, accent label + optional icon.
struct KindBadge: View {
    let title: String
    var systemImage: String? = "mic.fill"

    var body: some View {
        HStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .semibold))
            }
            Text(title)
                .font(AppTypography.badge)
        }
        .foregroundStyle(AppColors.accent)
        .padding(.vertical, 3)
        .padding(.horizontal, 10)
        .background(
            Capsule(style: .continuous)
                .fill(AppColors.accentBackground)
        )
    }
}

#Preview("KindBadge") {
    HStack(spacing: 8) {
        KindBadge(title: "Dictation")
        KindBadge(title: "Meeting", systemImage: "person.2.fill")
        KindBadge(title: "Media", systemImage: "headphones")
    }
    .padding()
    .background(AppColors.contentBackground)
    .themeRefresh()
}

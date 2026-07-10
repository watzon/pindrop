//
//  SectionHeader.swift
//  Pindrop
//
//  Created on 2026-07-09.
//

import SwiftUI

/// Uppercase section label + hairline rule + trailing meta (spec §5).
/// Optional `trailingContent` supports accent actions (e.g. Home "Open Library →").
struct SectionHeader<TrailingContent: View>: View {
    let title: String
    var trailing: String? = nil
    var isFirst: Bool = true
    private let trailingContent: TrailingContent

    init(
        title: String,
        trailing: String? = nil,
        isFirst: Bool = true,
        @ViewBuilder trailingContent: () -> TrailingContent = { EmptyView() }
    ) {
        self.title = title
        self.trailing = trailing
        self.isFirst = isFirst
        self.trailingContent = trailingContent()
    }

    var body: some View {
        HStack(spacing: 10) {
            Text(title.uppercased())
                .font(AppTypography.sectionHeader)
                .foregroundStyle(AppColors.textTertiary)
                .tracking(0.88)

            Rectangle()
                .fill(AppColors.border)
                .frame(height: 1)
                .frame(maxWidth: .infinity)

            if let trailing {
                Text(trailing)
                    .font(AppTypography.sectionHeader)
                    .foregroundStyle(AppColors.textSecondary)
            }

            trailingContent
        }
        .frame(height: 26)
        .padding(.top, isFirst ? 0 : 24)
    }
}

#Preview("SectionHeader") {
    VStack(alignment: .leading, spacing: 0) {
        SectionHeader(title: "Today", trailing: "4", isFirst: true)
        SectionHeader(title: "Yesterday", trailing: "12", isFirst: false)
        SectionHeader(title: "Recent", isFirst: false) {
            Text("Open Library →")
                .font(AppTypography.sectionHeader)
                .foregroundStyle(AppColors.accent)
        }
    }
    .padding(.horizontal, 24)
    .padding(.vertical, 16)
    .background(AppColors.contentBackground)
    .themeRefresh()
}

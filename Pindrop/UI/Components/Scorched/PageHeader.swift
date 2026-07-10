//
//  PageHeader.swift
//  Pindrop
//
//  Created on 2026-07-09.
//

import SwiftUI

/// Page title row: Newsreader title + Inter meta + trailing accessory (spec §4).
struct PageHeader<Trailing: View>: View {
    let title: String
    var meta: String? = nil
    @ViewBuilder var trailing: () -> Trailing

    init(title: String, meta: String? = nil, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.title = title
        self.meta = meta
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                Text(title)
                    .font(AppTypography.pageTitle)
                    .tracking(AppTypography.pageTitleTracking)
                    .foregroundStyle(AppColors.textPrimary)

                if let meta, !meta.isEmpty {
                    Text(meta)
                        .font(AppTypography.bodyMeta)
                        .foregroundStyle(AppColors.textSecondary)
                }
            }

            Spacer(minLength: 12)

            trailing()
        }
    }
}

extension PageHeader where Trailing == EmptyView {
    init(title: String, meta: String? = nil) {
        self.init(title: title, meta: meta) { EmptyView() }
    }
}

#Preview("PageHeader") {
    PageHeader(title: "Library", meta: "128 items") {
        SearchFieldChrome(text: .constant(""), placeholder: "Search", showsKeyboardHint: true)
            .frame(width: 240)
    }
    .padding(40)
    .background(AppColors.contentBackground)
    .themeRefresh()
}

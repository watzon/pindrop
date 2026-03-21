//
//  MainContentPageLayout.swift
//  Pindrop
//
//  Created on 2026-03-20.
//

import SwiftUI

struct MainContentPageLayout<Header: View, Content: View>: View {
    let scrollContent: Bool
    let showsIndicators: Bool
    let headerBottomPadding: CGFloat
    let contentTopPadding: CGFloat
    let header: Header
    let content: Content

    init(
        scrollContent: Bool,
        showsIndicators: Bool = false,
        headerBottomPadding: CGFloat = AppTheme.Spacing.xxl,
        contentTopPadding: CGFloat = 0,
        @ViewBuilder header: () -> Header,
        @ViewBuilder content: () -> Content
    ) {
        self.scrollContent = scrollContent
        self.showsIndicators = showsIndicators
        self.headerBottomPadding = headerBottomPadding
        self.contentTopPadding = contentTopPadding
        self.header = header()
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, AppTheme.Spacing.xxl)
                .padding(.top, AppTheme.Window.mainContentTopInset)
                .padding(.bottom, headerBottomPadding)
                .background(AppColors.contentBackground)

            if scrollContent {
                ScrollView(showsIndicators: showsIndicators) {
                    contentContainer
                }
            } else {
                contentContainer
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(AppColors.contentBackground)
        .themeRefresh()
    }

    private var contentContainer: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, AppTheme.Spacing.xxl)
            .padding(.top, contentTopPadding)
            .padding(.bottom, AppTheme.Spacing.xxl)
    }
}

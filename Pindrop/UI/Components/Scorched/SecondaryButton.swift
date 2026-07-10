//
//  SecondaryButton.swift
//  Pindrop
//
//  Created on 2026-07-09.
//

import SwiftUI

/// Secondary action button: page bg, line border, radius 8 (spec §6).
struct SecondaryButton: View {
    let title: String
    var systemImage: String? = nil
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
            .foregroundStyle(AppColors.textPrimary)
            .padding(.vertical, 6)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(AppColors.contentBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(AppColors.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

/// Export menu chrome matching `SecondaryButton` metrics (spec §6).
struct ExportMenuButton: View {
    let title: String
    var systemImage: String? = "square.and.arrow.up"
    let formats: [TranscriptExportFormat]
    var formatTitle: (TranscriptExportFormat) -> String
    var onSelect: (TranscriptExportFormat) -> Void

    var body: some View {
        Menu {
            ForEach(formats, id: \.rawValue) { format in
                Button(formatTitle(format)) {
                    onSelect(format)
                }
            }
        } label: {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 12, weight: .medium))
                }
                Text(title)
                    .font(AppTypography.label)
            }
            .foregroundStyle(AppColors.textPrimary)
            .padding(.vertical, 6)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(AppColors.contentBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(AppColors.border, lineWidth: 1)
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

#Preview("SecondaryButton") {
    HStack(spacing: 8) {
        SecondaryButton(title: "Copy", systemImage: "doc.on.doc", action: {})
        SecondaryButton(title: "Export", systemImage: "square.and.arrow.up", action: {})
    }
    .padding()
    .background(AppColors.windowBackground)
    .themeRefresh()
}

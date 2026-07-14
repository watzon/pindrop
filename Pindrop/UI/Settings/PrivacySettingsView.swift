//
//  PrivacySettingsView.swift
//  Pindrop
//
//  Created on 2026-07-14.
//

import AppKit
import SwiftData
import SwiftUI

struct PrivacySettingsView: View {
    @ObservedObject var settings: SettingsStore

    @Environment(\.locale) private var locale
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TrainingContribution.createdAt, order: .reverse)
    private var contributions: [TrainingContribution]

    @State private var errorMessage: String?
    @State private var showingReviewSheet = false
    @State private var showingDeleteConfirmation = false

    var body: some View {
        SettingsPaneStack {
            SettingsGroupCard {
                SettingsRow(showSeparator: true) {
                    SettingsRowLabel(
                        title: localized("Share anonymous usage data", locale: locale),
                        subtitle: localized("Anonymous diagnostics and usage signals. Never transcript text, audio, or personal content.", locale: locale)
                    )
                } control: {
                    SettingsToggle(
                        isOn: $settings.telemetryEnabled,
                        label: localized("Share anonymous usage data", locale: locale)
                    )
                    .accessibilityIdentifier("settings.toggle.telemetryEnabled")
                }

                SettingsRow(showSeparator: false) {
                    SettingsRowLabel(
                        title: localized("What does Pindrop collect?", locale: locale)
                    )
                } control: {
                    SettingsAccentLink(
                        title: localized("Learn More", locale: locale)
                    ) {
                        NSWorkspace.shared.open(TelemetryConsentView.collectionDetailsURL)
                    }
                    .accessibilityIdentifier("settings.link.telemetryDetails")
                }
            }

            SettingsGroupCard {
                SettingsRow(showSeparator: true) {
                    SettingsRowLabel(
                        title: localized("Contribute transcription fixes", locale: locale),
                        subtitle: localized("Keep before-and-after text pairs when AI enhancement or your edits improve a transcript. Stored only on this Mac — nothing is uploaded.", locale: locale)
                    )
                } control: {
                    SettingsToggle(
                        isOn: $settings.trainingDataContributionEnabled,
                        label: localized("Contribute transcription fixes", locale: locale)
                    )
                    .accessibilityIdentifier("settings.toggle.trainingDataContributionEnabled")
                }

                SettingsRow(showSeparator: false) {
                    SettingsRowLabel(
                        title: localized("Stored text pairs", locale: locale),
                        subtitle: "\(contributions.count)"
                    )
                } control: {
                    HStack(spacing: 8) {
                        Button {
                            showingReviewSheet = true
                        } label: {
                            SettingsMenuButton(
                                title: localized("Review…", locale: locale),
                                showsChevron: false
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("settings.button.reviewContributions")

                        Button {
                            exportContributions()
                        } label: {
                            SettingsMenuButton(
                                title: localized("Export JSONL…", locale: locale),
                                showsChevron: false
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(contributions.isEmpty)
                        .accessibilityIdentifier("settings.button.exportContributions")
                    }
                }
            }

            SettingsGroupCard {
                SettingsRow(showSeparator: true) {
                    SettingsRowLabel(
                        title: localized("Diagnostics", locale: locale),
                        subtitle: localized("Logs never include transcript text", locale: locale)
                    )
                } control: {
                    EmptyView()
                }

                SettingsRow(showSeparator: false) {
                    SettingsRowLabel(title: localized("Export Logs…", locale: locale))
                } control: {
                    Button {
                        SettingsLogExport.presentExportPanel(locale: locale) { message in
                            errorMessage = message
                        }
                    } label: {
                        SettingsMenuButton(
                            title: localized("Export Logs…", locale: locale),
                            showsChevron: false
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("settings.button.privacyExportLogs")
                }
            }

            if !contributions.isEmpty {
                SettingsDestructiveFooter(
                    title: localized("Delete all contributions…", locale: locale)
                ) {
                    showingDeleteConfirmation = true
                }
                .accessibilityIdentifier("settings.button.deleteAllContributions")
            }
        }
        .sheet(isPresented: $showingReviewSheet) {
            ContributionReviewSheet(contributions: contributions)
        }
        .alert(
            localized("Delete all stored text pairs?", locale: locale),
            isPresented: $showingDeleteConfirmation
        ) {
            Button(localized("Cancel", locale: locale), role: .cancel) {}
            Button(localized("Delete", locale: locale), role: .destructive) {
                deleteAllContributions()
            }
        } message: {
            Text(localized("This permanently deletes all stored text pairs from this Mac.", locale: locale))
        }
        .alert(
            localized("Error", locale: locale),
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button(localized("OK", locale: locale), role: .cancel) {}
        } message: {
            if let errorMessage {
                Text(errorMessage)
            }
        }
    }

    private func exportContributions() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "pindrop-training-data.jsonl"
        panel.canCreateDirectories = true
        panel.message = localized("Choose where to save the training data file.", locale: locale)
        let data = ContributionService.jsonlData(from: contributions)
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try data.write(to: url)
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } catch {
                Log.ui.error("Failed to export training contributions: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func deleteAllContributions() {
        do {
            try ContributionService.deleteAll(in: modelContext)
        } catch {
            Log.ui.error("Failed to delete training contributions: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }
    }
}

/// Minimal read-only list of stored before/after pairs so users can inspect
/// exactly what the contribution program has collected.
private struct ContributionReviewSheet: View {
    let contributions: [TrainingContribution]

    @Environment(\.locale) private var locale
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(localized("Training Data", locale: locale))
                    .font(AppTypography.labelStrongSelected)
                    .foregroundStyle(AppColors.textPrimary)
                Spacer()
                Button(localized("Close", locale: locale)) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding(.bottom, 12)

            if contributions.isEmpty {
                Text(localized("No contributions yet. Pairs are stored when AI enhancement or manual edits change a transcript.", locale: locale))
                    .font(AppTypography.captionLarge)
                    .foregroundStyle(AppColors.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(contributions) { contribution in
                            ContributionPairRow(contribution: contribution)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(20)
        .frame(width: 540, height: 440)
        .background(AppColors.windowBackground)
        .themeRefresh()
    }
}

private struct ContributionPairRow: View {
    let contribution: TrainingContribution

    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(contribution.createdAt.formatted(date: .abbreviated, time: .shortened))
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textTertiary)

            VStack(alignment: .leading, spacing: 4) {
                labeledText(
                    label: localized("Original", locale: locale),
                    text: contribution.inputText
                )
                labeledText(
                    label: localized("Corrected", locale: locale),
                    text: contribution.targetText
                )
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(AppColors.contentBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(AppColors.border, lineWidth: 1)
            )
        }
    }

    private func labeledText(label: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textSecondary)
            Text(text)
                .font(AppTypography.captionLarge)
                .foregroundStyle(AppColors.textPrimary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview {
    PrivacySettingsView(settings: SettingsStore())
        .frame(width: 620, height: 560)
        .background(AppColors.windowBackground)
        .themeRefresh()
        .modelContainer(
            try! ModelContainer(
                for: TrainingContribution.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            )
        )
}

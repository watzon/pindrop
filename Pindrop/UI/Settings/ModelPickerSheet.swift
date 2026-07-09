//
//  ModelPickerSheet.swift
//  Pindrop
//
//  Created on 2026-07-09.
//

import SwiftUI

/// Searchable modal picker over a provider's fetched model list for one assignment purpose.
struct ModelPickerSheet: View {
    let title: String
    let models: [AIModelService.AIModel]
    let selected: String?
    let onSelect: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @State private var query = ""

    private var filtered: [AIModelService.AIModel] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return models }
        return models.filter {
            $0.name.lowercased().contains(q) || $0.id.lowercased().contains(q)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                Button(localized("Done", locale: locale)) {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("settings.button.modelPickerDone")
            }
            .padding()

            Divider()

            if models.isEmpty {
                ContentUnavailableView {
                    Label(
                        localized("No models available", locale: locale),
                        systemImage: "tray"
                    )
                } description: {
                    Text(localized("Refresh the provider or open Edit to fetch models.", locale: locale))
                }
                .frame(maxHeight: .infinity)
                .accessibilityIdentifier("settings.modelPicker.empty")
            } else {
                List {
                    ForEach(filtered) { model in
                        Button {
                            onSelect(model.id)
                            dismiss()
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(model.name)
                                    Text(model.id)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if model.id == selected {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.tint)
                                }
                            }
                            .contentShape(Rectangle())
                            .padding(.vertical, 2)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("settings.modelPicker.row.\(model.id)")
                    }
                }
                .searchable(
                    text: $query,
                    placement: .sidebar,
                    prompt: localized("Search models", locale: locale)
                )
                .accessibilityIdentifier("settings.modelPicker.list")
            }
        }
        .frame(width: 440, height: 500)
        .accessibilityIdentifier("settings.modelPicker.sheet")
    }
}

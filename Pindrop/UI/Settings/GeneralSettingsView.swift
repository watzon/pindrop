//
//  GeneralSettingsView.swift
//  Pindrop
//
//  Created on 2026-01-25.
//

import SwiftUI

struct GeneralSettingsView: View {
    @ObservedObject var settings: SettingsStore
    
    var body: some View {
        Form {
            Section {
                Picker("Output Mode:", selection: $settings.outputMode) {
                    Text("Clipboard").tag("clipboard")
                    Text("Direct Insert").tag("directInsert")
                }
                .pickerStyle(.radioGroup)
                
                Text("Choose how transcribed text is delivered")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Output")
                    .font(.headline)
            }
            
            Section {
                Picker("Language:", selection: .constant("English")) {
                    Text("English").tag("English")
                }
                .disabled(true)
                
                Text("Additional languages coming soon")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Language")
                    .font(.headline)
            }
        }
        .formStyle(.grouped)
        .frame(width: 500)
    }
}

#Preview {
    GeneralSettingsView(settings: SettingsStore())
}

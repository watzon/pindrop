//
//  UpdateSettingsView.swift
//  Pindrop
//
//  Created on 2026-02-02.
//

import SwiftUI

struct UpdateSettingsView: View {
    @State private var updateService = UpdateService()
    @AppStorage("automaticallyCheckForUpdates") private var automaticallyCheckForUpdates = true
    
    var body: some View {
        VStack(spacing: 20) {
            SettingsCard(title: "Updates", icon: "arrow.triangle.2.circlepath") {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Automatic Updates")
                                .font(.body)
                            Text("Automatically check for new versions")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                        
                        Toggle("", isOn: $automaticallyCheckForUpdates)
                            .toggleStyle(.switch)
                            .labelsHidden()
                            .onChange(of: automaticallyCheckForUpdates) { _, newValue in
                                updateService.automaticallyChecksForUpdates = newValue
                            }
                    }
                    
                    Divider()
                    
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Check for Updates")
                                .font(.body)
                            Text("Manually check for new versions now")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                        
                        Button("Check Now") {
                            updateService.checkForUpdates()
                        }
                        .disabled(!updateService.canCheckForUpdates)
                    }
                }
            }
        }
        .padding(AppTheme.Spacing.lg)
        .onAppear {
            updateService.automaticallyChecksForUpdates = automaticallyCheckForUpdates
        }
    }
}

#Preview {
    UpdateSettingsView()
        .padding()
        .frame(width: 500)
}

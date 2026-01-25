//
//  HotkeysSettingsView.swift
//  Pindrop
//
//  Created on 2026-01-25.
//

import SwiftUI

struct HotkeysSettingsView: View {
    @ObservedObject var settings: SettingsStore
    @State private var isRecordingToggle = false
    @State private var isRecordingPushToTalk = false
    
    var body: some View {
        Form {
            Section {
                HStack {
                    Text("Toggle Recording:")
                        .frame(width: 150, alignment: .trailing)
                    
                    TextField("Hotkey", text: $settings.toggleHotkey)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 150)
                        .disabled(true)
                    
                    Button(isRecordingToggle ? "Recording..." : "Record") {
                        isRecordingToggle.toggle()
                    }
                    .buttonStyle(.bordered)
                    .disabled(isRecordingToggle)
                }
                
                Text("Press the button and then press your desired key combination")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Toggle Mode")
                    .font(.headline)
            }
            
            Section {
                HStack {
                    Text("Push-to-Talk:")
                        .frame(width: 150, alignment: .trailing)
                    
                    TextField("Hotkey", text: $settings.pushToTalkHotkey)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 150)
                        .disabled(true)
                    
                    Button(isRecordingPushToTalk ? "Recording..." : "Record") {
                        isRecordingPushToTalk.toggle()
                    }
                    .buttonStyle(.bordered)
                    .disabled(isRecordingPushToTalk)
                }
                
                Text("Hold this key to record, release to stop")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Push-to-Talk Mode")
                    .font(.headline)
            }
        }
        .formStyle(.grouped)
        .frame(width: 500)
    }
}

#Preview {
    HotkeysSettingsView(settings: SettingsStore())
}

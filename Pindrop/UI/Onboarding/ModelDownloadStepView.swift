//
//  ModelDownloadStepView.swift
//  Pindrop
//
//  Created on 2026-01-25.
//

import SwiftUI

struct ModelDownloadStepView: View {
    var modelManager: ModelManager
    var transcriptionService: TranscriptionService
    let modelName: String
    let onComplete: () -> Void
    let onCancel: () -> Void
    
    @State private var downloadError: String?
    @State private var hasStarted = false
    
    private var selectedModel: ModelManager.WhisperModel? {
        modelManager.availableModels.first { $0.name == modelName }
    }
    
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            
            progressIndicator
            
            statusText
            
            if downloadError != nil {
                errorView
            }
            
            Spacer()
            
            actionButtons
        }
        .padding(40)
        .task {
            await startDownload()
        }
    }
    
    private var progressIndicator: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.2), lineWidth: 8)
                .frame(width: 120, height: 120)
            
            Circle()
                .trim(from: 0, to: modelManager.downloadProgress)
                .stroke(
                    AppColors.accent,
                    style: StrokeStyle(lineWidth: 8, lineCap: .round)
                )
                .frame(width: 120, height: 120)
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.3), value: modelManager.downloadProgress)
            
            VStack(spacing: 4) {
                if modelManager.isDownloading {
                    Text("\(Int(modelManager.downloadProgress * 100))%")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                } else if downloadError != nil {
                    IconView(icon: .warning, size: 32)
                        .foregroundStyle(.orange)
                } else {
                    IconView(icon: .circleCheck, size: 32)
                        .foregroundStyle(.green)
                }
            }
        }
        .padding(20)
    }
    
    private var statusText: some View {
        VStack(spacing: 8) {
            Text(statusTitle)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
            
            Text(statusSubtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
    
    private var statusTitle: String {
        if downloadError != nil {
            return "Download Failed"
        } else if modelManager.isDownloading {
            if modelManager.downloadProgress > 0.8 {
                return "Preparing Model..."
            }
            return "Downloading \(selectedModel?.displayName ?? "Model")..."
        } else {
            return "Download Complete!"
        }
    }
    
    private var statusSubtitle: String {
        if downloadError != nil {
            return "Please check your internet connection and try again."
        } else if modelManager.isDownloading {
            if let model = selectedModel {
                let downloadedMB = Int(Double(model.sizeInMB) * modelManager.downloadProgress)
                return "\(downloadedMB) / \(model.sizeInMB) MB"
            }
            return "Please wait..."
        } else {
            return "Your model is ready to use."
        }
    }
    
    @ViewBuilder
    private var errorView: some View {
        if let error = downloadError {
            Text(error)
                .font(.caption)
                .foregroundStyle(.red)
                .padding()
                .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
        }
    }
    
    private var actionButtons: some View {
        HStack(spacing: 16) {
            if modelManager.isDownloading {
                Button("Cancel") {
                    onCancel()
                }
                .buttonStyle(.bordered)
            } else if downloadError != nil {
                Button("Go Back") {
                    onCancel()
                }
                .buttonStyle(.bordered)
                
                Button("Retry") {
                    downloadError = nil
                    Task { await startDownload() }
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button(action: onComplete) {
                    Text("Continue")
                        .font(.headline)
                        .frame(maxWidth: 200)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
    
    private func startDownload() async {
        guard !hasStarted else { return }
        hasStarted = true

        // Check if model is already downloaded
        if modelManager.isModelDownloaded(modelName) {
            Log.model.info("Model \(modelName) already downloaded, skipping download step")
            Task.detached { @MainActor in
                try? await self.transcriptionService.loadModel(modelName: self.modelName)
            }
            try? await Task.sleep(for: .milliseconds(300))
            onComplete()
            return
        }

        do {
            try await modelManager.downloadModel(named: modelName)

            Task.detached { @MainActor in
                try? await self.transcriptionService.loadModel(modelName: self.modelName)
            }

            try? await Task.sleep(for: .milliseconds(300))
            onComplete()
        } catch {
            downloadError = error.localizedDescription
            hasStarted = false
        }
    }
}

#if DEBUG
struct ModelDownloadStepView_Previews: PreviewProvider {
    static var previews: some View {
        ModelDownloadStepView(
            modelManager: PreviewModelManagerDownload(),
            transcriptionService: PreviewTranscriptionServiceDownload(),
            modelName: "openai_whisper-base.en",
            onComplete: {},
            onCancel: {}
        )
        .frame(width: 800, height: 600)
    }
}

final class PreviewModelManagerDownload: ModelManager {
    override init() {
        // Skip async initialization to avoid launching WhisperKit in preview
    }
}

final class PreviewTranscriptionServiceDownload: TranscriptionService {
    override init() {
        // Skip model loading in preview
    }
}
#endif

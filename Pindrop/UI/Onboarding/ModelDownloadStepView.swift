//
//  ModelDownloadStepView.swift
//  Pindrop
//
//  Created on 2026-01-25.
//

import SwiftUI

struct DownloadETAEstimator: Equatable, Sendable {
    private struct Sample: Equatable, Sendable {
        let date: Date
        let progress: Double
    }

    private var samples: [Sample] = []

    mutating func record(progress: Double, at date: Date = Date()) {
        let clamped = min(max(progress, 0), 1)
        if let last = samples.last, clamped < last.progress {
            samples.removeAll(keepingCapacity: true)
        }
        guard samples.last?.progress != clamped else { return }
        samples.append(Sample(date: date, progress: clamped))
        let cutoff = date.addingTimeInterval(-15)
        samples = Array(samples.suffix(8).drop { $0.date < cutoff })
    }

    var remainingSeconds: TimeInterval? {
        guard let first = samples.first,
              let last = samples.last,
              last.date > first.date,
              last.progress > first.progress,
              last.progress < 1
        else { return nil }

        let rate = (last.progress - first.progress) / last.date.timeIntervalSince(first.date)
        guard rate > 0.000_01 else { return nil }
        return max(1, (1 - last.progress) / rate)
    }
}

struct ModelDownloadStepView: View {
    var modelManager: ModelManager
    var transcriptionService: TranscriptionService
    let modelName: String
    let onComplete: () -> Void
    let onCancel: () -> Void

    @Environment(\.locale) private var locale
    @State private var downloadError: String?
    @State private var hasStarted = false
    @State private var etaEstimator = DownloadETAEstimator()

    private var selectedModel: ModelManager.WhisperModel? {
        modelManager.availableModels.first { $0.name == modelName }
    }

    private var activeSnapshot: ModelManager.DownloadSnapshot? {
        guard modelManager.downloadSnapshot?.modelName == modelName else {
            return nil
        }

        return modelManager.downloadSnapshot
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(statusTitle)
                .font(OnboardingType.stepHeading)
                .tracking(-0.42)
                .foregroundStyle(AppColors.textPrimary)

            Text(statusSubtitle)
                .font(OnboardingType.stepSubtitle)
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.top, 8)

            progressIndicator
                .padding(.top, 32)

            if downloadError != nil {
                errorView.padding(.top, 18)
            } else {
                hintRow.padding(.top, 30)
            }

            actionButtons.padding(.top, 24)
        }
        .task {
            await startDownload()
        }
        .onChange(of: modelManager.downloadProgress, initial: true) { _, progress in
            etaEstimator.record(progress: progress)
        }
    }

    private var progressIndicator: some View {
        VStack(spacing: 10) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(AppColors.border)
                    Capsule()
                        .fill(AppColors.accent)
                        .frame(width: proxy.size.width * max(0, min(1, modelManager.downloadProgress)))
                }
            }
            .frame(height: 8)
            .clipShape(.capsule)
            .appAnimation(.normal, value: modelManager.downloadProgress)

            HStack {
                Text(downloadMeta)
                    .foregroundStyle(AppColors.textSecondary)
                Spacer()
                Text(etaText)
                    .foregroundStyle(AppColors.textTertiary)
            }
            .font(AppTypography.monoTime)
        }
        .frame(width: 440)
    }

    private var etaText: String {
        guard modelManager.isDownloading else {
            return "\(Int(modelManager.downloadProgress * 100))%"
        }
        guard let seconds = etaEstimator.remainingSeconds else {
            return localized("Estimating time remaining…", locale: locale)
        }
        if seconds < 90 {
            return String(
                format: localized("about %d s left", locale: locale),
                max(1, Int(seconds.rounded()))
            )
        }
        return String(
            format: localized("about %d min left", locale: locale),
            max(1, Int((seconds / 60).rounded()))
        )
    }

    private var downloadMeta: String {
        guard let model = selectedModel else { return localized("Please wait...", locale: locale) }
        let downloadedMB = Int(Double(model.sizeInMB) * modelManager.downloadProgress)
        return String(
            format: localized("%@ of %@", locale: locale),
            formatStorage(downloadedMB),
            formatStorage(model.sizeInMB)
        )
    }

    private func formatStorage(_ megabytes: Int) -> String {
        megabytes >= 1000
            ? String(format: "%.1f GB", Double(megabytes) / 1000.0)
            : "\(megabytes) MB"
    }

    private var hintRow: some View {
        HStack(spacing: 8) {
            IconView(icon: .info, size: 12)
            Text(localized("Keep setting up while it downloads — we'll finish in the background.", locale: locale))
        }
        .font(AppTypography.captionLarge)
        .foregroundStyle(AppColors.textTertiary)
    }

    private var statusTitle: String {
        if downloadError != nil {
            return localized("Download Failed", locale: locale)
        } else if modelManager.isDownloading {
            switch activeSnapshot?.phase {
            case .compiling, .preparing, .completed:
                return localized("Preparing Model...", locale: locale)
            default:
                break
            }

            return localized("Downloading %@...", locale: locale)
                .replacingOccurrences(of: "%@", with: selectedModel?.displayName ?? localized("Model", locale: locale))
        } else {
            return localized("Download Complete!", locale: locale)
        }
    }

    private var statusSubtitle: String {
        if downloadError != nil {
            return localized("Please check your internet connection and try again.", locale: locale)
        } else if modelManager.isDownloading {
            if let activeSnapshot {
                switch activeSnapshot.phase {
                case .listing, .compiling, .preparing:
                    return localized("Please wait...", locale: locale)
                case .downloading(let completedFiles, let totalFiles):
                    if let completedFiles, let totalFiles {
                        return "\(completedFiles) / \(totalFiles)"
                    }
                case .completed:
                    return localized("Your model is ready to use.", locale: locale)
                case .idle:
                    break
                }
            }

            if let model = selectedModel {
                let downloadedMB = Int(Double(model.sizeInMB) * modelManager.downloadProgress)
                return String(
                    format: localized("%d / %d MB", locale: locale),
                    locale: locale,
                    arguments: [downloadedMB, model.sizeInMB]
                )
            }
            return localized("Please wait...", locale: locale)
        } else {
            return localized("Your model is ready to use.", locale: locale)
        }
    }

    @ViewBuilder
    private var errorView: some View {
        if let error = downloadError {
            Text(error)
                .font(AppTypography.captionLarge)
                .foregroundStyle(AppColors.error)
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 14) {
            if modelManager.isDownloading {
                OnboardingGhostButton(title: localized("Cancel", locale: locale), action: onCancel)
            } else if downloadError != nil {
                OnboardingGhostButton(title: localized("Go Back", locale: locale), action: onCancel)

                OnboardingPrimaryButton(title: localized("Retry", locale: locale), icon: nil) {
                    downloadError = nil
                    Task { await startDownload() }
                }
            } else {
                OnboardingPrimaryButton(title: localized("Continue", locale: locale), icon: nil, action: onComplete)
            }
        }
    }

    private func startDownload() async {
        guard !hasStarted else { return }
        hasStarted = true
        Log.boot.info("ModelDownloadStepView.startDownload task began modelName=\(modelName)")

        // Check if model is already downloaded
        if modelManager.isModelDownloaded(modelName) || modelManager.existingLocalModelPath(for: modelName) != nil {
            Log.model.info("Model \(modelName) already downloaded, skipping download step")
            Log.boot.info("Onboarding model download step: model already on disk name=\(modelName) scheduling TranscriptionService.loadModel")
            loadSelectedModelInBackground()
            try? await Task.sleep(for: .milliseconds(300))
            onComplete()
            return
        }

        do {
            Log.boot.info("Onboarding model download step: calling ModelManager.downloadModel name=\(modelName)")
            try await modelManager.downloadModel(named: modelName)
            Log.boot.info("Onboarding model download step: ModelManager.downloadModel returned scheduling TranscriptionService.loadModel name=\(modelName)")

            loadSelectedModelInBackground()

            try? await Task.sleep(for: .milliseconds(300))
            Log.boot.info("Onboarding model download step: invoking onComplete")
            onComplete()
        } catch {
            Log.boot.error("Onboarding model download step failed name=\(modelName) error=\(error.localizedDescription)")
            downloadError = error.localizedDescription
            hasStarted = false
        }
    }

    private func loadSelectedModelInBackground() {
        let localModelPath = modelManager.existingLocalModelPath(for: modelName)

        Task { @MainActor in
            do {
                if let localModelPath {
                    Log.boot.info("Onboarding background loadModel(path) starting name=\(self.modelName)")
                    try await self.transcriptionService.loadModel(modelPath: localModelPath.path)
                } else {
                    Log.boot.info("Onboarding background loadModel(name) starting name=\(self.modelName)")
                    try await self.transcriptionService.loadModel(modelName: self.modelName)
                }
                Log.boot.info("Onboarding background loadModel finished OK name=\(self.modelName)")
            } catch {
                Log.boot.error("Onboarding background loadModel failed name=\(self.modelName) error=\(error.localizedDescription)")
            }
        }
    }
}

#if DEBUG
struct ModelDownloadStepView_Previews: PreviewProvider {
    static var previews: some View {
        ModelDownloadStepView(
            modelManager: PreviewModelManagerDownload(),
            transcriptionService: TranscriptionService(),
            modelName: "openai_whisper-base.en",
            onComplete: {},
            onCancel: {}
        )
        .frame(width: 760, height: 500)
    }
}

final class PreviewModelManagerDownload: ModelManager {
    override init() {
        // Skip async initialization to avoid launching WhisperKit in preview
    }
}
#endif

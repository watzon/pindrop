//
//  MediaIngestionService.swift
//  Pindrop
//
//  Created on 2026-03-07.
//

import AVFoundation
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct ManagedMediaAsset: Equatable, Sendable {
    let directoryURL: URL
    let mediaURL: URL
    let thumbnailURL: URL?
    let sourceKind: MediaSourceKind
    let displayName: String
    let originalSourceURL: String?
}

struct MediaToolingStatus: Equatable, Sendable {
    let ytDLPPath: String?
    let ffmpegPath: String?

    var isReady: Bool {
        ytDLPPath != nil && ffmpegPath != nil
    }

    var missingToolsDescription: String {
        let missing = [
            ytDLPPath == nil ? "yt-dlp" : nil,
            ffmpegPath == nil ? "ffmpeg" : nil
        ]
        .compactMap { $0 }
        .joined(separator: ", ")

        return "To transcribe web links, install \(missing)."
    }
}

private struct ResolvedMediaTooling: Equatable, Sendable {
    let ytDLPURL: URL
    let ffmpegURL: URL
}

struct ProcessExecutionResult: Sendable {
    let terminationStatus: Int32
    let standardOutput: String
    let standardError: String
}

protocol ProcessRunning: Sendable {
    func run(
        executableURL: URL,
        arguments: [String],
        currentDirectoryURL: URL?,
        environment: [String: String]?,
        lineHandler: (@Sendable (String) -> Void)?
    ) async throws -> ProcessExecutionResult
}

protocol MediaLibraryManaging: AnyObject {
    func makeJobDirectory(for jobID: UUID) throws -> URL
    func importLocalFile(at sourceURL: URL, jobID: UUID) async throws -> ManagedMediaAsset
    func storeRecordedAudio(
        _ audioData: Data,
        jobID: UUID,
        displayName: String,
        sourceKind: MediaSourceKind
    ) throws -> ManagedMediaAsset
    func finalizeDownloadedAsset(
        in directoryURL: URL,
        sourceURL: String,
        suggestedTitle: String?
    ) async throws -> ManagedMediaAsset
}

enum MediaIngestionError: Error, LocalizedError {
    case unsupportedInput(String)
    case toolingUnavailable(String)
    case downloadFailed(String)
    case localFileImportFailed(String)
    case downloadedMediaMissing
    case metadataLookupFailed(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedInput(let message):
            return "Unsupported media input: \(message)"
        case .toolingUnavailable(let message):
            return message
        case .downloadFailed(let message):
            return "Media download failed: \(message)"
        case .localFileImportFailed(let message):
            return "Media import failed: \(message)"
        case .downloadedMediaMissing:
            return "Download finished but no playable media file was found."
        case .metadataLookupFailed(let message):
            return "Failed to inspect media link: \(message)"
        }
    }
}

private final class ProcessOutputCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var stdoutData = Data()
    private var stderrData = Data()
    private var stdoutRemainder = ""
    private var stderrRemainder = ""
    private let lineHandler: (@Sendable (String) -> Void)?

    init(lineHandler: (@Sendable (String) -> Void)?) {
        self.lineHandler = lineHandler
    }

    func appendStdout(_ data: Data) {
        append(data, isStdout: true)
    }

    func appendStderr(_ data: Data) {
        append(data, isStdout: false)
    }

    func consumeStdoutRemainder() {
        flushRemainder(isStdout: true)
    }

    func consumeStderrRemainder() {
        flushRemainder(isStdout: false)
    }

    func result(terminationStatus: Int32) -> ProcessExecutionResult {
        lock.lock()
        defer { lock.unlock() }
        return ProcessExecutionResult(
            terminationStatus: terminationStatus,
            standardOutput: String(data: stdoutData, encoding: .utf8) ?? "",
            standardError: String(data: stderrData, encoding: .utf8) ?? ""
        )
    }

    private func append(_ data: Data, isStdout: Bool) {
        guard !data.isEmpty else { return }

        lock.lock()
        defer { lock.unlock() }

        if isStdout {
            stdoutData.append(data)
        } else {
            stderrData.append(data)
        }

        let string = String(data: data, encoding: .utf8) ?? ""
        if isStdout {
            stdoutRemainder += string
            emitCompleteLines(from: &stdoutRemainder)
        } else {
            stderrRemainder += string
            emitCompleteLines(from: &stderrRemainder)
        }
    }

    private func flushRemainder(isStdout: Bool) {
        lock.lock()
        defer { lock.unlock() }

        if isStdout, !stdoutRemainder.isEmpty {
            lineHandler?(stdoutRemainder)
            stdoutRemainder = ""
        } else if !isStdout, !stderrRemainder.isEmpty {
            lineHandler?(stderrRemainder)
            stderrRemainder = ""
        }
    }

    private func emitCompleteLines(from remainder: inout String) {
        while let newlineRange = remainder.range(of: "\n") {
            let line = String(remainder[..<newlineRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !line.isEmpty {
                lineHandler?(line)
            }
            remainder.removeSubrange(...newlineRange.lowerBound)
        }
    }
}

struct DefaultProcessRunner: ProcessRunning {
    func run(
        executableURL: URL,
        arguments: [String],
        currentDirectoryURL: URL? = nil,
        environment: [String: String]? = nil,
        lineHandler: (@Sendable (String) -> Void)? = nil
    ) async throws -> ProcessExecutionResult {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectoryURL
        process.environment = environment

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let collector = ProcessOutputCollector(lineHandler: lineHandler)
        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            collector.appendStdout(data)
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            collector.appendStderr(data)
        }

        return try await withTaskCancellationHandler(operation: {
            try process.run()
            let status = await withCheckedContinuation { continuation in
                process.terminationHandler = { finishedProcess in
                    continuation.resume(returning: finishedProcess.terminationStatus)
                }
            }

            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            stderrPipe.fileHandleForReading.readabilityHandler = nil

            collector.appendStdout(stdoutPipe.fileHandleForReading.readDataToEndOfFile())
            collector.appendStderr(stderrPipe.fileHandleForReading.readDataToEndOfFile())
            collector.consumeStdoutRemainder()
            collector.consumeStderrRemainder()

            return collector.result(terminationStatus: status)
        }, onCancel: {
            if process.isRunning {
                process.terminate()
            }
        })
    }
}

final class ManagedMediaLibrary: MediaLibraryManaging {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func makeJobDirectory(for jobID: UUID) throws -> URL {
        let directory = Self.baseURL.appendingPathComponent(jobID.uuidString, isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    func importLocalFile(at sourceURL: URL, jobID: UUID) async throws -> ManagedMediaAsset {
        let directoryURL = try makeJobDirectory(for: jobID)
        let destinationURL = directoryURL.appendingPathComponent("media").appendingPathExtension(sourceURL.pathExtension)

        do {
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
        } catch {
            throw MediaIngestionError.localFileImportFailed(error.localizedDescription)
        }

        let thumbnailURL = try? await generateThumbnailIfPossible(for: destinationURL, in: directoryURL)

        return ManagedMediaAsset(
            directoryURL: directoryURL,
            mediaURL: destinationURL,
            thumbnailURL: thumbnailURL,
            sourceKind: .importedFile,
            displayName: sourceURL.lastPathComponent,
            originalSourceURL: sourceURL.absoluteString
        )
    }

    func storeRecordedAudio(
        _ audioData: Data,
        jobID: UUID,
        displayName: String,
        sourceKind: MediaSourceKind
    ) throws -> ManagedMediaAsset {
        let directoryURL = try makeJobDirectory(for: jobID)
        let destinationURL = directoryURL.appendingPathComponent("media").appendingPathExtension("caf")

        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }

        let format = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1)
            ?? AVAudioFormat()
        guard format.sampleRate > 0,
              let buffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(audioData.count / MemoryLayout<Float>.size)
              ),
              let channelData = buffer.floatChannelData else {
            throw MediaIngestionError.localFileImportFailed("Unable to prepare recorded audio for storage.")
        }

        let samples = audioData.count / MemoryLayout<Float>.size
        buffer.frameLength = AVAudioFrameCount(samples)
        audioData.withUnsafeBytes { rawBuffer in
            guard let source = rawBuffer.bindMemory(to: Float.self).baseAddress else { return }
            channelData[0].update(from: source, count: samples)
        }

        do {
            let outputFile = try AVAudioFile(forWriting: destinationURL, settings: format.settings)
            try outputFile.write(from: buffer)
        } catch {
            throw MediaIngestionError.localFileImportFailed(error.localizedDescription)
        }

        return ManagedMediaAsset(
            directoryURL: directoryURL,
            mediaURL: destinationURL,
            thumbnailURL: nil,
            sourceKind: sourceKind,
            displayName: displayName,
            originalSourceURL: nil
        )
    }

    func finalizeDownloadedAsset(
        in directoryURL: URL,
        sourceURL: String,
        suggestedTitle: String?
    ) async throws -> ManagedMediaAsset {
        guard let mediaURL = try locatePrimaryMediaFile(in: directoryURL) else {
            throw MediaIngestionError.downloadedMediaMissing
        }

        let thumbnailURL: URL?
        if let existingThumbnail = locateThumbnail(in: directoryURL) {
            thumbnailURL = existingThumbnail
        } else {
            thumbnailURL = try? await generateThumbnailIfPossible(for: mediaURL, in: directoryURL)
        }

        return ManagedMediaAsset(
            directoryURL: directoryURL,
            mediaURL: mediaURL,
            thumbnailURL: thumbnailURL,
            sourceKind: .webLink,
            displayName: (suggestedTitle?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? suggestedTitle! : mediaURL.lastPathComponent),
            originalSourceURL: sourceURL
        )
    }

    private func locatePrimaryMediaFile(in directoryURL: URL) throws -> URL? {
        let items = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        )

        return items
            .filter { url in
                guard let type = UTType(filenameExtension: url.pathExtension.lowercased()) else {
                    return false
                }
                if type.conforms(to: .image) || type.conforms(to: .json) || type.conforms(to: .plainText) {
                    return false
                }
                return type.conforms(to: .audio) || type.conforms(to: .movie) || type.conforms(to: .mpeg4Movie) || type.conforms(to: .video)
            }
            .sorted {
                let leftSize = (try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                let rightSize = (try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                return leftSize > rightSize
            }
            .first
    }

    private func locateThumbnail(in directoryURL: URL) -> URL? {
        guard let items = try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        return items.first { url in
            guard let type = UTType(filenameExtension: url.pathExtension.lowercased()) else {
                return false
            }
            return type.conforms(to: .image)
        }
    }

    private func generateThumbnailIfPossible(for mediaURL: URL, in directoryURL: URL) async throws -> URL? {
        let asset = AVURLAsset(url: mediaURL)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard !videoTracks.isEmpty else { return nil }

        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true

        let duration = try await asset.load(.duration)
        let seconds = max(duration.seconds.isFinite ? duration.seconds : 0, 0.1)
        let cgImage = try imageGenerator.copyCGImage(at: CMTime(seconds: min(1.0, seconds * 0.25), preferredTimescale: 600), actualTime: nil)
        let destinationURL = directoryURL.appendingPathComponent("thumbnail.png")

        guard let destination = CGImageDestinationCreateWithURL(destinationURL as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            return nil
        }

        CGImageDestinationAddImage(destination, cgImage, nil)
        guard CGImageDestinationFinalize(destination) else {
            return nil
        }

        return destinationURL
    }

    private static var baseURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Pindrop", isDirectory: true)
            .appendingPathComponent("MediaLibrary", isDirectory: true)
    }
}

private struct YTDLPMetadata: Decodable {
    let title: String?
    let webpageURL: String?

    private enum CodingKeys: String, CodingKey {
        case title
        case webpageURL = "webpage_url"
    }
}

private struct MediaDownloadAttempt {
    let format: String
    let extractorArgs: String?
    let mergeOutputFormat: String?
    let logLabel: String
}

@MainActor
final class MediaIngestionService {
    private let processRunner: any ProcessRunning
    private let mediaLibrary: any MediaLibraryManaging
    private let toolPathResolver: (String) -> String?

    init(
        processRunner: any ProcessRunning = DefaultProcessRunner(),
        mediaLibrary: any MediaLibraryManaging = ManagedMediaLibrary(),
        toolPathResolver: @escaping (String) -> String? = MediaIngestionService.defaultDirectToolPath(named:)
    ) {
        self.processRunner = processRunner
        self.mediaLibrary = mediaLibrary
        self.toolPathResolver = toolPathResolver
    }

    func checkTooling() async -> MediaToolingStatus {
        async let ytDLPPath = locateTool(named: "yt-dlp")
        async let ffmpegPath = locateTool(named: "ffmpeg")

        let status = await MediaToolingStatus(
            ytDLPPath: ytDLPPath,
            ffmpegPath: ffmpegPath
        )

        Log.app.info(
            "Media tooling check completed. yt-dlp=\(status.ytDLPPath ?? "missing"), " +
            "ffmpeg=\(status.ffmpegPath ?? "missing"), searchPath=\(Self.toolSearchPath)"
        )

        return status
    }

    func storeRecordedAudio(
        _ audioData: Data,
        jobID: UUID,
        displayName: String,
        sourceKind: MediaSourceKind
    ) throws -> ManagedMediaAsset {
        try mediaLibrary.storeRecordedAudio(
            audioData,
            jobID: jobID,
            displayName: displayName,
            sourceKind: sourceKind
        )
    }

    func ingest(
        request: MediaTranscriptionRequest,
        jobID: UUID,
        progressHandler: @escaping @MainActor (Double?, String) -> Void
    ) async throws -> ManagedMediaAsset {
        switch request {
        case .file(let url):
            return try await mediaLibrary.importLocalFile(at: url, jobID: jobID)
        case .link(let string):
            let tooling = await checkTooling()
            guard tooling.isReady else {
                throw MediaIngestionError.toolingUnavailable(tooling.missingToolsDescription)
            }
            let resolvedTooling = try resolvedTooling(from: tooling)
            return try await downloadLinkedMedia(
                from: string,
                tooling: resolvedTooling,
                jobID: jobID,
                progressHandler: progressHandler
            )
        case .manualCapture:
            throw MediaIngestionError.unsupportedInput("Manual capture uses the live recording flow instead of media ingestion.")
        }
    }

    private func locateTool(named tool: String) async -> String? {
        if let directPath = toolPathResolver(tool) {
            let resolvedPath = URL(fileURLWithPath: directPath).resolvingSymlinksInPath().path
            Log.app.debug("Resolved \(tool) via known directories: \(resolvedPath)")
            return resolvedPath
        }

        do {
            let result = try await processRunner.run(
                executableURL: URL(fileURLWithPath: "/usr/bin/which"),
                arguments: [tool],
                currentDirectoryURL: nil,
                environment: ["PATH": Self.toolSearchPath],
                lineHandler: nil
            )
            guard result.terminationStatus == 0 else {
                let stderr = result.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
                Log.app.debug("Failed to resolve \(tool) with /usr/bin/which. status=\(result.terminationStatus), stderr=\(stderr)")
                return nil
            }
            let path = result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !path.isEmpty else {
                Log.app.debug("Resolved \(tool) with /usr/bin/which but received an empty path")
                return nil
            }

            let resolvedPath = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
            Log.app.debug("Resolved \(tool) with /usr/bin/which: \(resolvedPath)")
            return resolvedPath
        } catch {
            Log.app.error("Failed to resolve \(tool): \(error.localizedDescription)")
            return nil
        }
    }

    private func downloadLinkedMedia(
        from urlString: String,
        tooling: ResolvedMediaTooling,
        jobID: UUID,
        progressHandler: @escaping @MainActor (Double?, String) -> Void
    ) async throws -> ManagedMediaAsset {
        guard let url = URL(string: urlString), let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) else {
            throw MediaIngestionError.unsupportedInput("Only http and https links are supported.")
        }

        let directoryURL = try mediaLibrary.makeJobDirectory(for: jobID)
        let metadata = try await fetchMetadata(for: urlString, tooling: tooling)
        let progressParser = MediaDownloadProgressParser()
        let attempts = downloadAttempts(for: url)
        var finalFailureMessage: String?

        for (index, attempt) in attempts.enumerated() {
            let downloadResult = try await processRunner.run(
                executableURL: tooling.ytDLPURL,
                arguments: downloadArguments(
                    for: urlString,
                    tooling: tooling,
                    attempt: attempt
                ),
                currentDirectoryURL: directoryURL,
                environment: processEnvironment(for: tooling),
                lineHandler: { line in
                    let progress = progressParser.progress(from: line)
                    let detail = progressParser.detail(from: line) ?? "Resolving media"
                    Task { @MainActor in
                        progressHandler(progress, detail)
                    }
                }
            )

            guard downloadResult.terminationStatus != 0 else {
                return try await mediaLibrary.finalizeDownloadedAsset(
                    in: directoryURL,
                    sourceURL: urlString,
                    suggestedTitle: metadata.title
                )
            }

            let output = [downloadResult.standardError, downloadResult.standardOutput]
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            finalFailureMessage = output.isEmpty ? "yt-dlp exited with status \(downloadResult.terminationStatus)" : output

            let isLastAttempt = index == attempts.index(before: attempts.endIndex)
            guard !isLastAttempt, shouldRetryYouTubeDownload(for: url, output: output) else {
                break
            }

            Log.app.warning(
                "yt-dlp \(attempt.logLabel) download attempt failed for \(url.host(percentEncoded: false) ?? "link"); retrying with compatibility fallback"
            )
        }

        throw MediaIngestionError.downloadFailed(userFacingDownloadErrorMessage(for: url, output: finalFailureMessage ?? ""))
    }

    private func fetchMetadata(
        for urlString: String,
        tooling: ResolvedMediaTooling
    ) async throws -> YTDLPMetadata {
        let result = try await processRunner.run(
            executableURL: tooling.ytDLPURL,
            arguments: [
                "--dump-single-json",
                "--no-playlist",
                "--ffmpeg-location", tooling.ffmpegURL.deletingLastPathComponent().path,
                urlString
            ],
            currentDirectoryURL: nil,
            environment: processEnvironment(for: tooling),
            lineHandler: nil
        )

        guard result.terminationStatus == 0 else {
            throw MediaIngestionError.metadataLookupFailed(result.standardError.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        guard let data = result.standardOutput.data(using: .utf8) else {
            throw MediaIngestionError.metadataLookupFailed("yt-dlp did not return valid metadata.")
        }

        do {
            return try JSONDecoder().decode(YTDLPMetadata.self, from: data)
        } catch {
            throw MediaIngestionError.metadataLookupFailed(error.localizedDescription)
        }
    }

    private func resolvedTooling(from status: MediaToolingStatus) throws -> ResolvedMediaTooling {
        guard let ytDLPPath = status.ytDLPPath,
              let ffmpegPath = status.ffmpegPath else {
            throw MediaIngestionError.toolingUnavailable(status.missingToolsDescription)
        }

        return ResolvedMediaTooling(
            ytDLPURL: URL(fileURLWithPath: ytDLPPath),
            ffmpegURL: URL(fileURLWithPath: ffmpegPath)
        )
    }

    private func downloadAttempts(for url: URL) -> [MediaDownloadAttempt] {
        let standardAttempt = MediaDownloadAttempt(
            format: "bestvideo*+bestaudio/best",
            extractorArgs: nil,
            mergeOutputFormat: "mp4",
            logLabel: "standard"
        )

        guard isYouTubeURL(url) else {
            return [standardAttempt]
        }

        let compatibilityAttempt = MediaDownloadAttempt(
            format: "best[ext=mp4]/best",
            extractorArgs: "youtube:player_client=default,-web,-web_safari,-web_creator",
            mergeOutputFormat: nil,
            logLabel: "compatibility"
        )

        return [standardAttempt, compatibilityAttempt]
    }

    private func downloadArguments(
        for urlString: String,
        tooling: ResolvedMediaTooling,
        attempt: MediaDownloadAttempt
    ) -> [String] {
        var arguments = [
            "--no-playlist",
            "--newline",
            "--progress"
        ]

        if let extractorArgs = attempt.extractorArgs {
            arguments += ["--extractor-args", extractorArgs]
        }

        arguments += [
            "--format", attempt.format
        ]

        if let mergeOutputFormat = attempt.mergeOutputFormat {
            arguments += ["--merge-output-format", mergeOutputFormat]
        }

        arguments += [
            "--ffmpeg-location", tooling.ffmpegURL.deletingLastPathComponent().path,
            "--write-thumbnail",
            "--convert-thumbnails", "png",
            "-o", "media.%(ext)s",
            urlString
        ]

        return arguments
    }

    private func shouldRetryYouTubeDownload(for url: URL, output: String) -> Bool {
        guard isYouTubeURL(url) else { return false }

        let normalizedOutput = output.lowercased()
        return normalizedOutput.contains("sabr streaming")
            || normalizedOutput.contains("http error 403")
            || normalizedOutput.contains("missing a url")
    }

    private func userFacingDownloadErrorMessage(for url: URL, output: String) -> String {
        guard isYouTubeURL(url) else { return output }

        let normalizedOutput = output.lowercased()
        if normalizedOutput.contains("sign in to confirm you’re not a bot")
            || normalizedOutput.contains("sign in to confirm you're not a bot")
            || normalizedOutput.contains("--cookies-from-browser")
            || normalizedOutput.contains("po token") {
            return """
            YouTube blocked anonymous access for this video. Try updating yt-dlp, or retry after exporting browser cookies for YouTube. Original error:
            \(output)
            """
        }

        return output
    }

    private func isYouTubeURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host == "youtube.com"
            || host == "www.youtube.com"
            || host == "m.youtube.com"
            || host == "youtu.be"
    }

    nonisolated private static func defaultDirectToolPath(named tool: String) -> String? {
        for directory in Self.toolSearchDirectories {
            let candidateURL = directory.appendingPathComponent(tool)
            if FileManager.default.isExecutableFile(atPath: candidateURL.path) {
                return candidateURL.path
            }
        }
        return nil
    }

    private func processEnvironment(for tooling: ResolvedMediaTooling) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment

        var directories = Self.toolSearchDirectories.map(\.path)
        directories.append(tooling.ytDLPURL.deletingLastPathComponent().path)
        directories.append(tooling.ffmpegURL.deletingLastPathComponent().path)

        if let existingPath = environment["PATH"], !existingPath.isEmpty {
            directories.append(contentsOf: existingPath.split(separator: ":").map(String.init))
        }

        environment["PATH"] = Array(NSOrderedSet(array: directories))
            .compactMap { $0 as? String }
            .joined(separator: ":")
        return environment
    }

    nonisolated private static var toolSearchDirectories: [URL] {
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
        let baseDirectories = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/opt/local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin"
        ].map { URL(fileURLWithPath: $0, isDirectory: true) } + [
            homeDirectory.appendingPathComponent(".local/bin", isDirectory: true),
            homeDirectory.appendingPathComponent("bin", isDirectory: true),
            homeDirectory.appendingPathComponent("homebrew/bin", isDirectory: true)
        ]

        let pathDirectories = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .map { URL(fileURLWithPath: String($0), isDirectory: true) }

        return Array(NSOrderedSet(array: baseDirectories + pathDirectories))
            .compactMap { $0 as? URL }
    }

    nonisolated private static var toolSearchPath: String {
        toolSearchDirectories.map(\.path).joined(separator: ":")
    }
}

private struct MediaDownloadProgressParser {
    func progress(from line: String) -> Double? {
        let pattern = #"\[download\]\s+(\d+(?:\.\d+)?)%"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = regex.firstMatch(in: line, range: range),
              let valueRange = Range(match.range(at: 1), in: line),
              let percent = Double(line[valueRange]) else {
            return nil
        }
        return max(0, min(percent / 100.0, 1.0))
    }

    func detail(from line: String) -> String? {
        if line.contains("Destination:") {
            return "Preparing download"
        }
        if line.contains("[download]") {
            return "Downloading media"
        }
        if line.contains("[Merger]") || line.contains("[ffmpeg]") {
            return "Finalizing media"
        }
        return nil
    }
}

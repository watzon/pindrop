//
//  Logger.swift
//  Pindrop
//
//  Created on 2026-01-25.
//

import Foundation
import os.log

enum Log {
    private static var isPreview: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }

    private static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["PINDROP_TEST_MODE"] == "1"
            || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    private static let subsystem: String = {
        if isPreview {
            return "tech.watzon.pindrop.preview"
        }
        return Bundle.main.bundleIdentifier ?? "tech.watzon.pindrop"
    }()

    private static let shouldPersistLogsToDisk = !isPreview && !isRunningTests

    static let audio = AppLogCategory(subsystem: subsystem, category: "Audio")
    static let transcription = AppLogCategory(subsystem: subsystem, category: "Transcription")
    static let model = AppLogCategory(subsystem: subsystem, category: "Model")
    static let output = AppLogCategory(subsystem: subsystem, category: "Output")
    static let hotkey = AppLogCategory(subsystem: subsystem, category: "Hotkey")
    static let app = AppLogCategory(subsystem: subsystem, category: "App")
    static let boot = AppLogCategory(subsystem: subsystem, category: "Boot")
    static let ui = AppLogCategory(subsystem: subsystem, category: "UI")
    static let update = AppLogCategory(subsystem: subsystem, category: "Update")
    static let aiEnhancement = AppLogCategory(subsystem: subsystem, category: "AIEnhancement")
    static let context = AppLogCategory(subsystem: subsystem, category: "Context")
    static let mcp = AppLogCategory(subsystem: subsystem, category: "MCP")

    static var logsDirectoryURL: URL {
        LogFileSink.shared.logsDirectoryURL
    }

    static var currentLogFileURL: URL {
        LogFileSink.shared.currentLogFileURL()
    }

    static var currentLogFileName: String {
        currentLogFileURL.lastPathComponent
    }

    static func bootstrap() {
        guard shouldPersistLogsToDisk else { return }
        LogFileSink.shared.bootstrap()
    }

    fileprivate static func record(
        level: AppLogLevel,
        category: String,
        message: String,
        file: StaticString,
        line: UInt
    ) {
        guard shouldPersistLogsToDisk else { return }
        LogFileSink.shared.write(
            level: level,
            category: category,
            message: message,
            file: String(describing: file),
            line: line
        )
    }
}

final class AppLogCategory {
    private let category: String
    private let logger: Logger

    init(subsystem: String, category: String) {
        self.category = category
        self.logger = Logger(subsystem: subsystem, category: category)
    }

    func debug(_ message: @autoclosure () -> String, file: StaticString = #fileID, line: UInt = #line) {
        log(level: .debug, message(), visibility: .hashedPrivate, file: file, line: line)
    }

    func info(_ message: @autoclosure () -> String, file: StaticString = #fileID, line: UInt = #line) {
        log(level: .info, message(), visibility: .hashedPrivate, file: file, line: line)
    }

    func warning(_ message: @autoclosure () -> String, file: StaticString = #fileID, line: UInt = #line) {
        log(level: .warning, message(), visibility: .hashedPrivate, file: file, line: line)
    }

    func error(_ message: @autoclosure () -> String, file: StaticString = #fileID, line: UInt = #line) {
        log(level: .error, message(), visibility: .hashedPrivate, file: file, line: line)
    }

    func debugVisible(_ message: @autoclosure () -> String, file: StaticString = #fileID, line: UInt = #line) {
        log(level: .debug, message(), visibility: .visible, file: file, line: line)
    }

    func infoVisible(_ message: @autoclosure () -> String, file: StaticString = #fileID, line: UInt = #line) {
        log(level: .info, message(), visibility: .visible, file: file, line: line)
    }

    func warningVisible(_ message: @autoclosure () -> String, file: StaticString = #fileID, line: UInt = #line) {
        log(level: .warning, message(), visibility: .visible, file: file, line: line)
    }

    func errorVisible(_ message: @autoclosure () -> String, file: StaticString = #fileID, line: UInt = #line) {
        log(level: .error, message(), visibility: .visible, file: file, line: line)
    }

    private func log(
        level: AppLogLevel,
        _ message: String,
        visibility: AppLogVisibility,
        file: StaticString,
        line: UInt
    ) {
        let redactedMessage = LogRedactor.redact(message: message, category: category)

        switch level {
        case .debug:
            writeToConsole(redactedMessage, level: .debug, visibility: visibility)
        case .info:
            writeToConsole(redactedMessage, level: .info, visibility: visibility)
        case .warning:
            writeToConsole(redactedMessage, level: .warning, visibility: visibility)
        case .error:
            writeToConsole(redactedMessage, level: .error, visibility: visibility)
        }

        Log.record(
            level: level,
            category: category,
            message: redactedMessage,
            file: file,
            line: line
        )
    }

    private func writeToConsole(_ message: String, level: AppLogLevel, visibility: AppLogVisibility) {
        switch (level, visibility) {
        case (.debug, .hashedPrivate):
            logger.debug("\(message, privacy: .private(mask: .hash))")
        case (.info, .hashedPrivate):
            logger.info("\(message, privacy: .private(mask: .hash))")
        case (.warning, .hashedPrivate):
            logger.warning("\(message, privacy: .private(mask: .hash))")
        case (.error, .hashedPrivate):
            logger.error("\(message, privacy: .private(mask: .hash))")
        case (.debug, .visible):
            logger.debug("\(message, privacy: .public)")
        case (.info, .visible):
            logger.info("\(message, privacy: .public)")
        case (.warning, .visible):
            logger.warning("\(message, privacy: .public)")
        case (.error, .visible):
            logger.error("\(message, privacy: .public)")
        }
    }
}

enum AppLogLevel: String {
    case debug = "DEBUG"
    case info = "INFO"
    case warning = "WARN"
    case error = "ERROR"
}

private enum AppLogVisibility {
    case hashedPrivate
    case visible
}

private final class LogFileSink {
    static let shared = LogFileSink()

    let logsDirectoryURL: URL

    private let queue = DispatchQueue(label: "tech.watzon.pindrop.log-file-sink", qos: .utility)
    private let fileManager = FileManager.default
    private let maxLogFileSizeBytes = 2_000_000
    private let maxRetainedLogFiles = 15

    private let sessionIdentifier: String
    private var currentSegment = 1
    private var currentFileURL: URL?
    private var currentFileHandle: FileHandle?
    private var hasWrittenSessionHeader = false

    private static let sessionFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return formatter
    }()

    private static let timestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone.current
        return formatter
    }()

    private init() {
        let supportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let appSupportURL = supportURL.appendingPathComponent("Pindrop", isDirectory: true)
        self.logsDirectoryURL = appSupportURL.appendingPathComponent("Logs", isDirectory: true)
        self.sessionIdentifier = Self.sessionFormatter.string(from: Date())
    }

    func bootstrap() {
        queue.async {
            self.ensureReadyForWrites()
            self.writeSessionHeaderIfNeeded()
        }
    }

    func currentLogFileURL() -> URL {
        queue.sync {
            ensureReadyForWrites()
            writeSessionHeaderIfNeeded()
            return currentFileURL ?? nextLogFileURL(segment: currentSegment)
        }
    }

    func write(level: AppLogLevel, category: String, message: String, file: String, line: UInt) {
        queue.async {
            self.ensureReadyForWrites()
            self.writeSessionHeaderIfNeeded()
            self.rotateIfNeeded(extraBytes: message.utf8.count + 256)

            let timestamp = Self.timestampFormatter.string(from: Date())
            let fileName = URL(fileURLWithPath: file).lastPathComponent
            let source = "\(fileName):\(line)"
            let lineText = "\(timestamp) [\(level.rawValue)] [\(category)] [\(source)] \(message)\n"
            self.append(lineText)
        }
    }

    private func ensureReadyForWrites() {
        do {
            try fileManager.createDirectory(at: logsDirectoryURL, withIntermediateDirectories: true)

            if currentFileURL == nil {
                currentFileURL = nextLogFileURL(segment: currentSegment)
            }

            guard let fileURL = currentFileURL else { return }

            if !fileManager.fileExists(atPath: fileURL.path) {
                fileManager.createFile(atPath: fileURL.path, contents: nil)
            }

            if currentFileHandle == nil {
                currentFileHandle = try FileHandle(forWritingTo: fileURL)
                currentFileHandle?.seekToEndOfFile()
            }
        } catch {
            // Intentionally avoid recursion via Log.* here.
        }
    }

    private func writeSessionHeaderIfNeeded() {
        guard !hasWrittenSessionHeader else { return }

        let timestamp = Self.timestampFormatter.string(from: Date())
        let processInfo = ProcessInfo.processInfo
        let physicalMemoryBytes = Int64(processInfo.physicalMemory)
        let physicalMemoryLabel = ByteCountFormatter.string(fromByteCount: physicalMemoryBytes, countStyle: .memory)
        let header = """
        ----------------------------------------------------------------
        Pindrop log session started at \(timestamp)
        App version: \(Bundle.main.appShortVersionString) (\(Bundle.main.appBuildVersionString))
        macOS: \(processInfo.operatingSystemVersionString)
        Process ID: \(processInfo.processIdentifier)
        Hardware: \(processInfo.processorCount) processors (\(processInfo.activeProcessorCount) active), physical memory \(physicalMemoryLabel)
        Locale: \(Locale.current.identifier)
        ----------------------------------------------------------------

        """

        append(header)
        hasWrittenSessionHeader = true
        pruneOldLogs()
    }

    private func rotateIfNeeded(extraBytes: Int) {
        guard let fileURL = currentFileURL else { return }
        let existingBytes = (try? fileManager.attributesOfItem(atPath: fileURL.path)[.size] as? NSNumber)?.intValue ?? 0
        guard existingBytes + extraBytes > maxLogFileSizeBytes else { return }

        closeCurrentFile()
        currentSegment += 1
        currentFileURL = nextLogFileURL(segment: currentSegment)
        hasWrittenSessionHeader = false
        ensureReadyForWrites()
        writeSessionHeaderIfNeeded()
    }

    private func closeCurrentFile() {
        do {
            try currentFileHandle?.close()
        } catch {
            // Best-effort close.
        }
        currentFileHandle = nil
    }

    private func append(_ text: String) {
        guard let data = text.data(using: .utf8) else { return }
        currentFileHandle?.write(data)
    }

    private func nextLogFileURL(segment: Int) -> URL {
        let fileName = "pindrop-\(sessionIdentifier)-\(segment).log"
        return logsDirectoryURL.appendingPathComponent(fileName, isDirectory: false)
    }

    private func pruneOldLogs() {
        guard let files = try? fileManager.contentsOfDirectory(
            at: logsDirectoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        let logFiles = files.filter { $0.pathExtension.lowercased() == "log" }
        guard logFiles.count > maxRetainedLogFiles else { return }

        let sortedByDate = logFiles.sorted { lhs, rhs in
            let lhsDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let rhsDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return lhsDate < rhsDate
        }

        let filesToRemove = sortedByDate.prefix(logFiles.count - maxRetainedLogFiles)
        for fileURL in filesToRemove {
            try? fileManager.removeItem(at: fileURL)
        }
    }
}

private enum LogRedactor {
    private static let quotedSingleRegex = try! NSRegularExpression(pattern: #"'[^'\n]{1,2000}'"#)
    private static let emailRegex = try! NSRegularExpression(pattern: #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#, options: [.caseInsensitive])
    private static let uuidRegex = try! NSRegularExpression(pattern: #"\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\b"#)
    private static let urlRegex = try! NSRegularExpression(pattern: #"https?://[^\s,;]+"#, options: [.caseInsensitive])
    private static let pathRegex = try! NSRegularExpression(pattern: #"(?<![A-Za-z0-9])/(?:Users|Volumes|private|var|tmp|Applications|System|Library|opt)[^\s,;)]*"#)
    private static let bearerRegex = try! NSRegularExpression(pattern: #"(?i)Bearer\s+[A-Za-z0-9._\-]{12,}"#)
    private static let secretValueRegex = try! NSRegularExpression(pattern: #"(?i)(api[_-]?key|token|secret|password)\s*[=:]\s*[^\s,;]+"#)

    static func redact(message: String, category: String) -> String {
        if message.isEmpty {
            return message
        }

        let lowercased = message.lowercased()

        if lowercased.contains("payload:") {
            return "payload redacted"
        }

        if category == "Transcription" && lowercased.contains("result:") {
            return "transcription result redacted"
        }

        if lowercased.contains("adding replacement:") {
            return "dictionary replacement updated (values redacted)"
        }

        var output = message

        // Hide quoted snippets, which commonly contain user/transcription text.
        output = replacingMatches(in: output, regex: quotedSingleRegex, template: "'<redacted>'")
        output = replacingMatches(in: output, regex: emailRegex, template: "<email>")
        output = replacingMatches(in: output, regex: uuidRegex, template: "<uuid>")
        output = replacingMatches(in: output, regex: urlRegex, template: "<url>")
        output = replacingMatches(in: output, regex: bearerRegex, template: "Bearer <redacted>")
        output = replacingMatches(in: output, regex: secretValueRegex, template: "$1=<redacted>")
        output = replacingMatches(in: output, regex: pathRegex, template: "<path>")

        if output.count > 1200 {
            output = String(output.prefix(1200)) + " … [truncated]"
        }

        return output
    }

    private static func replacingMatches(in input: String, regex: NSRegularExpression, template: String) -> String {
        let range = NSRange(input.startIndex..<input.endIndex, in: input)
        return regex.stringByReplacingMatches(in: input, options: [], range: range, withTemplate: template)
    }
}

extension Bundle {
    var appShortVersionString: String {
        infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    var appBuildVersionString: String {
        infoDictionary?["CFBundleVersion"] as? String ?? "0"
    }
}

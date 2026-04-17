//
//  MCPToolDispatcher.swift
//  Pindrop
//
//  Created on 2026-04-15.
//

import Foundation

/// Routes MCP tool calls to their handlers.
/// Five top-level tools each with subcommands accessed via the `action` parameter.
@MainActor
enum MCPToolDispatcher {

    // MARK: - Tool Definitions

    static func allToolDefinitions() -> [MCPToolDefinition] {
        [transcribeTool, historyTool, speakersTool, configureTool, libraryTool]
    }

    private static let transcribeTool = MCPToolDefinition(
        name: "transcribe",
        description: "Manage transcription jobs. Submit audio/video files or URLs, track progress, and retrieve diarized results. Typical flow: submit_file → poll status → result.",
        inputSchema: MCPToolInputSchema(
            properties: [
                "action": MCPPropertySchema(type: "string", description: "submit_file | submit_url | status | result | cancel | list", enumValues: ["submit_file", "submit_url", "status", "result", "cancel", "list"]),
                "path": MCPPropertySchema(type: "string", description: "(submit_file) Absolute path to local audio or video file"),
                "url": MCPPropertySchema(type: "string", description: "(submit_url) Web URL to download and transcribe; requires yt-dlp + ffmpeg"),
                "job_id": MCPPropertySchema(type: "string", description: "(status | result | cancel) Job ID returned by submit_file or submit_url"),
                "model": MCPPropertySchema(type: "string", description: "(submit_*) Whisper model name, e.g. openai_whisper-base. Defaults to current setting."),
                "language": MCPPropertySchema(type: "string", description: "(submit_*) Language code, e.g. en, auto, fr, de, zh-Hans. Defaults to current setting."),
                "diarization": MCPPropertySchema(type: "boolean", description: "(submit_*) Enable speaker diarization (requires diarization model to be downloaded)"),
                "output_format": MCPPropertySchema(type: "string", description: "(submit_*) Output format: plainText | subtitles (.srt) | timestamps (.json)", enumValues: ["plainText", "subtitles", "timestamps"]),
                "folder_id": MCPPropertySchema(type: "string", description: "(submit_*) UUID of destination folder in the media library"),
                "filter": MCPPropertySchema(type: "string", description: "(list) Filter jobs: pending | active | completed | all", enumValues: ["pending", "active", "completed", "all"])
            ],
            required: ["action"]
        )
    )

    private static let historyTool = MCPToolDefinition(
        name: "history",
        description: "Access stored transcription records. List, retrieve full content (including diarized segments), delete, or export records.",
        inputSchema: MCPToolInputSchema(
            properties: [
                "action": MCPPropertySchema(type: "string", description: "list | get | delete | export", enumValues: ["list", "get", "delete", "export"]),
                "id": MCPPropertySchema(type: "string", description: "(get | delete) UUID of the transcription record"),
                "folder_id": MCPPropertySchema(type: "string", description: "(list) Filter by folder UUID"),
                "search": MCPPropertySchema(type: "string", description: "(list) Full-text search query"),
                "limit": MCPPropertySchema(type: "integer", description: "(list) Max results, default 20"),
                "offset": MCPPropertySchema(type: "integer", description: "(list) Pagination offset, default 0"),
                "ids": MCPPropertySchema(type: "string", description: "(export) Comma-separated UUIDs to export; omit for all"),
                "format": MCPPropertySchema(type: "string", description: "(export) Export format: txt | json | csv", enumValues: ["txt", "json", "csv"])
            ],
            required: ["action"]
        )
    )

    private static let speakersTool = MCPToolDefinition(
        name: "speakers",
        description: "Manage named speaker profiles. Pre-register known voices so future transcriptions can automatically identify them.",
        inputSchema: MCPToolInputSchema(
            properties: [
                "action": MCPPropertySchema(type: "string", description: "list | register | rename | delete", enumValues: ["list", "register", "rename", "delete"]),
                "id": MCPPropertySchema(type: "string", description: "(rename | delete) Participant ID (normalizedName) from the list action"),
                "name": MCPPropertySchema(type: "string", description: "(register) Display name for the new participant"),
                "new_name": MCPPropertySchema(type: "string", description: "(rename) New display name")
            ],
            required: ["action"]
        )
    )

    private static let configureTool = MCPToolDefinition(
        name: "configure",
        description: "Inspect and update app configuration: transcription models, AI text enhancement, and vocabulary words that improve transcription accuracy.",
        inputSchema: MCPToolInputSchema(
            properties: [
                "action": MCPPropertySchema(type: "string", description: "get_settings | list_models | set_model | enhance_text | list_vocabulary | add_vocabulary | remove_vocabulary", enumValues: ["get_settings", "list_models", "set_model", "enhance_text", "list_vocabulary", "add_vocabulary", "remove_vocabulary"]),
                "model": MCPPropertySchema(type: "string", description: "(set_model) Model name to activate"),
                "text": MCPPropertySchema(type: "string", description: "(enhance_text) Text to improve with AI enhancement"),
                "prompt": MCPPropertySchema(type: "string", description: "(enhance_text) Custom system prompt override"),
                "word": MCPPropertySchema(type: "string", description: "(add_vocabulary | remove_vocabulary) Word to add or remove")
            ],
            required: ["action"]
        )
    )

    private static let libraryTool = MCPToolDefinition(
        name: "library",
        description: "Organize transcriptions into folders in the media library.",
        inputSchema: MCPToolInputSchema(
            properties: [
                "action": MCPPropertySchema(type: "string", description: "list_folders | create_folder | move", enumValues: ["list_folders", "create_folder", "move"]),
                "name": MCPPropertySchema(type: "string", description: "(create_folder) Name for the new folder"),
                "transcription_id": MCPPropertySchema(type: "string", description: "(move) UUID of the transcription to move"),
                "folder_id": MCPPropertySchema(type: "string", description: "(move) UUID of the destination folder")
            ],
            required: ["action"]
        )
    )

    // MARK: - Dispatch

    static func dispatch(
        toolName: String,
        arguments: [String: JSONValue],
        coordinator: AppCoordinator
    ) async -> MCPToolResult {
        Log.mcp.debug("Tool call: \(toolName) action=\(arguments["action"]?.stringValue ?? "(none)")")

        switch toolName {
        case "transcribe": return await handleTranscribe(arguments: arguments, coordinator: coordinator)
        case "history":    return await handleHistory(arguments: arguments, coordinator: coordinator)
        case "speakers":   return handleSpeakers(arguments: arguments, coordinator: coordinator)
        case "configure":  return await handleConfigure(arguments: arguments, coordinator: coordinator)
        case "library":    return await handleLibrary(arguments: arguments, coordinator: coordinator)
        default:
            return .error("Unknown tool: \(toolName). Available tools: transcribe, history, speakers, configure, library")
        }
    }

    // MARK: - transcribe

    private static func handleTranscribe(arguments: [String: JSONValue], coordinator: AppCoordinator) async -> MCPToolResult {
        guard let action = arguments["action"]?.stringValue else {
            return .error("Missing required parameter: action")
        }
        switch action {
        case "submit_file": return submitFile(arguments: arguments, coordinator: coordinator)
        case "submit_url":  return submitURL(arguments: arguments, coordinator: coordinator)
        case "status":      return jobStatus(arguments: arguments, coordinator: coordinator)
        case "result":      return await jobResult(arguments: arguments, coordinator: coordinator)
        case "cancel":      return cancelJob(arguments: arguments, coordinator: coordinator)
        case "list":        return listJobs(arguments: arguments, coordinator: coordinator)
        default:
            return .error("Unknown action '\(action)'. Valid: submit_file, submit_url, status, result, cancel, list")
        }
    }

    private static func submitFile(arguments: [String: JSONValue], coordinator: AppCoordinator) -> MCPToolResult {
        guard let path = arguments["path"]?.stringValue else {
            return .error("Missing required parameter: path")
        }
        let fileURL = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return .error("File not found: \(path)")
        }
        let options = buildJobOptions(arguments: arguments, coordinator: coordinator)
        let folderID = arguments["folder_id"]?.stringValue.flatMap(UUID.init)
        let job = MediaTranscriptionJobState(request: .file(fileURL), options: options, destinationFolderID: folderID)
        let mcpJobID = UUID().uuidString
        MCPJobRegistry.shared.register(mcpJobID: mcpJobID, stateID: job.id)
        coordinator.submitMCPTranscriptionJob(job)
        return .success(.object(["job_id": .string(mcpJobID)]))
    }

    private static func submitURL(arguments: [String: JSONValue], coordinator: AppCoordinator) -> MCPToolResult {
        guard let url = arguments["url"]?.stringValue, !url.isEmpty else {
            return .error("Missing required parameter: url")
        }
        let options = buildJobOptions(arguments: arguments, coordinator: coordinator)
        let folderID = arguments["folder_id"]?.stringValue.flatMap(UUID.init)
        let job = MediaTranscriptionJobState(request: .link(url), options: options, destinationFolderID: folderID)
        let mcpJobID = UUID().uuidString
        MCPJobRegistry.shared.register(mcpJobID: mcpJobID, stateID: job.id)
        coordinator.submitMCPTranscriptionJob(job)
        return .success(.object(["job_id": .string(mcpJobID)]))
    }

    private static func jobStatus(arguments: [String: JSONValue], coordinator: AppCoordinator) -> MCPToolResult {
        guard let mcpJobID = arguments["job_id"]?.stringValue else {
            return .error("Missing required parameter: job_id")
        }
        guard let stateID = MCPJobRegistry.shared.stateID(for: mcpJobID) else {
            return .error("Job not found: \(mcpJobID)")
        }
        guard let job = findJob(stateID: stateID, in: coordinator.mediaTranscriptionState) else {
            return .error("Job no longer in queue: \(mcpJobID). Use history/list to find the result.")
        }
        var result: [String: JSONValue] = [
            "job_id": .string(mcpJobID),
            "stage": .string(job.stage.rawValue),
            "detail": .string(job.detail)
        ]
        if let progress = job.progress { result["progress"] = .double(progress) }
        if let err = job.errorMessage  { result["error_message"] = .string(err) }
        if let rid = job.resultRecordID { result["result_record_id"] = .string(rid.uuidString) }
        return .success(.object(result))
    }

    private static func jobResult(arguments: [String: JSONValue], coordinator: AppCoordinator) async -> MCPToolResult {
        guard let mcpJobID = arguments["job_id"]?.stringValue else {
            return .error("Missing required parameter: job_id")
        }
        guard let stateID = MCPJobRegistry.shared.stateID(for: mcpJobID) else {
            return .error("Job not found: \(mcpJobID)")
        }
        guard let job = findJob(stateID: stateID, in: coordinator.mediaTranscriptionState) else {
            return .error("Job no longer in queue. Use history/list to search for the result.")
        }
        guard job.stage == .completed else {
            return .error("Job not yet complete (stage: \(job.stage.rawValue)). Poll status first.")
        }
        guard let resultID = job.resultRecordID else {
            return .error("Job is completed but result record ID is missing.")
        }
        do {
            guard let record = try coordinator.historyStore.fetchRecord(with: resultID) else {
                return .error("Result record not found in history store.")
            }
            return .success(recordToJSONValue(record))
        } catch {
            return .error("Failed to fetch result: \(error.localizedDescription)")
        }
    }

    private static func cancelJob(arguments: [String: JSONValue], coordinator: AppCoordinator) -> MCPToolResult {
        guard let mcpJobID = arguments["job_id"]?.stringValue else {
            return .error("Missing required parameter: job_id")
        }
        guard let stateID = MCPJobRegistry.shared.stateID(for: mcpJobID) else {
            return .error("Job not found: \(mcpJobID)")
        }
        coordinator.cancelMCPJob(stateID: stateID)
        MCPJobRegistry.shared.unregister(mcpJobID: mcpJobID)
        return .success(.object(["cancelled": .bool(true)]))
    }

    private static func listJobs(arguments: [String: JSONValue], coordinator: AppCoordinator) -> MCPToolResult {
        let filter = arguments["filter"]?.stringValue ?? "all"
        let state = coordinator.mediaTranscriptionState
        var jobs: [MediaTranscriptionJobState] = []
        switch filter {
        case "active":    if let j = state.currentJob { jobs = [j] }
        case "pending":   jobs = state.pendingJobs
        case "completed": jobs = state.completedJobs
        default:
            if let j = state.currentJob { jobs.append(j) }
            jobs.append(contentsOf: state.pendingJobs)
            jobs.append(contentsOf: state.completedJobs)
        }
        let values: [JSONValue] = jobs.map { job in
            let mcpID = MCPJobRegistry.shared.mcpJobID(for: job.id) ?? job.id.uuidString
            var obj: [String: JSONValue] = [
                "job_id": .string(mcpID),
                "stage": .string(job.stage.rawValue),
                "detail": .string(job.detail),
                "source": .string(job.request.displayName)
            ]
            if let rid = job.resultRecordID { obj["result_record_id"] = .string(rid.uuidString) }
            return .object(obj)
        }
        return .success(.object(["jobs": .array(values)]))
    }

    // MARK: - history

    private static func handleHistory(arguments: [String: JSONValue], coordinator: AppCoordinator) async -> MCPToolResult {
        guard let action = arguments["action"]?.stringValue else {
            return .error("Missing required parameter: action")
        }
        switch action {
        case "list":   return await historyList(arguments: arguments, coordinator: coordinator)
        case "get":    return await historyGet(arguments: arguments, coordinator: coordinator)
        case "delete": return await historyDelete(arguments: arguments, coordinator: coordinator)
        case "export": return await historyExport(arguments: arguments, coordinator: coordinator)
        default:
            return .error("Unknown action '\(action)'. Valid: list, get, delete, export")
        }
    }

    private static func historyList(arguments: [String: JSONValue], coordinator: AppCoordinator) async -> MCPToolResult {
        let limit = arguments["limit"]?.intValue ?? 20
        let offset = arguments["offset"]?.intValue ?? 0
        let search = arguments["search"]?.stringValue
        let folderID = arguments["folder_id"]?.stringValue.flatMap(UUID.init)
        do {
            var records = try coordinator.historyStore.fetchAll()
            if let folderID { records = records.filter { $0.folder?.id == folderID } }
            if let search, !search.isEmpty {
                let lower = search.lowercased()
                records = records.filter { $0.text.lowercased().contains(lower) }
            }
            let total = records.count
            let paged = Array(records.dropFirst(offset).prefix(limit))
            let formatter = ISO8601DateFormatter()
            let values: [JSONValue] = paged.map { r in
                .object([
                    "id": .string(r.id.uuidString),
                    "timestamp": .string(formatter.string(from: r.timestamp)),
                    "duration": .double(r.duration),
                    "model": .string(r.modelUsed),
                    "source_kind": .string(r.sourceKindRawValue ?? "unknown"),
                    "source_name": .string(r.sourceDisplayName ?? ""),
                    "text_preview": .string(String(r.text.prefix(200)))
                ])
            }
            return .success(.object([
                "records": .array(values),
                "total": .int(total),
                "offset": .int(offset),
                "limit": .int(limit)
            ]))
        } catch {
            return .error("Failed to fetch records: \(error.localizedDescription)")
        }
    }

    private static func historyGet(arguments: [String: JSONValue], coordinator: AppCoordinator) async -> MCPToolResult {
        guard let idString = arguments["id"]?.stringValue, let id = UUID(uuidString: idString) else {
            return .error("Missing or invalid parameter: id (must be a UUID string)")
        }
        do {
            guard let record = try coordinator.historyStore.fetchRecord(with: id) else {
                return .error("Record not found: \(idString)")
            }
            return .success(recordToJSONValue(record))
        } catch {
            return .error("Failed to fetch record: \(error.localizedDescription)")
        }
    }

    private static func historyDelete(arguments: [String: JSONValue], coordinator: AppCoordinator) async -> MCPToolResult {
        guard let idString = arguments["id"]?.stringValue, let id = UUID(uuidString: idString) else {
            return .error("Missing or invalid parameter: id (must be a UUID string)")
        }
        do {
            guard let record = try coordinator.historyStore.fetchRecord(with: id) else {
                return .error("Record not found: \(idString)")
            }
            try coordinator.historyStore.delete(record)
            return .success(.object(["deleted": .bool(true), "id": .string(idString)]))
        } catch {
            return .error("Failed to delete record: \(error.localizedDescription)")
        }
    }

    private static func historyExport(arguments: [String: JSONValue], coordinator: AppCoordinator) async -> MCPToolResult {
        let format = arguments["format"]?.stringValue ?? "txt"
        let idsString = arguments["ids"]?.stringValue
        do {
            var records: [TranscriptionRecord]?
            if let idsString, !idsString.isEmpty {
                let all = try coordinator.historyStore.fetchAll()
                let ids = idsString.split(separator: ",")
                    .compactMap { UUID(uuidString: String($0).trimmingCharacters(in: .whitespaces)) }
                records = all.filter { ids.contains($0.id) }
            }
            switch format {
            case "json": try coordinator.historyStore.exportToJSON(records: records)
            case "csv":  try coordinator.historyStore.exportToCSV(records: records)
            default:     try coordinator.historyStore.exportToPlainText(records: records)
            }
            return .success(.object(["exported": .bool(true), "format": .string(format)]))
        } catch {
            return .error("Export failed: \(error.localizedDescription)")
        }
    }

    // MARK: - speakers

    private static func handleSpeakers(arguments: [String: JSONValue], coordinator: AppCoordinator) -> MCPToolResult {
        guard let action = arguments["action"]?.stringValue else {
            return .error("Missing required parameter: action")
        }
        switch action {
        case "list":     return speakersList(coordinator: coordinator)
        case "register": return speakersRegister(arguments: arguments, coordinator: coordinator)
        case "rename":   return speakersRename(arguments: arguments, coordinator: coordinator)
        case "delete":   return speakersDelete(arguments: arguments, coordinator: coordinator)
        default:
            return .error("Unknown action '\(action)'. Valid: list, register, rename, delete")
        }
    }

    private static func speakersList(coordinator: AppCoordinator) -> MCPToolResult {
        do {
            let profiles = try coordinator.speakerIdentityService.fetchAllProfiles()
            let values: [JSONValue] = profiles.map { p in
                .object([
                    "id": .string(p.normalizedName),
                    "name": .string(p.displayName),
                    "evidence_count": .int(p.evidenceCount),
                    "total_duration_seconds": .double(p.totalEvidenceDuration)
                ])
            }
            return .success(.object(["participants": .array(values)]))
        } catch {
            return .error("Failed to fetch participants: \(error.localizedDescription)")
        }
    }

    private static func speakersRegister(arguments: [String: JSONValue], coordinator: AppCoordinator) -> MCPToolResult {
        guard let name = arguments["name"]?.stringValue, !name.isEmpty else {
            return .error("Missing required parameter: name")
        }
        do {
            let profile = try coordinator.speakerIdentityService.registerParticipant(displayName: name)
            return .success(.object([
                "participant_id": .string(profile.normalizedName),
                "name": .string(profile.displayName)
            ]))
        } catch {
            return .error("Failed to register participant: \(error.localizedDescription)")
        }
    }

    private static func speakersRename(arguments: [String: JSONValue], coordinator: AppCoordinator) -> MCPToolResult {
        guard let id = arguments["id"]?.stringValue, !id.isEmpty else {
            return .error("Missing required parameter: id")
        }
        guard let newName = arguments["new_name"]?.stringValue, !newName.isEmpty else {
            return .error("Missing required parameter: new_name")
        }
        do {
            let profiles = try coordinator.speakerIdentityService.fetchAllProfiles()
            guard let profile = profiles.first(where: { $0.normalizedName == id }) else {
                return .error("Participant not found: \(id). Use speakers/list to find valid IDs.")
            }
            try coordinator.speakerIdentityService.renameProfile(profile, to: newName)
            return .success(.object(["renamed": .bool(true), "new_name": .string(newName)]))
        } catch {
            return .error("Failed to rename participant: \(error.localizedDescription)")
        }
    }

    private static func speakersDelete(arguments: [String: JSONValue], coordinator: AppCoordinator) -> MCPToolResult {
        guard let id = arguments["id"]?.stringValue, !id.isEmpty else {
            return .error("Missing required parameter: id")
        }
        do {
            let profiles = try coordinator.speakerIdentityService.fetchAllProfiles()
            guard let profile = profiles.first(where: { $0.normalizedName == id }) else {
                return .error("Participant not found: \(id). Use speakers/list to find valid IDs.")
            }
            try coordinator.speakerIdentityService.deleteProfile(profile)
            return .success(.object(["deleted": .bool(true)]))
        } catch {
            return .error("Failed to delete participant: \(error.localizedDescription)")
        }
    }

    // MARK: - configure

    private static func handleConfigure(arguments: [String: JSONValue], coordinator: AppCoordinator) async -> MCPToolResult {
        guard let action = arguments["action"]?.stringValue else {
            return .error("Missing required parameter: action")
        }
        switch action {
        case "get_settings":      return configureGetSettings(coordinator: coordinator)
        case "list_models":       return await configureListModels(coordinator: coordinator)
        case "set_model":         return await configureSetModel(arguments: arguments, coordinator: coordinator)
        case "enhance_text":      return await configureEnhanceText(arguments: arguments, coordinator: coordinator)
        case "list_vocabulary":   return configureListVocabulary(coordinator: coordinator)
        case "add_vocabulary":    return configureAddVocabulary(arguments: arguments, coordinator: coordinator)
        case "remove_vocabulary": return configureRemoveVocabulary(arguments: arguments, coordinator: coordinator)
        default:
            return .error("Unknown action '\(action)'.")
        }
    }

    private static func configureGetSettings(coordinator: AppCoordinator) -> MCPToolResult {
        let s = coordinator.settingsStore
        // v2 config: "ai_enhancement_enabled" now reflects whether the transcription
        // enhancement purpose resolves to something usable. "ai_model" surfaces that
        // assignment's model when present.
        let transcription = s.resolveAssignment(for: .transcriptionEnhancement)
        return .success(.object([
            "model": .string(s.selectedModel),
            "language": .string(s.selectedLanguage),
            "diarization_enabled": .bool(s.diarizationFeatureEnabled),
            "streaming_enabled": .bool(s.streamingFeatureEnabled),
            "vad_enabled": .bool(s.vadFeatureEnabled),
            "ai_enhancement_enabled": .bool(transcription != nil),
            "ai_model": .string(transcription?.modelID ?? ""),
            "output_mode": .string(s.outputMode),
            "mcp_port": .int(s.mcpServerPort)
        ]))
    }

    private static func configureListModels(coordinator: AppCoordinator) async -> MCPToolResult {
        await coordinator.modelManager.refreshDownloadedModels()
        let all = coordinator.modelManager.availableModels
        let active = coordinator.settingsStore.selectedModel
        let values: [JSONValue] = all.map { m in
            .object([
                "name": .string(m.name),
                "display_name": .string(m.displayName),
                "size_mb": .int(m.sizeInMB),
                "is_downloaded": .bool(coordinator.modelManager.isModelDownloaded(m.name)),
                "is_active": .bool(m.name == active)
            ])
        }
        return .success(.object(["models": .array(values)]))
    }

    private static func configureSetModel(arguments: [String: JSONValue], coordinator: AppCoordinator) async -> MCPToolResult {
        guard let modelName = arguments["model"]?.stringValue, !modelName.isEmpty else {
            return .error("Missing required parameter: model")
        }
        do {
            try await coordinator.loadAndActivateModelForMCP(named: modelName)
            return .success(.object(["model": .string(modelName), "active": .bool(true)]))
        } catch {
            return .error("Failed to set model '\(modelName)': \(error.localizedDescription)")
        }
    }

    private static func configureEnhanceText(arguments: [String: JSONValue], coordinator: AppCoordinator) async -> MCPToolResult {
        guard let text = arguments["text"]?.stringValue, !text.isEmpty else {
            return .error("Missing required parameter: text")
        }
        let s = coordinator.settingsStore
        guard let assignment = s.resolveAssignment(for: .transcriptionEnhancement) else {
            return .error(
                "AI enhancement is not configured. Open Pindrop Settings → AI Enhancement and assign a provider + model for Transcription Enhancement."
            )
        }
        let customPrompt = arguments["prompt"]?.stringValue
            ?? assignment.prompt
            ?? AIEnhancementService.defaultSystemPrompt
        do {
            let enhanced = try await coordinator.aiEnhancementService.enhance(
                text: text,
                apiEndpoint: assignment.endpoint ?? "",
                apiKey: assignment.apiKey,
                model: assignment.modelID,
                customPrompt: customPrompt,
                provider: assignment.kind
            )
            return .success(.object(["enhanced_text": .string(enhanced)]))
        } catch {
            return .error("Enhancement failed: \(error.localizedDescription)")
        }
    }

    private static func configureListVocabulary(coordinator: AppCoordinator) -> MCPToolResult {
        do {
            let words = try coordinator.dictionaryStore.fetchAllVocabularyWords()
            let values: [JSONValue] = words.map { .string($0.word) }
            return .success(.object(["vocabulary": .array(values), "count": .int(values.count)]))
        } catch {
            return .error("Failed to fetch vocabulary: \(error.localizedDescription)")
        }
    }

    private static func configureAddVocabulary(arguments: [String: JSONValue], coordinator: AppCoordinator) -> MCPToolResult {
        guard let word = arguments["word"]?.stringValue, !word.trimmingCharacters(in: .whitespaces).isEmpty else {
            return .error("Missing required parameter: word")
        }
        let trimmed = word.trimmingCharacters(in: .whitespaces)
        do {
            try coordinator.dictionaryStore.add(VocabularyWord(word: trimmed))
            return .success(.object(["added": .bool(true), "word": .string(trimmed)]))
        } catch {
            return .error("Failed to add vocabulary word: \(error.localizedDescription)")
        }
    }

    private static func configureRemoveVocabulary(arguments: [String: JSONValue], coordinator: AppCoordinator) -> MCPToolResult {
        guard let word = arguments["word"]?.stringValue, !word.trimmingCharacters(in: .whitespaces).isEmpty else {
            return .error("Missing required parameter: word")
        }
        let trimmed = word.trimmingCharacters(in: .whitespaces)
        do {
            let words = try coordinator.dictionaryStore.fetchAllVocabularyWords()
            guard let match = words.first(where: { $0.word.lowercased() == trimmed.lowercased() }) else {
                return .error("Word not found in vocabulary: \(trimmed)")
            }
            try coordinator.dictionaryStore.delete(match)
            return .success(.object(["removed": .bool(true), "word": .string(match.word)]))
        } catch {
            return .error("Failed to remove vocabulary word: \(error.localizedDescription)")
        }
    }

    // MARK: - library

    private static func handleLibrary(arguments: [String: JSONValue], coordinator: AppCoordinator) async -> MCPToolResult {
        guard let action = arguments["action"]?.stringValue else {
            return .error("Missing required parameter: action")
        }
        switch action {
        case "list_folders":   return await libraryListFolders(coordinator: coordinator)
        case "create_folder":  return await libraryCreateFolder(arguments: arguments, coordinator: coordinator)
        case "move":           return await libraryMove(arguments: arguments, coordinator: coordinator)
        default:
            return .error("Unknown action '\(action)'. Valid: list_folders, create_folder, move")
        }
    }

    private static func libraryListFolders(coordinator: AppCoordinator) async -> MCPToolResult {
        do {
            let folders = try coordinator.historyStore.fetchFolders()
            let values: [JSONValue] = folders.map { f in
                .object([
                    "id": .string(f.id.uuidString),
                    "name": .string(f.name),
                    "record_count": .int(f.records.count)
                ])
            }
            return .success(.object(["folders": .array(values)]))
        } catch {
            return .error("Failed to fetch folders: \(error.localizedDescription)")
        }
    }

    private static func libraryCreateFolder(arguments: [String: JSONValue], coordinator: AppCoordinator) async -> MCPToolResult {
        guard let name = arguments["name"]?.stringValue, !name.trimmingCharacters(in: .whitespaces).isEmpty else {
            return .error("Missing required parameter: name")
        }
        do {
            let folder = try coordinator.historyStore.createFolder(named: name)
            return .success(.object(["folder_id": .string(folder.id.uuidString), "name": .string(folder.name)]))
        } catch {
            return .error("Failed to create folder: \(error.localizedDescription)")
        }
    }

    private static func libraryMove(arguments: [String: JSONValue], coordinator: AppCoordinator) async -> MCPToolResult {
        guard let tidStr = arguments["transcription_id"]?.stringValue, let tid = UUID(uuidString: tidStr) else {
            return .error("Missing or invalid parameter: transcription_id")
        }
        guard let fidStr = arguments["folder_id"]?.stringValue, let fid = UUID(uuidString: fidStr) else {
            return .error("Missing or invalid parameter: folder_id")
        }
        do {
            guard let record = try coordinator.historyStore.fetchRecord(with: tid) else {
                return .error("Transcription record not found: \(tidStr)")
            }
            let folders = try coordinator.historyStore.fetchFolders()
            guard let folder = folders.first(where: { $0.id == fid }) else {
                return .error("Folder not found: \(fidStr)")
            }
            try coordinator.historyStore.assign(record: record, to: folder)
            return .success(.object(["moved": .bool(true)]))
        } catch {
            return .error("Failed to move record: \(error.localizedDescription)")
        }
    }

    // MARK: - Helpers

    private static func buildJobOptions(arguments: [String: JSONValue], coordinator: AppCoordinator) -> TranscriptionJobOptions {
        let modelName = arguments["model"]?.stringValue ?? coordinator.settingsStore.selectedModel
        let langStr = arguments["language"]?.stringValue ?? coordinator.settingsStore.selectedLanguage
        let language = AppLanguage(rawValue: langStr) ?? .automatic
        let formatStr = arguments["output_format"]?.stringValue ?? "plainText"
        let format = TranscribeOutputFormat(rawValue: formatStr) ?? .plainText
        return TranscriptionJobOptions(modelName: modelName, language: language, outputFormat: format)
    }

    private static func findJob(stateID: UUID, in state: MediaTranscriptionFeatureState) -> MediaTranscriptionJobState? {
        if let j = state.currentJob, j.id == stateID { return j }
        if let j = state.pendingJobs.first(where: { $0.id == stateID }) { return j }
        if let j = state.completedJobs.first(where: { $0.id == stateID }) { return j }
        return nil
    }

    private static func recordToJSONValue(_ record: TranscriptionRecord) -> JSONValue {
        let formatter = ISO8601DateFormatter()
        var obj: [String: JSONValue] = [
            "id": .string(record.id.uuidString),
            "text": .string(record.text),
            "timestamp": .string(formatter.string(from: record.timestamp)),
            "duration": .double(record.duration),
            "model": .string(record.modelUsed)
        ]
        if let v = record.originalText     { obj["original_text"] = .string(v) }
        if let v = record.enhancedWith     { obj["enhanced_with"] = .string(v) }
        if let v = record.sourceKindRawValue { obj["source_kind"] = .string(v) }
        if let v = record.originalSourceURL { obj["source_url"] = .string(v) }
        if let v = record.sourceDisplayName { obj["source_name"] = .string(v) }

        if let segJSON = record.diarizationSegmentsJSON,
           let segData = segJSON.data(using: .utf8),
           let segments = try? JSONDecoder().decode([DiarizedTranscriptSegment].self, from: segData) {
            let segValues: [JSONValue] = segments.map { seg in
                .object([
                    "speaker_id": .string(seg.speakerId),
                    "speaker_label": .string(seg.speakerLabel),
                    "start_time": .double(seg.startTime),
                    "end_time": .double(seg.endTime),
                    "confidence": .double(Double(seg.confidence)),
                    "text": .string(seg.text)
                ])
            }
            obj["diarized_segments"] = .array(segValues)
        }
        return .object(obj)
    }
}

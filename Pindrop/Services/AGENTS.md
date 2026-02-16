# SERVICES LAYER

9 service modules handling all non-UI logic. All @MainActor except HotkeyManager.

## OVERVIEW

```
Services/
├── AudioRecorder.swift        # AVAudioEngine, 16kHz mono PCM
├── TranscriptionService.swift # WhisperKit integration
├── ModelManager.swift         # Model download/storage
├── HotkeyManager.swift        # Carbon Events (NOT @MainActor)
├── OutputManager.swift        # Clipboard + Accessibility
├── HistoryStore.swift         # SwiftData persistence
├── SettingsStore.swift        # @AppStorage + Keychain
├── PermissionManager.swift    # Mic + Accessibility permissions
└── AIEnhancementService.swift # OpenAI-compatible API
```

## WHERE TO LOOK

| Task                   | Service              | Key Methods                                   |
| ---------------------- | -------------------- | --------------------------------------------- |
| Start/stop recording   | AudioRecorder        | `startRecording()`, `stopRecording() -> Data` |
| Transcribe audio       | TranscriptionService | `loadModel()`, `transcribe(audioData:)`       |
| Download Whisper model | ModelManager         | `downloadModel()`, `listAvailableModels()`    |
| Register global hotkey | HotkeyManager        | `registerHotkey()`, `unregisterAll()`         |
| Output text            | OutputManager        | `output(_:)`, `setOutputMode()`               |
| Save transcription     | HistoryStore         | `save()`, `search()`, `export()`              |
| Read/write settings    | SettingsStore        | `@AppStorage`, `saveAPIKey()`                 |
| Check permissions      | PermissionManager    | `requestPermission()`, `checkAccessibility()` |
| Enhance text via AI    | AIEnhancementService | `enhance(text:apiEndpoint:apiKey:)`           |

## SERVICE DETAILS

### AudioRecorder

- **Input**: 16kHz mono PCM (WhisperKit requirement)
- **Engine**: AVAudioEngine with converter tap
- **Output**: `Data` (Float32 samples)
- **Error**: `AudioRecorderError`

### TranscriptionService (@Observable)

- **States**: `.unloaded` → `.loading` → `.ready` ⇄ `.transcribing`
- **Model loading**: `WhisperKitConfig` with prewarm
- **Concurrency**: Rejects concurrent transcriptions
- **Error**: `TranscriptionError`

### HotkeyManager (NOT @MainActor)

- **API**: Carbon Events (RegisterEventHotKey)
- **Modes**: `.toggle` (single press) or `.pushToTalk` (hold)
- **Callbacks**: `onKeyDown`, `onKeyUp` via DispatchQueue.main

### OutputManager

- **Modes**: `.clipboard` (always works) or `.directInsert` (requires Accessibility)
- **Fallback**: Always copies to clipboard even in directInsert mode
- **Text insertion**: CGEvent key simulation

### HistoryStore (SwiftData)

- **Model**: `TranscriptionRecord`
- **Search**: Case-insensitive text search
- **Export**: JSON, CSV, plain text
- **Read-only**: No edit/delete in UI

### SettingsStore

- **@AppStorage**: selectedModel, hotkeys, outputMode, toggles
- **Keychain**: API endpoint, API key
- **Never**: Store secrets in UserDefaults

## CONVENTIONS

- **Error enums**: Each service has nested error type
- **Logging**: Use `Log.{category}` matching service domain
- **Async init**: Services init sync, heavy work in async methods
- **State**: Use @Observable for reactive state (TranscriptionService)

## ANTI-PATTERNS

| DO NOT                         | WHERE                | WHY                            |
| ------------------------------ | -------------------- | ------------------------------ |
| Save audio to disk             | AudioRecorder        | Privacy, no persistence needed |
| Bundle models in app           | ModelManager         | Size (75MB-3GB per model)      |
| Store API keys in UserDefaults | SettingsStore        | Security                       |
| Use private APIs               | HotkeyManager        | App Store rejection            |
| Require Accessibility          | OutputManager        | Clipboard fallback required    |
| Implement streaming            | TranscriptionService | Out of scope v1                |

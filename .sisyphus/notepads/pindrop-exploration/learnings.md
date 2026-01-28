# Pindrop Codebase Exploration - Learnings

## Date: 2026-01-27

## Architecture Overview

### Core Pattern: Service-Oriented Architecture
- **AppCoordinator** acts as central orchestrator (@MainActor, @Observable)
- All services injected into coordinator at initialization
- Services communicate via callbacks and @Observable properties
- Clean separation: Services (business logic) → UI (presentation) → Models (data)

### Service Layer (10 Services)
All services are @MainActor except HotkeyManager (uses Carbon Events on background thread)

1. **AudioRecorder** - AVAudioEngine, 16kHz mono PCM conversion
2. **TranscriptionService** - WhisperKit integration with state machine
3. **ModelManager** - Model download/management, progress tracking
4. **HotkeyManager** - Carbon Events API for global shortcuts (NOT @MainActor)
5. **OutputManager** - Clipboard + Accessibility API for text insertion
6. **HistoryStore** - SwiftData persistence with search/export
7. **SettingsStore** - @AppStorage + Keychain for secrets
8. **PermissionManager** - Mic + Accessibility permission handling
9. **AIEnhancementService** - OpenAI-compatible API integration
10. **DictionaryStore** - Word replacements + vocabulary (NEW - added 2026-01-27)

### UI Layer
- **StatusBarController** - NSStatusBar menu with dynamic state
- **FloatingIndicatorController** - Notch-aware recording indicator
- **MainWindowController** - Dashboard + History views
- **OnboardingWindowController** - First-run setup flow
- **SettingsWindow** - Multi-tab settings interface
- **SplashController** - Loading screen during startup

### Models (SwiftData)
- **TranscriptionRecord** - History entries with optional AI enhancement
- **WordReplacement** - Dictionary replacements (originals → replacement)
- **VocabularyWord** - User vocabulary for AI context

## Key Patterns & Conventions

### State Management
- @Observable for reactive services (AppCoordinator, TranscriptionService)
- @AppStorage for user preferences
- Keychain for sensitive data (API keys, endpoints)
- SwiftData for persistent storage

### Concurrency
- All services @MainActor except HotkeyManager
- Async/await throughout
- Task groups for timeout handling (TranscriptionService)
- DispatchQueue.main.async for Carbon Events callbacks

### Error Handling
- Nested error enums per service (e.g., AudioRecorderError, TranscriptionError)
- LocalizedError conformance for user-facing messages
- AlertManager for centralized alert presentation

### Logging
- os.log with categorized loggers (Log.audio, Log.transcription, etc.)
- 7 categories: audio, transcription, model, output, hotkey, app, ui

### Recording Flow
1. User triggers hotkey → HotkeyManager callback
2. AppCoordinator.handleToggleRecording()
3. AudioRecorder.startRecording() → AVAudioEngine tap
4. Audio buffered and converted to 16kHz mono
5. AudioRecorder.stopRecording() → Data
6. TranscriptionService.transcribe() → WhisperKit
7. DictionaryStore.applyReplacements() → text with replacements
8. AIEnhancementService.enhance() (optional)
9. OutputManager.output() → clipboard + optional paste
10. HistoryStore.save() → SwiftData

### Dictionary System (NEW)
- **WordReplacement**: Multiple originals → single replacement
- **VocabularyWord**: Words to include in AI context
- Regex-based word boundary matching (case-insensitive)
- Longest-first replacement order to avoid conflicts
- Applied BEFORE AI enhancement
- Replacements tracked and passed to AI prompt

## Code Quality Observations

### Strengths
1. **Consistent architecture** - Clear service boundaries
2. **Type safety** - Extensive use of enums for states/errors
3. **Testability** - Services are protocol-based where needed
4. **Documentation** - AGENTS.md files in key directories
5. **Modern Swift** - @Observable, async/await, SwiftData
6. **Error handling** - Comprehensive error types with localized descriptions
7. **Logging** - Structured logging with categories
8. **Theme system** - Centralized design tokens (AppTheme, AppColors)

### Areas for Improvement
1. **No TODO/FIXME comments found** - Clean codebase
2. **Preview support** - Good use of #Preview and isPreview checks
3. **Timeout handling** - 60s timeout for model loading with helpful error
4. **Escape key cancellation** - Double-escape pattern for safety
5. **Notch awareness** - FloatingIndicator adapts to MacBook notch

## Notable Implementation Details

### Model Loading Timeout
- 60-second timeout using Task groups
- Helpful error message suggesting re-download
- Fallback to other downloaded models if selected model missing

### Escape Key Cancellation
- Double-escape within 400ms to cancel
- Visual feedback in floating indicator (yellow dot)
- Prevents accidental cancellation

### Output Modes
1. **Clipboard** - Always works, no permissions needed
2. **Direct Insert** - Requires Accessibility permission
   - Copies to clipboard first
   - Simulates Cmd+V paste
   - Restores previous clipboard after 500ms

### Hotkey System
- Carbon Events API (not NSEvent)
- Two modes: Toggle (press once) and Push-to-Talk (hold)
- Conflict detection needed (not implemented)
- Three hotkeys: toggle, push-to-talk, copy-last-transcript

### AI Enhancement
- Optional, off by default
- OpenAI-compatible API (any endpoint)
- Stores original text when enhanced
- Includes vocabulary and replacements in prompt
- Fails silently (returns original text on error)

### Dictionary Replacements
- Word boundary matching with regex
- Case-insensitive
- Longest-first to avoid partial matches
- Tracks applied replacements for AI context
- Import/export JSON format

## Testing Coverage
- Unit tests for all services
- Test files mirror service structure
- Mock implementations (PreviewMocks.swift)
- Preview support throughout UI

## Dependencies
- **WhisperKit** - Only external dependency
- **SwiftData** - Apple framework for persistence
- **AVFoundation** - Audio recording
- **Carbon** - Global hotkeys
- **ApplicationServices** - Accessibility API

## File Organization
```
Pindrop/
├── PindropApp.swift           # @main + AppDelegate
├── AppCoordinator.swift       # Central orchestrator
├── Services/                  # 10 service modules
├── UI/
│   ├── Main/                  # Dashboard, MainWindow, HistoryView
│   ├── Settings/              # Multi-tab settings
│   ├── Onboarding/            # 7-step onboarding flow
│   ├── Components/            # Reusable components
│   ├── Theme/                 # Design system
│   ├── StatusBarController.swift
│   ├── FloatingIndicator.swift
│   └── SplashScreen.swift
├── Models/                    # SwiftData models (3)
├── Utils/                     # Logger, AlertManager, Icons
└── Mocks/                     # Preview mocks
```

## Consistency with AGENTS.md
- ✅ All conventions followed
- ✅ @MainActor on services (except HotkeyManager)
- ✅ @Observable pattern used correctly
- ✅ Logging categories match documentation
- ✅ Error enum pattern consistent
- ✅ No API keys in UserDefaults
- ✅ Keychain for secrets
- ✅ SwiftData for persistence
- ✅ No TODO/FIXME comments

## Recent Additions (2026-01-27)
- DictionaryStore service
- WordReplacement model
- VocabularyWord model
- Dictionary settings view
- Import/export functionality
- Integration with AI enhancement prompts

# Pindrop

A native macOS menu bar dictation app using local speech-to-text with WhisperKit.

## Features

### Core Functionality
- 🎤 **Local Speech-to-Text** - Uses WhisperKit (OpenAI's Whisper) running entirely on your Mac
- ⌨️ **Global Keyboard Shortcuts** - Toggle or push-to-talk modes
- 📋 **Flexible Output** - Copy to clipboard or insert directly into active app
- 📚 **Transcription History** - Searchable history with export (JSON, CSV, plain text)
- 🎨 **Clean macOS Design** - Native menu bar app with Apple-like UI

### Privacy First
- ✅ 100% local processing by default
- ✅ No data sent to cloud unless you enable AI enhancement
- ✅ All transcriptions stored locally in SwiftData

### Optional Features
- 🤖 **AI Enhancement** - Optional text cleanup via any OpenAI-compatible API
- 📊 **Floating Indicator** - Visual recording status window
- 🎯 **Multiple Models** - Choose from Tiny to Large Whisper models

## Requirements

- macOS 14.0 (Sonoma) or later
- Apple Silicon (M1/M2/M3/M4) recommended for best performance
- Microphone access permission
- Accessibility permission (optional, for direct text insertion)

## Installation

### From Source

1. Clone the repository:
```bash
git clone <repository-url>
cd pindrop
```

2. Open in Xcode:
```bash
open Pindrop.xcodeproj
```

3. Build and run (Cmd+R)

The app will appear in your menu bar (look for the microphone icon).

## Usage

### First Launch

1. **Grant Microphone Permission** - Required for recording
2. **Open Settings** (Cmd+, or click menu bar icon → Settings)
3. **Download a Model** - Go to Models tab, start with "Tiny" for fastest performance
4. **Configure Keyboard Shortcut** - Default is Option+Space for toggle mode

### Recording

**Toggle Mode** (Default: Option+Space):
- Press once to start recording
- Press again to stop and transcribe

**Push-to-Talk Mode** (Configure in Settings):
- Hold key to record
- Release to stop and transcribe

### Output

Transcribed text is automatically:
- ✅ Copied to clipboard (always)
- ✅ Inserted at cursor (if Accessibility permission granted)

### Viewing History

1. Click menu bar icon → History (Cmd+H)
2. Search transcriptions
3. Export to JSON, CSV, or plain text
4. Copy individual transcriptions

## Keyboard Shortcuts

| Action | Default Shortcut | Customizable |
|--------|-----------------|--------------|
| Toggle Recording | Option+Space | ✅ Yes |
| Push-to-Talk | Not set | ✅ Yes |
| Open Settings | Cmd+, | ❌ No |
| Open History | Cmd+H | ❌ No |
| Start/Stop Recording | Cmd+R | ❌ No |
| Quit | Cmd+Q | ❌ No |

## Settings

### General Tab
- **Output Mode**: Choose between clipboard only or direct insertion
- **Language**: English only (v1.0)

### Hotkeys Tab
- **Toggle Hotkey**: Configure keyboard shortcut for toggle mode
- **Push-to-Talk Hotkey**: Configure keyboard shortcut for push-to-talk mode

### Models Tab
- **Available Models**: View all Whisper model sizes
- **Download**: Download models for offline use
- **Select Active**: Choose which model to use for transcription
- **Model Sizes**:
  - Tiny: ~75MB, fastest, good accuracy
  - Base: ~150MB, balanced
  - Small: ~500MB, better accuracy
  - Medium: ~1.5GB, high accuracy
  - Large: ~3GB, best accuracy

### AI Enhancement Tab
- **Enable/Disable**: Toggle AI text enhancement
- **API Endpoint**: Any OpenAI-compatible API
- **API Key**: Stored securely in macOS Keychain
- **Model**: Choose GPT model for enhancement

## Troubleshooting

### App doesn't appear in menu bar
- Check that the app is running (no dock icon by design)
- Look for microphone icon in top-right menu bar
- Try quitting and relaunching

### Microphone permission denied
1. Open System Settings → Privacy & Security → Microphone
2. Enable permission for Pindrop
3. Restart the app

### Direct text insertion not working
1. Open System Settings → Privacy & Security → Accessibility
2. Add Pindrop to allowed apps
3. Restart the app
4. Note: Clipboard output still works without this permission

### Transcription is slow
- Use a smaller model (Tiny or Base)
- Ensure you're on Apple Silicon (M1+)
- Close other resource-intensive apps

### Model download fails
- Check internet connection
- Ensure sufficient disk space (~75MB to 3GB depending on model)
- Try downloading again

### Hotkey doesn't work
- Check for conflicts with other apps
- Try a different key combination
- Ensure app has focus (click menu bar icon first)

## Architecture

### Services Layer
- **AudioRecorder**: AVAudioEngine-based recording (16kHz mono PCM)
- **TranscriptionService**: WhisperKit integration with Core ML
- **ModelManager**: Whisper model download and management
- **HotkeyManager**: Global keyboard shortcut handling (Carbon Events)
- **OutputManager**: Clipboard and direct text insertion
- **HistoryStore**: SwiftData persistence with search
- **SettingsStore**: @AppStorage + Keychain for settings
- **PermissionManager**: Microphone and Accessibility permissions
- **AIEnhancementService**: Optional OpenAI-compatible API integration

### UI Layer
- **StatusBarController**: Menu bar icon and dropdown menu
- **SettingsWindow**: SwiftUI settings with 4 tabs
- **HistoryWindow**: SwiftUI history browser with search
- **FloatingIndicator**: Optional recording status window

### Coordination
- **AppCoordinator**: Wires all services together, handles app lifecycle

## Development

### Running Tests
```bash
xcodebuild test -scheme Pindrop -destination 'platform=macOS'
```

### Building for Release
```bash
xcodebuild -scheme Pindrop -configuration Release build
```

### Project Structure
```
Pindrop/
├── App/
│   ├── PindropApp.swift          # @main entry point
│   └── AppCoordinator.swift      # Service coordination
├── Services/
│   ├── AudioRecorder.swift
│   ├── TranscriptionService.swift
│   ├── ModelManager.swift
│   ├── HotkeyManager.swift
│   ├── OutputManager.swift
│   ├── HistoryStore.swift
│   ├── SettingsStore.swift
│   ├── PermissionManager.swift
│   └── AIEnhancementService.swift
├── Models/
│   └── TranscriptionRecord.swift
├── UI/
│   ├── StatusBarController.swift
│   ├── SettingsWindow.swift
│   ├── HistoryWindow.swift
│   └── FloatingIndicator.swift
└── PindropTests/
    └── [Test files]
```

## License

MIT License - See LICENSE file for details

## Acknowledgments

- [WhisperKit](https://github.com/argmaxinc/WhisperKit) - Swift implementation of OpenAI's Whisper
- [OpenAI Whisper](https://github.com/openai/whisper) - Original speech recognition model

## Contributing

Contributions welcome! Please open an issue or pull request.

## Roadmap

- [ ] Multi-language support
- [ ] Custom vocabulary/phrases
- [ ] Batch file transcription
- [ ] Speaker diarization
- [ ] Real-time streaming transcription
- [ ] Shortcuts integration
- [ ] Per-app hotkey profiles

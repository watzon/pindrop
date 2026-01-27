# Draft: Dictionary Feature

## Requirements (confirmed)
- User wants a Dictionary feature similar to VoiceInk screenshot
- Two sections: Word Replacements + Vocabulary
- Integration with AI enhancement feature

## Research Findings (Complete)

### Codebase Patterns Discovered
- **Settings UI**: NavigationSplitView with tabs in SettingsWindow.swift
- **Tab Structure**: SettingsTab enum (general, hotkeys, models, ai, about)
- **Card Component**: SettingsCard<Content: View> in GeneralSettingsView.swift:201-219
- **List Pattern**: FilterButton + ForEach + Row (ModelsSettingsView.swift)
- **Theming**: AppTheme, AppColors, AppTypography in Theme.swift
- **Icons**: Icon enum + IconView in Utils/Icons.swift
- **Persistence**: 
  - @AppStorage for simple settings (booleans, strings, ints)
  - Keychain for secrets (API keys)
  - SwiftData for collections (HistoryStore pattern with TranscriptionRecord model)
- **Transcription Flow**: TranscriptionService.transcribe() → AIEnhancementService.enhance() → OutputManager.output()

### Adding a New Settings Tab
1. Add case to SettingsTab enum in SettingsWindow.swift
2. Add systemIcon property
3. Create new settings view file (e.g., DictionarySettingsView.swift)
4. Add case to switch in detailContent
5. Add to headerSubtitle function

### WhisperKit Integration Points
- Current DecodingOptions: task, language, withoutTimestamps only
- **WhisperKit DOES support vocabulary hints** via `promptTokens` in `DecodingOptions`

**How to use vocabulary hints:**
```swift
let vocabularyHints = " Pindrop WhisperKit macOS SwiftUI"
let promptTokens = tokenizer.encode(text: vocabularyHints)
let options = DecodingOptions(promptTokens: promptTokens)
```

**Considerations:**
- Keep prompts short (10-30 tokens) - Core ML decodes token-by-token
- Works best for proper nouns and technical jargon
- Requires access to `whisperKit.tokenizer` for encoding

### Post-Processing Injection Points (Detailed)
```
AudioRecorder → TranscriptionService.transcribe()
                        ↓
              transcribedText: String
                        ↓
        ┌───────────────────────────────┐
        │ INJECTION POINT #1 (line 476) │ ← Word Replacements BEFORE AI?
        └───────────────────────────────┘
                        ↓
        [if AI enhancement enabled]
                        ↓
              AIEnhancementService.enhance()
                        ↓
        ┌───────────────────────────────┐
        │ INJECTION POINT #2 (line 509) │ ← Word Replacements AFTER AI?
        └───────────────────────────────┘
                        ↓
              OutputManager.output()
                        ↓
              HistoryStore.save()
```

**Key Decision**: Should word replacements apply at Point #1 (before AI sees the text) or Point #2 (after AI processing)?
- Point #1: AI gets corrected input, can produce better enhancement
- Point #2: AI might "fix" intentional misspellings, replacements undo AI corrections

## Technical Decisions
- TBD: SwiftData vs @AppStorage for dictionary entries
- TBD: How to integrate with WhisperKit prompts
- TBD: UI tab structure (new tab vs subtab of AI Enhancement)

## User Decisions (Confirmed)

### Tab Placement
- **Decision**: New "Dictionary" tab (separate, like VoiceInk)

### Feature Architecture
Two distinct sections:
1. **Word Replacements**: Find/replace patterns
   - Apply BEFORE AI enhancement
   - Inform AI about replacements so it doesn't "undo" them
2. **Vocabulary**: Words to help recognition
   - Send to WhisperKit's `promptTokens` for transcription accuracy
   - Optionally requires AI Enhancement enabled to also inform AI

### WhisperKit Integration
- **Decision**: SKIP for now - focus on AI Enhancement only
- **Reason**: WhisperKit won't be the only transcription backend in future

### Import/Export
- **Decision**: YES - JSON format for backup/sharing

## Additional Decisions (Confirmed)

### Case Sensitivity
- **Decision**: Case-insensitive matching

### Multiple Originals
- **Decision**: Yes - tag-list UI (not comma-separated text)
- Example: ["Fae", "Faye", "fay"] → "Fae"

### Vocabulary Section
- **Decision**: AI Enhancement only (not WhisperKit)
- Vocabulary sent to AI prompt for context

## Final Decisions (All Complete)

### Storage
- **Decision**: SwiftData (like HistoryStore pattern)

### Test Strategy
- **Decision**: TDD approach - write tests first

## Scope Boundaries
- INCLUDE: TBD
- EXCLUDE: TBD

## From Screenshot (VoiceInk reference)
- Two sections: "Word Replacements" and "Vocabulary"
- Word Replacements: Original text → Replacement text (with comma support for multiple originals)
- Vocabulary: Words to help recognize
- Import/Export buttons visible
- Table-based editing with add/edit/delete

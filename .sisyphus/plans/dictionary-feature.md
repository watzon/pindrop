# Dictionary Feature - Word Replacements & Vocabulary

## TL;DR

> **Quick Summary**: Add a Dictionary settings tab with two features: Word Replacements (find/replace applied before AI) and Vocabulary (words sent to AI for context). SwiftData storage, tag-list UI, JSON import/export.
> 
> **Deliverables**:
> - New "Dictionary" settings tab with two sections
> - SwiftData models for WordReplacement and VocabularyWord
> - DictionaryStore service with CRUD operations
> - Integration with transcription pipeline (before AI enhancement)
> - AI prompt construction with vocabulary/replacement context
> - JSON import/export functionality
> 
> **Estimated Effort**: Medium
> **Parallel Execution**: YES - 3 waves
> **Critical Path**: Task 1 → Task 3 → Task 6 → Task 8

---

## Context

### Original Request
Add a dictionary feature similar to VoiceInk screenshot with:
- Word Replacements: Automatically replace specific words/phrases with custom formatted text
- Vocabulary: Add words to help recognition

### Interview Summary
**Key Discussions**:
- Tab placement: New "Dictionary" tab (separate from AI Enhancement)
- Replacement timing: Before AI Enhancement, with AI informed of changes
- Multiple originals: Tag-list UI (not comma-separated)
- Case sensitivity: Case-insensitive matching
- Storage: SwiftData (like HistoryStore pattern)
- Import/Export: JSON format

**Research Findings**:
- SettingsTab enum pattern ready to extend (SettingsWindow.swift:10-28)
- SettingsCard component available (GeneralSettingsView.swift:201-219)
- HistoryStore SwiftData pattern established
- AppCoordinator line ~478 is injection point for replacements
- `customPrompt` is a REPLACEMENT, not additive - must construct full prompt

### Metis Review
**Identified Gaps** (addressed):
- Word boundary matching required (prevent "dr" matching inside "address")
- Single-pass replacement needed (prevent infinite loops)
- Overlapping originals: longer match wins
- Empty replacement allowed (effectively delete word)
- Import is additive, not replace existing

---

## Work Objectives

### Core Objective
Enable users to define word replacements and vocabulary that improve transcription quality through post-processing and AI context.

### Concrete Deliverables
- `Pindrop/Models/WordReplacement.swift` - SwiftData model
- `Pindrop/Models/VocabularyWord.swift` - SwiftData model
- `Pindrop/Services/DictionaryStore.swift` - CRUD operations
- `Pindrop/UI/Settings/DictionarySettingsView.swift` - Settings tab
- Modified `AppCoordinator.swift` - Pipeline integration
- Modified `SettingsWindow.swift` - New tab entry

### Definition of Done
- [x] All tests pass: `xcodebuild test -scheme Pindrop -destination 'platform=macOS'`
- [x] Dictionary tab appears in Settings with icon
- [x] Word replacements apply before AI enhancement
- [x] Vocabulary appears in AI prompt when enhancement enabled
- [x] Import/Export produces valid JSON

### Must Have
- Word replacement with multiple originals (tag-list UI)
- Case-insensitive matching with word boundaries
- Vocabulary list for AI context
- JSON import/export
- SwiftData persistence

### Must NOT Have (Guardrails)
- NO regex support - literal string matching only
- NO "smart" matching (plurals, stemming, verb conjugation)
- NO iterative replacement - single-pass only
- NO inline editing of vocabulary (add/delete only)
- NO categorization/folders - flat lists only
- NO sync/cloud features - JSON export is the backup mechanism
- NO learning/auto-suggestion features
- NO per-context dictionaries - single global dictionary
- NO preview mode - save immediately, see results on next transcription
- NO WhisperKit integration - AI Enhancement only for future model flexibility

---

## Verification Strategy (MANDATORY)

### Test Decision
- **Infrastructure exists**: YES (XCTest via xcodebuild)
- **User wants tests**: TDD approach
- **Framework**: XCTest

### TDD Workflow

Each TODO follows RED-GREEN-REFACTOR:

**Task Structure:**
1. **RED**: Write failing test first
   - Test file: `PindropTests/[Feature]Tests.swift`
   - Test command: `xcodebuild test -scheme Pindrop -destination 'platform=macOS' -only-testing:PindropTests/[TestClass]`
   - Expected: FAIL (test exists, implementation doesn't)
2. **GREEN**: Implement minimum code to pass
   - Command: Same as above
   - Expected: PASS
3. **REFACTOR**: Clean up while keeping green
   - Command: Same as above
   - Expected: PASS (still)

---

## Execution Strategy

### Parallel Execution Waves

```
Wave 1 (Start Immediately):
├── Task 1: SwiftData models (no dependencies)
└── Task 2: Settings tab entry (no dependencies)

Wave 2 (After Wave 1):
├── Task 3: DictionaryStore service (depends: 1)
├── Task 4: Word Replacements UI (depends: 1, 2)
└── Task 5: Vocabulary UI (depends: 1, 2)

Wave 3 (After Wave 2):
├── Task 6: Pipeline integration (depends: 3)
├── Task 7: Import/Export (depends: 3)
└── Task 8: AI prompt construction (depends: 3, 6)

Critical Path: Task 1 → Task 3 → Task 6 → Task 8
Parallel Speedup: ~40% faster than sequential
```

### Dependency Matrix

| Task | Depends On | Blocks | Can Parallelize With |
|------|------------|--------|---------------------|
| 1 | None | 3, 4, 5 | 2 |
| 2 | None | 4, 5 | 1 |
| 3 | 1 | 6, 7, 8 | 4, 5 |
| 4 | 1, 2 | None | 3, 5 |
| 5 | 1, 2 | None | 3, 4 |
| 6 | 3 | 8 | 7 |
| 7 | 3 | None | 6 |
| 8 | 3, 6 | None | 7 |

### Agent Dispatch Summary

| Wave | Tasks | Recommended Agents |
|------|-------|-------------------|
| 1 | 1, 2 | `delegate_task(category="quick", load_skills=[], run_in_background=true)` |
| 2 | 3, 4, 5 | dispatch parallel after Wave 1 completes |
| 3 | 6, 7, 8 | dispatch parallel after Wave 2 completes |

---

## TODOs

### Task 1: Create SwiftData Models

**What to do**:
- Create `WordReplacement.swift` with fields: id, originals (array), replacement, createdAt, sortOrder
- Create `VocabularyWord.swift` with fields: id, word, createdAt
- Add both models to the SwiftData schema in `PindropApp.swift`

**Must NOT do**:
- No computed properties for matching logic (keep model pure)
- No validation in model (handle in store)

**Recommended Agent Profile**:
- **Category**: `quick`
- **Skills**: []
- **Reason**: Simple model creation following existing TranscriptionRecord pattern

**Parallelization**:
- **Can Run In Parallel**: YES
- **Parallel Group**: Wave 1 (with Task 2)
- **Blocks**: Tasks 3, 4, 5
- **Blocked By**: None

**References**:
- `Pindrop/Models/TranscriptionRecord.swift:11-41` - SwiftData model pattern with @Model, @Attribute(.unique), init
- `Pindrop/PindropApp.swift:32` - Schema registration in modelContainer

**Acceptance Criteria**:
- [x] **RED**: Create test file `PindropTests/DictionaryModelsTests.swift`
  - Test: Create WordReplacement, verify originals is array of strings
  - Test: Create VocabularyWord, verify word property exists
  - `xcodebuild test -scheme Pindrop -destination 'platform=macOS' -only-testing:PindropTests/DictionaryModelsTests` → FAIL
- [x] **GREEN**: Create model files, add to schema
  - `xcodebuild test ...` → PASS
- [x] Models compile without errors
- [x] App launches without SwiftData migration errors

**Commit**: YES
- Message: `feat(models): add WordReplacement and VocabularyWord SwiftData models`
- Files: `Pindrop/Models/WordReplacement.swift`, `Pindrop/Models/VocabularyWord.swift`, `Pindrop/PindropApp.swift`

---

### Task 2: Add Dictionary Tab to Settings Window

**What to do**:
- Add `.dictionary` case to `SettingsTab` enum with "Dictionary" title and "text.book.closed" icon
- Add case to `detailContent` switch returning placeholder view
- Add subtitle in `headerSubtitle` function

**Must NOT do**:
- No actual settings view content yet (placeholder only)
- No icon customization beyond SF Symbols

**Recommended Agent Profile**:
- **Category**: `quick`
- **Skills**: []
- **Reason**: Simple enum case addition following existing pattern

**Parallelization**:
- **Can Run In Parallel**: YES
- **Parallel Group**: Wave 1 (with Task 1)
- **Blocks**: Tasks 4, 5
- **Blocked By**: None

**References**:
- `Pindrop/UI/Settings/SettingsWindow.swift:10-28` - SettingsTab enum pattern
- `Pindrop/UI/Settings/SettingsWindow.swift:116-127` - detailContent switch
- `Pindrop/UI/Settings/SettingsWindow.swift:149-157` - headerSubtitle function

**Acceptance Criteria**:
- [x] Manual verification: Open Settings, "Dictionary" tab appears in sidebar
- [x] Tab has book icon (`text.book.closed`)
- [x] Clicking tab shows placeholder content
- [x] Tab order: General, Hotkeys, Models, AI Enhancement, Dictionary, About

**Commit**: YES
- Message: `feat(settings): add Dictionary tab placeholder to settings`
- Files: `Pindrop/UI/Settings/SettingsWindow.swift`

---

### Task 3: Create DictionaryStore Service

**What to do**:
- Create `DictionaryStore.swift` following HistoryStore pattern
- Implement CRUD for WordReplacement: fetchAll, add, delete, reorder
- Implement CRUD for VocabularyWord: fetchAll, add, delete
- Implement `applyReplacements(to text: String) -> (String, [(original: String, replacement: String)])` returning both result and applied replacements
- Word boundary matching using `\b` regex equivalent
- Case-insensitive matching
- Single-pass replacement (longer matches first)

**Must NOT do**:
- No regex support in user-defined patterns
- No iterative replacement (single pass only)
- No import/export (separate task)

**Recommended Agent Profile**:
- **Category**: `unspecified-high`
- **Skills**: []
- **Reason**: Core logic with word boundary matching algorithm

**Parallelization**:
- **Can Run In Parallel**: YES
- **Parallel Group**: Wave 2 (with Tasks 4, 5)
- **Blocks**: Tasks 6, 7, 8
- **Blocked By**: Task 1

**References**:
- `Pindrop/Services/HistoryStore.swift:14-128` - SwiftData store pattern with modelContext, fetch, save, error handling
- `Pindrop/Services/HistoryStore.swift:45-67` - save() pattern
- `Pindrop/Services/HistoryStore.swift:69-92` - fetch() with FetchDescriptor pattern

**Acceptance Criteria**:
- [ ] **RED**: Create test file `PindropTests/DictionaryStoreTests.swift`
  - Test: `applyReplacements` with "dr" → "Doctor" on "dr smith" returns "Doctor smith"
  - Test: Case-insensitive: "hello" → "hi" on "HELLO world" returns "hi world"
  - Test: Word boundary: "is" → "was" on "this is a test" returns "this was a test" (NOT "thwas was a test")
  - Test: Longer match wins: "new york" vs "york" - "new york city" → only "new york" matches
  - Test: Single pass: ["a"→"b", "b"→"c"] on "a" returns "b" (not "c")
  - `xcodebuild test ...` → FAIL
- [ ] **GREEN**: Implement DictionaryStore
  - `xcodebuild test ...` → PASS
- [ ] `applyReplacements` returns tuple with applied replacements list

**Commit**: YES
- Message: `feat(services): add DictionaryStore with word replacement logic`
- Files: `Pindrop/Services/DictionaryStore.swift`, `PindropTests/DictionaryStoreTests.swift`

---

### Task 4: Create Word Replacements UI

**What to do**:
- Create Word Replacements section in DictionarySettingsView
- Tag-list input for multiple originals (add tags, remove tags)
- Single text field for replacement
- Add button to create new replacement
- List of existing replacements with delete action
- Empty state with helpful text

**Must NOT do**:
- No edit mode (delete and re-add)
- No drag-to-reorder (use sort order internally)
- No search/filter

**Recommended Agent Profile**:
- **Category**: `visual-engineering`
- **Skills**: [`frontend-ui-ux`]
- **Reason**: UI component with tag-list interaction pattern

**Parallelization**:
- **Can Run In Parallel**: YES
- **Parallel Group**: Wave 2 (with Tasks 3, 5)
- **Blocks**: None
- **Blocked By**: Tasks 1, 2

**References**:
- `Pindrop/UI/Settings/GeneralSettingsView.swift:201-219` - SettingsCard component
- `Pindrop/UI/Settings/ModelsSettingsView.swift:97-108` - FilterButton capsule tag pattern
- `Pindrop/UI/Settings/ModelsSettingsView.swift:261-440` - Row pattern with actions
- `Pindrop/UI/Settings/AIEnhancementSettingsView.swift:211-238` - TextField with button pattern

**Acceptance Criteria**:
- [x] Manual verification: Can add tags for originals (e.g., "Fae", "Faye")
- [x] Can enter replacement text
- [x] Add button creates replacement and clears form
- [x] Existing replacements show in list with originals as tags
- [x] Delete button removes replacement
- [x] Empty state shows "No word replacements configured" with hint

**Commit**: YES
- Message: `feat(ui): add Word Replacements section to Dictionary settings`
- Files: `Pindrop/UI/Settings/DictionarySettingsView.swift`

---

### Task 5: Create Vocabulary UI

**What to do**:
- Create Vocabulary section in DictionarySettingsView
- Single text field for adding vocabulary word
- Add button to create new vocabulary entry
- Tag-cloud or list display of existing vocabulary
- Delete action for each word
- Info text explaining vocabulary is sent to AI Enhancement

**Must NOT do**:
- No edit mode (delete and re-add)
- No categorization

**Recommended Agent Profile**:
- **Category**: `visual-engineering`
- **Skills**: [`frontend-ui-ux`]
- **Reason**: UI component following existing patterns

**Parallelization**:
- **Can Run In Parallel**: YES
- **Parallel Group**: Wave 2 (with Tasks 3, 4)
- **Blocks**: None
- **Blocked By**: Tasks 1, 2

**References**:
- `Pindrop/UI/Settings/GeneralSettingsView.swift:201-219` - SettingsCard component
- `Pindrop/UI/Settings/ModelsSettingsView.swift:97-108` - Tag/capsule display pattern
- `Pindrop/UI/Theme/Theme.swift:255-290` - View modifiers for styling

**Acceptance Criteria**:
- [x] Manual verification: Can enter vocabulary word and add
- [x] Vocabulary displays as tags or compact list
- [x] Can delete vocabulary words
- [x] Info text explains: "Vocabulary words are provided to AI Enhancement for context"
- [x] Empty state shows "No vocabulary words added"

**Commit**: YES
- Message: `feat(ui): add Vocabulary section to Dictionary settings`
- Files: `Pindrop/UI/Settings/DictionarySettingsView.swift`

---

### Task 6: Integrate Word Replacements into Pipeline

**What to do**:
- Add DictionaryStore to AppCoordinator (init and property)
- In `stopRecordingAndTranscribe()`, apply replacements BEFORE AI enhancement
- Store applied replacements for passing to AI prompt construction
- Ensure DictionaryStore uses same ModelContext as HistoryStore

**Must NOT do**:
- No UI feedback about replacements (history shows original)
- No conditional replacement (always apply if entries exist)

**Recommended Agent Profile**:
- **Category**: `unspecified-high`
- **Skills**: []
- **Reason**: Pipeline integration with existing service wiring

**Parallelization**:
- **Can Run In Parallel**: YES
- **Parallel Group**: Wave 3 (with Task 7)
- **Blocks**: Task 8
- **Blocked By**: Task 3

**References**:
- `Pindrop/AppCoordinator.swift:56-79` - Service initialization pattern
- `Pindrop/AppCoordinator.swift:461-477` - Transcription result handling
- `Pindrop/AppCoordinator.swift:478-509` - AI enhancement section
- `Pindrop/PindropApp.swift:44` - AppCoordinator initialization with modelContext

**Acceptance Criteria**:
- [x] **RED**: Create test or use manual verification
  - Given replacement "dr" → "Doctor" in dictionary
  - When transcribing audio that produces "dr smith"
  - Then output contains "Doctor smith"
- [x] **GREEN**: Implement pipeline integration
- [x] Replacements applied before AI enhancement
- [x] Applied replacements list captured for AI prompt

**Commit**: YES
- Message: `feat(pipeline): integrate DictionaryStore word replacements`
- Files: `Pindrop/AppCoordinator.swift`

---

### Task 7: Implement Import/Export

**What to do**:
- Add `exportToJSON() -> Data` to DictionaryStore
- Add `importFromJSON(_ data: Data, strategy: ImportStrategy)` to DictionaryStore
- ImportStrategy enum: `.additive` (add new, skip existing), `.replace` (clear and import)
- Export format: `{ "version": 1, "replacements": [...], "vocabulary": [...], "exportedAt": "ISO8601" }`
- Add Export and Import buttons to DictionarySettingsView with NSSavePanel/NSOpenPanel

**Must NOT do**:
- No VoiceInk format import
- No partial import on error (all or nothing)

**Recommended Agent Profile**:
- **Category**: `unspecified-low`
- **Skills**: []
- **Reason**: File I/O with Codable and standard panels

**Parallelization**:
- **Can Run In Parallel**: YES
- **Parallel Group**: Wave 3 (with Tasks 6, 8)
- **Blocks**: None
- **Blocked By**: Task 3

**References**:
- `Pindrop/Services/HistoryStore.swift:178-240` - JSON export pattern with Codable structs
- `Pindrop/AppCoordinator.swift:610-636` - NSSavePanel/NSOpenPanel pattern

**Acceptance Criteria**:
- [x] **RED**: Test export produces valid JSON
  - Test: Export with 2 replacements, 3 vocabulary words
  - Test: Import exported file, verify all entries restored
- [x] **GREEN**: Implement import/export
- [x] Export button shows save panel, saves `.json` file
- [x] Import button shows open panel, imports `.json` file
- [x] Import with additive strategy preserves existing entries
- [x] Malformed JSON shows error alert, no partial import

**Commit**: YES
- Message: `feat(dictionary): add JSON import/export functionality`
- Files: `Pindrop/Services/DictionaryStore.swift`, `Pindrop/UI/Settings/DictionarySettingsView.swift`

---

### Task 8: Construct AI Prompt with Dictionary Context

**What to do**:
- In AppCoordinator, construct enhanced system prompt when AI enhancement enabled:
  - Start with user's custom prompt (or default)
  - Append vocabulary section if vocabulary exists: `"\n\nUser's vocabulary includes: word1, word2, word3"`
  - Append replacements section if replacements were applied: `"\n\nNote: These automatic replacements were applied to the transcription: 'dr' → 'Doctor'. Please preserve these corrections."`
- Pass constructed prompt to `aiEnhancementService.enhance()`

**Must NOT do**:
- No modification to AIEnhancementService signature
- No separate API call for vocabulary

**Recommended Agent Profile**:
- **Category**: `unspecified-low`
- **Skills**: []
- **Reason**: String construction and prompt engineering

**Parallelization**:
- **Can Run In Parallel**: YES
- **Parallel Group**: Wave 3 (with Tasks 6, 7)
- **Blocks**: None
- **Blocked By**: Tasks 3, 6

**References**:
- `Pindrop/AppCoordinator.swift:482-509` - AI enhancement call with customPrompt
- `Pindrop/Services/AIEnhancementService.swift:50-56` - enhance() signature with customPrompt parameter
- `Pindrop/Services/SettingsStore.swift:67` - aiEnhancementPrompt property

**Acceptance Criteria**:
- [x] Manual verification: With vocabulary ["Pindrop", "WhisperKit"]
  - AI prompt includes "User's vocabulary includes: Pindrop, WhisperKit"
- [x] With replacement "dr" → "Doctor" applied:
  - AI prompt includes "These automatic replacements were applied"
- [x] Custom prompt from settings is preserved (not replaced)
- [x] When no vocabulary/replacements, prompt unchanged

**Commit**: YES
- Message: `feat(ai): include dictionary context in AI enhancement prompt`
- Files: `Pindrop/AppCoordinator.swift`

---

## Commit Strategy

| After Task | Message | Files | Verification |
|------------|---------|-------|--------------|
| 1 | `feat(models): add WordReplacement and VocabularyWord SwiftData models` | Models/*.swift, PindropApp.swift | App launches |
| 2 | `feat(settings): add Dictionary tab placeholder to settings` | SettingsWindow.swift | Tab visible |
| 3 | `feat(services): add DictionaryStore with word replacement logic` | DictionaryStore.swift, Tests | Tests pass |
| 4 | `feat(ui): add Word Replacements section to Dictionary settings` | DictionarySettingsView.swift | Manual UI test |
| 5 | `feat(ui): add Vocabulary section to Dictionary settings` | DictionarySettingsView.swift | Manual UI test |
| 6 | `feat(pipeline): integrate DictionaryStore word replacements` | AppCoordinator.swift | E2E test |
| 7 | `feat(dictionary): add JSON import/export functionality` | DictionaryStore.swift, UI | Export/import works |
| 8 | `feat(ai): include dictionary context in AI enhancement prompt` | AppCoordinator.swift | Manual AI test |

---

## Success Criteria

### Verification Commands
```bash
# Run all tests
xcodebuild test -scheme Pindrop -destination 'platform=macOS'

# Build release
xcodebuild -scheme Pindrop -configuration Release build
```

### Final Checklist
- [ ] All "Must Have" present
- [ ] All "Must NOT Have" absent
- [ ] All tests pass
- [ ] Dictionary tab functional
- [ ] Word replacements apply correctly
- [ ] Vocabulary appears in AI prompt
- [ ] Import/Export works end-to-end

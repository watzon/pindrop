# Pindrop "Scorched Earth" Redesign — Implementation Plan

Date: 2026-07-09
Design source: Paper file **"Pindrop — Scorched Earth Redesign"** (28 artboards) — https://app.paper.design/file/01KX4FB7VPQTSSGH2Q2NM8JCNT/1-0
Companion research: `docs/hig-redesign-research.md` (structural/HIG groundwork this design assumes)
Basis: full artboard survey + verified 11-area code gap analysis (22-agent adversarially-verified sweep, 2026-07-09).

---

## 0. TL;DR

The design is *mostly* achievable on the existing backend — the heavy machinery (diarization + speaker profiles, AI summaries, media playback with click-transcript-to-seek, media import pipeline, theme engine, notes, MCP server) already exists. The real backend work concentrates in **six areas**:

1. **Dictation audio persistence + retention** (the design's headline feature — audio is currently *discarded* after transcription)
2. **Insertion-target tracking** ("inserted into Cursor", "→ Slack" — resolved transiently today, never persisted)
3. **Stats aggregation** (Home page needs windowed/day-bucketed stats + streak; only all-time totals exist)
4. **Dictionary semantics** (match modes, order-respecting application, usage counts, recognizer biasing)
5. **Schema V8 migration** (new optional fields — lightweight, follows the V1→V7 precedent)
6. **Commands/keyboard infrastructure** (menu bar, ⌘1–5/⌘N/⌘F, list selection + Delete/Escape — the HIG P0)

Two design elements are **not** backed by anything and should be deferred or explicitly de-scoped (see Decisions): the bundled on-device LLM ("Qwen 2.5 — 3B" picker) and the "Text corrector — 340 M" helper model.

Recommended sequencing: **Phase B (backend) and Phase U1 (design system) in parallel → shell → pages → settings/onboarding → floating surfaces → a11y/keyboard sweep.**

---

## 1. Design inventory (artboard → what it demands)

| Artboard | Surface | Backend it needs | UI work |
|---|---|---|---|
| 01/03 Library (light + dark) | Main page | audio persistence (B2), destination tracking (B3), search/sort (B7), 4-way filter relabel | new list rows, expansion player card, filter chips |
| 02 Home | Main page | stats service (B4) | hero headline, stat tiles, recent list, weekday bar chart |
| 04 Theme presets | Token system | — | preset catalog remap (U1) |
| 05 Notes | Main page | notes nav + ⌘N (B6) | pinned/week groups, list rows |
| 06 Dictionary | Main page | match modes, ordering, usage counts (B5) | vocab chips, replacements table, drag-reorder |
| 07 Models | Main page | (LLM catalog **deferred** — Decision 3) | sectioned model list, active badges, disk total |
| 08 Meeting detail | Drill-in | *exists* (diarization, summary, seek) | restyle + speaker color dots; un-gate for long dictations |
| 10–16 Settings ×7 | Settings window | retention setting + disk usage (B2), openLibrary hotkey + live conflicts (B8), log level + export logs (B9), AI simplified pane (B10) | restyle all panes; structure stays (620 pt, toolbar tabs — already HIG-correct) |
| 20–26 Onboarding ×7 | Wizard | — (steps map 1:1 to existing flow) | restyle at 760×560 |
| 30 Note editor | Floating window | speak-to-append (B6), checkboxes (B6) | 480×560 window, serif title, listening chip |
| 31 What's New | Floating window | — | restyle 460×540 |
| 32 Toasts | Overlay | inserted-toast (B3), copy-undo (B7) | dark ink surface, bottom-right (Decision 7) |
| 40/41 Orb + Pill states | Floating indicator | mic-mute signal for "Muted · dim 40%" state | shader fill-layer restyle only — **goo physics + locked interaction spec unchanged** |
| 42 Orb glass study | Floating indicator | — | dark-glass body + aurora ribbon (theme accent) + wax-red recording thread; per-preset ribbon hues |

Current → new navigation mapping: **Home** stays · **History → Library** · **Notes promoted to page** (from History filter) · **Transcribe page removed** (import becomes an action inside Library; results are Library items) · **Models** stays · Meeting detail becomes a proper drill-in.

---

## 2. Phase B — Backend plan (no visual changes; independently shippable)

Everything here can merge before a single pixel changes. Ordered by dependency.

### B1. Schema migrations (V8) — *foundation for B2/B3/B4*

`Pindrop/Models/TranscriptionRecordSchema.swift` — add `TranscriptionRecordSchemaV8` (complete snapshot of ALL models, per SwiftData rules) + `MigrationStage.lightweight(V7→V8)`:

- `destinationAppName: String?` — localized name at insert time ("Cursor")
- `destinationAppBundleID: String?` — for icon resolution via `NSWorkspace.icon(forBundleIdentifier:)` at render time (never persist icons)
- `wordCount: Int?` — cached; computed at save; lazily backfilled for old records on first read (avoids a custom migration stage)

Dictionary models (locate their schema/versioning first — they may live outside the TranscriptionRecord plan):
- `WordReplacement.matchModeRawValue: String?` (nil ⇒ `caseInsensitive`, preserving today's behavior), `WordReplacement.usageCount: Int = 0`
- `VocabularyWord.usageCount: Int = 0`

All additions are optional-or-defaulted → lightweight migration. **Do not** add waveform peaks or audio expiry to the schema (sidecar file / computed, see B2).

Tests: in-memory container migration test (populate V7 shape → open with V8 plan → assert counts + field defaults), per the established Swift Testing pattern. Manual pass on a real database copy before release.

### B2. Dictation audio persistence + retention — *the headline feature*

Today: `voiceRecording` audio is discarded in memory post-transcription; only imported media keeps files (`ManagedMediaLibrary`). The whole playback stack (MediaPlaybackController/AVPlayer, rate control, click-transcript-to-seek in `MediaTranscriptionDetailView`) already exists and will Just Work once dictations have files.

- **Persist**: encode the captured PCM to AAC `.m4a` (~1 MB/min) via `AVAudioFile`/`AVAssetWriter` into a `ManagedMediaLibrary`-managed `DictationAudio/` area; set `managedMediaPath` on save. Async, off the hot path — insertion latency must not regress.
- **Retention setting**: `SettingsStore.dictationAudioRetention` — `off / 7 days / 30 days / forever` (design shows "7 days"; see Decision 2 for the default). Applies to `voiceRecording` audio only — never auto-delete user-imported media.
- **Sweeper**: launch-time + daily task; deletes expired audio + sidecar peaks, clears `managedMediaPath`, keeps the transcript. Log via `Log.audio`.
- **Disk usage**: aggregate size + count for the Dictation pane ("Audio on disk: 142 MB · 64 snippets") + **Delete all audio** action (files only — distinct from delete-all-history).
- **Waveform peaks**: extract ~150–250 buckets at save time (AVAudioFile + Accelerate/vDSP downsample) → **sidecar file** next to the audio (`<uuid>.peaks`), not a schema field. Backfill on-demand when a row without peaks is expanded.
- **Library row copy** ("audio kept 7 days") is computed from `timestamp` + the setting — no per-record expiry field.

Tests: retention sweeper (fixed clock), peaks extraction on a fixture WAV, disk-usage aggregation.

### B3. Insertion-target capture + success toast

- `OutputManager.output()/pasteViaClipboard()` already resolves the frontmost `NSRunningApplication` — return `(bundleID, localizedName)` in an enriched `OutputResult` instead of discarding it. Capture unconditionally (also in clipboard mode: "frontmost app at copy time").
- `HistoryStore.save(...)` gains `destinationAppName/destinationAppBundleID/wordCount` params; `AppCoordinator` passes them at the post-output save (~AppCoordinator.swift:3050).
- Success toast after insertion: "Inserted into {app} · {n} words" (today only error toasts exist around output).

### B4. Stats service (Home page)

New `DashboardStatsService` (or `HistoryStore` extension) returning a value struct: `wordsToday, wordsThisWeek, sessionsThisWeek, wpmThisWeek (words ÷ stored duration), streakDays, wordsPerWeekday[7], dictationDurationThisWeek, timeSavedThisWeek`.

- Shared word-count helper (`TranscriptionRecord.computedWordCount` / String extension) replacing the four inline `split(separator: " ")` copies; prefer the cached `wordCount` field.
- Calendar-week bucketing respecting `Calendar.current.firstWeekday` (design shows Mon–Sun; follow locale).
- Streak = consecutive calendar days with ≥1 record, walking back from today.
- Time-saved: `(words ÷ 40 wpm typing) − actual dictation duration`, windowed to the week.
- Pure functions over fetched records; unit-test with fixture dates (streak edges: today empty, gap yesterday, DST).
- Defer persisted daily rollups until scale demands it (note as future work).

### B5. Dictionary semantics

- `ReplacementMatchMode` enum: `caseInsensitive` (default) / `exact` / `command`. Branch `DictionaryStore.applyReplacements`.
- **Command mode**: resolve to text insertion of control sequences ("new paragraph" → `"\n\n"`) *within the transcript before output* — no keystroke synthesis needed. Ship a small command palette (new paragraph, new line, tab).
- **Ordering fix**: `applyReplacements` currently sorts by match length; change to `sortOrder`-primary so "first match wins" matches the design copy. ⚠️ Behavior change — audit existing tests + changelog it.
- **Usage counts**: increment `WordReplacement.usageCount` when a rule fires; scan final transcript for vocabulary hits (`VocabularyWord.usageCount`). Batched save, off hot path.
- **Recognizer biasing** (Decision 4): vocabulary is currently only an LLM hint gated behind AI enhancement (off by default) — the design copy "words the recognizer should trust" is not true today. Cheap win: feed vocabulary into WhisperKit's initial prompt. Parakeet hotword biasing = research task, defer.

### B6. Notes plumbing

- `MainNavItem.notes` case + extract History's notes list logic into a Notes page data path (or resurrect dead `NotesView.swift`).
- **Speak-to-append**: new `AppCoordinator` path that appends a transcription into an *open* note (distinct from quick-capture-creates-new-note), plus `isListening/elapsed` state exposed to `NoteEditorView` (reuse the `indicatorState` pattern).
- **Checkboxes**: `- [ ]`/`- [x]` parsing + click-to-toggle + checked strikethrough in `MarkdownEditor` (content stays a plain markdown String — no schema change).
- ⌘N global command (rides on B9 command infra). Pinned grouping is view-layer (`isPinned` exists).

### B7. Library query + export + clipboard undo

- `HistoryStore` descriptor: sort parameter (newest/oldest; reuse `MediaLibrarySortMode`), broadened search predicate (title/summary/source — parity with `matchesMediaLibrarySearch`).
- Delete for plain voice rows (context menu + `onDelete` callback; keyboard Delete rides on B9 selection model).
- Per-recording **Export**: txt/md always; SRT/JSON when segments exist (reuse `TranscribeOutputFormat` machinery) via `NSSavePanel`.
- **Copy-undo**: snapshot prior `NSPasteboard` contents before overwrite; "Copied to clipboard — Undo" toast restores it (reuse the dictionary-learning Undo-toast pattern).
- Un-gate the detail page so long voice dictations can drill in (currently `isMediaTranscription`-only).

### B8. Hotkeys

- New `openLibrary` hotkey slot (SettingsStore triple + `registerHotkeysFromSettings()` branch → show main window on Library).
- Live conflict feedback during capture (today: post-save blocking NSAlert, Pindrop-internal only). Add inline "No conflicts found" / conflict message; best-effort static table of common system shortcuts (⌘Space etc.) — Carbon can't enumerate third-party bindings; keep the copy honest.

### B9. Commands, menus, selection model, Advanced-pane odds & ends

The HIG P0, and the design's What's New card promises it ("Keyboard everywhere"):
- Full menu bar (File/View/Window/Help) with ⌘1–5 nav, ⌘N, ⌘F (focus Library search), export, sidebar-appropriate items — via `.commands`/NSMenu in the existing AppKit setup.
- List selection/focus model for Library/Notes/Dictionary rows + Delete-to-remove (→ existing confirm flow) + Escape-to-dismiss/deselect.
- User-facing **log level** setting mapped onto `AppLogLevel` (exists internally, no setting) + **Export Logs…** (file-backed log store or OSLogStore export) for the Advanced pane.
- Launch-at-login already exists (`LaunchAtLoginManager`) — no work.

### B10. AI enhancement adapter

- Simplified pane semantics: one "Enhance transcripts" toggle + Provider + Model + Prompt preset over the existing per-purpose Assignments system (target `.transcriptionEnhancement`; keep assignments as the advanced substrate). Backend toggle semantics already exist; this is an adapter layer.
- Prompt presets exist (`BuiltInPresets`) — add per-preset before/after example strings for the pane's example block.
- Close the known localized-prompt-persistence risk (CLAUDE.md): guarantee English prompt source when saving unedited defaults + surface the "Prompts are sent in English" note.
- **Deferred** (Decision 3): bundled local LLM runtime (MLX/llama.cpp + "Qwen 2.5 — 3B") and "Text corrector — 340 M". Today's on-device paths are Apple Foundation Models (macOS 26+) and BYO Ollama/LM Studio endpoints. Aligns with the existing ASR+LLM fusion assessment (`plans/asr-llm-fusion-assessment.md`) — don't reopen live LLM refinement as part of a visual redesign.

### B11. Small signals

- Mic-mute detection to drive the orb/pill "Muted · dim 40%" state (input device mute/volume observation via CoreAudio property listener).
- Meeting row metadata ("3 speakers · diarized · summary ready") is derivable today (`diarizedSegments`, `aiSummary != nil`) — helper on the record, no schema work.

---

## 3. Phase U — UI overhaul plan

### U1. Design-system foundation *(parallel with Phase B)*

**Tokens.** Keep `PindropThemeController` architecture (semantic roles, dynamic `NSColor(name:)` light/dark). Retarget the derivation to the Scorched Earth roles:

| Token | Light | Dark ("Candlelit") |
|---|---|---|
| ground | `#F6F4EE` | `#1B1916` |
| page | `#FCFBF7` | `#242119` |
| ink / ink-2 / ink-3 | `#201D18` / `#6E6759` / `#9B937F` | `#EFEBE2` / `#A59D8C` / `#6E675B` |
| line | `#E3DFD3` | `#37332B` |
| accent / accent-soft | `#1F6D53` / `#E7EFE7` | `#4CA582` / `#263A30` |
| record / record-soft | `#B03A2E` / `#F6E7E3` | `#D25B4C` / — |

Map existing 37 roles onto these (windowBackground→ground, contentBackground→page, textPrimary→ink, …), delete dead roles, and add **WCAG clamp** at palette-resolution time (HIG P0 #4): text roles ≥4.5:1, warn in Appearance when a preset can't reach it.

**Presets.** "A preset only remaps `--color-accent` and the two grounds." New default **Library** (`#1F6D53`); remap pindrop/paper/harbor/evergreen/signal onto the new derivation (accents: `#F2B54A`, `#2E4E73`, `#14708A`, `#4D7A4A`, `#F06D4F`); Graphite → Decision 6. What's New copy: "Your theme presets carry over — plus a new default, Library."

**Type.** Bundle Newsreader + Inter + JetBrains Mono (Decision 1): add font files to the target, set `ATSApplicationFontsPath` in Info.plist. Roles: Newsreader (page titles, hero stats, transcript body in expanded cards, note titles, taglines), Inter (all UI controls/body/labels), JetBrains Mono (timestamps, counts, kbd chips, endpoints). Ramp per design tokens: 11/12/13/15/18/24/34/46. Kill all-`.rounded`; route the ~124 ad-hoc `.system(size:)` uses through the new ramp. Provide graceful fallback (system fonts) if a face fails to load.

**Icons.** Unify on SF Symbols (thin/light weights match the design's stroke style); keep 4 provider brand logos; delete `Icons.swift` (HIG P1 #6).

**Components** (build once, screenshot-compare against artboards): sidebar item · "Ready to dictate" status card · filter chip · section header with hairline rule + trailing meta · list row (fixed-width time/icon lanes) · expansion card · play chip (▸ 0:31) · destination pill (→ Slack) · primary/ghost/destructive buttons · search field with ⌘F kbd hint · toggle/settings rows · kbd badge · empty states (`ContentUnavailableView` restyled) · waveform scrubber view.

**Extraction discipline:** during implementation, pull exact values with Paper MCP `get_jsx`/`get_computed_styles` per artboard — never eyeball from screenshots. **Localization discipline:** every new string goes through `Localization/` YAML + `just l10n-sync` for all shipped locales — the redesign rewrites most user-facing copy, so this is a standing cost on every U-phase PR.

### U2. Main window shell

Hidden-titlebar window with full-height sidebar (traffic lights in sidebar, per design); replace the zero-safe-area hack (HIG P1 #7). Nav: Home / Library(+count) / Notes / Dictionary / Models, ⌘1–5 (B9). Footer: status card bound to `FloatingIndicatorState` (Ready / Recording / Processing) + hotkey hint; Settings row with ⌘,. Remove Transcribe nav + `showTranscribe()` reroute. Sidebar keeps collapse + leading/trailing settings (Decision 4): design the collapsed 64 pt icon-rail variant (status dot replaces the footer card; count badges hidden) and verify the trailing/RTL mirror — neither exists in the Paper file, so mock both in Paper before building. Min size per Decision 8 (design canvas is 1160×760).

### U3. Library page *(needs B2, B3, B7)*

Header (serif "Library" + counts) · search + sort · filter chips **All/Dictations/Meetings/Media** (4-way relabel; Notes filter leaves — Notes is a page now) · day sections with item counts · collapsed rows (time, kind icon, preview, destination pill, play chip; expired-audio play chip struck through per artboard 01's 0:24 row) · expanded card (kind badge, "inserted into X", retention note, serif transcript, waveform player with speed control, Copy/Insert again/Export/Delete) · media import affordance (toolbar button + drop-target + link paste; inline job progress replacing the Transcribe page) · meeting rows → detail page (restyle `MediaTranscriptionDetailView`: back link, meta row, summary block with accent bar, speaker turns with stable per-speaker color dots, active-line highlight; seek-by-line already works).

### U4. Home page *(needs B4)*

Date kicker · serif hero with italic accent metric ("You spoke *4,210 words* this week.") · sub-line (duration + time saved) · four stat tiles (mono numerals) · Recent (3 rows, reuse Library row) + "Open Library →" · THIS WEEK weekday bar chart (accent = today, muted = past, hairline = future) + week total.

### U5. Notes page + note editor *(needs B6)*

Page: pinned card section, date-grouped list, search, New note (⌘N). Editor window: 480×560, pinned badge, serif title, interactive checkboxes with strikethrough, "● Listening — speak to append… 0:07" chip while dictating into the note, footer word count + "⌘S to save".

### U6. Dictionary page *(needs B5)*

Vocabulary chip row with usage-count badges + dashed Add chip · Replacements table (mono pattern → replacement, mode label right-aligned: case-insensitive/exact/command) · drag-to-reorder wired to `DictionaryStore.reorder` · footer: "Replacements run in order. Drag rows to re-order — the first match wins."

### U7. Models page

Sections: SPEECH TO TEXT / ON-DEVICE HELPERS. Row: name + Active badge, description meta, size (mono), Installed / Download button. Header: total disk usage. Footer privacy note. Data all exists (`ModelManager`, `FeatureModelType.diarization`). "Text corrector — 340 M" row per Decision 3 (omit or "coming soon").

### U8. Settings restyle *(needs B2, B8, B9, B10)*

Keep the recently-rebuilt structure (620 pt, toolbar tabs, grouped forms — HIG-correct; don't regress). Restyle to warm ground + white grouped cards + green switches. Content deltas: **General** — reset-all footer link. **Dictation** — retention picker, audio-on-disk row + Delete all audio, speaker profiles summary ("3 trained") + Manage. **Appearance** — System/Light/Dark segmented, 6 preset chips with contrast-validation caption, Orb/Pill indicator picker. **Shortcuts** — 4 rows incl. Open Library recorder + inline "No conflicts" line. **AI** — simplified single-flow pane + example block. **Advanced** — MCP toggle/port/endpoint, log level, Export Logs. **About** — centered icon, version + Sparkle channel (mono), tagline "Speak. It's written." (serif italic), links row.

### U9. Onboarding restyle

Same 7 steps, same order — pure restyle at 760×560 fixed: warm ground, serif headings, progress dots (design includes the download step as a dot; current excludes it — follow design), quiet card selections, permission rows with Granted/Grant states, hotkey capture with conflict line, "Try it now" finale.

### U10. Floating surfaces

- **Orb** — locked interaction spec unchanged (idle 30 pt / hover swells 44 pt / recording 56 pt + quiet pill (timer+stop, 10 pt gap) / processing "Transcribing…" / streaming serif live-transcript card / muted dim 40% — needs B11 mute signal). Visual: glass-study fill — dark glass body, aurora ribbon tinted from the active preset's accent, wax-red thread woven in only while recording ("mic is hot" constant across themes). Fill layers are shader-swappable by design; goo physics untouched. Mock shader look before Swift integration (per orb-workflow memory). Honor Reduce Motion (static fallback).
- **Pill (legacy)** — kept as a settings choice: 44×10 resting sliver, live waveform + red dot + timer + stop while recording, transcript card while streaming; draggable, right-click menu retained.
- **Toasts** — dark ink surface over any wallpaper, position per Decision 7; variants: inserted (B3) · copied + Undo (B7) · mic unavailable + Settings action.
- **What's New** — 460×540 restyle; ship with content matching the design (replay, new look, keyboard everywhere).

### U11. Cross-cutting sweep (gates release)

Accessibility (VoiceOver labels on all icon-only controls, grouped rows, recording-state announcements, live-region on streaming pill), Reduce Motion gate in the animation token layer, Increase Contrast/Reduce Transparency response, focus rings + full keyboard traversal, RTL pass, `just l10n-lint` clean, `axiom:accessibility-auditor` run before ship.

---

## 4. Sequencing & PR shape

```
B1 schema ──► B2 audio ──► U3 Library player
         └──► B3 insert-target ──► U3 pills / toasts
B4 stats ──────────────────────► U4 Home
B5 dictionary ─────────────────► U6
B6 notes ──────────────────────► U5
B7/B8/B9 ──────────────────────► U2/U3 + menus everywhere
B10 AI adapter ────────────────► U8 AI pane
U1 tokens/type/components (parallel with all B) ──► U2 shell ──► U3…U10 pages ──► U11 sweep
```

Each B-item is an independent PR with unit tests (`just test`); U1 lands behind the existing theme engine so old UI keeps working until U2 flips the shell. Suggested release framing: one big v0.10 "A new look" release (matches the What's New artboard) with B-items landing silently in prior patch releases.

Verification per PR: `just build`, `just test`, migration test for B1, and screenshot-vs-artboard comparison for each U-phase page (Paper `get_screenshot` as reference).

---

## 5. Decisions

Resolved with Chris on 2026-07-09 (1–4); 5–8 are recommendations to confirm during implementation kickoff.

| # | Decision | Outcome |
|---|---|---|
| 1 | **Fonts** | ✅ **DECIDED: bundle all three** — Newsreader + Inter + JetBrains Mono (OFL; ~1–2 MB). Add to bundle + `ATSApplicationFontsPath`; full fidelity to the Paper design |
| 2 | **Audio retention default** | ✅ **DECIDED: 7 days by default**, prominent onboarding/What's New disclosure + easy "Off" in Dictation settings |
| 3 | **Bundled local LLM + 340 M corrector** | ✅ **DECIDED: defer.** Ship AI pane over existing providers (Apple FM / BYO local server / cloud); omit corrector row until the fusion-project runtime exists |
| 4 | **Sidebar collapse + leading/trailing setting** | ✅ **DECIDED: keep both.** The new sidebar must spec a collapsed (64 pt) variant and mirror correctly in trailing position — adds a U2 design task (derive collapsed/trailing variants from the Paper sidebar; icon-only rail with status dot in the footer card) |
| 5 | **Vocabulary→recognizer biasing** — WhisperKit prompt-bias now + Parakeet later vs relabel copy | Recommend: **WhisperKit prompt now**, Parakeet biasing as follow-up research; keep design copy |
| 6 | **Graphite preset** — migrate its users to Library vs keep as 7th preset | Recommend: **keep as legacy 7th** (settings-only), default new installs to Library |
| 7 | **Toast position** — design says bottom-right; current is top-center | Recommend: **follow design** (bottom-right) |
| 8 | **Min window size** — design canvas 1160×760; HIG doc recommends ≤900 min width | Recommend: **min ~980×640**, default 1160×760 — pages must tolerate narrower widths |

---

## 6. Explicitly out of scope

- Orb interaction/behavior spec (locked) — visual fill layers only
- Live LLM refinement / self-correcting streaming (separate fusion project)
- Settings window *structure* (rebuilt recently, HIG-correct — restyle only)
- CloudKit/sync, Liquid Glass adoption (remains the forward path per HIG doc §3.7)

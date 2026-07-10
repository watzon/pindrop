# Scorched Earth — Extracted Design Spec (U1 foundation)

Source of truth: Paper file "Pindrop — Scorched Earth Redesign" (https://app.paper.design/file/01KX4FB7VPQTSSGH2Q2NM8JCNT/1-0).
Values below were extracted with Paper's JSX/computed-style export (NOT eyeballed). Paper px == SwiftUI pt 1:1.
This file covers the global tokens + the Library-page component vocabulary (which defines most shared components). Home/Settings/Onboarding/floating specs get appended as those phases start.

## 1. Color tokens

| Role | Light | Dark ("Candlelit") |
|---|---|---|
| ground (window/sidebar bg, cards-on-page) | `#F6F4EE` | `#1B1916` |
| page (content bg, selected-item bg) | `#FCFBF7` | `#242119` |
| ink (primary text) | `#201D18` | `#EFEBE2` |
| ink-2 (secondary text) | `#6E6759` | `#A59D8C` |
| ink-3 (tertiary/placeholder) | `#9B937F` | `#6E675B` |
| line (hairlines, borders) | `#E3DFD3` | `#37332B` |
| accent | `#1F6D53` | `#4CA582` |
| accent-soft (badges, status card bg) | `#E7EFE7` | `#263A30` |
| record (destructive/recording) | `#B03A2E` | `#D25B4C` |
| record-soft | `#F6E7E3` | — (derive) |

Theme presets remap ONLY accent (+accent-soft derivation) and the two grounds: Library `#1F6D53` (default) · Pindrop `#F2B54A` · Paper `#2E4E73` · Harbor `#14708A` · Evergreen `#4D7A4A` · Signal `#F06D4F`.

## 2. Typography (bundle Newsreader + Inter + JetBrains Mono — decided)

| Role | Font | Size/Line | Weight | Tracking | Used for |
|---|---|---|---|---|---|
| wordmark | Newsreader | 22/28 | 600 | -0.01em | sidebar "Pindrop" |
| page title | Newsreader | 34/38 | 500 | -0.015em | "Library", "Notes"… |
| transcript body | Newsreader | 17/26 | 400 | 0 | expanded-card transcript |
| body | Inter | 13/16 | 400 | 0 | row preview text |
| body-meta | Inter | 13/22 | 400 | 0 | header meta line |
| label | Inter | 12/16 | 500 | 0 | buttons, chips, nav secondary |
| label-strong | Inter | 13/16 | 500–600 | 0 | nav items (600 = selected) |
| badge | Inter | 11/14 | 600 | 0 | kind badges ("Dictation") |
| caption | Inter | 11/14 | 400 | 0 | "audio kept 7 days" |
| mono-time | JetBrains Mono | 12/16 | 500 | 0 | row times, elapsed/total |
| mono-small | JetBrains Mono | 11/14 | 400–500 | 0 | counts, kbd hints (⌘F, ⌘,), speed chip |
| section header | Inter (measured, artboards 02/08) | 11/14 | 600 | uppercase, +0.08em | "TODAY", "SUMMARY", "THIS WEEK" |

Icons: 16×16 viewBox custom strokes at 1.4 width (thin-stroke look). Map to SF Symbols light/thin weights; keep 1.4-ish optical weight. Icon slots are fixed-width frames (18×18 nav, 16×16 rows) with flexShrink 0 — lane alignment matters.

## 3. Window & sidebar

- Sidebar: **236 pt wide**, bg ground, 1 pt right border line. Padding: 16 top / 16 left / 12 right / 12 bottom.
- Traffic lights inline at top (12 pt circles, 8 pt gap, 22 pt below-padding) → hidden-titlebar window, full-height sidebar.
- Wordmark row: 28 pt below-padding.
- Nav column: 2 pt gap between items, 4 pt right padding.
- **Nav item**: radius 8, padding 7 vert / 10 horiz, 10 pt gap, 18×18 icon slot. Unselected: transparent bg, ink-2 label (Inter 13 · 500), ink-2 icon. Selected: page bg + 1 pt line border, ink label (600), accent icon. Count badge: mono 11 · 500 ink-3, right-aligned.
- **Status card** ("Ready to dictate"): accent-soft bg, radius 10, padding 12, 6 pt gap; row 1: 14 pt mic icon (accent) + Inter 12 · 600 accent; row 2: mono 11 · 500 ink-2 ("⌥ Space anywhere"). States to design: Ready (accent) / Recording (record + timer) / Processing.
- Settings row: nav-item metrics, ⌘, in mono 11 ink-3 right-aligned.

## 4. Page header (Library pattern)

- Content padding: 40 pt top, 40 pt horizontal; 18 pt gap header→filters.
- Title row: baseline-aligned — Newsreader 34 title + Inter 13/22 ink-2 meta, 16 pt gap; spacer; search field right.
- **Search field**: 240 pt wide, ground bg, 1 pt line border, radius 8, padding 7/12, 8 pt gap: 14 pt magnifier (ink-3), placeholder Inter 13 ink-3, trailing ⌘F mono 11 ink-3.
- **Filter chips**: 6 pt gap. Chip: radius full, padding 5/12, Inter 12 · 500. Selected: ink bg, page text. Unselected: 1 pt line border, ink-2 text. Sort chip (right): same + 12 pt icon, 6 pt gap.

## 5. List (Library pattern)

- **Section header**: uppercase label + hairline rule (1 pt line) filling middle + trailing count (both ends 11–12 pt, ink-3/ink-2); ~26 pt tall, groups after the first get extra top padding (~24 pt).
- **Row** (collapsed): 1 pt bottom border line; padding 13 vert / 24 horiz; 10 pt gap. Lanes: time (mono 12 · 500 ink-2, **fixed 64 pt**) → kind icon (16×16 slot, 13 pt glyph, ink-3) → preview (Inter 13 ink, 1-line clamp, flex) → destination "→ Slack" (Inter 12 ink-3, shrink 0) → **play chip**.
- **Play chip**: 74 pt fixed width, radius full, 1 pt line border, padding 3/9, 5 pt gap: 8 pt play triangle (accent fill) + duration mono 11 · 500 ink-2. Expired-audio variant: no play glyph, struck-through duration (artboard 01, 2:30 PM row).
- Meeting row: title Inter 13 ink + meta "3 speakers · diarized · summary ready" ink-3 (from B11 helper).

## 6. Expanded player card (Library)

- Card: ground bg, 1 pt line border, **radius 14**, padding 20 vert / 24 horiz, 16 pt column gap.
- Meta row (20 pt): time (mono 12 · 500 ink-2, 64 pt lane) · **kind badge** (accent-soft bg pill, radius full, padding 3/10, 6 pt gap, 11 pt mic icon accent 1.6 stroke, Inter 11 · 600 accent) · "inserted into Cursor" (Inter 12 ink-2) · spacer · "audio kept 7 days" (Inter 11 ink-3).
- Transcript: **Newsreader 17/26 ink** (the serif moment).
- Player row (44 pt, 16 pt gap): **play button** 44 pt circle accent bg, 16 pt white (page-color) triangle · waveform (32 pt tall, flex): bars 3.5 pt wide, radius 1.75, 15 pt pitch; played = accent, unplayed = line; **playhead**: 2 pt × 32 pt ink bar · elapsed/total mono 12 · 500 ink-2 · **speed chip** (radius full, line border, padding 4/10, mono 11 · 500 ink-2, "1.5×").
- Actions row (2 pt top padding, 8 pt gap): **secondary button** = page bg, 1 pt line border, radius 8, padding 6/12, 6 pt gap, 12 pt icon + Inter 12 · 500 ink (Copy / Insert again / Export); spacer; **destructive ghost** = no bg/border, radius 8, padding 6/10, record-colored icon + label (Delete).

## 7. Component → SwiftUI mapping notes

- Build as `ScorchedTheme`-aware ViewModifiers/components in `Pindrop/UI/Theme/` + `Pindrop/UI/Components/`: `SidebarItem`, `StatusCard`, `PageHeader`, `SearchField`, `FilterChip`, `SectionHeader`, `LibraryRow`, `PlayChip`, `KindBadge`, `PlayerCard`, `WaveformView` (consumes B2 peaks sidecars; bar geometry above), `SecondaryButton`, `DestructiveGhostButton`.
- All colors through the theme engine roles (map: ground→windowBackground/sidebarBackground, page→contentBackground/surface, ink*→text*, line→border, accent, record→error/recording). WCAG clamp on ink-2/ink-3 per plan.
- Fonts: bundled Newsreader/Inter/JetBrains Mono via `ATSApplicationFontsPath`; expose as `AppTypography` roles per §2 (system-font fallback if load fails).
- Fixed lanes (64 pt time, 74 pt play chip, 16/18 pt icon slots) are load-bearing for vertical alignment — use `.frame(width:)` + `flexShrink`-equivalent, not spacing.

## 8. Meeting detail page (artboard 08 — extracted)

- Breadcrumb: 12 pt chevron-left + "Library" (Inter 12, ink-2), navigates back; 16 pt below-gap.
- Title block (8 pt column gap): title **Newsreader 30/36 · 500 · -0.015em** ink; meta row (10 pt gaps): "Today, 8:02 AM" (mono 12 ink-2) · "·" (ink-3) · duration mono · "3 speakers" (Inter 12 ink-2) · spacer · Copy + Export secondary buttons (spec §6 style).
- Player bar: §6 player row (44 pt play circle, waveform, elapsed/total, speed chip) inside a ground card with 1 pt line border (radius 12, ~16 pt padding).
- **Summary block**: 3 pt accent bar (radius 2, full height) · 16 pt gap · column (6 pt gap): "SUMMARY" (Inter 11 · 600, +0.08em tracking, ink-3, uppercase) then body **Newsreader 15/23** ink; 4 pt vertical padding.
- Transcript section header: §5 section-header pattern + trailing hint "click a line to jump playback" (ink-3).
- **Transcript turn row**: 10 pt vertical padding, 14 pt lane gaps. Lanes: timestamp **44 pt fixed** (mono 11 ink-3, 3 pt top pad) · speaker **92 pt fixed** (7 pt colored dot + Inter 12 · 600 ink, 6 pt gap) · text **Newsreader 15/23** ink (flex). Speaker dot colors: stable per-speaker palette (e.g. #14708A teal seen in design); derive a small stable palette hashed by speaker id.
- Active (playing) turn: accent-soft background pill spanning the row (radius 10), timestamp tinted accent; clicking any row seeks playback to its timestamp (existing behavior).

## 9. Home page (artboard 02 — extracted)

- Date kicker: "WEDNESDAY, JULY 9" — Inter 11 · 600, wide tracking (~0.07–0.08em), ink-3, uppercase; sits above the hero.
- **Hero sentence**: Newsreader **46/52 · -0.02em**, baseline-aligned wrap, 11 pt word-gaps, 10 pt bottom padding. Plain segments in ink at weight 400; the metric segment ("4,210 words") in **accent, italic, 500**.
- Hero sub-line: Inter 13-ish ink-2 ("2 h 38 m of dictation — about 1 h 51 m saved over typing it out.").
- **Stats strip**: 36 pt top / 40 pt bottom padding. Stat groups separated by 1×40 pt line dividers with 32 pt horizontal padding between. Each stat (4 pt gap): number **JetBrains Mono 22/28 · 500 ink** ("1,214", "96", "12", "14-day") over label **Inter 11 · 600 +0.07em ink-3 uppercase** (WORDS TODAY / WORDS / MIN / SESSIONS / STREAK).
- **Recent**: §5 section-header pattern with trailing "Open Library →" accent link; 3 rows reusing the Library row anatomy (time lane, icon, preview, destination, play chip).
- **THIS WEEK chart** (40 pt top padding, 14 pt gap): section header (Inter 11 · 600 +0.08em ink-3 + hairline rule). Bars row: 110 pt tall, bottom-aligned, 28 pt gaps; bars **30 pt wide, top radius 5 / bottom radius 2**; past days with data = line color at proportional heights; **today = accent bar + accent 600 label**; future days = 4 pt stub in line color; weekday labels Inter 11 · 500 ink-3, 8 pt below bars. Right-aligned week total: mono 22/28 · 500 ink over "WORDS SO FAR" label, 24 pt bottom padding.

## 10. Notes page + note editor (artboards 05/30 — extracted)

- Header: title "Notes" + "24 notes" meta (§4 pattern); search field ~200 pt; **primary button** "＋ New note ⌘N" (accent bg, page-color label — the one filled-accent button in the app; radius 8, ~32 pt tall).
- **Pinned card**: ground bg, 1 pt line border, **radius 12**, padding 16 vert / 20 horiz, 6 pt gap, 8 pt bottom margin. Title row (10 pt gaps): title **Newsreader 17/22 · 500 ink** (flex) · 12 pt pin icon (accent stroke) · "edited 2 h ago" Inter 12 ink-3. Preview Inter 13/20 ink-2.
- **Note row**: 1 pt bottom border; padding 13 vert / 20 horiz; 10 pt gaps. Lanes: 16 pt note icon slot (13 pt glyph ink-3) · title Inter 13 · 500 ink **fixed 220 pt** · preview Inter 13 ink-2 1-line clamp (flex) · date Inter 12 ink-3 right-aligned **88 pt** lane.
- **Note editor window (480×560)**: titlebar 46 pt (traffic lights + "Pinned" badge right); editor content 432 pt wide: title Newsreader ~22/30, body Inter 13/20-ish, checkbox rows (MarkdownEditor); **listening chip**: accent-soft bg, radius 10, padding 10 vert / 12 horiz, 6 pt top margin, 8 pt gaps — 7 pt record-color dot · "Listening — speak to append…" Inter 12 · 500 ink · spacer · elapsed mono 11 ink-2. Footer 39 pt: "42 words · edited just now" (11-ish ink-3) · "⌘S to save" mono right.

## 11. Dictionary page (artboard 06 — extracted)

- Header: title + "Teach Pindrop your words" meta + primary "＋ Add word" button.
- **Vocabulary chips** (8 pt wrap gaps): ground bg, 1 pt line border, radius full, padding 6 vert / 12 horiz, 7 pt gap — word Inter 13 · 500 ink + count **JetBrains Mono 10/12 ink-3**. **Add chip**: DASHED 1 pt line border, 10 pt plus icon ink-3 + "Add" Inter 13 · 500 ink-3.
- Section headers: §5 pattern ("VOCABULARY" + trailing "Words the recognizer should trust"; "REPLACEMENTS" + "Applied after transcription, before insert").
- **Replacement row**: 1 pt bottom border; padding 12 vert / 20 horiz; 14 pt gaps. Lanes: pattern **JetBrains Mono 13 · 500 ink, fixed 220 pt** · 14 pt arrow icon (accent, →) · replacement JetBrains Mono 13 ink (flex) · mode label Inter 12 ink-3 right ("case-insensitive" / "exact" / "command"). Drag-to-reorder wired to DictionaryStore.reorder.
- Footnote: 12 pt info icon + "Replacements run in order. Drag rows to re-order — the first match wins." (ink-3).

## 12. Models page (artboard 07 — extracted)

- Header: title + "Everything runs on this Mac" meta + right-aligned disk total (mono 15-ish "3.2 GB" over "ON DISK" caption).
- Section headers: SPEECH TO TEXT / ON-DEVICE HELPERS (§5 pattern, 10 pt below-padding).
- **Model row card**: radius 12, padding 14 vert / 20 horiz, 12 pt gaps, 8 pt stacking margin. **Active row: ground bg + 1 pt ACCENT border**; inactive: 1 pt line border, no fill. Content: name **Inter 14/18 · 600 ink** + **Active badge** (accent-soft pill, padding 2/9, 5 pt gap, 6 pt accent dot, Inter 11 · 600 accent) over description Inter 12 ink-2 (3 pt gap); right: size **JetBrains Mono 12 ink-2** · "Installed" Inter 12 · 500 ink-3 OR **Download button** (line border, radius 8, padding 5/12, 11 pt download icon + Inter 12 · 500 ink).
- Footnote: shield icon + privacy line (ink-3): "Models never leave this Mac. Audio is processed locally unless you choose a cloud provider in Settings → AI."
- Per product decision: NO "Text corrector — 340 M" row (deferred runtime).

## 13. Settings window (artboards 10–16 — extracted from General; other panes reuse)

- Window: 620×640 (fixed width, vertical resize OK), **ground** bg. Titlebar row: traffic lights in a 60 pt lane · centered pane title Inter 13 · 600 ink · 60 pt spacer; padding 14 top / 16 sides / 8 bottom.
- **Tab strip** (replaces stock toolbar appearance; structure stays tabbed): centered row, 4 pt gaps, 1 pt line bottom border, padding 4 top / 10 bottom. Tab: radius 8, padding 7 vert / 12 horiz, column (4 pt gap) of 17 pt icon + Inter 11 label. Selected: accent-soft bg, accent icon + label 600. Unselected: ink-2 icon + label 500.
- Content column: padding 20 top / 24 sides / 24 bottom, **16 pt gap between group cards**; pane scrolls inside the fixed frame.
- **Group card**: page bg, 1 pt line border, **radius 10**. Rows: padding 12 vert / 16 horiz, 12 pt gap, 1 pt line separators between rows. Row anatomy: title Inter 13 · 500 ink over optional subtitle Inter 12 ink-2 (1 pt gap), control right-aligned.
- **Toggle switch**: 36×21, radius full, 2 pt padding, 17 pt knob in `#FCFBF7`; on = accent track, off = line track.
- **Dropdown / small button**: ground bg, 1 pt line border, **radius 7**, padding 5 vert / 12 horiz, Inter 12 · 500 ink (+ 9 pt chevron for menus, 8 pt gap).
- Destructive footer action: centered "Reset all settings…" Inter 12 · 500 record color.
- Pane-specific pieces reuse established vocabulary: Appearance = segmented System/Light/Dark (chip-row pattern) + preset chips (accent dot + name, selected = accent-soft border treatment per artboard 12) + Orb/Pill picker chips; Dictation = rows + "Delete all audio…" record link + Manage… button; Shortcuts = recorder rows with kbd chips (mono) + inline conflict line; AI = rows + prompt preview (ground inset card, mono 12) + example block (accent-soft card, strikethrough before-text); Advanced = rows + mono endpoint text; About = centered icon 64 pt (accent rounded square + mic glyph), Newsreader title, mono version line, serif-italic tagline, accent link row.

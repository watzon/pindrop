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

## 14. Onboarding (artboards 20–26 — extracted)

- **Window frame**: all 7 steps are **760×560**, ground bg, radius 12, padding 24, overflow clip. Flex column, items centered. Two rows: **Body** (flexGrow 1, centered vertically + horizontally, 100% width) then **Dots** row (paddingTop 8, pinned to the bottom edge).
- **7 steps → 7 progress dots**: 1 Welcome · 2 Model choice · 3 Download · 4 AI enhancement · 5 Permissions · 6 Hotkey · 7 Ready. The **model-choice (2) and model-download (3) are separate dots** — download gets its own step.
- **Progress dots**: flex, 7 pt gap. Dot height 6, radius full. **Active = accent, 18 pt wide**; inactive = line color, 6×6. Active dot = current step index.
- **Serif heading roles** (two sizes): **big** (Welcome, Ready) = Newsreader **40/46–48 · 500 · -0.02em** ink (Welcome LH 46, Ready LH 48); **step** (Model, Download, AI, Permissions, Hotkey) = Newsreader **28/34 · 500 · -0.015em** ink.
- **Sub-line**: Welcome = Inter **14/22** ink-2, centered, max-width 400, paddingTop 12; other steps = Inter **13/16** ink-2, paddingTop 8.
- **Icon medallion (84×84)**: Welcome = accent bg, radius 24, marginBottom 26, mic glyph SVG 40 (16-viewBox) stroke page (`#FCFBF7`) 1.4. Ready = accent-soft bg, radius full, marginBottom 24, check glyph SVG 40 stroke accent 1.8.
- **Primary onboarding button**: accent bg, **radius 10, padding 10 vert / 22 horiz**, gap 8; label Inter **14 · 600 page** (`#FCFBF7`). Welcome adds a trailing arrow SVG 13 (stroke page 1.6). marginTop 18–30 by step. (Distinct from §10 primary — taller, 14 pt label vs radius-8 / ~32 pt.) **Ghost secondary** ("Skip for now") = Inter 13 · 500 ink-2, no bg/border, gap 14 to the right of the primary.
- **Card selections (step 2 · Model)**: 2 cards, gap 12, container width 560, paddingTop 28; each card page bg, radius 12, padding 18, column gap 8, flexGrow 1. **Selected** = 1.5 pt accent border; **quiet** = 1 pt line border. Header (gap 8): leading 15×15 glyph (accent stroke 1.4 selected / ink-2 quiet) + title Inter 14 · 600 ink (flex) + trailing state — selected = filled accent check disc (r 6.5, page check); quiet = 15×15 radio ring (1.5 pt line, radius full). Body Inter 12/18 ink-2. "RECOMMENDED" tag Inter 11/14 · 600 accent (selected card only).
- **Progress bar (step 3 · Download)**: column gap 10, width 440, paddingTop 32. Track = line bg, radius full, **height 8**, overflow clip; fill = accent bg, radius full, height 8, width % (62% shown). Meta row: mono **12/16** ink-2 left ("684 MB of 1.1 GB") + mono 12/16 ink-3 right ("about 38 s left"). Hint (paddingTop 30, gap 8): 12 pt info icon (ink-3 1.3) + Inter 12/16 ink-3 ("Keep setting up while it downloads — we'll finish in the background.").
- **AI enhancement (step 4)**: column gap 10, width 480, paddingTop 26. **"YOU SAY" card** = page bg, 1 pt line border, radius 12, padding 16 vert / 18 horiz, gap 8; label Inter **11/14 · 600 · +0.07em ink-3**, quote Inter 13/16 ink-2. **"PINDROP WRITES" card** = accent-soft bg (no border), radius 12, padding 16/18, gap 8; label Inter 11/14 · 600 +0.07em accent, result **Newsreader 16/20 ink** (the serif moment). Buttons: gap 14, marginTop 28 — primary "Enable enhancement" + ghost "Skip for now".
- **Permission rows (step 5)**: column gap 10, width 480, paddingTop 26; each row page bg, 1 pt line border, radius 12, padding 16 vert / 18 horiz, gap 14, items center. Icon tile **38×38, radius 10** — **Granted** (mic) = accent-soft bg, glyph SVG 17 accent 1.4; **Grant** (accessibility) = ground bg + 1 pt line border, glyph SVG 17 ink-2 1.4. Text col (gap 2): title Inter 14 · 600 ink + subtitle Inter 12/16 ink-2. Trailing state — **Granted** = gap 6, filled accent check disc (r 6.5, page check) + "Granted" Inter 12 · 600 accent; **Grant** = accent button (radius 8, padding 6 vert / 14 horiz) "Grant…" Inter 12 · 600 page. Footnote (paddingTop 22): Inter 12/16 ink-3 ("Without Accessibility, Pindrop copies text to the clipboard instead."). Continue button marginTop 18.
- **Hotkey capture (step 6)**: keycaps row gap 10, paddingTop 34; each cap page bg, radius 12, padding 14 vert / 22–30 horiz, glyph **JetBrains Mono 24/30 · 500 ink** ("⌥", "Space"). Change hint (paddingTop 22): Inter 12/16 ink-3 ("Press a different combination to change it"). Conflict line (paddingTop 8, gap 8): 12 pt check-circle icon accent 1.3 + Inter 12/16 ink-2. Only the positive **"No conflicts found"** state is drawn; the **conflict/warning variant is (not in design — TBD)** (§13 Shortcuts references an "inline conflict line"). Buttons: gap 14, marginTop 26 — Continue + Skip for now.
- **Ready finale (step 7)**: accent-soft check medallion (above) → "You're set." Newsreader 40/48. Instruction sentence (paddingTop 14, baseline row, gap 7): Inter 14/18 ink-2 "Press" + **inline kbd chip** (page bg, radius 6, padding 2 vert / 8 horiz, "⌥ Space" JetBrains Mono 12/16 · 500 ink) + Inter 14/18 ink-2 "…and start talking — Pindrop types wherever your cursor is." "Try it now" primary button marginTop 30.

## 15. Floating surfaces (artboards 31–42 — extracted)

> The orb/pill boards (40–42) render each state as a tile on a **dark presentation stage** — tile bg `#FFFFFF08`, 1 pt `#FFFFFF12` border, radius 14; caption footer border-top `#FFFFFF12`, 88 pt tall, label Inter 11/14 · 600 +0.07em `#EFEBE2`, desc Inter 11/16 `#B8B1A1`. That tile/caption chrome is **showcase scaffolding, not app UI** — the orb/pill/card values below are the shippable spec. (Note editor floating window is in §10.)

- **The Orb (artboard 40) — locked interaction spec**: hover swells the orb (never a pill), tap toggles recording, the pill appears **only while working**, fill layers are shader-swappable.
- **Orb sizes per state**: idle **30 pt** · hover **44 pt** · recording **56 pt** · processing 44 pt · streaming 56 pt · muted 30 pt (dim 40%). (Verified idle 30 / hover 44 / recording 56 as expected.)
- **Recording orb (56)**: organic blob (border-radius 49%/48% … 52%/47%), radial green interior (oklab), **accent glow** shadow `#206E5299` (≈ accent @ 60%) 0 8px 26px; layered interior "band" blooms (oklab green radials at varying alpha) + white specular; **dashed 44 pt hover ring** `#FFFFFF24` 1 pt.
- **Quiet pill (recording)** — sits right of orb, **resting gap 10 pt**: surface `#181511` @ ~92% (`#181511EB`), 1 pt `#FFFFFF1F` border, radius full, shadow `#00000066` 0 4px 14px; padding 8 vert / 14 horiz, gap 9. Contents: **record dot** 8×8 dark-record (`#D25B4C`) + **timer** JetBrains Mono **13/16 · 500** dark-ink (`#EFEBE2`) + 1×14 divider `#FFFFFF24` + **stop square** 10×10 radius 2.5 dark-ink @ 72% (`#EFEBE2B8`). Timer + stop, nothing else.
- **Processing**: orb 44 "calm" (green radial + white specular, glow `#14523C8C`); pill shell + **3 breathing dots** (4×4, gap 3, dark-accent `#4CA582` at 100 / 55 / 25% alpha) + "Transcribing…" Inter 12 · 500 dark-ink.
- **Streaming**: orb holds 56; **live-transcript card** right of orb (gap 10): surface `#181511EB`, 1 pt `#FFFFFF1F` border, radius 16, shadow as above, padding 12 vert / 16 horiz, column gap 6, **width 250**. Header (gap 8): record dot 7×7 dark-record + timer JetBrains Mono 11/14 · 500 dark-ink-2 (`#A59D8C`) + spacer + stop 9×9 radius 2 dark-ink@72%. Body **Newsreader 14/20 dark-ink** (serif, newest text pinned to tail).
- **Muted**: orb 30 desaturated + dimmed to 40% — same "not listening" signal as the pill.
- **Orb glass study (artboard 42)** — dark glass body + aurora ribbon; **ribbon hue tracks `--color-accent` per theme, wax-red thread stays constant**. Hero shown at **150 pt for detail (runs at 56 pt)**.
  - **Glass body**: radial oklab dark near-black (~L 34%→23%→15%), radius full, overflow clip; theme-accent glow shadow (default `#1F6D5373` = accent @ ~45%, 0 14px 48px). Interior warm/green blooms (oklab radials @ 16–22% alpha).
  - **Aurora ribbon** (SVG wavy bands, back→front): `#17614A` deep green @ .6 · `#B9F0D6` pale mint @ .38 · `#6FDCAF` mint @ .95 (dominant thread) · `#EFD9A8` warm sand @ .75 · **`#D25B4C` wax red @ .8 (recording thread — woven in only while mic is hot)** · `#F0937F` coral @ .35.
  - **Rim**: 1.5 pt `#FFFFFF24` ring + accent arcs (`#6FDCAF` @ .8 bottom-left, `#EFD9A8` @ .7 top-right). Specular white radials @ 55% / 35%.
  - **State variants**: idle glass (30) = single ribbon band `#6FDCAF` @ .5, glow `#1F6D5359`, one white specular @ 28% ("ribbon settles to one dim thread"); hover (44) swells + ribbon brightens; processing (44) ribbon slows to a calm pulse; muted (30) aurora extinguished, glass goes cold.
  - **Theme ribbon remaps** (2-band idle ribbon at 56 pt): **Library** mint `#6FDCAF` + cream `#EFD9A8`, glow `#1F6D5373`; **Pindrop** amber `#F2B54A` + cream `#F7E3BC`, glow `#F2B54A59`; **Harbor** marine `#4FB3D1` + fog `#CFE9F0`, glow `#14708A66`. (Preset accents per §1: Pindrop `#F2B54A`, Harbor `#14708A`.)
- **Pill (legacy) (artboard 41)** — kept as a settings choice; draggable, right-clickable.
  - **Resting**: **44×10 pt** sliver, radius full; fill linear-gradient (oklab ~L 45%→29% @ 95% — dark green-gray), 1 pt `#FFFFFF24` border, shadow `#00000066` 0 3px 10px. Muting → 40% opacity (same signal as orb).
  - **Recording**: pill shell (`#181511EB`, `#FFFFFF1F` border, radius full, shadow 0 4px 14px, padding 8/14, gap 9). Left→right: record dot 8×8 dark-record + **waveform** (SVG 44×14, **9 bars 2.5 pt wide, radius 1.25**, dark-accent `#4CA582`, heights 4–12) + timer JetBrains Mono 13/16 · 500 dark-ink + 1×14 divider + stop 10×10 radius 2.5. Red dot, timer, stop — nothing else.
  - **Processing**: same shell — 3 breathing dark-accent dots (4×4, gap 3) + "Transcribing…" Inter 12 · 500 dark-ink.
  - **Streaming**: transcript card `#181511EB`, radius 16, padding 12/16, gap 6, **width 270**. Header (gap 8): record dot 7×7 + timer mono 11/14 · 500 dark-ink-2 + spacer + **lang chip "en" mono 10/12 dark-ink-3 (`#6E675B`)** + stop 9×9 radius 2. Body Newsreader 14/20 dark-ink.
- **Toasts (artboard 32)** — float bottom-right; the dark ink surface reads over any wallpaper.
  - Toast anatomy: surface **ink** (`#201D18`), radius 12, padding 11 vert / 16 horiz, gap 10, items center. Leading 14 pt status glyph (16-viewBox) + label Inter **13/16 · 500** dark-ink (`#EFEBE2`) + trailing meta/action. (Toast uses dark-theme role hexes as literal surface colors regardless of app theme — always a dark ink chip.)
  - **Inserted** ("Inserted into Cursor"): check glyph dark-accent (`#4CA582`) 1.8 + trailing meta "32 words" JetBrains Mono 11/14 dark-ink-2 (`#A59D8C`).
  - **Copied + Undo** ("Copied to clipboard"): copy glyph dark-accent 1.4 + **"Undo"** action Inter 12 · 600 dark-accent.
  - **Mic unavailable** ("Microphone unavailable — using MacBook Pro Microphone"): warning-triangle glyph **dark-record** (`#D25B4C`) 1.4 + **"Settings"** action Inter 12 · 600 dark-accent.
- **What's New window (artboard 31 — 460×540)**: ground bg, radius 12, padding 20 top / 24 bottom / 28 horiz, overflow clip, flex column.
  - Titlebar: 3 traffic dots 12×12, gap 8, paddingBottom 20 (close `#FF5F57`, other two inert `#E9E5DA`).
  - Heading Newsreader 28/34 · 500 · -0.015em ink ("What's new"); version line JetBrains Mono 12/16 ink-2 ("Pindrop 0.9.4 · July 2026"), paddingTop 4 / paddingBottom 22.
  - **Feature list** (flexGrow 1, column gap 18). **Feature row** (gap 14): 36×36 accent-soft tile, radius 10, accent glyph SVG 16; text col (gap 3): title Inter 14/18 · 600 ink + body Inter 12/18 ink-2.
  - Footer (centered, paddingTop 16): primary "Continue" accent bg, radius 10, padding 9 vert / 26 horiz, Inter 13 · 600 page.

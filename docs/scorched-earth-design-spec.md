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
| section header | Inter (assumed; verify vs mono) | 11–12/14 | 500 | uppercase, wide | "TODAY", "VOCABULARY" |

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

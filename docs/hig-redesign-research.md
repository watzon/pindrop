# Pindrop × Apple HIG — Redesign Research

Date: 2026-07-09
Scope: research only — no code changes. Basis: Apple Human Interface Guidelines (macOS), WWDC 2025 Liquid Glass guidance (macOS Tahoe 26), SF Symbols 7, Apple typography guidance, and a full inventory of Pindrop's UI surface.

---

## 1. Executive summary

Pindrop is a heavily custom-drawn app: every window is a transparent `NSWindow`/`NSPanel` with hand-rolled chrome, a bespoke 37-token theme engine, custom typography (all `.rounded`, hardcoded sizes), a custom sidebar, and a mixed icon system. That gives it a distinctive look — which matters for the product goal (a viral, best-in-class OSS dictation app) — but it diverges from the macOS platform in ways that cost real usability: almost no keyboard access, a nearly empty menu bar, one accessibility label in the entire app, no Reduce Motion handling, no contrast validation on user themes, and an enormous 1215 pt minimum window width.

The redesign shouldn't mean "strip the personality and use stock AppKit." The HIG-compatible move is: **keep the brand layer (theme presets, orb, rounded type as display accents) but rebuild the structural layer on platform primitives** — scenes, menus, keyboard, semantic hierarchy, accessibility — and leave a clean seam for Liquid Glass adoption when the deployment target reaches macOS 26.

Three structural bright spots to preserve: the Settings window (native `.preference` toolbar tabs + grouped Forms — recently rebuilt, correct), the status-bar menu (SF Symbols, correct anatomy), and the theme engine's *architecture* (semantic token names, dynamic `NSColor(name:)` light/dark resolution — the right shape, wrong validation).

---

## 2. Current state inventory (condensed)

| Surface | Implementation | File |
|---|---|---|
| App entry | Placeholder 0×0 `WindowGroup`; all real UI is AppKit-managed | `Pindrop/PindropApp.swift:22` |
| Status bar | `NSStatusItem` + `NSMenu`, template icon, CA ripple animation | `Pindrop/UI/StatusBarController.swift` |
| Main window | Transparent `NSWindow`, `TitlebarlessHostingView` (zeroed safe areas), custom 42 pt title bar, custom sidebar (272/64 pt), notification-based navigation | `Pindrop/UI/Main/MainWindow.swift:56-198` |
| Settings | `NSTabViewController` `.toolbar` style, `.preference` toolbar, grouped Forms, fixed 620 pt width | `Pindrop/UI/Settings/SettingsWindowController.swift` |
| Onboarding | 7-step wizard, floating transparent window, `.ultraThinMaterial` accents | `Pindrop/UI/Onboarding/` |
| Recording overlay | Orb (Metal goo shader) + pill; non-activating panels, all-spaces | `Pindrop/UI/OrbFloatingIndicator.swift`, `PillFloatingIndicator.swift` |
| Toasts | Borderless `.hudWindow` `NSPanel`, bottom-right | `Pindrop/UI/ToastWindowController.swift` |
| Theme | 37 semantic tokens derived from user hex presets via mix/alpha math; in-app light/dark override; 6 presets + contrast knob | `Pindrop/UI/Theme/Theme.swift`, `ThemeModels.swift` |
| Typography | `AppTypography`: 12 hardcoded sizes, all `.rounded`; plus ~125 ad-hoc uses of system text styles elsewhere | `Theme.swift:178-191` |
| Icons | Custom Lucide-style template assets (`IconView`, 35 uses) **and** SF Symbols (103 uses) | `Pindrop/Utils/Icons.swift` |

Quantitative signals (whole app target):

- `.accessibilityLabel`: **1** (the orb). `.help()` tooltips: 18. `accessibilityIdentifier`: 41 (test IDs, not VoiceOver).
- `.keyboardShortcut`: **4**. No `onDeleteCommand` / `onExitCommand` / `.focusable()` anywhere.
- Reduce Motion checks: **0** (Metal shader + CA animations + springs everywhere).
- Hardcoded `.system(size:)` fonts: ~124. Semantic text styles: ~125 (split brain).
- `Table`: 0. Main content lists are `ScrollView` + `LazyVStack` cards.
- `ContentUnavailableView`: 4 (good — pattern already known).
- Materials: `.ultraThinMaterial` in onboarding only; everything else opaque custom fills.

---

## 3. Findings by HIG domain

### 3.1 App composition & scenes — biggest structural gap

**Now:** `PindropApp` declares one placeholder `WindowGroup` (`PindropApp.swift:22-32`) sized 0×0; the delegate builds everything in AppKit. No `MenuBarExtra`, no `Settings` scene, no `Window` scenes, no `.commands`.

**HIG/modern expectation:** menu bar utilities use `MenuBarExtra` (macOS 13+); preferences use the `Settings` scene (free Cmd+, plus App-menu item); singleton auxiliary windows use `Window`. Scene-level `.commands` populate the menu bar and keyboard shortcuts.

**Nuance:** the animated status icon (CA ripple rings on the `NSStatusItem` button, `StatusBarController.swift:553-600`) is *not* reproducible with `MenuBarExtra`'s label — SwiftUI's label doesn't expose the button layer. Keeping `NSStatusItem` is a defensible exception. The rest (Settings scene, Window scenes for main/history/note editor, commands) does not depend on that exception.

**Cost of the current shape:** no window restoration, no free File/Window/View menu behavior, `openSettings`/`openWindow` environment actions unusable, every window reimplements activation/centering/frame autosave by hand.

### 3.2 Menu bar & keyboard access — most user-visible HIG violation

**Now:** the hand-built main menu (`PindropApp.swift:146-182`) has only an App menu and an Edit menu. No File, View, Window, or Help menus. 4 keyboard shortcuts in the whole app (Cmd+, / Cmd+Q / Cmd+Z / std edit keys). Toolbar-equivalent actions (start recording, new note, open history, export) have no menu items and no shortcuts when the main window is frontmost.

**HIG:** "The menu bar must contain ALL actions your app supports." macOS users are keyboard-first; an action that exists only as a button is invisible to keyboard and VoiceOver users. Delete/Escape key handling on lists (`onDeleteCommand`, `onExitCommand`) is absent.

**Redesign direction:** full menu bar (File: New Note / New Transcription / Export…; View: sidebar toggle, nav sections with Cmd+1…5; Window: standard; Help: standard) driven by scene `.commands` + `focusedSceneValue` routing. This is also what makes the app feel "real Mac app" rather than ported.

### 3.3 Navigation & layout

- **Custom sidebar** (`MainWindow.swift:166-175`) reimplements `NavigationSplitView` without its free behavior: no View-menu/sidebar toggle command, no standard collapse animation, no per-window state via `@SceneStorage`. The "sidebar position: leading/trailing" setting is nonstandard on macOS (trailing sidebars conflict with RTL semantics — the code manually juggles `layoutDirection` to compensate, `MainWindow.swift:130-143`).
- **History is a Table use case.** Multi-column sortable data (date, duration, words, source) rendered as card rows in `ScrollView`+`LazyVStack`. HIG: use `Table` when 2+ sortable columns benefit users — column sort/resize/reorder for free, plus proper keyboard selection.
- **Minimum window size 1215×600** (`Theme.swift:78`) is hostile to smaller displays and split-screen use. Apple apps of similar scope run comfortably at ~800-900 pt min width. This forces the window to consume nearly the full width of a 13" MacBook display.
- **Stale window tokens:** `AppTheme.Window.settingsMinWidth: 1024` vs the real controller's fixed 620 pt (`SettingsWindowController.swift:110-115`). Dead tokens should be deleted in the redesign to avoid future confusion.
- **Zeroed safe areas** (`TitlebarlessHostingView`, `MainWindow.swift:56-87`) — a deliberate hack to draw under the title bar. Works, but the redesign should prefer `.windowStyle(.hiddenTitleBar)` + standard full-size content, which keeps traffic lights and drag regions correct without fighting AppKit.

### 3.4 Color system — right architecture, missing guardrails

The theme engine is semantically structured (37 named roles, dynamic light/dark via `NSColor(name:)`) — that part matches HIG intent. Gaps:

1. **No contrast validation.** Text colors are alpha-blends of the user's foreground hex over the user's background hex (`Theme.swift:244-320`). Nothing guarantees 4.5:1 (WCAG AA) for `textSecondary` (0.70-0.72 alpha) or `textTertiary` (0.48 alpha — likely fails on many presets). The "contrast knob" adjusts borders/surfaces, not text. Recommendation: compute WCAG ratios at palette-resolution time and clamp text alphas to meet ≥4.5:1 (≥3:1 for large text); warn in the theme editor when a user hex pair can't reach it.
2. **In-app appearance override** (`PindropThemeController.applyAppAppearance`, `Theme.swift:31-38`): HIG explicitly discourages app-specific light/dark toggles ("users expect apps to honor their systemwide choice"). It's a common power-user feature and defensible for a theming-centric app — but "System" must remain the default, and the redesign should keep the override at the theme layer rather than forcing `NSApp.appearance` globally if Liquid Glass adoption comes later (glass adapts per-appearance; a forced appearance dampens it).
3. **No Increase Contrast / Reduce Transparency response.** `NSWorkspace.accessibilityDisplayShouldIncreaseContrast` / `ShouldReduceTransparency` are never consulted. Custom-drawn surfaces don't get the free system behavior.
4. **System accent color ignored.** Fine as a product choice (theme accent is the brand), but selection highlights inside standard controls (menus, pickers) will use the system accent while custom controls use the theme accent — two accents on screen. Worth a deliberate rule in the redesign.

### 3.5 Typography

- `AppTypography` hardcodes 12 sizes and applies `.rounded` to everything (`Theme.swift:178-191`). HIG guidance: rounded is an accent voice (Reminders uses it selectively); body/reading text in SF Pro reads better at small sizes. All-rounded at 11-14 pt is a legibility tax.
- The 11 pt `tiny` style is used for interactive labels in places (below Apple's floor for readable content; HIG reference: avoid `caption2`-scale text for content users must read).
- ~124 ad-hoc `.system(size:)` uses bypass the token system entirely — the split brain means neither system wins.
- **Redesign direction:** map the ramp onto semantic text styles (`.largeTitle`…`.caption`) with `Font.system(_:design:)` so weight/size relationships track the platform, keep `.rounded` for display/stat/hero text only, and route all usage through the tokens. macOS has no user-facing Dynamic Type, but semantic styles still buy correct optical sizes, Catalyst/future-proofing, and consistency.

### 3.6 Iconography — unify on SF Symbols

Two icon systems coexist: custom Lucide-style template assets (`Icons.swift`, 35 uses — includes `zap`, `sticky-note`, `hard-drive`…) and SF Symbols (103 uses). Costs of the custom set: no weight matching to adjacent text, no `.symbolRenderingMode` hierarchy/palette, no symbol effects, manual scaling (`IconView` hard frames), and visual drift against the SF Symbols used one view over.

Nearly every custom icon has a direct SF Symbol equivalent (`zap`→`bolt.fill`, `sticky-note`→`note.text`, `hard-drive`→`internaldrive`, `eye-off`→`eye.slash`, …). The only justified exceptions are the four brand logos (OpenAI, Anthropic, Google, OpenRouter) — keep those as assets or convert to custom SF Symbols so they gain weight variants.

**Missed delight:** only 3 `symbolEffect` uses. Recording state changes, copy confirmation (`checkmark` draw-on), download progress, processing spinners are all canonical symbol-effect moments (`.bounce` on tap, `.variableColor` while processing, `.replace` content transitions). SF Symbols 7 Draw On/Off (macOS 26) could later animate the mic/waveform beautifully — availability-gated.

### 3.7 Materials & Liquid Glass readiness (macOS Tahoe 26)

Current deployment target is macOS 14, so Liquid Glass is a *forward path*, not a today-task. Findings for that path:

1. **Opaque custom fills everywhere will suppress automatic adoption.** When the app is eventually built against the macOS 26 SDK, standard components only pick up glass if custom backgrounds are removed. The redesign should establish the two-layer rule now: *navigation layer* (sidebar, title bar, toolbars, floating controls) kept free of opaque custom backgrounds where possible; *content layer* (cards, lists, editors) keeps theme fills. That seam is what makes later `#available(macOS 26)` adoption cheap.
2. **Onboarding's `.ultraThinMaterial` accents** (badges, capsules — `WelcomeStepView.swift:87`, `AIEnhancementStepView.swift:286-455`, etc.) are the correct pre-glass idiom and map 1:1 to `.glassEffect()` later.
3. **The orb is already the app's "liquid glass" signature** — a Metal goo shader predating the system material. Per the locked orb spec, don't rebuild it on `.glassEffect()`; it's content-layer art, not chrome, and the system material can't do audio-reactive lobes anyway.
4. **Toasts and the pill** are floating chrome — prime `.glassBackgroundEffect()` candidates when gated on macOS 26; today they'd benefit from `NSVisualEffectView`/`.regularMaterial` backing instead of flat custom fills, which also gets Reduce Transparency behavior for free.
5. **Theme presets vs glass tension:** fully custom window backgrounds are exactly what Apple says "interferes" with glass. Resolution: theme presets tint the *content layer*; chrome stays system-material. Decide this in the redesign, not during a later SDK bump.
6. If a macOS 26 SDK build happens before design work is ready, `UIDesignRequiresCompatibility` (Info.plist) preserves current appearance while auditing.

### 3.8 Motion

Good: a centralized animation token set (`AppTheme.Animation`) with sane spring parameters. Gaps:

- **Zero Reduce Motion handling.** SwiftUI `symbolEffect`s respect it automatically, but the Metal orb shader, CA ripple rings on the status item, onboarding slide transitions, and spring-heavy hover states do not. Add a single `@Environment(\.accessibilityReduceMotion)` / `NSWorkspace.accessibilityDisplayShouldReduceMotion` gate in the token layer (e.g., `AppTheme.Animation.resolved(_:)` returning opacity-fades under Reduce Motion) so every consumer inherits compliance.
- Status-item ripple runs indefinitely during recording — reasonable signal, but under Reduce Motion it should fall back to the static dot + tint.

### 3.9 Accessibility (summary — deserves its own audit pass)

- **1 VoiceOver label app-wide.** Every `IconView`-only and symbol-only button is unlabeled; custom card rows aren't grouped (`.accessibilityElement(children: .combine)`); recording state changes aren't announced; the live transcript pill has no live-region semantics.
- The 41 `accessibilityIdentifier`s are UI-test IDs, not user-facing accessibility.
- Keyboard: no focus management on custom lists, no Escape-to-dismiss on custom panels (system sheets/popovers get it free; the custom windows don't).
- The `axiom:accessibility-auditor` agent should run as a dedicated follow-up before the redesign ships; this research treats accessibility as a P0 workstream but doesn't enumerate every violation.

### 3.10 What's already right (preserve in redesign)

- Settings window: native preferences anatomy (`.toolbar` tab style, `.preference` toolbar, grouped Forms, fixed width, vertical-only resize) — matches HIG precisely. Recent work; don't regress it.
- Status-bar menu anatomy: status row, contextual insert/remove of recording actions, SF Symbols with `isTemplate`, submenu for recents — textbook.
- `ContentUnavailableView` for empty states (4 uses) — extend the pattern, don't replace it.
- Context menus on history/note rows.
- Hairline borders computed from `displayScale` — nice detail, keep.
- Localization discipline (locale plumbed everywhere, RTL layout direction handling) — unusual and good.

---

## 4. Prioritized recommendations

**P0 — platform-structural (do first; unblocks everything else)**
1. Scene modernization: `Settings` scene, `Window` scenes for main/note editor/what's-new, keep `NSStatusItem` as documented exception. Delete the placeholder-WindowGroup hack.
2. Full menu bar + keyboard shortcuts via `.commands` + `focusedSceneValue` (File/View/Window/Help, Cmd+1…5 nav, Cmd+N, Cmd+E export, Delete on rows, Escape dismissal).
3. Accessibility pass: VoiceOver labels on all icon-only controls, grouped card rows, recording-state announcements; Reduce Motion gate in the animation token layer; Increase Contrast/Reduce Transparency response for custom surfaces.
4. Contrast validation in the theme engine (clamp text alphas to WCAG AA; theme-editor warning).

**P1 — visual-system consolidation (the redesign proper)**
5. Typography: semantic ramp, `.rounded` demoted to display accent, eliminate ad-hoc `.system(size:)`, kill 11 pt interactive text.
6. Iconography: migrate the 35 custom icons to SF Symbols (keep 4 brand logos), delete `Icons.swift`, add symbol effects at the canonical moments.
7. Main window: `NavigationSplitView` (or a custom sidebar that at least adopts `@SceneStorage`, sidebar toggle command, and standard metrics), History → `Table`, min width down to ≤900 pt, drop the sidebar-position setting (or keep as hidden power toggle), replace zero-safe-area hack with `.hiddenTitleBar`.
8. Two-layer material rule: chrome on system materials (`NSVisualEffectView`/`.regularMaterial` today), theme tint on content layer. This is the Liquid Glass seam.

**P2 — forward-looking polish**
9. Liquid Glass adoption plan behind `#available(macOS 26, *)`: glass on toasts/pill/toolbars, `.glassBackgroundEffect()` on floating panels, SF Symbols 7 draw animations. Orb untouched.
10. Layered app icon via Icon Composer (macOS 26 dynamic icon variants).
11. Onboarding: consider sheet-on-main-window instead of separate floating window; material accents already map to glass.

**Explicit non-goals**
- Orb behavior/spec (locked: blob orb, quiet pill, hover swells orb, tap toggles recording).
- Theme presets as a feature (differentiator — make them validated + content-layer-scoped, not removed).
- Settings window structure (recently rebuilt, HIG-correct).

---

## 5. Open questions for the redesign kickoff

1. **Brand vs platform dial:** how much of the custom chrome (transparent windows, 28 pt panel radii, custom title bar) is identity vs incidental? The two-layer rule needs a decision on whether the *main window* reads as "themed canvas" (current) or "Mac window with themed content."
2. **Deployment target:** stay macOS 14, or move to 15 (gains `UtilityWindow` for floating panels) — 26 for full glass presumably too aggressive for the OSS audience today?
3. **Sidebar position setting:** keep (power-user), or drop for `NavigationSplitView` conformance?
4. **System accent color:** offer "match system accent" as a 7th preset?

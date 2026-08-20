# Console Mode Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a macOS 26 menu-bar note console summoned by a global hotkey, with SQLite-backed notes, Liquid Glass UI, and sub-50ms summon latency.

**Architecture:** AppKit `NSPanel` shell hosts SwiftUI content. `NoteStore` (GRDB) is the single source of truth; `ValueObservation` pushes list updates. `PanelGeometry` is pure math, tested without `NSScreen`.

**Tech Stack:** Swift 6.3, SwiftPM executable, GRDB 7.11.1, KeyboardShortcuts 1.10.0, Swift Testing, Makefile app bundle.

**Spec:** `docs/superpowers/specs/2026-08-20-console-mode-design.md`

## Global Constraints

- Deployment target: **macOS 26.0** only (`LSMinimumSystemVersion = 26.0`).
- Dependencies: **GRDB.swift ≥ 7.11.1**, **KeyboardShortcuts ≥ 1.10.0** — no others.
- App name / bundle id: **Console Mode** / `com.seanperkins.ConsoleMode`.
- `LSUIElement = true` — no Dock icon.
- Default hotkey: **⌃⇧`** (`Shortcut(.backtick, modifiers: [.control, .shift])`).
- Storage: `~/Library/Application Support/ConsoleMode/notes.sqlite`.
- Collapsed height = `PanelGeometry.contentHeight(rowCount: 1)` → **89pt**.
- Expanded max = **half** screen height.
- Return commits single-line notes; completion stays in place with strikethrough.
- One glass surface on the card; honor Reduce Transparency.

---

### Task 1: SwiftPM scaffold + app bundle

Create `Package.swift`, `Makefile`, `Resources/Info.plist`, `Main.swift`, stub `AppDelegate`, `README.md`.

Verify: `swift build && make bundle`.

Commit: `feat: SwiftPM scaffold and app bundle Makefile`.

---

### Task 2: NoteStore (TDD)

Files: `Note.swift`, `NoteStore.swift`, `NoteStoreTests.swift`.

API: `append` trims and returns nil if empty; `setCompleted`; `fetchRecent`; `observeRecent` via GRDB `ValueObservation.tracking`.

Tests: trim/reject, newest-first order, completion round-trip.

Commit: `feat: NoteStore with GRDB schema and tests`.

---

### Task 3: PanelGeometry (TDD)

Files: `ScreenMetrics.swift`, `PanelGeometry.swift`, `PanelGeometryTests.swift`.

Tests: `contentHeight(1) == 89`, half-screen clamp, horizontal centering.

Commit: `feat: PanelGeometry with half-screen clamp tests`.

---

### Task 4: ConsolePanel

Nonactivating status-bar panel, show/hide animation, prewarm hosting view at launch, `ScreenLocator.screenForMouse()`.

Commit: `feat: ConsolePanel with prewarm and frame animation`.

---

### Task 5: NoteListModel + views

`NoteListModel`, `ConsoleView`, `NoteRow` — glass card, placeholder row, expand, observation limits 1/200.

Commit: `feat: ConsoleView with Liquid Glass card and note rows`.

---

### Task 6: Hotkey + status item

`HotkeyName.swift`, signpost, ⌃⇧ toggle, Settings/Quit menu, click-outside + Esc dismiss.

Manual smoke: hotkey, Return, checkbox, expand, dismiss.

Commit: `feat: global hotkey, status item, dismiss monitors`.

---

### Task 7: Settings

`SettingsView` with `KeyboardShortcuts.Recorder` and launch-at-login.

Commit: `feat: settings with hotkey recorder and launch at login`.

---

### Task 8: README + latency

OSSignposter median summon time (<50ms target), full `swift test`, README with `make run`.

Commit: `docs: README and summon latency notes`.

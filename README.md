# Console Mode

macOS 26 quick-capture note console. Summon with **⌃⇧`** (Control–Shift–backtick), type a line, press Return.

## Requirements

- macOS 26+
- Xcode 26 / Swift 6.3

## Build & run

```bash
make run      # build, bundle, launch
make test     # unit tests
make bundle   # ConsoleMode.app only
```

## Usage

| Action | Result |
|---|---|
| **⌃⇧`** (default) | Toggle the note console |
| **Return** | Save note, clear field |
| **Esc** | Dismiss console |
| **Click outside** | Dismiss console |
| **Chevron** | Expand/collapse list (max half screen) |
| **Checkbox** | Mark note complete (stays in place) |

Rebind the shortcut from the menu bar icon → **Settings…**.

## Storage

Notes: `~/Library/Application Support/ConsoleMode/notes.sqlite`

## Architecture

- **ConsoleModeKit** — SQLite store (GRDB), panel geometry, SwiftUI views, global hotkey
- **ConsoleMode** — thin `@main` executable (`LSUIElement` menu bar app)

## Docs

- Spec: `docs/superpowers/specs/2026-08-20-console-mode-design.md`
- Plan: `docs/superpowers/plans/2026-08-20-console-mode.md`

## Latency

Summon uses `onKeyDown` (fires on press, not release). The `Summon` signpost in Instruments (`subsystem: com.seanperkins.ConsoleMode`) ends on the hosting view’s first draw after `orderFront`, not when `show()` returns — so it measures hotkey-to-first-frame, not the 0.18s drop animation. Target: under 50ms.
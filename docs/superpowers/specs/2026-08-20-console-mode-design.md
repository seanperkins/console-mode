# Console Mode — Design

**Date:** 2026-08-20
**Status:** Approved, ready for implementation planning

## Goal

A keystroke-summoned note console for macOS. Press the global hotkey anywhere, a
Spotlight-style card drops from the top of the screen, type a line, press Return.
The note is saved with a timestamp. Notes carry a completion state you toggle
with a checkbox. The card shows the previous note by default and expands to a
scrollable list capped at half the screen height.

The app optimizes for capture latency. Summoning it must never feel like
launching something.

## Non-goals

Rich text, tags, search, multi-line notes, sync, sharing, an Obsidian bridge,
reminders, recurrence, and nested tasks are all out of scope. Each is a separate
request if it ever becomes one.

## Platform and dependencies

| Item | Value | Why |
|---|---|---|
| Deployment target | macOS 26.0 | Public SwiftUI Liquid Glass API. Single rendering path. |
| Language | Swift 6.3, strict concurrency | Toolchain default. |
| UI | AppKit shell hosting SwiftUI content | See "Approach" below. |
| Storage | SQLite via GRDB.swift | `ValueObservation` drives the list without polling; correct WAL and threading for free. |
| Hotkey | sindresorhus/KeyboardShortcuts | Modern API, no Carbon, no Accessibility permission prompt, ships a `Recorder` view for rebinding. |
| Build | SwiftPM executable + `make` bundling step | No `.xcodeproj` to hand-edit. Follows the itsypad precedent. |
| Tests | Swift Testing (`import Testing`) | Native to this toolchain. |

Two dependencies total. Rejected: SwiftData (opaque, heavy, and SQLite was
specified), soffes/HotKey (wraps Carbon, deprecated ~15 years),
`NSGlassEffectView` (see "Risks").

## Approach

**AppKit shell, SwiftUI content.** `NSApplication` plus an `AppDelegate` owns a
custom `NSPanel`; the panel's content is a SwiftUI tree inside an
`NSHostingView`.

AppKit retains control of the things SwiftUI's window abstractions do not expose:
window level, non-activating behavior, collection behavior across Spaces, and
frame animation. SwiftUI provides the visual layer — Liquid Glass, SF Symbols,
native toggles, spring animations — that would otherwise be hand-rolled.

Rejected alternatives:

- **Pure AppKit** (`NSTextField` + `NSTableView`). Marginally lower latency at a
  large cost in code: strikethrough, dimming, glass, and every animation done by
  hand. `NSTableView` cell reuse buys nothing for a list capped at ~20 visible
  rows.
- **Pure SwiftUI lifecycle** (`@main App`, `MenuBarExtra`). Cannot control window
  level, non-activating behavior, or centered positioning. AnyDoor explicitly
  chose `NSStatusItem` + `NSPanel` over `MenuBarExtra` for these reasons.

## Architecture

Six units. Each has one responsibility and a stated dependency edge.

| Unit | Responsibility | Depends on |
|---|---|---|
| `NoteStore` | Owns the database. `append`, `setCompleted`, `observeRecent`. No UI knowledge. | GRDB |
| `PanelGeometry` | Pure functions computing the panel's frame. Holds no state and no AppKit objects. | — |
| `ConsolePanel` | `NSPanel` subclass. Level, collection behavior, show/hide and expand motion. No note knowledge. | `PanelGeometry` |
| `NoteListModel` | `@Observable`. Draft text, expanded flag, recent notes. Commits drafts. | `NoteStore` |
| `ConsoleView`, `NoteRow` | SwiftUI presentation only. | `NoteListModel` |
| `AppDelegate` | Activation policy, status item, hotkey registration, settings, launch-at-login. | all |

Data flow is one-directional:

```
hotkey ──▶ AppDelegate ──▶ ConsolePanel.toggle()
                                  │
typing ──▶ NoteListModel.draft ───┤
                                  ▼
Return ──▶ NoteStore.append ──▶ SQLite ──▶ ValueObservation
                                              │
                                              ▼
                              NoteListModel.recent ──▶ SwiftUI re-render
```

No manual refresh call exists anywhere. Writes land in SQLite and the observation
pushes the new list back.

## Data

```sql
CREATE TABLE note (
  id           INTEGER PRIMARY KEY AUTOINCREMENT,
  body         TEXT    NOT NULL,
  created_at   REAL    NOT NULL,
  completed_at REAL
);
CREATE INDEX note_created_at_idx ON note(created_at DESC);
```

`completed_at` is a nullable Unix timestamp: `NULL` means open. This encodes both
the completion state and the moment of completion at no extra storage cost, which
is strictly more information than a boolean flag.

- **Location:** `~/Library/Application Support/ConsoleMode/notes.sqlite`
- **Pragmas:** `journal_mode = WAL`, `synchronous = NORMAL`
- **Queries, three total:**
  - `INSERT INTO note (body, created_at) VALUES (?, ?)`
  - `UPDATE note SET completed_at = ? WHERE id = ?`
  - `SELECT * FROM note ORDER BY created_at DESC LIMIT ?` — limit 1 collapsed, 200 expanded

Bodies are trimmed of surrounding whitespace before insert. An empty or
whitespace-only draft is discarded rather than stored.

## Interaction

| Input | Result |
|---|---|
| Global hotkey (default ⌃⇧`) | Toggles the panel. Opening focuses the input field. |
| Return | Commits the draft, clears the field, keeps focus. Fire several in a row. |
| Escape | Dismisses the panel. Focus returns to the app you were in. |
| Click outside | Dismisses the panel. |
| Expand button | Toggles between the collapsed card and the tall list. |
| Checkbox click | Toggles that note's completion. |

The default hotkey is written ⌃⇧` because `~` is physically Shift-backtick; ⌃~
and ⌃⇧` are the same chord. It is rebindable in Settings via
`KeyboardShortcuts.Recorder`.

A completed note stays exactly where it is in the chronological list, rendered
with a filled checkbox, strikethrough body, and reduced opacity. Nothing
reorders and nothing disappears, so the row under the cursor never moves out
from under a second click.

## Geometry and motion

Frame math lives in `PanelGeometry` as pure functions so the clamping logic is
testable without a screen.

- **Width:** 640pt, fixed.
- **Horizontal position:** centered on the screen containing the cursor
  (`NSEvent.mouseLocation`), not unconditionally the main display.
- **Top edge:** `screen.visibleFrame.maxY - 120`.
- **Collapsed height:** 92pt — one previous-note row (28) + input (36) + 12pt
  padding top and bottom + a hairline divider.
- **Expanded height:** `min(contentHeight, screen.visibleFrame.height / 2)`.
  Content beyond that scrolls. This clamp is the only non-obvious geometry, and
  it gets direct test coverage.
- **Corner radius:** 16pt.

Motion:

- **Drop in, 0.18s, ease-out.** The window origin animates down 24pt into its
  final position while alpha goes 0 to 1.
- **Dismiss, 0.12s.** The reverse. Faster out than in, which is the pattern
  Apple uses across the system.
- **Expand and collapse.** Window height animates with a spring; the list is a
  `ScrollView`.

Window configuration:

- `styleMask`: `[.nonactivatingPanel, .titled, .fullSizeContentView]`, with
  `titlebarAppearsTransparent = true`, `titleVisibility = .hidden`, and
  `isMovable = false`. `canBecomeKey` is overridden to return `true`.
- `level = .statusBar` and
  `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]`,
  so the panel appears over fullscreen apps and follows you between Spaces.
- `isOpaque = false`, `backgroundColor = .clear`, `hidesOnDeactivate = false`.

`.nonactivatingPanel` lets the panel take keystrokes without activating the app,
so whatever you were working in stays frontmost and Escape drops you straight
back into it with no app switch.

## Visual design

Exactly one glass surface: the card background. Apple's guidance for Liquid Glass
is that it belongs to the navigation layer and never to content, and that glass
must never be stacked on glass because glass cannot sample glass. Rows,
checkboxes, timestamps, and body text are therefore plain content drawn on top of
a single glass panel.

```swift
GlassEffectContainer {
    VStack(spacing: 0) { /* previous note, divider, input */ }
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
}
```

**Reduce Transparency.** macOS 26 users can tune system glassiness, and the
setting must be honored. When
`NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency` is true, the
card renders as an opaque `.windowBackgroundColor` rect of the same geometry
instead of glass. No layout changes.

Row anatomy, 28pt tall: leading checkbox (SF Symbol `circle` /
`checkmark.circle.fill`), body text in `.body`, trailing timestamp in `.caption`
with `.secondary` foreground. Completed rows apply `.strikethrough()` and 40%
opacity to the body and timestamp only — the checkbox stays at full opacity so it
remains an obvious click target for undoing.

## Performance

The requirement is that summoning never feels like launching. Made concrete:

1. The panel and its `NSHostingView` are constructed once in
   `applicationDidFinishLaunching` and retained for the process lifetime. Showing
   the panel sets a frame and runs an animation; it never builds a view tree.
2. `LSUIElement = true`. No Dock icon, no window restoration work.
3. The database opens once at launch. GRDB caches prepared statements.
4. Zero timers and zero polling at idle. The only live objects are the hotkey
   handler and the status item.
5. **Budget: hotkey to first frame under 50ms.** Instrumented with
   `OSSignposter`. The measured number gets reported rather than asserted.

## Settings and lifecycle

A minimal `NSStatusItem` is required, not decorative: under `LSUIElement` there
is otherwise no route to quit the app or rebind the hotkey. Its menu holds
Settings, Quit, and nothing else.

Settings is a small standard window with the `KeyboardShortcuts.Recorder` and a
launch-at-login toggle backed by `SMAppService.mainApp`.

## Build and distribution

SwiftPM executable target plus a `Makefile` that assembles `ConsoleMode.app`:
copies the binary, writes `Info.plist` (`LSUIElement`, `CFBundleIdentifier`,
`LSMinimumSystemVersion = 26.0`, `NSPrincipalClass = NSApplication`), and ad-hoc
signs with `codesign --force --sign -` for a stable bundle identity.

Personal use, so no notarization and no App Store target. `make run` builds,
bundles, and launches.

## Testing

Unit tests only where they defend a contract that could plausibly break:

- **`NoteStore`**, against an in-memory database: insert ordering, completion
  round-trip, `completed_at` null semantics, whitespace-only drafts rejected.
- **`PanelGeometry`**: the half-screen clamp at and beyond the boundary,
  collapsed versus expanded heights, cursor-screen selection with multiple
  displays.

Nothing else gets a unit test. Window behavior, glass rendering, focus, and
motion are verified by launching the app and driving it: hotkey opens it, typing
and Return commits, the previous note appears above the field, expand clamps at
half screen, the checkbox strikes a row through in place, Escape returns focus to
the prior app. Claims about the UI come from watching it run.

## Risks

Three unknowns, each with a concrete fallback. All three resolve during
implementation, not planning.

1. **Does SwiftUI `.glassEffect()` sample behind-window content in a transparent
   `NSPanel`?** Unverified. If it renders as flat translucency instead of true
   glass, fall back to an `NSVisualEffectView` with `.hudWindow` material and
   `.behindWindow` blending as the panel's content root, with the SwiftUI tree
   layered above it.

2. **SwiftUI `TextField` focus inside a non-activating panel is historically
   fiddly.** Mitigation: explicitly `makeFirstResponder` on the hosting view and
   set `@FocusState` when showing. If SwiftUI focus proves unreliable, wrap an
   `NSTextField` in an `NSViewRepresentable`, which sidesteps SwiftUI focus
   entirely and costs nothing visually — the field is a plain single-line input.

3. **Animating the window frame while glass re-samples may stutter.** There is a
   [confirmed macOS 26.2 defect](https://developer.apple.com/forums/thread/810314)
   where `NSGlassEffectView` caches its backdrop and stops updating when a window
   moves — which is why the AppKit glass route is rejected outright. If the
   SwiftUI route shows similar artifacts during the drop-in, switch the animation
   from the window frame to alpha plus an internal content offset, keeping the
   window frame static.

## Reference implementations

- [itsypad](https://github.com/nickustinov/itsypad-macos) (MIT) — pure-SwiftPM
  macOS app structure, global hotkey overlay, markdown checklist toggling.
  Closest architectural precedent.
- [Quickeys](https://github.com/alexrosenfeld10/Quickeys) (BSD-3) — hotkey-toggled
  dropdown note window. Closest feature precedent; dated implementation.
- [notchify](https://github.com/fr0sty1122/notchify) — borderless floating
  `NSPanel` anchored to the top of the screen.
- [AnyDoor](https://github.com/ZingerLittleBee/AnyDoor) — `NSStatusItem` plus
  floating `NSPanel`, deliberately not `MenuBarExtra`.
- [Antinote](https://onmymenubar.app/antinote/) (closed source) — interaction and
  motion reference for a hotkey overlay that draws over fullscreen apps.

# Terminal Tab Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a third `ConsoleTab` (`.terminal`) — a live PTY-backed shell inside the same quick-capture panel — without compromising the panel's core promise: **⌃⇧` to visible content in effectively zero perceived latency**, every time, regardless of whether the terminal has ever been used.

**Performance is the spec, not a constraint on the spec.** Every task below carries a measurable budget. A task that meets its functional acceptance but misses its budget is not done.

**Architecture:** `GhosttyTerminal` (Lakr233/libghostty-spm, MIT, Metal-accelerated, wraps the actual `libghostty` engine — verified real via GitHub, not SwiftTerm) supplies `TerminalSurfaceView` (SwiftUI) over an `.inMemory(session)` backend bridging to a real `Process`+PTY. The PTY process lives on `ConsoleShell`, sibling to `NoteListModel`/`UsageMonitor`, spawned lazily and kept alive independent of panel visibility.

**Tech stack addition:** `Lakr233/libghostty-spm` (`GhosttyTerminal` product only — not `GhosttyTheme`/`ShellCraftKit`, both unnecessary weight for a single default-themed embedded shell).

---

## Global Constraints (performance budgets)

- **Cold panel summon** (⌃⇧` from a fully idle app, terminal tab never touched): unaffected. **0ms added** — nothing terminal-related runs until the terminal tab is actually selected. Regression here is the one unacceptable outcome of this whole feature.
- **First terminal-tab activation**: PTY spawn + shell rc-file load + first Metal frame, **P50 < 150ms, P95 < 400ms** (a resolved `.zshrc`/`.bashrc` with typical prompt tooling, e.g. Starship, dominates this — budget accounts for it).
- **Subsequent terminal-tab activation** (session already spawned, panel re-summoned or tab re-switched): **< 16ms** to first frame — this is a visibility toggle, not a spawn, and must feel identical to switching to Notes/Usage.
- **Idle cost when the terminal tab is not the active tab, panel visible**: **0% CPU, no Metal frames submitted.** Only the active tab's content should ever render.
- **Idle cost when the panel is hidden (Esc/click-outside/summon toggle off)**: **0% CPU, no Metal frames submitted**, PTY process itself stays alive (so `top`/a background build survives dismissal) but produces no rendering work. `GhosttyTerminal`'s `isSurfaceVisible = false` is the documented primitive for exactly this — verify it actually parks the render loop, not just skips presentation.
- **Steady-state memory**: bounded scrollback (target **5,000 lines**, tunable in Settings) so a session left open for days does not grow unbounded. Measure RSS delta with the terminal tab spawned + idle vs. before this feature existed.
- **App bundle size delta**: report it (the prebuilt XCFramework has real weight — `libghostty-spm`'s README doesn't state a number; measure `ConsoleMode.app` before/after `make bundle`). This is a disclosure requirement, not a hard gate, but it must be visible in the PR/commit, not discovered later.
- **Key-routing overhead on every keystroke, in every tab** (not just terminal): the existing `ConsoleKeyBinding.action(for:)` fast path must stay allocation-free and branch on tab identity first — a Notes-tab keystroke must not pay for terminal-tab dispatch logic it never uses.

---

### Task 0: Spike — key-routing contract (build this before any terminal UI)

This determines whether the feature is viable at all with this panel's existing global key interception; get it wrong and no amount of terminal rendering quality saves it.

Files: `ConsoleKeyBinding.swift` (read fully first), `Tests/ConsoleModeTests/PanelHarnessTests.swift` (`KeyDriver`, existing pattern).

Change: extend `ConsoleKeyBinding.action(for:)` (or add a tab-aware sibling) so that when `activeTab == .terminal`, only `⌃Tab` (cycle tabs) and the global summon chord pass through as app-level actions — everything else (`⌃C`, `⌃R`, arrow keys, `⌃1`/`⌃2`/`⌃3`) must resolve to "pass to the terminal" (`nil` from the app's perspective, exactly like `plainDigitsReachTheTextField` already does for the Notes tab's text field).

Tests: table-driven, mirroring the existing `KeyDriver` tests exactly — for every chord currently claimed by the app (`⌃1`, `⌃2`, `⌃R`, `⌃C`, arrows), assert it resolves to `nil`/passthrough when `activeTab == .terminal`, and unchanged behavior when `activeTab == .notes`/`.usage`.

Verify: `swift test --filter PanelHarnessTests` green; manually reason through (no terminal UI exists yet to test live) that no chord a shell user expects (reverse-search, SIGINT, history) is silently eaten.

Commit: `feat: tab-aware key routing contract for a future terminal tab`.

---

### Task 1: Dependency + `TerminalConfig` + lazy-activation state — **done, revised below**

Files: `Package.swift` (added `Lakr233/libghostty-spm`, `GhosttyTerminal` product only), `TerminalConfig.swift` (pure settings struct + `TerminalSettings`, mirrors `UsageConfig`), `ConsoleShell.swift` (`terminalEnabled`, `hasActivatedTerminal`).

**Revision from the originally written Task 1/2 split, found while reading the real API before writing Task 2:** there is no hand-rolled `Process`+`Pipe` PTY bridge to write. `GhosttyTerminal` ships a `TerminalSessionBackend.exec` case — setting `TerminalSurfaceOptions(backend: .exec, workingDirectory:, envVars:, command: nil)` spawns a *real* PTY to the user's actual login shell (`$SHELL`, unset `command` = the engine's own default, the same code path the real Ghostty app uses), entirely inside `libghostty`'s C core. `.inMemory(session)` — the bytes-in/bytes-out bridge `TerminalSession.swift` was going to wrap — is for a host that wants to intercept/synthesize the byte stream itself (e.g. `ShellCraftKit`'s sandboxed shell). We want the user's real shell, so `.exec` is correct and there is nothing left to hand-roll: no `TerminalSession.swift` file, no custom scrollback counter (the engine owns scrollback; `TerminalConfig.scrollbackLines` still exists as the number handed to it once Task 2 wires it through, if the API exposes a knob — verify during Task 2 and drop the setting if it doesn't).

Commit: `feat: libghostty-spm dependency, TerminalConfig, lazy terminal-activation state` (landed).

---

### Task 2: TerminalView + tab wiring, with the visibility *and persistence* contract enforced

Files: new `TerminalTabView.swift` (SwiftUI, wraps `GhosttyTerminal.TerminalSurfaceView` + `TerminalViewState`, backend `.exec`), `ConsoleTab.swift` (add the `.terminal` case — every exhaustive switch over `ConsoleTab` needs a case added in this same commit: `title`/`symbol`/`commandDigit`, `ConsoleShell.select`, `ConsoleView.body`, `PanelGeometry.panelHeight`), `ConsoleShell.swift` (`select(.terminal)` calls `markTerminalActivated()`), `ConsoleView.swift`, `PanelGeometry.swift` (fixed `terminalHeight: CGFloat` constant — no per-content sizing), `AppDelegate.swift` (pass `terminalActive: shell.activeTab == .terminal` into `ConsoleKeyBinding.action(for:terminalActive:)`, closing the loop Task 0 opened).

**The persistence trap (found reading `TerminalViewState`/`TerminalSurfaceView` before writing this task):** `ConsoleView.body` currently does `switch shell.activeTab { case .notes: ...; case .usage: ... }` directly inside a `VStack` — SwiftUI tears down and rebuilds view identity on every case change. A naive `case .terminal: TerminalTabView(...)` in that same switch would destroy the underlying `NSView`/surface (and the PTY it owns) every time the user switched to Notes or Usage — exactly the "session survives tab switch" requirement failing silently. `GhosttyTerminal`'s own README says exactly how a host is supposed to avoid this: *"A host that keeps several surfaces mounted at once (tabs hidden behind `opacity(0)`) sets `terminal.isSurfaceVisible = false` on the hidden ones. The surface keeps its grid, scrollback, and session; only rendering stops."*

So `ConsoleView.body` needs a `ZStack`, not a bare `switch`, for the terminal case specifically: the existing `switch` keeps handling `.notes`/`.usage` exactly as today (no regression there), and `TerminalTabView` is layered on top, gated by `shell.hasActivatedTerminal` for *mounting* (stays absent from the tree — zero cost — until first activation) and by `.opacity(shell.activeTab == .terminal ? 1 : 0)` + `.allowsHitTesting(...)` for *visibility* thereafter (mounted permanently once activated, session persists, rendering gates via `isSurfaceVisible`). Two independent gates, two independent constraints — do not collapse them into one `if`.

Change: `TerminalTabView` sets `context.isSurfaceVisible = (shell.activeTab == .terminal)` and additionally `false` whenever the panel itself is not shown (wire through whatever `ConsolePanel`/`ConsoleShell` visibility signal already exists for prewarm/dismiss) — both conditions gate rendering, matching the two idle-cost budgets in Global Constraints. `PanelGeometry` gets a `terminalHeight: CGFloat` constant (propose ~20 rows worth, matching `usageRowHeight`-scale reasoning) and `panelHeight(tab:...)`'s `switch` gains a `.terminal` case using it.

Tests: `PanelGeometryTests` — `.terminal` case returns the fixed height regardless of PTY/scrollback state. `PanelHarnessTests` — tab switch to `.terminal` and back doesn't affect notes/usage geometry; `hasActivatedTerminal` flips exactly once across repeated `.terminal` selections (already covered for the flag itself in Task 1 — this test covers `select(_:)` actually calling it). Key-routing: `AppDelegate`'s dispatch now passes `terminalActive` — no unit-testable surface there beyond what Task 0 already covers directly on `ConsoleKeyBinding`.

Verify: `swift build`, `swift test --filter "PanelGeometryTests|PanelHarnessTests"` green. Manual: launch, toggle to terminal tab, confirm a real prompt renders and accepts input; toggle away and back, confirm the session (cwd, scrollback, running command) survived; confirm Esc/⌃R/⌃1 reach the shell per Task 0's contract, not the app.

Commit: `feat: terminal tab UI wired to exec-backend PTY with visibility and identity persistence`.

---

### Task 3: Settings + performance verification pass

Files: `SettingsView.swift` (new terminal section: enable toggle, scrollback line cap stepper, shell path override defaulting to `$SHELL`), `TerminalConfig.swift` (mirrors `UsageConfig`'s `Settings.current` pattern).

Verify (this is the task — budgets from Global Constraints, measured not assumed):
- Cold summon latency, terminal never touched: capture before/after this feature with `Instruments` or a coarse `CFAbsoluteTimeGetCurrent()` bracket around the hotkey handler in a debug build; **must show no regression**.
- First terminal activation latency: P50/P95 over ~20 samples (fresh spawn each time — toggle terminal off/on in Settings to force re-spawn between samples, or restart the app).
- Idle CPU: `top -pid <ConsoleMode PID>` sampled over 30s with the terminal tab active-but-panel-hidden, and again with a different tab active-and-panel-visible — both must read ~0% attributable to terminal rendering.
- Bundle size: `du -sh ConsoleMode.app` before this plan's first commit vs. after Task 3, reported in the commit message, not silently absorbed.

Commit: `feat: terminal settings; perf verification documented in commit`.

---

### Task 4: README

Files: `README.md` — extend the "Usage tab" precedent section with a "Terminal tab" section: what it is, the lazy-spawn/visibility-gated performance model in plain language (so a user who cares about "why does this stay light" gets an answer), scrollback cap default, shell override.

Commit: `docs: terminal tab section, performance model explained`.

---

## Deliberately out of scope (raises the performance/complexity budget, not core to "lightweight and quick")

- Multiple terminal sessions/tabs-within-the-tab — one shell, one session, matches the panel's single-purpose ethos.
- Custom shell themes (`GhosttyTheme` product) — default rendering only; picking a theme system is a separate decision with its own weight.
- Terminal-tab search/copy-mode UI beyond whatever `GhosttyTerminal` gives for free — scope creep away from performance-first.
- Split panes, tmux-style layout — this panel is deliberately small (`cardWidth = 640`); a split terminal is not "lightweight."

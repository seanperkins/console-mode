import GhosttyTerminal
import SwiftUI

/// The terminal tab's content: a single, persistent PTY session to the
/// user's real login shell.
///
/// Backend is `.exec`, not `.inMemory` — `.exec` is `libghostty`'s own
/// PTY-spawn path (the same one the real Ghostty app uses), so there is no
/// custom `Process`/`Pipe` bridge to write or maintain here. `command: nil`
/// and `workingDirectory: nil` mean "the engine's own defaults" — the
/// user's `$SHELL`, in their home directory — unless overridden in Settings.
///
/// Mounted exactly once, by `ConsoleView` gating on
/// `shell.hasActivatedTerminal` — never torn down after that. Tab switches
/// and panel dismissal only ever toggle `isSurfaceVisible`, so the shell
/// process, its working directory, and its scrollback survive every switch;
/// only the render loop stops.
struct TerminalTabView: View {
    @Bindable var shell: ConsoleShell
    @StateObject private var terminal: TerminalViewState

    init(shell: ConsoleShell) {
        self.shell = shell
        // Seeded with the live theme at construction (first activation), not
        // `.default` — `onChange` below keeps it current after that.
        _terminal = StateObject(wrappedValue: TerminalViewState(theme: shell.theme.terminalTheme()))
    }

    private var isVisible: Bool {
        shell.activeTab == .terminal && shell.isPanelVisible
    }

    var body: some View {
        TerminalSurfaceView(context: terminal)
            // The underlying AppKit view otherwise reports its own intrinsic
            // grid size (its idea of a default terminal, not this card's
            // fixed content height) and paints past it — this is what pins
            // it to exactly the space `ConsoleView`'s ZStack gives it, the
            // same content height Notes/Usage already share.
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .onAppear {
                let config = TerminalSettings.current
                terminal.configuration = TerminalSurfaceOptions(
                    backend: .exec,
                    workingDirectory: config.workingDirectory.isEmpty ? nil : config.workingDirectory,
                    command: config.shellPath.isEmpty ? nil : config.shellPath
                )
                terminal.isSurfaceVisible = isVisible
                if isVisible {
                    terminal.requestFocus()
                }
            }
            .onChange(of: isVisible) { _, visible in
                terminal.isSurfaceVisible = visible
                if visible {
                    // Deterministic, not the best-effort SwiftUI FocusState
                    // bridge: ⌃3/click must land the cursor in the terminal
                    // on the same keystroke that switches to it, not on a
                    // second one.
                    terminal.requestFocus()
                }
            }
            .onChange(of: shell.themeID) { _, _ in
                terminal.setTheme(shell.theme.terminalTheme())
            }
    }
}

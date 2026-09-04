import Foundation

enum ClaudeStatusLineError: LocalizedError, Equatable {
    case settingsUnreadable(String)
    case settingsUnwritable(String)
    case wrapperUnwritable(String)

    var errorDescription: String? {
        switch self {
        case .settingsUnreadable(let detail):
            return "Could not read ~/.claude/settings.json: \(detail)"
        case .settingsUnwritable(let detail):
            return "Could not write ~/.claude/settings.json: \(detail)"
        case .wrapperUnwritable(let detail):
            return "Could not write the statusline wrapper script: \(detail)"
        }
    }
}

/// Installs a tiny wrapper as Claude Code's `statusLine` command so this app
/// can read the documented statusline JSON feed (rate limits + Claude's own
/// cost estimate, see `ClaudeStatusSnapshot`) without touching credentials
/// or depending on a third-party statusline tool.
///
/// Whatever `statusLine` command was configured before install is recorded
/// and chained: the wrapper tees the payload to our cache, then forwards the
/// same bytes to that command unchanged, so the visible status line in
/// Claude Code is unaffected. `uninstall()` restores it exactly.
struct ClaudeStatusLineInstaller: Sendable {
    var settingsURL: URL
    var supportDirectory: URL

    static let `default` = ClaudeStatusLineInstaller(
        settingsURL: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json"),
        supportDirectory: {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            return base.appendingPathComponent("ConsoleMode", isDirectory: true)
        }()
    )

    var cacheURL: URL { supportDirectory.appendingPathComponent("claude-statusline.json") }
    var wrapperURL: URL { supportDirectory.appendingPathComponent("claude-statusline-wrapper.sh") }
    var stateURL: URL { supportDirectory.appendingPathComponent("claude-statusline-state.json") }

    /// Marks a wrapper script this installer wrote, so `isInstalled` never
    /// mistakes an unrelated file at the same path for our own.
    private static let marker = "# installed-by: ConsoleMode claude-statusline"

    /// Whole prior `statusLine` object, not just the fields this app cares
    /// about — documented keys also include `refreshInterval` and
    /// `hideVimModeIndicator`, and future ones may exist. Stored as raw JSON
    /// so nothing there is ever lost or guessed at.
    private struct InstallState {
        var previousStatusLine: [String: Any]?
        var hadStatusLine: Bool
    }

    /// True only when the wrapper file exists *and* the active
    /// `statusLine.command` actually points at it — either alone can be
    /// stale (a hand-edited settings.json, or a wrapper deleted out from
    /// under an active config).
    var isInstalled: Bool {
        guard let settings = try? readSettings(), commandIsOurs(in: settings) else { return false }
        return (try? String(contentsOf: wrapperURL, encoding: .utf8))?.contains(Self.marker) ?? false
    }

    func install() throws {
        do {
            try FileManager.default.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
        } catch {
            throw ClaudeStatusLineError.wrapperUnwritable(error.localizedDescription)
        }

        let settings = try readSettings()

        if commandIsOurs(in: settings) {
            // Already wired to our wrapper (a repeat install, or the wrapper
            // file went missing under an active config): repair the wrapper
            // from whatever was actually saved before we were first
            // installed. Never treat our own command as "the previous
            // command" — that would make the wrapper forward to itself.
            try writeWrapperScript(previousCommand: readState()?.previousStatusLine?["command"] as? String)
            return
        }

        let existing = settings["statusLine"] as? [String: Any]
        let previousCommand = existing?["command"] as? String
        try writeState(InstallState(previousStatusLine: existing, hadStatusLine: existing != nil))
        try writeWrapperScript(previousCommand: previousCommand)

        // Clone whatever was there before (padding, refreshInterval,
        // hideVimModeIndicator, ...) and only replace the command, so every
        // other setting the user configured survives untouched.
        var newStatusLine = existing ?? ["type": "command"]
        newStatusLine["command"] = Self.shellQuoted(wrapperURL.path)

        var updated = settings
        updated["statusLine"] = newStatusLine
        try writeSettings(updated)
    }

    func uninstall() throws {
        var settings = try readSettings()

        // If the current `statusLine.command` no longer points at our
        // wrapper, the user (or something else) already changed it since
        // install — a later edit wins, and restoring our saved snapshot over
        // it would silently clobber that change.
        guard commandIsOurs(in: settings) else {
            cleanupInstalledFiles()
            return
        }

        if let state = readState() {
            if state.hadStatusLine, let previousStatusLine = state.previousStatusLine {
                settings["statusLine"] = previousStatusLine
            } else {
                settings.removeValue(forKey: "statusLine")
            }
        } else {
            // No recorded state (installed by a version that predates it, or
            // the state file was deleted): drop our entry rather than guess.
            settings.removeValue(forKey: "statusLine")
        }
        try writeSettings(settings)
        cleanupInstalledFiles()
    }

    private func commandIsOurs(in settings: [String: Any]) -> Bool {
        guard let statusLine = settings["statusLine"] as? [String: Any],
              let command = statusLine["command"] as? String
        else { return false }
        return command.contains(wrapperURL.path)
    }

    private func cleanupInstalledFiles() {
        try? FileManager.default.removeItem(at: wrapperURL)
        try? FileManager.default.removeItem(at: stateURL)
        try? FileManager.default.removeItem(at: cacheURL)
    }

    // MARK: - settings.json

    private func readSettings() throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: settingsURL.path) else { return [:] }
        let data: Data
        do {
            data = try Data(contentsOf: settingsURL)
        } catch {
            throw ClaudeStatusLineError.settingsUnreadable(error.localizedDescription)
        }
        guard !data.isEmpty else { return [:] }
        do {
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw ClaudeStatusLineError.settingsUnreadable("not a JSON object")
            }
            return object
        } catch let error as ClaudeStatusLineError {
            throw error
        } catch {
            throw ClaudeStatusLineError.settingsUnreadable(error.localizedDescription)
        }
    }

    private func writeSettings(_ settings: [String: Any]) throws {
        do {
            try FileManager.default.createDirectory(
                at: settingsURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: settingsURL, options: .atomic)
        } catch {
            throw ClaudeStatusLineError.settingsUnwritable(error.localizedDescription)
        }
    }

    // MARK: - Install state

    private func writeState(_ state: InstallState) throws {
        var object: [String: Any] = ["hadStatusLine": state.hadStatusLine]
        if let previousStatusLine = state.previousStatusLine {
            object["previousStatusLine"] = previousStatusLine
        }
        do {
            let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: stateURL, options: .atomic)
        } catch {
            throw ClaudeStatusLineError.wrapperUnwritable(error.localizedDescription)
        }
    }

    private func readState() -> InstallState? {
        guard let data = try? Data(contentsOf: stateURL),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hadStatusLine = object["hadStatusLine"] as? Bool
        else { return nil }
        return InstallState(previousStatusLine: object["previousStatusLine"] as? [String: Any], hadStatusLine: hadStatusLine)
    }

    // MARK: - Wrapper script

    private func writeWrapperScript(previousCommand: String?) throws {
        let forward = previousCommand.map { "printf '%s' \"$input\" | \($0)\n" } ?? ""
        let script = """
        #!/bin/sh
        \(Self.marker)
        # Reads Claude Code's statusLine JSON once, caches it for ConsoleMode,
        # then forwards the same bytes to whatever statusLine command ran
        # before this was installed (if any) so the visible line is unchanged.
        input="$(cat)"
        tmp="\(cacheURL.path).tmp.$$"
        printf '%s' "$input" > "$tmp" && mv "$tmp" "\(cacheURL.path)"
        \(forward)
        """
        do {
            try script.write(to: wrapperURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: wrapperURL.path)
        } catch {
            throw ClaudeStatusLineError.wrapperUnwritable(error.localizedDescription)
        }
    }

    /// POSIX single-quote escaping. `statusLine.command` is executed as a
    /// shell command line, and this app's own support directory can contain
    /// spaces ("Application Support") — an unquoted path there would split
    /// into multiple words and fail to launch.
    private static func shellQuoted(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

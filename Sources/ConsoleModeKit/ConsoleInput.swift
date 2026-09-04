import Foundation

/// Commands that need the app shell rather than the note store.
enum ConsoleAction: Equatable, Sendable {
    case openSettings
    case quit
}

/// A command typed as `/name argument`.
enum SlashCommand: String, CaseIterable, Equatable, Sendable {
    case help
    case tag
    case untag
    case done
    case clear
    case delete
    case expand
    case collapse
    case settings
    case quit
    case find
    case project
    case todo
    case all
    case review
    case next
    case copy
    case remind
    case unremind
    case analyze
    case actions
    case unaction

    /// Shorthands. Kept separate from the raw values so `CaseIterable` stays clean.
    private static let aliases: [String: SlashCommand] = [
        "h": .help,
        "?": .help,
        "t": .tag,
        "d": .done,
        "x": .delete,
        "rm": .delete,
        "e": .expand,
        "c": .collapse,
        "q": .quit,
        "prefs": .settings,
        "scan": .analyze,
        "a": .actions,
    ]
    /// Every name that resolves to a command — canonical names plus aliases.
    static func matchableEntries() -> [(name: String, command: SlashCommand)] {
        var entries = allCases.map { ($0.rawValue, $0) }
        for (alias, command) in aliases {
            entries.append((alias, command))
        }
        return entries
    }


    static func named(_ raw: String) -> SlashCommand? {
        let key = raw.lowercased()
        return SlashCommand(rawValue: key) ?? aliases[key]
    }

    var takesArgument: Bool {
        switch self {
        case .tag, .find, .project, .remind, .analyze: true
        default: false
        }
    }

    var summary: String {
        switch self {
        case .help: "list commands"
        case .tag: "set the project on the selected note"
        case .untag: "remove the project"
        case .done: "toggle completion"
        case .clear: "empty the input"
        case .delete: "delete the selected note"
        case .expand: "show the full list"
        case .collapse: "show one note"
        case .settings: "open settings"
        case .quit: "quit Console Mode"
        case .find: "search note text"
        case .project: "filter by project"
        case .todo: "show incomplete notes"
        case .all: "clear filters"
        case .review: "step through to-do notes"
        case .next: "skip to next in review"
        case .copy: "copy selected note"
        case .remind: "set a reminder (also: every weekday 9am)"
        case .unremind: "clear the reminder"
        case .analyze: "classify notes with omp + Claude"
        case .actions: "show actionable notes only"
        case .unaction: "clear action review on selected note"
        }
    }
}


/// One row in the slash-command suggestion palette.
struct CommandSuggestion: Equatable, Sendable, Identifiable {
    let command: SlashCommand
    let name: String
    let summary: String

    var id: String { name }

    var insertText: String {
        command.takesArgument ? "/\(command.rawValue) " : "/\(command.rawValue)"
    }
}

/// What the user typed, resolved before anything touches the database.
enum ConsoleInput: Equatable {
    case empty
    case command(SlashCommand, argument: String)
    case unknownCommand(String)
    /// A note plus any `#tags` pulled out of it. `body` has the tags removed.
    case note(body: String, tags: [String])

    /// `/` and `#` are only special at the start of a word, so URLs and C-style
    /// comments in the middle of a note survive untouched.
    static func parse(_ raw: String) -> ConsoleInput {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .empty }

        if trimmed.hasPrefix("/") {
            let withoutSlash = trimmed.dropFirst()
            let parts = withoutSlash.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            guard let name = parts.first, !name.isEmpty else { return .unknownCommand("") }

            let argument = parts.count > 1
                ? parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                : ""

            guard let command = SlashCommand.named(String(name)) else {
                return .unknownCommand(String(name))
            }
            return .command(command, argument: argument)
        }

        let (body, tags) = extractTags(from: trimmed)
        return .note(body: body, tags: tags)
    }

    /// Pulls `#tag` tokens out and returns the remaining prose. Tags are normalized
    /// to the same slug form the tagger uses so manual and model labels agree.
    static func extractTags(from text: String) -> (body: String, tags: [String]) {
        var tags: [String] = []
        var kept: [String] = []

        for token in text.split(separator: " ", omittingEmptySubsequences: true) {
            let candidate = token.dropFirst()
            // The character after `#` must be alphanumeric, so `##fff` and `#-x`
            // read as prose rather than tags.
            guard token.hasPrefix("#"),
                  let lead = candidate.first,
                  lead.isLetter || lead.isNumber,
                  let slug = ProjectTagger.normalize(String(candidate))
            else {
                kept.append(String(token))
                continue
            }
            if !tags.contains(slug) {
                tags.append(slug)
            }
        }

        let body = kept.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return (body, tags)
    }

    static var helpText: String {
        SlashCommand.allCases
            .map { "/\($0.rawValue)" }
            .joined(separator: "  ")
    }
    static func isCommandDraft(_ raw: String) -> Bool {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("/")
    }

    /// Partial command name after `/`, before the first space. Nil when not composing a command.
    private static func commandBody(from raw: String) -> Substring? {
        let leadingTrimmed = raw.drop(while: { $0.isWhitespace })
        guard leadingTrimmed.hasPrefix("/") else { return nil }
        return leadingTrimmed.dropFirst()
    }

    static func commandNamePrefix(from raw: String) -> String? {
        guard isCommandDraft(raw), let withoutSlash = commandBody(from: raw) else { return nil }
        guard let space = withoutSlash.firstIndex(where: { $0.isWhitespace }) else {
            return String(withoutSlash)
        }
        return String(withoutSlash[..<space])
    }

    /// True while the user is still typing the command token (not its argument).
    static func shouldOfferCommandSuggestions(for raw: String) -> Bool {
        guard isCommandDraft(raw), let withoutSlash = commandBody(from: raw) else { return false }
        guard !withoutSlash.contains(where: { $0.isWhitespace }) else { return false }
        return true
    }

    /// Prefix-filtered slash commands for autocomplete. Empty prefix lists everything.
    static func commandSuggestions(for raw: String) -> [CommandSuggestion] {
        guard shouldOfferCommandSuggestions(for: raw) else { return [] }
        let prefix = (commandNamePrefix(from: raw) ?? "").lowercased()

        var bestByName: [String: CommandSuggestion] = [:]
        for entry in SlashCommand.matchableEntries() {
            guard prefix.isEmpty || entry.name.hasPrefix(prefix) else { continue }
            let suggestion = CommandSuggestion(
                command: entry.command,
                name: entry.name,
                summary: entry.command.summary
            )
            if let existing = bestByName[entry.name] {
                // Prefer the canonical rawValue spelling when both alias and name match.
                if entry.name == entry.command.rawValue, existing.name != entry.command.rawValue {
                    bestByName[entry.name] = suggestion
                }
            } else {
                bestByName[entry.name] = suggestion
            }
        }

        return bestByName.values.sorted { lhs, rhs in
            let lhsExact = !prefix.isEmpty && lhs.name == prefix
            let rhsExact = !prefix.isEmpty && rhs.name == prefix
            if lhsExact != rhsExact { return lhsExact }
            if lhs.name.count != rhs.name.count { return lhs.name.count < rhs.name.count }
            return lhs.name < rhs.name
        }
    }

    /// Replace the typed command token with a chosen suggestion.
    static func applyCommandSuggestion(_ suggestion: CommandSuggestion, to raw: String) -> String {
        suggestion.insertText
    }

    /// Longest shared prefix across suggestions — used for incremental completion.
    static func commonCommandPrefix(in suggestions: [CommandSuggestion]) -> String? {
        guard let first = suggestions.first?.name else { return nil }
        var common = first
        for suggestion in suggestions.dropFirst() {
            common = String(common.commonPrefix(with: suggestion.name))
            if common.isEmpty { return nil }
        }
        return common
    }

    /// Extend the draft to the shared prefix of all current matches.
    static func applyCommonCommandPrefix(from raw: String) -> String? {
        let suggestions = commandSuggestions(for: raw)
        guard suggestions.count > 1,
              let prefix = commonCommandPrefix(in: suggestions),
              let typed = commandNamePrefix(from: raw),
              prefix.count > typed.count
        else { return nil }
        let cmd = suggestions.first { $0.name == prefix }?.command
            ?? suggestions.first!.command
        let suggestion = CommandSuggestion(command: cmd, name: prefix, summary: cmd.summary)
        return applyCommandSuggestion(suggestion, to: raw)
    }

    /// Hint shown in the placeholder while composing a slash command.
    static func commandPlaceholder(for raw: String) -> String {
        guard isCommandDraft(raw) else { return "" }

        switch parse(raw) {
        case .command(let command, let argument):
            if command.takesArgument, argument.isEmpty {
                switch command {
                case .tag: return "/tag project-name"
                case .find: return "/find search text"
                case .project: return "/project name"
                case .remind: return "/remind tomorrow 9am, or every weekday 9am"
                case .analyze: return "/analyze 15"
                default: return "/\(command.rawValue) …"
                }
            }
            return command.summary
        case .unknownCommand(let name):
            if name.isEmpty { return "help, tag, done, delete…" }
            return "Unknown /\(name) — try /help"
        case .empty:
            return "Command…"
        case .note:
            return "Command…"
        }
    }

}

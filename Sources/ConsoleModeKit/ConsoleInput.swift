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
    ]

    static func named(_ raw: String) -> SlashCommand? {
        let key = raw.lowercased()
        return SlashCommand(rawValue: key) ?? aliases[key]
    }

    var takesArgument: Bool { self == .tag }

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
        }
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
}

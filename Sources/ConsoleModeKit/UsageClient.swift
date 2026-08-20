import Foundation

enum UsageClientError: LocalizedError, Equatable {
    case ompNotFound
    case launchFailed(String)
    case timedOut
    case exitFailure(code: Int32, message: String)
    case undecodable(String)

    var errorDescription: String? {
        switch self {
        case .ompNotFound:
            return "Could not find the omp CLI. Set its path in Settings."
        case .launchFailed(let detail):
            return "Could not run omp: \(detail)"
        case .timedOut:
            return "omp usage timed out."
        case .exitFailure(let code, let message):
            let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "omp usage failed (exit \(code))." : trimmed
        case .undecodable(let detail):
            return "Could not read omp usage output: \(detail)"
        }
    }
}

/// Runs `omp usage --json` and decodes it. Deliberately a plain value type: it owns
/// no state, so the monitor decides entirely when a fetch happens.
struct UsageClient: Sendable {
    var executableOverride: String?
    var timeout: TimeInterval = 30

    /// A GUI app launched from Finder does not inherit the shell `PATH`, so the
    /// usual `command -v` lookup fails. Probe known install roots first because
    /// that avoids paying for a login shell on every poll.
    static let probePaths: [String] = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return [
            "\(home)/.bun/bin/omp",
            "\(home)/.local/bin/omp",
            "\(home)/.volta/bin/omp",
            "/opt/homebrew/bin/omp",
            "/usr/local/bin/omp",
        ]
    }()

    func resolveExecutable() -> String? {
        if let executableOverride, !executableOverride.isEmpty {
            return FileManager.default.isExecutableFile(atPath: executableOverride) ? executableOverride : nil
        }
        if let hit = Self.probePaths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            return hit
        }
        return Self.lookupViaLoginShell()
    }

    /// Last resort: ask the user's own shell, which knows about version managers
    /// and custom PATH entries this app cannot guess.
    private static func lookupViaLoginShell() -> String? {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = ["-lc", "command -v omp"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let path = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty, FileManager.default.isExecutableFile(atPath: path) else { return nil }
        return path
    }

    func fetch() async throws -> UsageSnapshot {
        guard let executable = resolveExecutable() else { throw UsageClientError.ompNotFound }
        let data = try await run(executable: executable, arguments: ["usage", "--json"])
        return try Self.decode(data)
    }

    static func decode(_ data: Data) throws -> UsageSnapshot {
        do {
            return try JSONDecoder().decode(UsageSnapshot.self, from: data)
        } catch {
            throw UsageClientError.undecodable(error.localizedDescription)
        }
    }

    private func run(executable: String, arguments: [String]) async throws -> Data {
        let timeout = self.timeout
        return try await withCheckedThrowingContinuation { continuation in
            // Off the main actor: a cold `omp usage` has been measured at ~5s.
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = arguments
                // Non-interactive, so omp does not try to draw a TUI or prompt.
                var environment = ProcessInfo.processInfo.environment
                environment["NO_COLOR"] = "1"
                environment["TERM"] = "dumb"
                process.environment = environment

                let out = Pipe()
                let err = Pipe()
                process.standardOutput = out
                process.standardError = err

                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: UsageClientError.launchFailed(error.localizedDescription))
                    return
                }

                // Drain concurrently: a full pipe buffer would deadlock waitUntilExit.
                var outData = Data()
                var errData = Data()
                let group = DispatchGroup()
                group.enter()
                DispatchQueue.global(qos: .utility).async {
                    outData = out.fileHandleForReading.readDataToEndOfFile()
                    group.leave()
                }
                group.enter()
                DispatchQueue.global(qos: .utility).async {
                    errData = err.fileHandleForReading.readDataToEndOfFile()
                    group.leave()
                }

                let deadline = DispatchTime.now() + timeout
                let watchdog = DispatchWorkItem {
                    if process.isRunning { process.terminate() }
                }
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: deadline, execute: watchdog)

                process.waitUntilExit()
                watchdog.cancel()
                group.wait()

                guard process.terminationStatus == 0 else {
                    if process.terminationReason == .uncaughtSignal {
                        continuation.resume(throwing: UsageClientError.timedOut)
                    } else {
                        let message = String(decoding: errData, as: UTF8.self)
                        continuation.resume(
                            throwing: UsageClientError.exitFailure(code: process.terminationStatus, message: message)
                        )
                    }
                    return
                }
                continuation.resume(returning: outData)
            }
        }
    }
}

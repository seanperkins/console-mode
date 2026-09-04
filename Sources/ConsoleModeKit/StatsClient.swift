import Foundation

enum StatsClientError: LocalizedError, Equatable {
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
            return "omp stats timed out."
        case .exitFailure(let code, let message):
            let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "omp stats failed (exit \(code))." : trimmed
        case .undecodable(let detail):
            return "Could not read omp stats output: \(detail)"
        }
    }
}

/// Runs `omp stats --json` and decodes it. Mirrors `UsageClient` rather than
/// sharing code with it: each client that shells out to `omp` owns its own
/// executable resolution and process plumbing (see also
/// `ActionReviewClient`), because their error messages and cadences differ.
struct StatsClient: Sendable {
    var executableOverride: String?
    /// `omp stats` syncs the full session-log history on a cold run, which is
    /// measurably slower than `omp usage`'s broker round trip.
    var timeout: TimeInterval = 60

    static let probePaths: [String] = UsageClient.probePaths

    func resolveExecutable() -> String? {
        if let executableOverride, !executableOverride.isEmpty {
            return FileManager.default.isExecutableFile(atPath: executableOverride) ? executableOverride : nil
        }
        if let hit = Self.probePaths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            return hit
        }
        return Self.lookupViaLoginShell()
    }

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

    func fetch() async throws -> StatsSnapshot {
        guard let executable = resolveExecutable() else { throw StatsClientError.ompNotFound }
        let data = try await run(executable: executable, arguments: ["stats", "--json"])
        return try Self.decode(data)
    }

    /// `omp stats --json` writes a `"Synced N entries..."` progress line to
    /// stdout before the JSON payload, so decoding starts at the first `{`
    /// rather than assuming the whole stream is JSON.
    static func decode(_ data: Data) throws -> StatsSnapshot {
        guard let start = data.firstIndex(of: UInt8(ascii: "{")) else {
            throw StatsClientError.undecodable("no JSON object in output")
        }
        do {
            return try JSONDecoder().decode(StatsSnapshot.self, from: data[start...])
        } catch {
            throw StatsClientError.undecodable(error.localizedDescription)
        }
    }

    private func run(executable: String, arguments: [String]) async throws -> Data {
        let timeout = self.timeout
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = arguments
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
                    continuation.resume(throwing: StatsClientError.launchFailed(error.localizedDescription))
                    return
                }

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
                        continuation.resume(throwing: StatsClientError.timedOut)
                    } else {
                        let message = String(decoding: errData, as: UTF8.self)
                        continuation.resume(
                            throwing: StatsClientError.exitFailure(code: process.terminationStatus, message: message)
                        )
                    }
                    return
                }
                continuation.resume(returning: outData)
            }
        }
    }
}

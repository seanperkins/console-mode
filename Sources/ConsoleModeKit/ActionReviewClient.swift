import Foundation

enum ActionReviewClientError: LocalizedError, Equatable {
    case ompNotFound
    case launchFailed(String)
    case timedOut
    case exitFailure(code: Int32, message: String)
    case reviewer(ActionReviewerError)

    var errorDescription: String? {
        switch self {
        case .ompNotFound:
            return "Could not find the omp CLI. Set its path in Settings."
        case .launchFailed(let detail):
            return "Could not run omp: \(detail)"
        case .timedOut:
            return "Action review timed out."
        case .exitFailure(let code, let message):
            let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "omp failed (exit \(code))." : trimmed
        case .reviewer(let error):
            return error.errorDescription
        }
    }
}

/// Runs `omp -p` with a structured prompt and parses the JSON verdict batch.
struct ActionReviewClient: Sendable {
    var config: ActionReviewConfig

    init(config: ActionReviewConfig) {
        self.config = config
    }

    func review(notes: [Note]) async throws -> ActionReviewBatch {
        guard !notes.isEmpty else { return ActionReviewBatch(reviews: []) }

        let ompPath = ActionReviewSettings.resolvedOmpPath(from: config)
        let usageClient = UsageClient(executableOverride: ompPath, timeout: config.timeout)
        guard let executable = usageClient.resolveExecutable() else {
            throw ActionReviewClientError.ompNotFound
        }

        let prompt = ActionReviewer.userPrompt(for: notes)
        let arguments = [
            "-p",
            "--no-tools",
            "--no-session",
            "--mode=text",
            "--model=\(config.model)",
            "--system-prompt=\(ActionReviewer.systemPrompt)",
            prompt,
        ]

        let data = try await run(executable: executable, arguments: arguments, timeout: config.timeout)
        let text = String(decoding: data, as: UTF8.self)
        do {
            return try ActionReviewer.parseResponse(text)
        } catch let error as ActionReviewerError {
            throw ActionReviewClientError.reviewer(error)
        }
    }

    private func run(executable: String, arguments: [String], timeout: TimeInterval) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
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
                    continuation.resume(throwing: ActionReviewClientError.launchFailed(error.localizedDescription))
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
                        continuation.resume(throwing: ActionReviewClientError.timedOut)
                    } else {
                        let message = String(decoding: errData, as: UTF8.self)
                        continuation.resume(
                            throwing: ActionReviewClientError.exitFailure(
                                code: process.terminationStatus,
                                message: message
                            )
                        )
                    }
                    return
                }
                continuation.resume(returning: outData)
            }
        }
    }
}

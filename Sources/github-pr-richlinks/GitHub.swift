import Foundation

enum GitHubError: Error, CustomStringConvertible {
    case ghNotFound
    case commandFailed(status: Int32, stderr: String)
    case timedOut
    case emptyTitle

    var description: String {
        switch self {
        case .ghNotFound: return "GitHub CLI (`gh`) not found on PATH, /opt/homebrew/bin or /usr/local/bin"
        case .commandFailed(let status, let stderr):
            let detail = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return "gh exited with status \(status)\(detail.isEmpty ? "" : ": \(detail)")"
        case .timedOut: return "gh timed out"
        case .emptyTitle: return "gh returned an empty title"
        }
    }
}

enum GitHub {
    static let timeout: TimeInterval = 30
    private static let extraPaths = ["/opt/homebrew/bin", "/usr/local/bin"]

    /// Locates `gh`: on PATH first, then the usual Homebrew locations.
    static func locateGH() -> URL? {
        let env = ProcessInfo.processInfo.environment
        let path = env["PATH"] ?? ""
        let dirs = path.split(separator: ":").map(String.init) + extraPaths
        for dir in dirs {
            let candidate = URL(fileURLWithPath: dir).appendingPathComponent("gh")
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }

    /// Fetches title and diff stats for a PR via `gh pr view --json`.
    static func fetch(_ link: PRLink) throws -> PRInfo {
        guard let gh = locateGH() else { throw GitHubError.ghNotFound }

        let process = Process()
        process.executableURL = gh
        process.arguments = ["pr", "view", link.canonicalURL, "--json", "title,additions,deletions"]

        var env = ProcessInfo.processInfo.environment
        env["PATH"] = ([env["PATH"] ?? ""] + extraPaths).filter { !$0.isEmpty }.joined(separator: ":")
        env["GH_PROMPT_DISABLED"] = "1"
        env["GH_NO_UPDATE_NOTIFIER"] = "1"
        env["NO_COLOR"] = "1"
        process.environment = env

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        process.standardInput = FileHandle.nullDevice

        try process.run()

        let watchdog = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)

        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errData = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let timedOut = watchdog.isCancelled == false && process.terminationReason == .uncaughtSignal
        watchdog.cancel()

        if timedOut { throw GitHubError.timedOut }
        guard process.terminationStatus == 0 else {
            throw GitHubError.commandFailed(
                status: process.terminationStatus,
                stderr: String(data: errData, encoding: .utf8) ?? ""
            )
        }

        let info = try JSONDecoder().decode(PRInfo.self, from: outData)
        guard !info.title.isEmpty else { throw GitHubError.emptyTitle }
        return info
    }
}

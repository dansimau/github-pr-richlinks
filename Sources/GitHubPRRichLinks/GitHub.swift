import Foundation

public enum GitHubError: Error, Equatable, CustomStringConvertible {
    case ghNotFound
    case commandFailed(status: Int32, stderr: String)
    case timedOut
    case emptyTitle

    public var description: String {
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

public enum GitHub {
    public static let defaultTimeout: TimeInterval = 30
    public static let extraPaths = ["/opt/homebrew/bin", "/usr/local/bin"]

    /// Locates `gh` in the given search path, then the usual Homebrew locations.
    public static func locateGH(
        searchPath: String = ProcessInfo.processInfo.environment["PATH"] ?? "",
        fallbacks: [String] = extraPaths
    ) -> URL? {
        let dirs = searchPath.split(separator: ":").map(String.init) + fallbacks
        for dir in dirs {
            let candidate = URL(fileURLWithPath: dir).appendingPathComponent("gh")
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }

    /// Fetches title and diff stats for a PR via `gh pr view --json`.
    ///
    /// - Parameters:
    ///   - link: The PR to look up. Only its canonical URL is passed to `gh`.
    ///   - executable: Path to `gh`; located automatically when nil.
    ///   - timeout: How long to wait before terminating `gh`.
    public static func fetch(
        _ link: PRLink,
        executable: URL? = nil,
        timeout: TimeInterval = defaultTimeout
    ) throws -> PRInfo {
        guard let gh = executable ?? locateGH() else { throw GitHubError.ghNotFound }

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

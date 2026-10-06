import Foundation
import Testing
@testable import GitHubPRRichLinks

/// A temp directory holding a fake `gh` shell script.
struct FakeGH {
    let dir: URL
    let executable: URL
    let argsFile: URL

    /// `body` is the script after the shebang; it may read `$@` and must handle stdout itself.
    /// Invoked arguments are recorded to `argsFile`, one per line.
    init(body: String) throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("fake-gh-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        executable = dir.appendingPathComponent("gh")
        argsFile = dir.appendingPathComponent("args")
        let script = """
        #!/bin/sh
        printf '%s\\n' "$@" > "\(argsFile.path)"
        \(body)
        """
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
    }

    var recordedArgs: [String] {
        (try? String(contentsOf: argsFile, encoding: .utf8))?
            .split(separator: "\n", omittingEmptySubsequences: false)
            .dropLast()
            .map(String.init) ?? []
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: dir)
    }
}

@Suite("GitHub.fetch")
struct GitHubFetchTests {
    let link = PRLink(originalURL: "https://github.com/a/b/pull/9/files#x", owner: "a", repo: "b", number: 9)

    @Test func parsesJSONAndPassesCanonicalURL() throws {
        let gh = try FakeGH(body: #"printf '{"title":"Hello & <world>","additions":12,"deletions":3}'"#)
        defer { gh.cleanup() }

        let info = try GitHub.fetch(link, executable: gh.executable)

        #expect(info == PRInfo(title: "Hello & <world>", additions: 12, deletions: 3))
        #expect(gh.recordedArgs == ["pr", "view", "https://github.com/a/b/pull/9", "--json", "title,additions,deletions"])
    }

    @Test func nonZeroExitSurfacesStderr() throws {
        let gh = try FakeGH(body: "echo 'GraphQL: Could not resolve to a PullRequest' >&2; exit 1")
        defer { gh.cleanup() }

        #expect(throws: GitHubError.commandFailed(status: 1, stderr: "GraphQL: Could not resolve to a PullRequest\n")) {
            try GitHub.fetch(link, executable: gh.executable)
        }
    }

    @Test func emptyTitleIsAnError() throws {
        let gh = try FakeGH(body: #"printf '{"title":"","additions":0,"deletions":0}'"#)
        defer { gh.cleanup() }

        #expect(throws: GitHubError.emptyTitle) {
            try GitHub.fetch(link, executable: gh.executable)
        }
    }

    @Test func malformedJSONThrowsDecodingError() throws {
        let gh = try FakeGH(body: "printf 'not json'")
        defer { gh.cleanup() }

        #expect(throws: DecodingError.self) {
            try GitHub.fetch(link, executable: gh.executable)
        }
    }

    @Test func hungProcessIsTerminatedAfterTimeout() throws {
        let gh = try FakeGH(body: "exec sleep 30")
        defer { gh.cleanup() }

        let start = Date()
        #expect(throws: GitHubError.timedOut) {
            try GitHub.fetch(link, executable: gh.executable, timeout: 0.3)
        }
        #expect(Date().timeIntervalSince(start) < 5)
    }

    @Test func missingExecutableThrowsGHNotFound() throws {
        // Point at an empty directory with no fallbacks so the real gh isn't found.
        let empty = FileManager.default.temporaryDirectory.appendingPathComponent("empty-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: empty) }

        #expect(GitHub.locateGH(searchPath: empty.path, fallbacks: []) == nil)
    }

    @Test func locateGHSearchesPathThenFallbacks() throws {
        let gh = try FakeGH(body: "exit 0")
        defer { gh.cleanup() }
        let empty = FileManager.default.temporaryDirectory.appendingPathComponent("empty-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: empty) }

        #expect(GitHub.locateGH(searchPath: "\(empty.path):\(gh.dir.path)", fallbacks: []) == gh.executable)
        #expect(GitHub.locateGH(searchPath: empty.path, fallbacks: [gh.dir.path]) == gh.executable)
        #expect(GitHub.locateGH(searchPath: "", fallbacks: [gh.dir.path]) == gh.executable)
    }
}

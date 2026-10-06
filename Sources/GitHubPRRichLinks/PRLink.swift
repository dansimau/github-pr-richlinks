import Foundation

/// A GitHub pull request URL as found on the clipboard.
public struct PRLink: Equatable, Sendable {
    /// The URL exactly as copied (whitespace trimmed), e.g. including `/files` or a `#discussion_r…` anchor.
    public let originalURL: String
    public let owner: String
    public let repo: String
    public let number: Int

    public init(originalURL: String, owner: String, repo: String, number: Int) {
        self.originalURL = originalURL
        self.owner = owner
        self.repo = repo
        self.number = number
    }

    /// The bare `https://github.com/owner/repo/pull/N` form, suitable for passing to `gh`.
    public var canonicalURL: String {
        "https://github.com/\(owner)/\(repo)/pull/\(number)"
    }

    private static let pattern = #/^https://github\.com/([^/\s]+)/([^/\s]+)/pull/(\d+)(?:[/?#]\S*)?$/#

    /// Parses clipboard text into a `PRLink`, or returns nil if it isn't a GitHub PR URL.
    public static func parse(_ text: String) -> PRLink? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let match = trimmed.wholeMatch(of: pattern),
              let number = Int(match.3) else { return nil }
        return PRLink(originalURL: trimmed, owner: String(match.1), repo: String(match.2), number: number)
    }
}

/// Details fetched from GitHub for a pull request.
public struct PRInfo: Decodable, Equatable, Sendable {
    public let title: String
    public let additions: Int
    public let deletions: Int

    public init(title: String, additions: Int, deletions: Int) {
        self.title = title
        self.additions = additions
        self.deletions = deletions
    }
}

public enum RichLink {
    /// The link text as it will appear in rich-text contexts: `Title [+A -D]`.
    public static func label(for info: PRInfo) -> String {
        "\(info.title) [+\(info.additions) -\(info.deletions)]"
    }

    /// HTML fragment placed on the pasteboard as `public.html`.
    public static func html(for link: PRLink, info: PRInfo) -> String {
        ":pull-request: <a href=\"\(escape(link.originalURL))\">\(escape(label(for: info)))</a>"
    }

    public static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
         .replacingOccurrences(of: "\"", with: "&quot;")
    }
}

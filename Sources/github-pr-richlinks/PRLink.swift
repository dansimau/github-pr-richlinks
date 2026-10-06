import Foundation

/// A GitHub pull request URL as found on the clipboard.
struct PRLink: Equatable {
    /// The URL exactly as copied (whitespace trimmed), e.g. including `/files` or a `#discussion_r…` anchor.
    let originalURL: String
    let owner: String
    let repo: String
    let number: Int

    /// The bare `https://github.com/owner/repo/pull/N` form, suitable for passing to `gh`.
    var canonicalURL: String {
        "https://github.com/\(owner)/\(repo)/pull/\(number)"
    }

    private static let pattern = #/^https://github\.com/([^/\s]+)/([^/\s]+)/pull/(\d+)(?:[/?#]\S*)?$/#

    /// Parses clipboard text into a `PRLink`, or returns nil if it isn't a GitHub PR URL.
    static func parse(_ text: String) -> PRLink? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let match = trimmed.wholeMatch(of: pattern),
              let number = Int(match.3) else { return nil }
        return PRLink(originalURL: trimmed, owner: String(match.1), repo: String(match.2), number: number)
    }
}

/// Details fetched from GitHub for a pull request.
struct PRInfo: Decodable {
    let title: String
    let additions: Int
    let deletions: Int
}

enum RichLink {
    /// The link text as it will appear in rich-text contexts: `Title [+A -D]`.
    static func label(for info: PRInfo) -> String {
        "\(info.title) [+\(info.additions) -\(info.deletions)]"
    }

    /// HTML fragment placed on the pasteboard as `public.html`.
    static func html(for link: PRLink, info: PRInfo) -> String {
        ":pull-request: <a href=\"\(escape(link.originalURL))\">\(escape(label(for: info)))</a>"
    }

    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
         .replacingOccurrences(of: "\"", with: "&quot;")
    }
}

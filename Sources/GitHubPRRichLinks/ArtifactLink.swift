import AppKit
import Foundation
import ScriptingBridge

/// A Claude artifact URL as found on the clipboard.
public struct ArtifactLink: Equatable, Sendable {
    /// The URL exactly as copied (whitespace trimmed), including any `?sk=…` share key.
    public let originalURL: String
    /// The path segment after `/artifact/`, e.g. `T1LYkmCE7aXds8iHA4Lw8d`.
    public let id: String

    public init(originalURL: String, id: String) {
        self.originalURL = originalURL
        self.id = id
    }

    private static let pattern = #/^https://claude\.ai/(?:code/)?artifact/([\w-]+)(?:[/?#]\S*)?$/#

    /// Parses clipboard text into an `ArtifactLink`, or returns nil if it isn't a Claude artifact URL.
    public static func parse(_ text: String) -> ArtifactLink? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let match = trimmed.wholeMatch(of: pattern) else { return nil }
        return ArtifactLink(originalURL: trimmed, id: String(match.1))
    }

    /// Whether a browser tab at `tabURL` is showing this artifact.
    public func matches(tabURL: String) -> Bool {
        guard let other = ArtifactLink.parse(tabURL) else { return false }
        // claude.ai may prefix the id with a readable slug (`my-title-<id>`).
        return other.id == id || other.id.hasSuffix("-" + id) || id.hasSuffix("-" + other.id)
    }
}

public enum ArtifactError: Error, Equatable, CustomStringConvertible {
    case chromeFailed(String)
    case tabNotFound
    case titleNotLoaded

    public var description: String {
        switch self {
        case .chromeFailed(let detail): return "could not read Google Chrome's tabs: \(detail)"
        case .tabNotFound: return "artifact is not open in a Google Chrome tab, so its title is unknown"
        case .titleNotLoaded: return "the artifact's Chrome tab has not loaded its title yet"
        }
    }
}

@objc private protocol ChromeApplication {
    @objc optional func windows() -> SBElementArray
}

@objc private protocol ChromeWindow {
    @objc optional func tabs() -> SBElementArray
}

extension SBApplication: ChromeApplication {}
extension SBObject: ChromeWindow {}

private final class EventFailureRecorder: NSObject, SBApplicationDelegate {
    var failure: String?

    func eventDidFail(_ event: UnsafePointer<AppleEvent>, withError error: Error) -> Any? {
        let nsError = error as NSError
        failure = nsError.code == -1743
            ? "not allowed to control Google Chrome; enable it under System Settings > Privacy & Security > Automation"
            : "\(nsError.localizedDescription) (\(nsError.code))"
        return nil
    }
}

/// Looks up artifact titles from open Google Chrome tabs.
///
/// claude.ai does not expose artifact titles to non-browser clients, so the title is
/// taken from the tab the URL was (most likely) copied from.
public enum ChromeTabs {
    public struct Tab: Equatable, Sendable {
        public let url: String
        public let title: String

        public init(url: String, title: String) {
            self.url = url
            self.title = title
        }
    }

    public static let bundleIdentifier = "com.google.Chrome"
    public static let defaultTimeout: TimeInterval = 10

    /// Returns the title of the Chrome tab showing `link`.
    public static func title(for link: ArtifactLink, timeout: TimeInterval = defaultTimeout) throws -> String {
        let (tabs, failure) = openTabs(timeout: timeout)
        do {
            return try title(for: link, in: tabs)
        } catch ArtifactError.tabNotFound {
            if let failure { throw ArtifactError.chromeFailed(failure) }
            throw ArtifactError.tabNotFound
        }
    }

    /// Lists the tabs of every running Chrome instance, without launching Chrome.
    ///
    /// Each instance is addressed by pid: with several running (e.g. a browser-automation
    /// profile next to the everyday one) a by-name Apple event reaches only one of them.
    static func openTabs(timeout: TimeInterval) -> (tabs: [Tab], failure: String?) {
        var tabs: [Tab] = []
        var failure: String?
        for running in NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier) {
            guard let app = SBApplication(processIdentifier: running.processIdentifier) else { continue }
            let recorder = EventFailureRecorder()
            app.delegate = recorder
            app.timeout = Int(timeout * 60)  // ticks

            for case let window as SBObject in (app as ChromeApplication).windows?() ?? [] {
                guard let windowTabs = (window as ChromeWindow).tabs?() else { continue }
                // One Apple event per property per window, rather than per tab.
                let urls = windowTabs.array(byApplying: NSSelectorFromString("URL")) as? [String] ?? []
                let titles = windowTabs.array(byApplying: NSSelectorFromString("title")) as? [String] ?? []
                // A tab opened or closed between the two events would misalign them.
                guard urls.count == titles.count else { continue }
                tabs += zip(urls, titles).map(Tab.init)
            }
            failure = recorder.failure ?? failure
        }
        return (tabs, failure)
    }

    public static func title(for link: ArtifactLink, in tabs: [Tab]) throws -> String {
        let matching = tabs.filter { link.matches(tabURL: $0.url) }
        guard !matching.isEmpty else { throw ArtifactError.tabNotFound }
        guard let title = matching.lazy.compactMap({ clean($0.title) }).first else {
            throw ArtifactError.titleNotLoaded
        }
        return title
    }

    private static let siteSuffix = #/\s+[-–—|]\s+Claude$/#
    private static let placeholders: Set<String> = ["", "Claude", "Claude Artifact", "claude.ai"]

    /// Strips the ` - Claude` site suffix; returns nil for the placeholder shown while loading.
    public static func clean(_ tabTitle: String) -> String? {
        let title = tabTitle
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacing(siteSuffix, with: "")
        return placeholders.contains(title) || title.hasPrefix("https://") ? nil : title
    }
}

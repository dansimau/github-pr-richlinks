import AppKit
import Foundation

/// Polls a pasteboard and rewrites GitHub PR and Claude artifact URLs as rich links.
@MainActor
public final class ClipboardWatcher {
    public typealias Fetcher = @Sendable (PRLink) throws -> PRInfo
    public typealias ArtifactTitleFetcher = @Sendable (ArtifactLink) throws -> String

    /// What ends up on the pasteboard for a recognised URL.
    private struct Rendered: Sendable {
        let html: String
        let label: String
    }

    private let pasteboard: NSPasteboard
    private let interval: TimeInterval
    private let fetch: Fetcher
    private let fetchArtifactTitle: ArtifactTitleFetcher
    private var lastChangeCount: Int
    private var timer: Timer?

    public init(
        pasteboard: NSPasteboard = .general,
        interval: TimeInterval = 0.5,
        fetch: @escaping Fetcher = { link in try GitHub.fetch(link) },
        fetchArtifactTitle: @escaping ArtifactTitleFetcher = { link in try ChromeTabs.title(for: link) }
    ) {
        self.pasteboard = pasteboard
        self.interval = interval
        self.fetch = fetch
        self.fetchArtifactTitle = fetchArtifactTitle
        self.lastChangeCount = pasteboard.changeCount
    }

    public func start() {
        Log.info("watching clipboard every \(Int(interval * 1000))ms")
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { _ = self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Checks the pasteboard once. If a new PR or artifact URL is present, returns the task
    /// that fetches its details and rewrites the pasteboard; otherwise returns nil.
    @discardableResult
    public func tick() -> Task<Void, Never>? {
        let changeCount = pasteboard.changeCount
        guard changeCount != lastChangeCount else { return nil }
        lastChangeCount = changeCount

        guard let text = pasteboard.string(forType: .string) else {
            Log.debug("clipboard changed (#\(changeCount)) but has no plain text")
            return nil
        }

        let url: String
        let render: @Sendable () throws -> Rendered
        if let link = PRLink.parse(text) {
            Log.info("PR URL copied: \(link.originalURL)")
            let fetch = self.fetch
            url = link.originalURL
            render = {
                let info = try fetch(link)
                return Rendered(html: RichLink.html(for: link, info: info), label: RichLink.label(for: info))
            }
        } else if let link = ArtifactLink.parse(text) {
            Log.info("artifact URL copied: \(link.originalURL)")
            let fetchTitle = self.fetchArtifactTitle
            url = link.originalURL
            render = {
                let title = try fetchTitle(link)
                return Rendered(html: RichLink.html(for: link, title: title), label: title)
            }
        } else {
            Log.debug("clipboard changed (#\(changeCount)), not a PR or artifact URL")
            return nil
        }

        return Task.detached(priority: .userInitiated) {
            do {
                let rendered = try render()
                await MainActor.run { self.write(url: url, rendered: rendered, expectedChangeCount: changeCount) }
            } catch {
                Log.error("\(url): \(error)")
            }
        }
    }

    private func write(url: String, rendered: Rendered, expectedChangeCount: Int) {
        guard pasteboard.changeCount == expectedChangeCount else {
            Log.info("clipboard changed while fetching \(url); leaving it alone")
            return
        }

        let item = NSPasteboardItem()
        item.setString(rendered.html, forType: .html)
        item.setString(url, forType: .string)

        pasteboard.clearContents()
        pasteboard.writeObjects([item])
        // Our own write bumps the change count; remember it so we don't process it again.
        lastChangeCount = pasteboard.changeCount

        Log.info("rewrote clipboard: \(rendered.label)")
    }
}

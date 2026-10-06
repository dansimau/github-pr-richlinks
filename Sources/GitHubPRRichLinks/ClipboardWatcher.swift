import AppKit
import Foundation

/// Polls a pasteboard and rewrites GitHub PR URLs as rich links.
@MainActor
public final class ClipboardWatcher {
    public typealias Fetcher = @Sendable (PRLink) throws -> PRInfo

    private let pasteboard: NSPasteboard
    private let interval: TimeInterval
    private let fetch: Fetcher
    private var lastChangeCount: Int
    private var timer: Timer?

    public init(
        pasteboard: NSPasteboard = .general,
        interval: TimeInterval = 0.5,
        fetch: @escaping Fetcher = { link in try GitHub.fetch(link) }
    ) {
        self.pasteboard = pasteboard
        self.interval = interval
        self.fetch = fetch
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

    /// Checks the pasteboard once. If a new PR URL is present, returns the task that
    /// fetches its details and rewrites the pasteboard; otherwise returns nil.
    @discardableResult
    public func tick() -> Task<Void, Never>? {
        let changeCount = pasteboard.changeCount
        guard changeCount != lastChangeCount else { return nil }
        lastChangeCount = changeCount

        guard let text = pasteboard.string(forType: .string) else {
            Log.debug("clipboard changed (#\(changeCount)) but has no plain text")
            return nil
        }
        guard let link = PRLink.parse(text) else {
            Log.debug("clipboard changed (#\(changeCount)), not a PR URL")
            return nil
        }

        Log.info("PR URL copied: \(link.originalURL)")
        let fetch = self.fetch
        return Task.detached(priority: .userInitiated) {
            do {
                let info = try fetch(link)
                await MainActor.run { self.write(link: link, info: info, expectedChangeCount: changeCount) }
            } catch {
                Log.error("\(link.canonicalURL): \(error)")
            }
        }
    }

    private func write(link: PRLink, info: PRInfo, expectedChangeCount: Int) {
        guard pasteboard.changeCount == expectedChangeCount else {
            Log.info("clipboard changed while fetching \(link.canonicalURL); leaving it alone")
            return
        }

        let html = RichLink.html(for: link, info: info)
        let item = NSPasteboardItem()
        item.setString(html, forType: .html)
        item.setString(link.originalURL, forType: .string)

        pasteboard.clearContents()
        pasteboard.writeObjects([item])
        // Our own write bumps the change count; remember it so we don't process it again.
        lastChangeCount = pasteboard.changeCount

        Log.info("rewrote clipboard: \(RichLink.label(for: info))")
    }
}

import AppKit
import Foundation

/// Polls a pasteboard and rewrites GitHub PR URLs as rich links.
///
/// Copying the same PR URL twice in a row leaves the second copy as plain text, so the
/// raw URL can be forced into rich-text destinations. Copying it a third time rewrites
/// it again.
@MainActor
public final class ClipboardWatcher {
    public typealias Fetcher = @Sendable (PRLink) throws -> PRInfo

    private let pasteboard: NSPasteboard
    private let interval: TimeInterval
    private let fetch: Fetcher
    private var lastChangeCount: Int
    /// The link most recently rewritten (or being rewritten), cleared by any other clipboard
    /// change. A fresh copy of this exact URL is treated as a request for the plain-text version.
    private var lastRewrittenLink: PRLink?
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
        // Only a copy immediately following a rewrite counts as "the same link twice".
        let previousLink = lastRewrittenLink
        lastRewrittenLink = nil

        guard let text = pasteboard.string(forType: .string) else {
            Log.debug("clipboard changed (#\(changeCount)) but has no plain text")
            return nil
        }
        guard let link = PRLink.parse(text) else {
            Log.debug("clipboard changed (#\(changeCount)), not a PR URL")
            return nil
        }

        if link == previousLink {
            Log.info("PR URL copied again: \(link.originalURL); leaving it as plain text")
            return nil
        }

        Log.info("PR URL copied: \(link.originalURL)")
        lastRewrittenLink = link
        let fetch = self.fetch
        return Task.detached(priority: .userInitiated) {
            do {
                let info = try fetch(link)
                await MainActor.run { self.write(link: link, info: info, expectedChangeCount: changeCount) }
            } catch {
                Log.error("\(link.canonicalURL): \(error)")
                // Nothing was rewritten, so copying the URL again should retry rather than
                // be read as a request for plain text.
                await MainActor.run { self.forget(link) }
            }
        }
    }

    private func forget(_ link: PRLink) {
        if lastRewrittenLink == link { lastRewrittenLink = nil }
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

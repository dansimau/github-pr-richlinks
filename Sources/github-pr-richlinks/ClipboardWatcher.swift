import AppKit
import Foundation

/// Polls the general pasteboard and rewrites GitHub PR URLs as rich links.
@MainActor
final class ClipboardWatcher {
    private let pasteboard = NSPasteboard.general
    private let interval: TimeInterval
    private var lastChangeCount: Int
    private var timer: Timer?

    init(interval: TimeInterval) {
        self.interval = interval
        self.lastChangeCount = pasteboard.changeCount
    }

    func start() {
        Log.info("watching clipboard every \(Int(interval * 1000))ms")
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        let changeCount = pasteboard.changeCount
        guard changeCount != lastChangeCount else { return }
        lastChangeCount = changeCount

        guard let text = pasteboard.string(forType: .string) else {
            Log.debug("clipboard changed (#\(changeCount)) but has no plain text")
            return
        }
        guard let link = PRLink.parse(text) else {
            Log.debug("clipboard changed (#\(changeCount)), not a PR URL")
            return
        }

        Log.info("PR URL copied: \(link.originalURL)")
        Task.detached(priority: .userInitiated) {
            do {
                let info = try GitHub.fetch(link)
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

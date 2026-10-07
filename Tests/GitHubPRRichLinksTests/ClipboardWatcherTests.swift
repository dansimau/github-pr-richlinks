import AppKit
import Foundation
import Testing
@testable import GitHubPRRichLinks

/// Tests run against a private named pasteboard so the user's clipboard is never touched.
@Suite("ClipboardWatcher", .serialized)
@MainActor
struct ClipboardWatcherTests {
    let pasteboard: NSPasteboard
    let url = "https://github.com/a/b/pull/77/files"
    let info = PRInfo(title: "Make it work", additions: 5, deletions: 2)

    init() {
        pasteboard = NSPasteboard(name: NSPasteboard.Name("github-pr-richlinks-test-\(UUID().uuidString)"))
    }

    func copy(_ text: String) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    func makeWatcher(fetch: @escaping ClipboardWatcher.Fetcher) -> ClipboardWatcher {
        ClipboardWatcher(pasteboard: pasteboard, interval: 0.5, fetch: fetch)
    }

    @Test func ignoresUnchangedPasteboard() {
        copy(url)
        let watcher = makeWatcher { _ in Issue.record("fetch should not be called"); throw GitHubError.emptyTitle }
        // The watcher snapshots the change count at init, so existing content is not processed.
        #expect(watcher.tick() == nil)
        pasteboard.releaseGlobally()
    }

    @Test func ignoresNonPRText() {
        let watcher = makeWatcher { _ in Issue.record("fetch should not be called"); throw GitHubError.emptyTitle }
        copy("just some text")
        #expect(watcher.tick() == nil)
        #expect(pasteboard.string(forType: .string) == "just some text")
        #expect(pasteboard.string(forType: .html) == nil)
        pasteboard.releaseGlobally()
    }

    @Test func ignoresPasteboardWithoutPlainText() {
        let watcher = makeWatcher { _ in Issue.record("fetch should not be called"); throw GitHubError.emptyTitle }
        pasteboard.clearContents()
        pasteboard.setData(Data([0, 1, 2]), forType: .tiff)
        #expect(watcher.tick() == nil)
        pasteboard.releaseGlobally()
    }

    @Test func rewritesPRURLWithHTMLAndPlainText() async throws {
        let watcher = makeWatcher { [info] link in
            #expect(link.canonicalURL == "https://github.com/a/b/pull/77")
            return info
        }
        copy(url)

        let task = try #require(watcher.tick())
        await task.value

        #expect(pasteboard.string(forType: .html)
            == #":pull-request: <a href="https://github.com/a/b/pull/77/files">Make it work [+5 -2]</a>"#)
        #expect(pasteboard.string(forType: .string) == url)

        // Both representations live on one item so apps pick whichever they prefer.
        let items = try #require(pasteboard.pasteboardItems)
        #expect(items.count == 1)
        #expect(items[0].types.contains(.html))
        #expect(items[0].types.contains(.string))
        pasteboard.releaseGlobally()
    }

    @Test func doesNotReprocessItsOwnWrite() async throws {
        var calls = 0
        let watcher = makeWatcher { [info] _ in
            calls += 1
            return info
        }
        copy(url)
        await watcher.tick()?.value
        #expect(calls == 1)

        // The rewrite bumped the change count, but the watcher must treat that as already seen.
        #expect(watcher.tick() == nil)
        #expect(calls == 1)
        #expect(pasteboard.string(forType: .html) != nil)
        pasteboard.releaseGlobally()
    }

    @Test func discardsResultIfPasteboardChangedDuringFetch() async throws {
        let gate = DispatchSemaphore(value: 0)
        let watcher = makeWatcher { [info] _ in
            gate.wait()
            return info
        }
        copy(url)
        let task = try #require(watcher.tick())

        // User copies something else while gh is still running.
        copy("something newer")
        gate.signal()
        await task.value

        #expect(pasteboard.string(forType: .string) == "something newer")
        #expect(pasteboard.string(forType: .html) == nil)
        pasteboard.releaseGlobally()
    }

    @Test func leavesPasteboardAloneWhenFetchFails() async throws {
        let watcher = makeWatcher { _ in throw GitHubError.commandFailed(status: 1, stderr: "nope") }
        copy(url)
        await watcher.tick()?.value

        #expect(pasteboard.string(forType: .string) == url)
        #expect(pasteboard.string(forType: .html) == nil)
        pasteboard.releaseGlobally()
    }

    @Test func processesSubsequentCopies() async throws {
        var seen: [Int] = []
        let watcher = makeWatcher { link in
            seen.append(link.number)
            return PRInfo(title: "PR \(link.number)", additions: link.number, deletions: 0)
        }

        copy("https://github.com/a/b/pull/1")
        await watcher.tick()?.value
        copy("not a pr")
        #expect(watcher.tick() == nil)
        copy("https://github.com/a/b/pull/2")
        await watcher.tick()?.value

        #expect(seen == [1, 2])
        #expect(pasteboard.string(forType: .html)?.contains("PR 2 [+2 -0]") == true)
        #expect(pasteboard.string(forType: .string) == "https://github.com/a/b/pull/2")
        pasteboard.releaseGlobally()
    }

    @Test func copyingSameLinkTwiceLeavesPlainText() async throws {
        var calls = 0
        let watcher = makeWatcher { [info] _ in
            calls += 1
            return info
        }
        copy(url)
        await watcher.tick()?.value
        #expect(pasteboard.string(forType: .html) != nil)

        // Copying the same URL again is a request for the raw URL.
        copy(url)
        #expect(watcher.tick() == nil)
        #expect(calls == 1)
        #expect(pasteboard.string(forType: .string) == url)
        #expect(pasteboard.string(forType: .html) == nil)
        pasteboard.releaseGlobally()
    }

    @Test func copyingSameLinkThirdTimeRewritesAgain() async throws {
        var calls = 0
        let watcher = makeWatcher { [info] _ in
            calls += 1
            return info
        }
        copy(url)
        await watcher.tick()?.value
        copy(url)
        #expect(watcher.tick() == nil)

        copy(url)
        await watcher.tick()?.value
        #expect(calls == 2)
        #expect(pasteboard.string(forType: .html) != nil)
        pasteboard.releaseGlobally()
    }

    @Test func doubleCopyDuringFetchLeavesPlainText() async throws {
        let gate = DispatchSemaphore(value: 0)
        var calls = 0
        let watcher = makeWatcher { [info] _ in
            calls += 1
            gate.wait()
            return info
        }
        copy(url)
        let task = try #require(watcher.tick())

        // A quick second Cmd+C lands before gh has returned.
        copy(url)
        #expect(watcher.tick() == nil)
        gate.signal()
        await task.value

        #expect(calls == 1)
        #expect(pasteboard.string(forType: .string) == url)
        #expect(pasteboard.string(forType: .html) == nil)
        pasteboard.releaseGlobally()
    }

    @Test func copyingLinkAfterSomethingElseRewritesAgain() async throws {
        var calls = 0
        let watcher = makeWatcher { [info] _ in
            calls += 1
            return info
        }
        copy(url)
        await watcher.tick()?.value
        copy("unrelated")
        #expect(watcher.tick() == nil)

        // Not "in succession" any more, so the link is rewritten as usual.
        copy(url)
        await watcher.tick()?.value
        #expect(calls == 2)
        #expect(pasteboard.string(forType: .html) != nil)
        pasteboard.releaseGlobally()
    }

    @Test func copyingDifferentFormOfSameLinkRewrites() async throws {
        var calls = 0
        let watcher = makeWatcher { [info] _ in
            calls += 1
            return info
        }
        copy(url)
        await watcher.tick()?.value

        // Same PR, different URL (no /files suffix): treated as a new link.
        copy("https://github.com/a/b/pull/77")
        await watcher.tick()?.value
        #expect(calls == 2)
        #expect(pasteboard.string(forType: .html)?.contains(#"href="https://github.com/a/b/pull/77""#) == true)
        pasteboard.releaseGlobally()
    }

    @Test func recopyingAfterFailedFetchRetries() async throws {
        var calls = 0
        let watcher = makeWatcher { [info] _ in
            calls += 1
            if calls == 1 { throw GitHubError.commandFailed(status: 1, stderr: "nope") }
            return info
        }
        copy(url)
        await watcher.tick()?.value
        #expect(pasteboard.string(forType: .html) == nil)

        // Nothing was rewritten, so the second copy is a retry, not a plain-text request.
        copy(url)
        await watcher.tick()?.value
        #expect(calls == 2)
        #expect(pasteboard.string(forType: .html) != nil)
        pasteboard.releaseGlobally()
    }
}

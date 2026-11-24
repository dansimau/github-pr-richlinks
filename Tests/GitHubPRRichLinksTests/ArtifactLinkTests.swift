import AppKit
import Foundation
import Testing
@testable import GitHubPRRichLinks

@Suite("ArtifactLink")
struct ArtifactLinkTests {
    let url = "https://claude.ai/artifact/T1LYkmCE7aXds8iHA4Lw8d?sk=oT0M_yWo0rurOEQxqc4JuA"

    @Test func parsesArtifactURLs() {
        #expect(ArtifactLink.parse(" \(url)\n") == ArtifactLink(originalURL: url, id: "T1LYkmCE7aXds8iHA4Lw8d"))
        #expect(ArtifactLink.parse("https://claude.ai/artifact/abc")?.id == "abc")
        #expect(ArtifactLink.parse("https://claude.ai/code/artifact/0a1b-2c3d/")?.id == "0a1b-2c3d")
    }

    @Test(arguments: [
        "https://claude.ai/chat/T1LYkmCE7aXds8iHA4Lw8d",
        "https://claude.ai/artifact/",
        "https://example.com/artifact/abc",
        "http://claude.ai/artifact/abc",
        "see https://claude.ai/artifact/abc",
        "https://claude.ai/artifact/abc and more",
    ])
    func rejectsOtherText(text: String) {
        #expect(ArtifactLink.parse(text) == nil)
    }

    @Test func matchesTabsShowingTheSameArtifact() throws {
        let link = try #require(ArtifactLink.parse(url))
        #expect(link.matches(tabURL: "https://claude.ai/artifact/T1LYkmCE7aXds8iHA4Lw8d"))
        #expect(link.matches(tabURL: "https://claude.ai/artifact/T1LYkmCE7aXds8iHA4Lw8d/?org=x#top"))
        #expect(link.matches(tabURL: "https://claude.ai/artifact/ai-tracker-T1LYkmCE7aXds8iHA4Lw8d"))
        #expect(!link.matches(tabURL: "https://claude.ai/artifact/somethingElse"))
        #expect(!link.matches(tabURL: "https://claude.ai/new"))
    }

    @Test func rendersHTML() throws {
        let link = try #require(ArtifactLink.parse(url))
        #expect(RichLink.html(for: link, title: "Q&A <Tracker>")
            == #":claude: <a href="\#(url)">Q&amp;A &lt;Tracker&gt;</a>"#)
    }
}

@Suite("ChromeTabs")
struct ChromeTabsTests {
    let link = ArtifactLink(originalURL: "https://claude.ai/artifact/abc?sk=k", id: "abc")

    @Test func cleansTabTitles() {
        #expect(ChromeTabs.clean("AI Task Force Tracker") == "AI Task Force Tracker")
        #expect(ChromeTabs.clean("AI Task Force Tracker - Claude") == "AI Task Force Tracker")
        #expect(ChromeTabs.clean("AI Task Force Tracker | Claude") == "AI Task Force Tracker")
        #expect(ChromeTabs.clean("Notes - Claude vs GPT") == "Notes - Claude vs GPT")
        #expect(ChromeTabs.clean("Claude Artifact") == nil)
        #expect(ChromeTabs.clean("Claude") == nil)
        #expect(ChromeTabs.clean("") == nil)
    }

    @Test func picksTheMatchingTab() throws {
        let tabs: [ChromeTabs.Tab] = [
            .init(url: "https://claude.ai/artifact/other", title: "Other"),
            .init(url: "https://claude.ai/artifact/abc", title: "Claude Artifact"),
            .init(url: "https://claude.ai/artifact/abc?sk=k", title: "Tracker - Claude"),
        ]
        #expect(try ChromeTabs.title(for: link, in: tabs) == "Tracker")
    }

    @Test func reportsMissingOrUnloadedTabs() {
        #expect(throws: ArtifactError.tabNotFound) {
            try ChromeTabs.title(for: link, in: [.init(url: "https://claude.ai/artifact/other", title: "Other")])
        }
        #expect(throws: ArtifactError.titleNotLoaded) {
            try ChromeTabs.title(for: link, in: [.init(url: "https://claude.ai/artifact/abc", title: "Claude Artifact")])
        }
    }
}

@Suite("ClipboardWatcher artifacts", .serialized)
@MainActor
struct ClipboardWatcherArtifactTests {
    let pasteboard = NSPasteboard(name: NSPasteboard.Name("github-pr-richlinks-test-\(UUID().uuidString)"))
    let url = "https://claude.ai/artifact/T1LYkmCE7aXds8iHA4Lw8d?sk=oT0M_yWo0rurOEQxqc4JuA"

    func copy(_ text: String) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    func makeWatcher(title: @escaping ClipboardWatcher.ArtifactTitleFetcher) -> ClipboardWatcher {
        ClipboardWatcher(
            pasteboard: pasteboard,
            fetch: { _ in Issue.record("PR fetch should not be called"); throw GitHubError.emptyTitle },
            fetchArtifactTitle: title
        )
    }

    @Test func rewritesArtifactURLWithHTMLAndPlainText() async throws {
        let watcher = makeWatcher { link in
            #expect(link.id == "T1LYkmCE7aXds8iHA4Lw8d")
            return "AI Task Force Tracker"
        }
        copy(url)
        await (try #require(watcher.tick())).value

        #expect(pasteboard.string(forType: .html)
            == #":claude: <a href="\#(url)">AI Task Force Tracker</a>"#)
        #expect(pasteboard.string(forType: .string) == url)
        #expect(watcher.tick() == nil)
        pasteboard.releaseGlobally()
    }

    @Test func leavesPasteboardAloneWhenTabIsNotOpen() async throws {
        let watcher = makeWatcher { _ in throw ArtifactError.tabNotFound }
        copy(url)
        await watcher.tick()?.value

        #expect(pasteboard.string(forType: .string) == url)
        #expect(pasteboard.string(forType: .html) == nil)
        pasteboard.releaseGlobally()
    }
}

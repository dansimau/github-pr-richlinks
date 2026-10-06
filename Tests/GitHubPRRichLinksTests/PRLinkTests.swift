import Testing
@testable import GitHubPRRichLinks

@Suite("PRLink.parse")
struct PRLinkParseTests {
    @Test func parsesBasicURL() throws {
        let link = try #require(PRLink.parse("https://github.com/wetravel/app/pull/123"))
        #expect(link.owner == "wetravel")
        #expect(link.repo == "app")
        #expect(link.number == 123)
        #expect(link.originalURL == "https://github.com/wetravel/app/pull/123")
        #expect(link.canonicalURL == "https://github.com/wetravel/app/pull/123")
    }

    @Test func trimsSurroundingWhitespace() throws {
        let link = try #require(PRLink.parse("  \n https://github.com/a/b/pull/7\n\t"))
        #expect(link.originalURL == "https://github.com/a/b/pull/7")
        #expect(link.number == 7)
    }

    @Test(arguments: [
        "https://github.com/a/b/pull/42/files",
        "https://github.com/a/b/pull/42/files#diff-abc123",
        "https://github.com/a/b/pull/42#discussion_r99",
        "https://github.com/a/b/pull/42?diff=split",
        "https://github.com/a/b/pull/42/commits/deadbeef",
    ])
    func preservesSuffixInOriginalButNotCanonical(url: String) throws {
        let link = try #require(PRLink.parse(url))
        #expect(link.originalURL == url)
        #expect(link.canonicalURL == "https://github.com/a/b/pull/42")
        #expect(link.number == 42)
    }

    @Test func allowsDotsAndDashesInOwnerAndRepo() throws {
        let link = try #require(PRLink.parse("https://github.com/my-org.io/some.repo-name/pull/1"))
        #expect(link.owner == "my-org.io")
        #expect(link.repo == "some.repo-name")
    }

    @Test(arguments: [
        "",
        "hello world",
        "https://github.com/a/b/issues/1",
        "https://github.com/a/b/pulls",
        "https://github.com/a/b/pull/",
        "https://github.com/a/b/pull/12abc",
        "https://github.com/a/b/pull/abc",
        "https://github.com/a/pull/1",
        "http://github.com/a/b/pull/1",
        "https://gitlab.com/a/b/pull/1",
        "https://github.com.evil.example/a/b/pull/1",
        "github.com/a/b/pull/1",
        "see https://github.com/a/b/pull/1 please",
        "https://github.com/a/b/pull/1\nhttps://github.com/a/b/pull/2",
        "https://github.com/a/b/pull/1 trailing",
    ])
    func rejectsNonPRText(text: String) {
        #expect(PRLink.parse(text) == nil)
    }
}

@Suite("RichLink")
struct RichLinkTests {
    let link = PRLink(originalURL: "https://github.com/a/b/pull/5", owner: "a", repo: "b", number: 5)

    @Test func labelAppendsDiffStats() {
        let info = PRInfo(title: "Drop the SHA1 row id", additions: 52, deletions: 20)
        #expect(RichLink.label(for: info) == "Drop the SHA1 row id [+52 -20]")
    }

    @Test func htmlWrapsLabelInAnchorWithEmojiPrefix() {
        let info = PRInfo(title: "Fix thing", additions: 1, deletions: 0)
        #expect(RichLink.html(for: link, info: info)
            == #":pull-request: <a href="https://github.com/a/b/pull/5">Fix thing [+1 -0]</a>"#)
    }

    @Test func htmlEscapesTitle() {
        let info = PRInfo(title: #"Use <T> & "quotes" > 3"#, additions: 0, deletions: 0)
        #expect(RichLink.html(for: link, info: info)
            == #":pull-request: <a href="https://github.com/a/b/pull/5">Use &lt;T&gt; &amp; &quot;quotes&quot; &gt; 3 [+0 -0]</a>"#)
    }

    @Test func htmlEscapesURL() {
        let link = PRLink(originalURL: "https://github.com/a/b/pull/5?x=1&y=\"2\"", owner: "a", repo: "b", number: 5)
        let info = PRInfo(title: "t", additions: 0, deletions: 0)
        #expect(RichLink.html(for: link, info: info).contains(#"href="https://github.com/a/b/pull/5?x=1&amp;y=&quot;2&quot;""#))
    }

    @Test func escapeIsIdempotentOnPlainText() {
        #expect(RichLink.escape("plain title 123") == "plain title 123")
    }
}

import AppKit
import Foundation

let usage = """
usage: github-pr-richlinks [--interval SECONDS] [--verbose]
       github-pr-richlinks render URL
       github-pr-richlinks --help

Watches the clipboard for GitHub pull request URLs. When one is copied, the
clipboard is rewritten so that rich-text contexts get
  :pull-request: <a href="URL">Title [+added -removed]</a>
while plain-text contexts still get the raw URL.

Options:
  --interval SECONDS  Poll interval (default 0.5)
  --verbose, -v       Log every clipboard change, not just PR URLs
  render URL          Fetch the PR and print the HTML fragment, then exit
"""

func fail(_ message: String) -> Never {
    FileHandle.standardError.write("github-pr-richlinks: \(message)\n".data(using: .utf8)!)
    exit(1)
}

var interval: TimeInterval = 0.5
var renderURL: String?

var args = Array(CommandLine.arguments.dropFirst())
while !args.isEmpty {
    let arg = args.removeFirst()
    switch arg {
    case "--help", "-h":
        print(usage)
        exit(0)
    case "--verbose", "-v":
        Log.verbose = true
    case "--interval":
        guard !args.isEmpty, let value = TimeInterval(args.removeFirst()), value > 0 else {
            fail("--interval requires a positive number of seconds")
        }
        interval = value
    case "render":
        guard !args.isEmpty else { fail("render requires a URL") }
        renderURL = args.removeFirst()
    default:
        fail("unknown argument '\(arg)'\n\n\(usage)")
    }
}

if let renderURL {
    guard let link = PRLink.parse(renderURL) else { fail("not a GitHub PR URL: \(renderURL)") }
    do {
        let info = try GitHub.fetch(link)
        print(RichLink.html(for: link, info: info))
        exit(0)
    } catch {
        fail("\(error)")
    }
}

let watcher = MainActor.assumeIsolated { ClipboardWatcher(interval: interval) }
MainActor.assumeIsolated { watcher.start() }

signal(SIGINT) { _ in exit(0) }
signal(SIGTERM) { _ in exit(0) }

RunLoop.main.run()

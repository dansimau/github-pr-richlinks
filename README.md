# github-pr-richlinks

[![Coded with Claude Code](https://vibecoded.fyi/badges/flat/agents/claude-code.svg)](https://vibecoded.fyi/)

A small macOS daemon that watches the clipboard for GitHub pull request URLs
and rewrites them as rich links. Copy

    https://github.com/org/repo/pull/123

and the clipboard becomes:

| Pasteboard type        | Content                                                                      |
| ---------------------- | ---------------------------------------------------------------------------- |
| `public.html`          | `:pull-request: <a href="https://github.com/org/repo/pull/123">Title [+52 -20]</a>` |
| `public.utf8-plain-text` | `https://github.com/org/repo/pull/123`                                     |

Rich-text destinations (Slack, Notes, Google Docs, Mail) paste the titled link
with the diff stats; plain-text destinations (terminals, editors, URL bars)
still get the raw URL.

To paste the raw URL into a rich-text destination, copy the same URL twice in
a row. The second copy is left as plain text. Copying it a third time turns it
back into a rich link, and copying anything else in between resets the count.

## Requirements

- macOS 13+
- Swift toolchain (Xcode or Command Line Tools)
- [GitHub CLI](https://cli.github.com) (`gh`), authenticated via `gh auth login`
  or `GITHUB_TOKEN`. Looked up on `PATH`, then `/opt/homebrew/bin` and `/usr/local/bin`.

## Usage

```sh
swift build
.build/debug/github-pr-richlinks            # poll every 500ms, log to stderr
.build/debug/github-pr-richlinks --verbose  # also log non-PR clipboard changes
.build/debug/github-pr-richlinks --interval 1
.build/debug/github-pr-richlinks render https://github.com/cli/cli/pull/1   # print HTML and exit
```

## Tests

```sh
swift test
```

## Run at login

```sh
make install   # builds release, installs to ~/.local/bin and ~/Library/LaunchAgents
make start     # launchctl bootstrap
make log       # tail ~/Library/Logs/github-pr-richlinks/github-pr-richlinks.log
make stop / make restart / make uninstall
```

Set `PREFIX` to install elsewhere, e.g. `make install PREFIX=/usr/local`.

If you previously used the Maccy trigger from `github-pr.sh`, disable it
first; otherwise both will rewrite the clipboard and Maccy's version (without
the plain-text URL or diff stats) wins the race.

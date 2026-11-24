# github-pr-richlinks

[![Coded with Claude Code](https://vibecoded.fyi/badges/flat/agents/claude-code.svg)](https://vibecoded.fyi/)

A small macOS daemon that watches the clipboard for GitHub pull request URLs
(and Claude artifact URLs) and rewrites them as rich links. Copy

    https://github.com/org/repo/pull/123

and the clipboard becomes:

| Pasteboard type        | Content                                                                      |
| ---------------------- | ---------------------------------------------------------------------------- |
| `public.html`          | `:pull-request: (repo) <a href="https://github.com/org/repo/pull/123">Title [+52 -20]</a>` |
| `public.utf8-plain-text` | `https://github.com/org/repo/pull/123`                                     |

Rich-text destinations (Slack, Notes, Google Docs, Mail) paste the titled link
with the diff stats; plain-text destinations (terminals, editors, URL bars)
still get the raw URL.

### Claude artifacts

Claude artifact links get the same treatment. Copy

    https://claude.ai/artifact/T1LYkmCE7aXds8iHA4Lw8d?sk=…

and rich-text destinations paste
`:claude: <a href="https://claude.ai/artifact/T1LYkmCE7aXds8iHA4Lw8d?sk=…">AI Task Force Tracker</a>`.

claude.ai doesn't serve artifact titles to non-browser clients, so the title is
read from the Google Chrome tab that has the artifact open. If no Chrome tab
is showing it (or the tab is still loading), the clipboard is left as the plain
URL. The first lookup triggers a macOS prompt to let the daemon control Google
Chrome (System Settings > Privacy & Security > Automation).

## Requirements

- macOS 13+
- Swift toolchain (Xcode or Command Line Tools)
- [GitHub CLI](https://cli.github.com) (`gh`), authenticated via `gh auth login`
  or `GITHUB_TOKEN`. Looked up on `PATH`, then `/opt/homebrew/bin` and `/usr/local/bin`.
- Google Chrome, for Claude artifact links only

## Usage

```sh
swift build
.build/debug/github-pr-richlinks            # poll every 500ms, log to stderr
.build/debug/github-pr-richlinks --verbose  # also log unrecognised clipboard changes
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

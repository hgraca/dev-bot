---
date: 2026-11-27
keywords: ["mcp", "playwright", "output-dir", "user-data-dir", "tilde"]
aliases: ["literal tilde directory", "home path not expanded in mcp args", "~/.playwright-mcp verbatim"]
trigger-on: ["mcp-stdio-path-args", "playwright-mcp-output-dir"]
---

## An MCP stdio command is not shell-expanded — `~` in its arguments stays literal

A user-scope MCP server is spawned as a program with an argv array, not through a shell, so `~` and `$HOME` inside its arguments reach it verbatim: `--user-data-dir ~/.cache/x` creates a directory literally named `~` under the server's working directory, and every artifact lands there instead of in the home cache. The server does not rescue it either — `@playwright/mcp` 0.0.80 resolves both `--output-dir` and `--user-data-dir` with `path.resolve`, which expands no tilde, and its bundle ships no `expand-tilde` helper. Register the command through a shell when a home-relative path is wanted (`bash -c 'exec npx @playwright/mcp@latest … --user-data-dir "$HOME/.cache/…"'`) or pass an absolute path. A **relative** `--output-dir` is resolved the same way, against the server's cwd — the project root when the client launches it there — which is why the unset default shows up as `./.playwright-mcp` in the repo rather than anywhere in the home directory.

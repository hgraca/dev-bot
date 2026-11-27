---
date: 2026-11-27
keywords: ["devbot", "checkout", "install", "release"]
trigger-on: ["devbot-tooling-change-not-live"]
---

## A merged devbot fix is inert until the pinned install checkout moves

`~/.local/bin/devbot` symlinks to `~/.local/share/dev-bot/bin/devbot`, so the CLI, its MCP servers and every skill are served from whatever commit that checkout holds — on this machine a detached `1.24.0` tag. Merging a change to `src/tools/` or `src/agentic/` updates origin only: the running agent keeps calling the old tool until the checkout is moved onto the new tip, so a fix can look broken when it simply is not loaded. Confirm the version before diagnosing behaviour the change was meant to correct (`git -C ~/.local/share/dev-bot log --oneline -1` versus the merge commit), and say which of the two is being observed when reporting a result.

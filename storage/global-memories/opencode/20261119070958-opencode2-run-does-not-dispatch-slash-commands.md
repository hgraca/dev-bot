---
date: 2026-11-19
keywords: ["opencode", "slash-command", "opencode2", "run", "cli"]
aliases: ["command not dispatched from run", "slash command sent as text"]
trigger-on: ["opencode-slash-command-invocation", "non-interactive-agent-run"]
---

## `opencode2 run "/<command>"` sends the slash string as text, it does not run the command

Verified on 2.3.0: `opencode2 run --format json --auto "/devbot/stats"` exits 0 and stores the literal `/devbot/stats` as the session's first user message — the model then improvises from that text, and the command's body (with its `$ARGUMENTS` substitution and instructions) never runs. v1 has a `run --command <name>` flag for this; v2's `run` has no `--command`, and its `Command not found:` string belongs to the TUI/API path, not to `run`. Anything that starts a run non-interactively must therefore send the command's *body* (read the command file, strip the frontmatter, substitute the arguments) or go through the v2 session command API — never assume a slash-command id resolves inside a `run` message.

---
date: 2026-09-10
keywords: ["claudecode", "transcript", "jsonl", "usage", "subagents"]
trigger-on: ["claudecode-transcript-parse", "claudecode-token-usage"]
---

## Claude Code writes one JSONL line per content block — group by message id before summing usage

Claude Code has no stats command; usage must be derived from `~/.claude/projects/<slug>/*.jsonl` (slug = cwd with `/` → `-`). Each assistant response is written as **one line per content block**, repeating the same `message.id` and the full `message.usage` on every line. Iterating lines independently double-counts tokens (~1.5× on real data). Group lines by `message.id` (or `requestId`), take the usage once, and split it across that message's `tool_use` blocks. `message.usage` carries tokens only (`input_tokens`, `output_tokens`, `cache_read_input_tokens`, `cache_creation_input_tokens`) — there is **no cost field anywhere** in the transcript. Subagent sessions live under `<projects>/<slug>/<session>/subagents/*.jsonl`; a shallow `*/*.jsonl` glob misses them, so recurse and de-duplicate globally by message id.

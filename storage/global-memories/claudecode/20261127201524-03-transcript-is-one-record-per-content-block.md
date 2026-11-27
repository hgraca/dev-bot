---
date: 2026-11-27
keywords: ["claudecode", "transcript", "stop-hook", "subagents", "jsonl"]
---

## A Claude Code transcript is one record per content block, not per message

Session transcripts are JSONL where every assistant **content block** is its own line, repeating the message id, so "the last line" is not the last turn: a Stop hook must group the trailing records by `message.id` before judging what the assistant said, or it loses earlier text and any `tool_use` that later evidence depends on. A delegated agent gets its own transcript under a `subagents/` directory and its Stop hook fires too — reporting from there overwrites the pane's shared status while the primary turn is still running, so skip any transcript path containing a `subagents` segment. Read from the end of the file with a bounded window that widens until the selected turn is complete; transcripts grow for the life of a session, and a naive full read on every Stop makes the hook progressively slower.

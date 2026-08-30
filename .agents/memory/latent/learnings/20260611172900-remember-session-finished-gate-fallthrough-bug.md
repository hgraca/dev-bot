---
date: 2026-06-11
keywords: ["devbot", "remember-session", "plugin", "FINISHED!", "gate", "NEEDS_INPUT", "session.idle"]
---

# remember-session idle plugin FINISHED! gate checked all assistant messages instead of just the last

The `lastAssistantMessageEndsWithFinished` function in `on-session_idle-remember-session.ts` iterated ALL assistant messages from newest to oldest, returning `true` if ANY of them had a text part whose last line was `FINISHED!`. When the latest message ended with `NEEDS_INPUT:` or `BLOCKED:`, the function would continue iterating to older messages and find an earlier `FINISHED!` — causing the idle plugin to inject a remember-session prompt even though the orchestrator was waiting for user input.

Fix: add `return false` after the inner part-checking loop so the function stops at the chronologically last assistant message. Committed in 85cb702.

Apply when modifying the remember-session plugin to ensure any future gate logic only considers the latest assistant message.

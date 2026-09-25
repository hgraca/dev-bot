---
date: 2026-09-25
keywords: ["pty-monitor", "opencode-pty", "session-removal"]
see: ["ADRs/20260925085456-pty-monitor-starts-server-only-on-request.md"]
---

## The PTY monitor removes sessions on demand only — no automatic reaping

The `pty-monitor` sidebar gained manual session removal: a `✕` on each row and a `(clear finished)` action in the header, both issuing `DELETE /api/sessions/:id/cleanup`. Removal is deliberately manual — no TTL, no max-sessions cap and no auto-eviction was added — because opencode-pty retains a finished session's output for later reading, so reaping it automatically would silently destroy the user's ability to inspect a completed run (every `sleep`-wait PTY and `make test` run leaves one behind). The `✕` confirms before removing a `running` session, because that kills a live process, and acts immediately on a finished one; `(clear finished)` never confirms because it can only touch non-running sessions, and it is rendered only while something is actually clearable. `killing` is treated as not-finished so a clear cannot race the process teardown, while the `✕` still lets it through without a prompt since that session is already on its way out. Removal refreshes the list immediately, and `refresh` takes a `force` flag so that a user-driven refresh is queued rather than dropped while a poll is in flight; a plain poll tick may still be skipped, because queueing those would let a hanging server be retried back-to-back instead of once per poll interval.

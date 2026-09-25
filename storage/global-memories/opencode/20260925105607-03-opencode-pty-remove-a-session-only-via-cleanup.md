---
date: 2026-09-25
keywords: ["opencode", "opencode-pty", "session-lifecycle"]
trigger-on: ["opencode-pty-session-cleanup"]
---

## opencode-pty drops a session from its map only via cleanup, and cleanup works on finished sessions

opencode-pty keeps every PTY session in an in-memory `Map` for the life of the opencode process. `kill(id)` terminates the process but RETAINS the entry so its output stays readable; only `kill(id, true)` — reached over HTTP as `DELETE /api/sessions/:id/cleanup` — also clears the ring buffer and deletes the map entry. `DELETE /api/sessions/:id` is the plain kill, `DELETE /api/sessions` clears everything including running sessions, and the cleanup route answers HTTP 400 when the id is unknown. Cleanup is safe on an already-`exited` session: the kill step is skipped for a non-`running` status and the delete still happens, which is what makes a "remove finished sessions" action possible at all. Note that `SessionInfo` (what `GET /api/sessions` returns) carries `createdAt` but NO exit/end timestamp, so any grace-period or TTL policy needs client-side "first seen terminal" tracking rather than arithmetic on the returned fields.

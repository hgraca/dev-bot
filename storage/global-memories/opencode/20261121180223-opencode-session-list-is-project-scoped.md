---
date: 2026-11-21
keywords: ["opencode", "session-list", "session-management"]
aliases: ["session list project scope", "session list directory"]
---

## `opencode session list` is project-scoped, not directory-scoped

`opencode session list --format json` returns the sessions of the **project** the working directory
belongs to, and a project spans every worktree of one checkout: run from inside
`.agents/worktrees/<branch>` it still returns the main checkout's sessions, newest first, each row
carrying `id`, `title`, `updated` (epoch ms), `created`, `projectId` and `directory`.

Anything assuming "row 0 is the session I am in" is therefore wrong as soon as a sibling checkout or
worktree holds a newer session. Filter on each row's `directory` (compare resolved paths) before
picking the newest, and keep an unfiltered fallback for a session that recorded a parent directory
instead of `$(pwd)`.

The listing is also the cheapest way for an outer process to learn the id after the harness exits:
no state file, no schema knowledge, and the same payload on 1.x and 2.x. `-s`/`--session` resumes a
specific id on both versions; `-c`/`--continue` resumes the last one.

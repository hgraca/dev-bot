---
date: 2026-11-18
keywords: ["refactor", "response contract", "no-op", "engine pinning"]
---

# `ok` is not `changed`: a refactor apply can succeed and write nothing

The refactor module's response answered `ok: true` for a run that changed zero files — a wrong name, or
one already renamed — and the only hint was a `notice` a caller checks only if it parses the payload.
While the scratch engine floated (`^2.6` → 2.8.5), that combination reported a _successful_ fix that
never happened: `"Renamed test -> scenario in 0 file(s)"` with `ok: true`.

The contract now carries `changed` on an apply (all three engines), absent on a plan, `false` after a
rolled-back failure and `false` for a same-name rename. Two rules for anything that reports work:

- separate "did the run work" from "did anything change", and give the second a field, not prose;
- derive it from what was written, not from what was visited — a visited file list is non-empty for a
  no-op, and a rollback un-writes what a failed multi-step run did.

Pinning the engine is the other half: `provision` installed whatever a caret range resolved to, so a
version no test had ever agreed with reached users, and the e2e that covered it skipped when no engine
was present. A missing engine may skip; an engine that is not the pinned one must fail.

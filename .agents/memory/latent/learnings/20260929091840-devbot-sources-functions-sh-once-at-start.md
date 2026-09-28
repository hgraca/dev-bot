---
date: 2026-09-29
keywords: ["devbot", "functions-sh", "session-release", "hook"]
---

# `bin/devbot` sources functions.sh once, at start

`bin/devbot` sources `src/_shared/functions.sh` when the process starts and keeps that copy in memory for the session's lifetime. An edit to `functions.sh` — e.g. adding a call inside `_devbot_session_release` — therefore does **not** take effect in the already-running `devbot`, including on its own exit path, so a newly added last-session action will not fire on the session in which it was written; it takes effect from the next `devbot` launch. Do not report such a change as "it will run on exit now" without that caveat — the running process predates the edit.

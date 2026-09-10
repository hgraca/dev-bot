---
date: 2026-09-10
keywords: ["devbot", "update", "reinit", "version", "wiring-hash"]
---

## Auto-update on bare start, with a per-project `version`-driven reinit

A bare `devbot` start now runs `devbot update --auto` before wiring — a quiet one-line no-op when already on the newest release, non-fatal on failure (offline/conflict) so a start is never blocked, opt-out via the global `auto_update` (default true). After a real release move, `update` writes the tag into the global config's `version` and no longer runs `reinit --all`. Reinit became lazy and per project: each project's `.devbot.project.sha` is now a combined hash of the global + project configs, so a `version` bump changes every project's wiring hash and each reinits on its own next start. This replaced the old design where the global config baseline lived in one shared `${DEV_BOT_ROOT}/.devbot.global.sha` — that file only ever triggered a reinit for the first project to start after a global change, so the change did not propagate to the remaining projects. Consequences: `devbot update` no longer reinits anything immediately (the version bump drives it on next start); a global config change now reinits every project, not just one; and the retired `.devbot.global.sha` is dropped.

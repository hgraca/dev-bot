---
date: 2026-09-17
keywords: ["devbot", "dist-config", "harness-init", "seed-once", "reinit"]
trigger-on: ["devbot-dist-config", "devbot-harness-wiring", "devbot-init-seed"]
---

## Dist-backed configs are seed-once: an entry added to a dist never reaches an already-seeded project

`opencode.dist.jsonc` / `tui.dist.jsonc` are applied by `_write_jsonc_from_dist`, which **skips when the target already exists** — so a project receives the dist only at first seed, and every later addition to a dist silently passes it by. This broke a shipped dependency in the wild: the PTY monitor TUI plugin was wired into every consumer while `opencode-pty` (the *server* plugin it calls) was not, because nothing adds a dist entry to an existing `opencode.jsonc` — `_link_module_plugins` upserts only what a **module declares** via `plugin.opencode.json`, and a dist entry is not a module declaration. The only symptom was a generic "server unavailable" in the panel; the real cause (`Command not found: pty-show-server-url`) never surfaced. Fix: `_ensure_dist_plugins <dist> <config>` re-adds the dist's **npm-spec** entries to an existing config on every init/reinit, idempotently via the shipped `_upsert_opencode_plugin`, skipping local paths (those are symlink farms owned by `_link_harness_hooks` / `_link_tui_plugins`). Applied to both surfaces.

Also worth knowing when wiring anything harness-level: **the reinit-on-start is gated by config, not code.** `_devbot_wiring_sha` hashes only `DEV_BOT_ROOT/.devbot.global.jsonc` and the project's `.devbot.project.jsonc`, and `bin/devbot`'s auto-reinit fires on a changed hash — so a harness *code* change reaches existing projects only via a **released update** (which writes a `version` into the global config) or an explicit `devbot reinit`. When adding harness wiring, expect consumers to need a reinit, and test the integration on a real seeded project — the sandbox tests exercise the functions, not the "was it already seeded?" path that actually failed here.

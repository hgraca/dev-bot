---
date: 2026-10-12
keywords: ["external-modules", "devbot-init", "vendored-skill", "wiring"]
---

# External-module wiring: merge, clone and symlink have different triggers

Declaring an external skill repo in `src/<area>/<module>/external-modules.json` provisions it in
three independent steps, each with its own command and gate:

| Step                                                            | Command                       | Enablement-gated? |
| --------------------------------------------------------------- | ----------------------------- | ----------------- |
| Merge declaration into `.devbot.global.jsonc::external_modules` | `devbot install`, `devbot up` | No                |
| Clone to `vendor/<owner>/<repo>`                                | `devbot install` / `update`   | No                |
| Symlink `.agents/skills/<key>`                                  | `devbot init` / `reinit`      | Yes               |

`devbot up` never symlinks — it only merges the config — so after enabling a module and running
`up`, the entry is visible in `devbot module list` while `.agents/skills/<key>` is still absent
until an `init`/`reinit` runs, and even then only when the declaring module is enabled for that
project. The config **key** is the symlink name; the `paths` value is a path relative to the clone
root (e.g. `skills/modern-web-guidance`), not to a fixed `skills/` convention. A declaring module
needs no `install.sh`/`init.sh` — the merge is central (`_devbot_rebuild_external_module_config`).

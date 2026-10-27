---
date: 2026-10-27
keywords: ["external-modules", "devbot", "vendor", "mirror", "stamp"]
aliases: ["module update on start", "vendor clone sync", "mirror completeness", "24h check gate"]
---

# External module updates: the contract the up/install paths enforce

## When the check runs

`src/tools/external-modules/up.sh` runs on every `devbot` start and `devbot up`. The read-only compare is one `git ls-remote` per **destination**, run in parallel; writes (fetch + hard reset + mirror render) stay serial under a per-destination `flock` (`vendor/<owner>/<repo>.lock`). The whole check is gated by a stamp in `storage/run/external-modules.checked` that carries a SHA-256 of the configured entry set — a new module, an edited URL/paths, or a missing checkout/mirror bypasses the interval (default 24 h, `DEV_BOT_EXTERNAL_MODULES_CHECK_INTERVAL`).

## Validation before a reset

`_install_one_module` fetches the configured URL, then validates every configured path **against the incoming commit** (`git ls-tree` mode: a string path must resolve to a tree, following symlinks inside the commit; a mapped file must be a blob) and every alias's paths for a shared clone. A miss cancels the update with an error and leaves the legacy checkout untouched. A retained checkout whose `remote.origin.url` does not match the configured URL (or has none) is refused rather than rewritten; paths and module names are rejected if absolute, traversal-bearing, or control-character-bearing.

## Mirror invariants

`storage/external-agentic-modules/<name>/` holds symlinks only: configured paths plus any lifecycle script (`up.sh`, `init.sh`, …) the checkout ships. `_external_module_mirror_incomplete` verifies each link's *target*, not mere existence, and the start path runs it on every pass; a conflicting regular file is reported, preserved, and makes the render fail so no stamp is written. Entries are wired into the project (`.agents/<type>/<name>`) only after a successful render and only when the project does not disable the module.

## One sync implementation

`_external_module_install_all` backs `install.sh` (`devbot install`/`update`, including the start-time self-update) and `devbot module install`. `bin/update.sh` no longer has its own external pass: the module update loop (`external-modules/update.sh` → `install.sh`) is that pass. An explicit `devbot update` that moves no release refreshes externals before exiting; `--auto` does not (the start-time gate owns it). A completed install/update stamps the check.

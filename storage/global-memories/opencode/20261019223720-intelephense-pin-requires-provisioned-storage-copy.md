---
date: 2026-10-19
keywords: ["opencode", "intelephense", "lsp", "php", "devbot-harness"]
aliases: ["intelephense version", "pinned lsp version", "storage/intelephense"]
trigger-on: ["opencode-lsp-intelephense", "intelephense-version-pin"]
---

## The pinned Intelephense version is inert until its storage copy is provisioned

`dev-bot/src/harnesses/opencode/versions.env` pins `INTELEPHENSE_VERSION=1.18.5`, and `src/harnesses/opencode/lsp/intelephense.sh` prefers `${DEV_BOT_ROOT}/storage/intelephense/node_modules/.bin/intelephense` over the copy opencode bundles (1.16.5). The wrapper's fallback chain is silent: if the provisioned copy is absent it execs opencode's bundled binary with no warning, so a machine can advertise the pin in `versions.env` and still run 1.16.5. `storage/` is gitignored, so a fresh checkout or a cleaned storage dir silently loses the pin. Provision with `bash dev-bot/src/harnesses/opencode/install.sh` (idempotent, installs `intelephense@$INTELEPHENSE_VERSION` into `storage/intelephense`), then verify the copy with `python3 -c "import json;print(json.load(open('dev-bot/storage/intelephense/node_modules/intelephense/package.json'))['version'])"`; a running opencode session keeps its already-spawned LSP process, so restart opencode after provisioning. Do not confuse this with opencode's own `~/.cache/opencode` / `~/.local/share/opencode` copies — those stay at the bundled version by design and need no edit.

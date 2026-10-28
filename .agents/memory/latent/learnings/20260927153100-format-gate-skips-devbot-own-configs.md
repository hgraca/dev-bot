---
date: 2026-09-27
keywords: ["format-json", "prettier-gate", "opencode.jsonc", "force"]
superseded_by: ["ADRs/20261028151924-format-hooks-fall-back-to-devbot-prettier-defaults.md"]
---

# The prettier gate silently stops dev-bot normalizing its own generated configs

> **Superseded.** There is no prettier gate any more: a project that declares no prettier config
> is formatted with dev-bot's shipped defaults, so these call sites format without `--force`.
> See ADR `20261028151924-format-hooks-fall-back-to-devbot-prettier-defaults.md`.

`src/_shared/prettier_gate.py` gates every file/directory `format-*` run on the
TARGET PROJECT declaring prettier (`.prettierrc*`, `prettier.config.*`, or a
`prettier` key in `package.json`). That is right for a project's own source, but
`bin/init.sh:_format_opencode_config` and `bin/up.sh` (the `.devbot.global.jsonc`
merge) format dev-bot's OWN generated files: the project's `opencode.jsonc` and
the install-root global config. In any project that never declares prettier the
gate made those calls a silent no-op, so the MCP-merge output kept its
inserted-entry formatting (a lone `,`, mixed compact/expanded entries) — valid
JSON, but visibly drifted (audit-69 NOTE-4).

Fix: `format-json.py` gained `--force`, which skips `has_prettier_config` for an
explicit call, and both dev-bot-owned call sites pass it. Pipe mode was already
ungated. Rule of thumb: the prettier gate protects a project's source from a
formatter it did not adopt; it must never govern files dev-bot itself writes.

Testing caveat: `has_prettier_config` walks up from the argument, so a path
argument (including a bare `--force`) resolves against the CWD — a test that runs
from the repo root (which declares prettier) passes even without the flag. Run
the tool from the target project dir to exercise the gate.

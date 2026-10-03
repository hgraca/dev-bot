---
date: 2026-10-03
keywords: ["devbot", "prerequisites", "pre.sh", "install", "modules"]
---

## Module pre.sh: notice for install-provided prereqs, error for manual ones

Stakeholder rule (2026-10-03): a module's `pre.sh` must classify every
prerequisite by **who can provide it**, and behave accordingly:

- **Provisioned by the module's own `install.sh`/`update.sh`** (aws: `unzip`,
  `uv`, `mcp-proxy-for-aws-cli`, the aws CLI) — a missing tool is a **notice**
  that `devbot install`/`devbot update` will install it, and the check
  **continues** (exit 0). Before the first install these are always absent, so
  treating them as failures produced a false "prerequisites missing — run
  install.sh" on every fresh install, immediately followed by the same run
  installing them.
- **Required from the machine, installable only by the user** (`curl`/`wget`,
  `docker`, `npx`, a language runtime) — a missing tool is a fatal **error**: the
  check stops (exit non-zero), because init/update cannot provide it.

Optional tools — a verification step that merely degrades (e.g. `jq` in aws,
`curl` in sentry/signoz) — stay an `_info`, never an error.

Implemented as `_prereq_module_installed` / `_prereq_manual` in
`src/_shared/functions.sh`; modules call them from their `pre.sh`.
`_run_module_prereqs` keeps running **before** the module installs — with this
classification a pre-install notice for an install-provided tool is correct, and
the ordering no longer needs to change.

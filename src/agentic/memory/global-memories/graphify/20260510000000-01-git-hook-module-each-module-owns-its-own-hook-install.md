---
date: 2026-05-10
keywords: ["graphify", "graph"]
---

## Git hook module: each module owns its own hook install via install_devbot_hook

Date: 2026-05-10 (revised same day from earlier monolithic version)
Each git-hook-owning module installs its own hooks from its own `init.sh`, using the shared helper `install_devbot_hook <hook-name> <body>` (defined in `src/functions/git.sh`, autoloaded). The helper writes a DEVBOT-marked section into `${PROJ}/.git/hooks/<hook-name>`, uses the first non-empty line of `<body>` as a per-module fingerprint, and on re-install replaces ONLY the section matching that fingerprint — so multiple modules can contribute independent sections to the same hook file idempotently without clobbering each other.

Module layout:

- Runner script: `src/<module>/<module>-hook-runner.sh` — self-contained, takes `<project-path>` as `$1`, sets `-uo pipefail`, gates on `OPENCODE_SESSION_ID` when human commits should pass through untouched.
- Installer: `src/<module>/init.sh` — sources `autoload.sh`, validates `PROJ`, builds the hook body, calls `install_devbot_hook`. Wire the module name into `INIT_APPS` in `bin/init.sh` so `devbot init` runs it.

Body conventions:

- Background hooks (post-commit / post-checkout): `bash "<runner>" "<proj>" >/dev/null 2>&1 & disown` — prevents MCP git server from waiting on child FDs.
- Blocking hooks (pre-commit): `bash "<runner>" "<proj>" || exit 1` — non-zero exit aborts the commit so the LLM sees the failure.

Current consumers: `graphify` (post-checkout + post-commit), `codebase-index` (post-commit), `git-hook-remember-session` (post-commit), `git-hook-run-tests` (pre-commit). The previous monolithic `src/graphify/hooks-init.sh` was removed in `a8a6e74` to restore encapsulation. See [[gotchas]] for the awk-based section replacement details.

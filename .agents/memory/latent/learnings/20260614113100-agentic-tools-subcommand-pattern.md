---
date: 2026-06-14
keywords: ["devbot", "agentic-tools", "subcommand", "cli", "pattern"]
see: ["project/20260614113300-format-md-pipe-mode-in-bash.md"]
---

# Agentic-tools subcommand pattern

The `devbot agentic-tools` subcommand follows the `bin/init.sh` pattern for lifecycle scripts: `#!/usr/bin/env bash` with `set -euo pipefail`, resolve `DEV_BOT_ROOT` from `BASH_SOURCE[0]`, source `src/_shared/functions.sh`, define functions, call `main()`. Uses `_header_1`, `_info`, `_ok`, `_warn` from functions.sh for output. Inline Python via `python3 -c` for parsing (same pattern as init.sh uses for JSON). The CLI dispatch in `bin/devbot` follows the `cmd_install` pattern (simple bash delegation, no exec).

The subcommand scans `.opencode/tools/*.ts` (these are symlinks into `src/agentic/<module>/tools/`), extracts description from the `tool({...})` export using Python regex, and outputs a markdown table with columns: tool, path, description, how-to. The how-to column is auto-generated from the first sentence of the description plus parameter names extracted from the Parameters section. Both DevBot and Sidekick agents should run `devbot agentic-tools` at session start to discover available custom tools. The table output is piped through `format-md.py` for column alignment.

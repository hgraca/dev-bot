---
date: 2026-09-25
keywords: ["refactor", "mcp", "cli", "canonical-ops", "skill"]
see: ["ADRs/20260731173000-remove-agentic-tools-cli.md", "ADRs/20260925204158-skill-description-may-list-operations.md"]
---

## The refactor tool is a CLI exposed by a skill, with one canonical operation vocabulary

`devbot-tools_refactor` was removed: the refactor tool is now `tools/refactor.sh` (bash) plus `lib/refactor-lib.py` (JSON), invoked as `devbot tool refactor <op>` and documented by the `devbot:refactor` skill. It has no `mcp.json` and no `.mcp.sh`, so the shared `devbot-tools` server no longer lists it — a deliberate deviation from ADR `20260731173000` (custom tools go through that MCP server), taken because the tool's operation surface grows and a shell CLI documented on demand costs less always-on context than a permanent MCP entry. The core is language-agnostic: it discovers `langs/<lang>/plugin.sh`, and each plugin declares its canonical operations in `meta` as `map: canonical -> {kind -> native}`. The vocabulary (`rename`, `move`, `extract`, `inline`, `encapsulate`, `add-parameter`, `remove-parameter`, `remove-unused`, `privatize`, `promote-readonly`) is the tool's public surface; `--kind` selects the per-language native op, so the core never learns a language's op names and adding a language adds no entry to the core. The skill and `docs.md` carry one identical operations table, guarded by `tests/ops_table_check.py`.

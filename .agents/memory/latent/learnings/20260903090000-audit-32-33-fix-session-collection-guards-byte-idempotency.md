---
date: 2026-09-03
keywords: ["audit-32", "audit-33", "byte-idempotency", "search-memories", "resolve_collection", "guards", "file.edited", "remove_mcp_key", "mcp_key_is_current", "project_name"]
see: []
---

# audit-32/33 fix session: collection fallback, opencode guards/race, reinit byte-idempotency

Fixes from the audit-32 (opencode) + audit-33 (claudecode) reports, all committed on `feature/mac-fixes-local-external-modules` tagged `(audit-32)` / `(audit-32/33)`. Root causes and the non-obvious mechanics, so future audits re-verify the fixed behavior instead of re-flagging stale symptoms.

## search-memories default collection (shared FAIL)

`resolve_collection()` in `search-memories.py` fell back to the literal `"devbot"`; `qmd/init.sh` registers the collection under the **project-dir basename**. Two files that must agree on a default disagreed → `Collection not found: devbot` on every default invocation (CLI, MCP, remember-session dedup). Fix has two halves:

1. `resolve_collection()` fallback → `Path(project_root).name`, treating an **empty** `project_name` as missing too (qmd's `${VAR:-basename}` semantics — a present-but-empty key previously returned `""` and broke `qmd -c ""`).
2. `devbot-cli/init.sh` injects a missing/empty `project_name` (dir basename) into an existing `.devbot.project.jsonc` on reinit — the fixture's harness `set_harness` writes only harness+modules, so reinit never added the key before.

**Testing gotcha**: the python unit tests (`test_search_memories.py`) run standalone (`python3 test_search_memories.py`), NOT under `make test` — the bats suite is the make-test surface. Regression lives in `search-memories_tests.bats` (imports the hyphenated module via importlib).

## opencode guards not enforced live (audit-32)

`on-hooks.ts` read `process.env.DEVBOT_ROOT` (never exported — the harness exports `DEV_BOT_ROOT` and the plugin computes its own root from `import.meta.dir`). `--global-config ""` → only project config merged → no guard rules. Claudecode's adapter already did it right (`os.path.join(DEV_BOT_ROOT, ".devbot.global.jsonc")` from realpath). Fix: `resolveGlobalConfigPath(pluginRoot, env)` helper in `on-hooks-utils.ts` — `.devbot.global.jsonc` beside the plugin root (existsSync) first, then env `DEV_BOT_ROOT`. Plugin modules can only export the factory, so testable helpers live in `on-hooks-utils.ts` (tested in `on-hooks.test.ts` under bun).

## format-yml burst-edit race (audit-32)

Two `file.edited` events within ~1s ran two concurrent format hooks whose read-modify-write interleaves corrupted the file. Fix: `createFileEditGate()` in `on-hooks-utils.ts` — per-file serialization; one in-flight run, edits landing mid-run coalesce into one trailing re-run (dirty flag), failing runs never wedge the file. Wired into `on-hooks.ts`'s `file.edited` dispatch.

## reinit byte-idempotency (audit-32 NOTE) — three drift sources, all fixed

The audit observed a second `devbot reinit` regenerating `opencode.jsonc` (148→188 lines) and AGENTS.md differently. Local repro (no container needed): copy the repo minus heavy dirs (`--exclude storage node_modules no-vcs .git graphify-out vendor tests/test-project/.agents`) to a scratch install, copy the fixture to a scratch project, run `bin/reinit.sh` twice with an isolated `HOME`, and `cmp` the generated files. Three independent causes:

1. **`remove_mcp_key.py` whole-file `json.dump(indent=2)` rewrite** on every reset — expanded compact template objects to multi-line AND dropped JSONC comments. Rewritten as **text surgery** mirroring `merge_mcp_jsonc.py`: string/comment-aware entry location, delete only the entry + one adjacent comma/newline, fix dangling comma before the map close. Handles middle/last/only-entry cases.
2. **Graphify AGENTS.md section removal left a trailing blank**: `graphify install` appends a `## graphify` section (with blank separator) at EOF; graphify init's awk strip removed the section but kept the separator. Fixed by stripping trailing blank lines after the removal.
3. **reset.sh churned MCP keys that already matched their module templates** — removed `devbot-tools`+`qmd` (opencode) / every agentic-module key (claudecode), so init re-appended them at map end → reordering. New `mcp_key_is_current.py` compares the registered def against the module template (all four shapes: config `mcp`/`mcpServers` × template top-level-key/`mcpServers`); `__GPU_ENABLED__` counts as current-any-value (resolved GPU is machine-dependent). Both resets now skip removal when current; genuinely stale entries (old env/command shape) are still dropped.

The e2e harness now encodes this: `test-reinit.sh` runs a second reinit and prints BYTE-IDEMPOTENCY-PASS/FAIL, and audit.md's §1 documents the probe.

**Gotcha**: after any fix, re-sync changed files into the scratch install (`cp src/... scratch/install/...`) before re-running the repro — the scratch install is a copy, not a symlink.

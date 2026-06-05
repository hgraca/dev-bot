---
date: 2026-05-10
keywords: ["opencode", "plugin", "tool"]
---

## Opencode custom tools require flat layout AND co-located `node_modules` — the `tools/devbot` symlink convention does NOT work

- **Symptom**: After committing `feat(tools): convert format-md script into opencode custom tool` (commit `d790ef1`), querying `GET /experimental/tools/ids` on `opencode serve` returned the built-in tool list with **no `format-md`** entry. Adding a flat-file symlink at `.opencode/tools/format-md.ts → src/instructions/tools/format-md/format-md.ts` caused the tool registration to be _attempted_, which then failed with `UnknownError: ResolveMessage: Cannot find module '@opencode-ai/plugin' from '/.../src/instructions/tools/format-md/format-md.ts'`.
- **Two distinct problems**:
    1. **Layout**: Tools nested under a subdir of `.opencode/tools/` (e.g. `.opencode/tools/devbot/format-md/format-md.ts` via the `devbot → src/instructions/tools` symlink) are **not discovered**. Custom tools must live directly under `.opencode/tools/` as `*.ts` files (per the docs example `database.ts` at the root). The `skills/devbot → ...`, `plugins/devbot → ...`, `commands/devbot → ...`, `agents/devbot → ...` symlink pattern that works for the other four opencode artifact dirs does **not** carry over to `tools/`.
    2. **Module resolution**: Even when opencode finds the `.ts` file via a flat symlink, the file is resolved at its _real_ path (the symlink target). The `import { tool } from "@opencode-ai/plugin"` then resolves relative to that real path, which lives at `src/instructions/tools/format-md/format-md.ts` — and there is no `node_modules/@opencode-ai/plugin` reachable from there. `@opencode-ai/plugin` is only installed at `.opencode/node_modules/`. Bun's module resolution walks up from the file's real path, never traversing the symlink, so the package is unreachable.
- **Why we missed this**: The docs example puts `add.py` and `python-add.ts` directly in `.opencode/tools/`. We assumed tools followed the `<artifact-type>/devbot/<name>/` convention used by skills/plugins/agents/commands — they don't. The `init.test.sh` suite only asserts the `skills/devbot` symlink (not plugins/agents/commands/tools), so the wiring change passed CI even though the tool never registered.
- **Verification commands** (paste-ready, server on port 49998):
    - List registered tool IDs: `opencode serve --port 49998 & sleep 5; curl -s http://127.0.0.1:49998/experimental/tools/ids`
    - List full tool definitions: `curl -s http://127.0.0.1:49998/experimental/tool`
    - Both endpoints are under `/experimental/`, undocumented but stable. The agent's whitelist (`opencode debug agent <name>` → `"tools": {...}`) shows the **agent's allowed-tool filter**, not the registry — a tool absent from `/experimental/tools/ids` will also be absent from the agent dump, but the agent dump alone is insufficient evidence that registration succeeded.
- **Fix options** (none implemented yet — `format-md` tool is currently non-functional in production):
    - **A**: Move the `.ts` file (and its co-located `package.json` with `@opencode-ai/plugin` dep) into `.opencode/tools/` as a real directory, abandoning the symlink-from-`src/instructions/` convention for tools only.
    - **B**: Put the `.ts` files in `src/instructions/tools/` but install `@opencode-ai/plugin` there too (separate `node_modules`), and use **per-file flat symlinks** like `.opencode/tools/format-md.ts → src/instructions/tools/format-md/format-md.ts`. Requires `init.sh` to enumerate tool files instead of linking a directory.
    - **C**: Inline the tool definition into an existing plugin (plugins do work via the symlink because their `import` resolves through `.opencode/plugins/devbot/` → `.opencode/node_modules/` chain at install time).
- **MUST**: Before committing any opencode custom tool, verify registration by `curl http://127.0.0.1:<port>/experimental/tools/ids | grep <tool-name>` on a running `opencode serve`. Do not rely on `pytest` of the underlying script — the script works, the **tool registration** is the gate.
- See [[patterns]] for the (now-known-broken) tool-conversion pattern that needs revision.

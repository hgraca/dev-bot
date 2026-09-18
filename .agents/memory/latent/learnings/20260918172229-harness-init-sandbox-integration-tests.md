---
date: 2026-09-18
keywords: ["testing", "harness-init", "bats", "sandbox", "opencode"]
---

# Harness init.sh can be run against a sandbox for integration tests

`src/harnesses/opencode/init.sh` and `src/harnesses/claudecode/init.sh` are top-level scripts — sourcing them executes the whole init, so a single function (e.g. `_register_dynamic_mcps`, `_wire_mcp`) cannot be unit-tested in isolation.

They *can* be executed against a throwaway project dir:

```bash
SB=$(mktemp -d)
printf '{ "modules": { "opencode": true, "jetbrains": false } }\n' > "$SB/.devbot.project.jsonc"
mkdir -p "$SB/.opencode" && printf '{"jetbrains": {"type": "remote", "url": "http://127.0.0.1:64442/stream"}}\n' > "$SB/.opencode/jetbrains.mcp.json"
bash src/harnesses/opencode/init.sh "$SB"
```

The script computes `DEV_BOT_ROOT` from its own location (the real repo), so it reads the real templates while every write targets `$SB`. The real repo stays clean (verified with `git status --porcelain`), and the project `.devbot.project.jsonc` pins module state — it overrides the global `modules` map — so the test is hermetic even when the global config changes.

Three testing patterns exist in this repo; pick by what you need:

- **stripped + stubbed** (`claudecode/tests/init_tests.bats`: `sed '/^# ── main/,$d' init.sh` plus a fake `functions.sh`) — tests one function in isolation, but every helper it calls must be stubbed.
- **real run in a sandbox** (this note; `src/harnesses/*/tests/dynamic_mcp_tests.bats`) — faithful end-to-end behavior, at ~5s per test because the full init runs.
- **extracted pure helper** (e.g. `_devbot_manifest_owner_disabled`, `_mcp_declares_hybrid`) — when the unit under test is a decision, pull it into `_shared/functions.sh` and unit-test it directly.

Caveat: a new helper in `_shared/functions.sh` needs mirroring in the *stubbed* BATS fixtures (`bin/tests/*.bats`) only when the code under test calls it; the real-run sandbox pattern picks it up automatically.

---
date: 2026-11-04
keywords: ["mcp_translate", "REFRESH_MODULES", "canonical-manifest", "opencode"]
---

# A new canonical MCP key reaches existing installs only via REFRESH_MODULES

`mcp_translate.py` fails loudly on an `ENTRY_KEYS` member it does not know, but silently **drops nothing** — the corollary is that a new canonical field exists only once three things agree: `ENTRY_KEYS`, `_validate_entry`, and the per-harness branch of `translate()`. Adding a key to a module's `mcp.json` without all three makes the manifest invalid, and adding it to the translator without the refresh list leaves every existing project on the old shape.

Registration is skip-if-exists (`merge_mcp_jsonc.py`), and `mcp_key_is_current.py` compares the translated template against the config entry, so a config entry lacking the new key reads as **stale**. But reset only drops stale entries for the modules named in `REFRESH_MODULES` (`src/harnesses/opencode/reset.sh`) — every other module's entry is treated as user-owned and survives reinit forever.

So shipping a new canonical field is a four-part change: translator key + validation + emission, the module manifest, `REFRESH_MODULES`, and a reset test asserting the module is listed. `enabled` and `timeout` are both opencode-only and dropped for claudecode, which carries startup budget separately (`MCP_TIMEOUT`); the translator comment says so, keep that contract when adding the next one.

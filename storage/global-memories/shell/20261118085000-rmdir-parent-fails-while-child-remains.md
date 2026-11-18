---
date: 2026-11-18
keywords: ["shell", "rmdir", "cleanup", "idempotency"]
---

## `rmdir` on a parent silently fails while any child directory remains

Retiring a generated directory farm with `rmdir <parent>` is a no-op when the tree still holds a nested directory: `rmdir` refuses a non-empty target, and the `2>/dev/null || true` most cleanup loops carry hides the refusal, so the "retired" path survives every run. In dev-bot's opencode-v2 harness, `for dir in .opencode/tui-plugins .opencode/v2; do rmdir "$dir"; done` left `.opencode/v2/plugins/` — and therefore `.opencode/v2/` — in the project through every reinit. Remove children before parents (`.opencode/v2/plugins`, then `.opencode/v2`), or use `rm -rf` once the subtree is verified to hold no user files. Assert the end state (`refute [ -d "$dir" ]`), never the command's exit status: the failure is silent by construction, and an empty leftover directory reads as live config to the next reader.

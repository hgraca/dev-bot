---
date: 2026-05-17
keywords: ["opencode", "plugin", "file.edited", "gather-context-cache", "format-md"]
---

## gather-context-cache tool writes files directly, bypassing file.edited event

The `gather-context-cache` tool uses Node's `fs.writeFile()` to persist cache files to disk. This is a direct filesystem write that never passes through opencode's file-editing pipeline, so no `file.edited` event is emitted and plugins like `on_file.edited-format-md` never fire. The fix is to call `format-md` (or any required post-write processor) inside the tool itself, immediately after `writeFile`, as a detached fire-and-forget process — not in the skill. Placing it in the tool is deterministic: every caller gets formatting regardless of which skill or workflow invokes the tool. Placing it in the skill is fragile: any caller that bypasses that skill step silently skips formatting. General rule: the tool owns the write, so the tool owns any mandatory post-write side effects. See also [[global/opencode/20260510000000-05-opencode-custom-tool-thin-ts-wrapper-delegating-to-a-colocated.md]].

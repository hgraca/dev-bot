---
date: 2026-09-07
keywords: ["opencode", "edit", "format hook", "fuzzy match", "hooks"]
trigger-on: ["opencode-fuzzy-edit-format-hook"]
---

## opencode fuzzy edit + async format hook: a stale-indentation second edit corrupts the file

With dev-bot's auto-format hooks (format-md/json/yml) running async on
file.edited, two rapid edits to the same file corrupt it: the formatter
normalizes after edit 1 (e.g. re-indents YAML to 2 spaces), then edit 2 — whose
oldString came from the pre-format content with stale indentation — is
fuzzy-spliced by opencode's indentation-insensitive matcher into the normalized
file, leaving mixed indentation that prettier cannot parse (it refuses to
repair unparseable YAML). Nothing self-heals; the corruption is visible only in
the next read/diagnostics. This is the same mechanism audit-48's skipOnCreate
fixed for the create path, resurfacing between two edits. Mitigations (all
in-repo): the adapter logs `file.edited hooks rewrote <file>` to
`.agents/logs/hooks.log` when a hook changed the file; and the agent must
re-read a file after an edit that triggers a formatter before issuing a
further edit in it. The root cause is opencode's edit tool (out of repo).

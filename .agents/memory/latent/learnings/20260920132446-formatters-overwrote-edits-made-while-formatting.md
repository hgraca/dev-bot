---
date: 2026-09-20
keywords: ["format-md", "formatter", "race", "hooks"]
---

# The formatters could overwrite an edit made while they ran

`format_file` in `format-md.py`, `format-json.py` and `format-yml.py` read the file, ran prettier over it, then wrote the result back unconditionally. The read→write window spans the whole prettier subprocess, so an edit landing inside it was silently discarded by the stale write.

This is what actually lost a table row in `docs/commands.md`: the `file.edited` hook rewrote the file from a pre-edit copy. The hook already had four layers of mitigation (edit debounce, per-file gate, rewrite-echo suppression, create-vs-edit classification) and none of them could help — the write happens inside the tool the hook shells out to, not in the hook itself. Symptom to recognise: a just-applied edit is missing on re-read, and `.agents/logs/hooks.log` carries two `file.edited hooks rewrote …` lines close together.

Fixed by re-reading immediately before the write and backing off with a `WARN:` when the content changed since the read — the next edit event formats the newer content, so the newer edit always wins over the older formatting.

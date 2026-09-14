---
date: 2026-09-14
keywords: ["devbot", "format-md", "prettier", "editorconfig"]
---

# Editing a doc file reformats every embedded jsonc block in it

`format-md` runs prettier, which honours `.editorconfig` — this repo sets `indent_size = 2` for `{yml,yaml,json,jsonc,md}`. Saving a `.md` therefore reindents **every** embedded JSONC code block in the file (e.g. 4 → 2 spaces), not just the lines being edited, so a one-line prose change can produce dozens of unrelated diff lines.

Stage selectively (`git add -p`, or lift the intended hunk out of `git diff` and `git apply --cached` it) and let the normalization land as its own `style(docs)` commit instead of burying it in a content or fix commit. The hook is also async: after any `.md` edit, re-read the file before issuing a further edit, since indentation and line numbers may have shifted.

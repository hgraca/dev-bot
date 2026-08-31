---
date: 2026-06-17
keywords: ["opencode", "edit", "json", "indentation", "formatting"]
---

## edit tool reformats JSON files to 2-space indentation

The `edit` tool applies automatic JSON formatting when modifying `.json` files, converting the entire file from its original indentation (e.g., 4-space) to 2-space indentation. This is not documented in the tool's description and causes unexpected reformatting of the entire file when only a small add/edit was intended. The diff appears as a full-file rewrite with all lines changed. Workaround: use `sed` via `bash` to make targeted string insertions/deletions in JSON files, or use `write` with the entire file content at the correct indentation. The `edit` tool does NOT reformat other file types (Dockerfiles, YAML, Markdown) — only JSON/JSONC.

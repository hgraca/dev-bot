---
date: 2026-05-10
keywords: ["bash", "shell"]
---

## `IFS=$'\t' read -r` collapses adjacent empty fields

In `bin/module.sh::cmd_sync` (commit `3a8b55a`), a python helper emitted `name\turl\t\t{json}` (4 tab-separated fields, with `local_path` empty in the middle) and bash parsed it with `while IFS=$'\t' read -r _name _url _local_path _paths_json`. Because tab is an IFS _whitespace_ character, bash's `read` collapses runs of IFS whitespace into a single delimiter — so `\t\t` became one separator, the JSON spilled into `_local_path`, and `_paths_json` was empty. Symptom in this case: `module sync` tried to symlink `vendor/local/{"agents": "agents", ...}` to itself. The bug only triggers when an _interior_ field is empty; trailing-empty fields would also hit it.
Fix: Use a non-whitespace delimiter (ASCII Unit Separator `\x1f` is ideal — non-printable, can't appear in paths or JSON, and `read` treats it as a regular IFS character so empty fields are preserved). Pattern: `print(name + '\x1f' + url + '\x1f' + local_path + '\x1f' + json.dumps(paths))` paired with `while IFS=$'\x1f' read -r ...`. This same trap applies to any tab/space-delimited stream where interior fields can be empty. See [[patterns]] for shell scripting conventions.

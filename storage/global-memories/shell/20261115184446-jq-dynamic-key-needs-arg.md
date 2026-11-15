---
date: 2026-11-15
keywords: ["shell", "jq", "interpolation", "quoting"]
aliases: ["jq computed key", "jq key from variable", "jq error X is not defined"]
trigger-on: ["jq-dynamic-key", "shell-jq-program-quoting"]
---

## A jq computed key must be passed with `--arg`, never interpolated into the program

Writing `jq -nc "{($server): {...}}"` puts the program in a **double-quoted shell string**, so the shell expands `$server` before jq parses it: `{($server): …}` becomes `{(aws-prod): …}` and jq reports `aws/0 is not defined` — the key was read as the expression `aws - prod`. The failure is loud but reads like a jq bug. Use `--arg s "$server" '{($s): …}'` and a single-quoted program; the same rule applies to any value interpolated into a jq program (`--argjson` for non-strings). Symptom to recognise: `jq: error: <name>/0 is not defined` where `<name>` is the first word of your variable's value.

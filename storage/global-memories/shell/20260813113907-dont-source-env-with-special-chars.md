---
date: 2026-08-13
keywords: ['shell', 'env', 'source', 'pipe']
---

## Don't `source` a .env containing shell special characters

`source <(grep -E '^KEY=' .env)` (or `set -a; source .env`) mangles values that contain shell metacharacters. A value like `GIATA_USERNAME=giata|get-e.com` contains a `|`, which the shell interprets as a pipe — the assignment truncates at the pipe and the remainder is executed as a command (`get-e.com: command not found`), and `*` in a password expands as a glob. Prefer a proper `.env` parser, or read the specific value without evaluating it (e.g. `grep '^KEY=' .env | cut -d= -f2-`), and always quote when interpolating.

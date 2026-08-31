---
date: 2026-05-20
keywords: ["shell", "grep", "bash", "testing"]
---

## `grep -qF "<token>"` does not match `<token-suffix>` — angle brackets are not wildcards

When a test uses `grep -qF "<model>"` to assert a usage string contains `<model>`, it performs a literal fixed-string search. The string `<model-name>` does NOT contain the substring `<model>` because `<model>` ends with `>` but in `<model-name>` the `>` only appears after `-name`. Fix: align the usage string in the script to use exactly the token the test expects (e.g. `<model>` not `<model-name>`), or update the test needle to match the actual token. Discovered while implementing `bin/pull-model.sh` in the DevBot CLI.

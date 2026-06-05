---
date: 2026-05-10
keywords: ["opencode"]
---

## `sort -V -r | head -1` SIGPIPEs under `set -o pipefail`

In `patch-opencode.sh`'s `latest` ref resolver, `git ls-remote --tags ... | sort -V -r | head -1` triggered SIGPIPE on `sort` because `head -1` closes the pipe early. Under `set -o pipefail` this propagates as failure even though the output is correct. Symptoms: command silently exits non-zero mid-script with no error message.
Fix: Use `sort -V | tail -1` instead — `tail` consumes the entire stream, no early-close, no SIGPIPE. Same result, pipefail-safe. Applied at `patch-opencode.sh` (commit `7d3eaab`).

---
date: 2026-05-15
keywords: ["git", "commit", "hook"]
---

## Pre-commit hook runs full test suite and blocks indefinitely

The repo's pre-commit hook was configured to run the full test suite before every commit. On a large codebase this takes >15 min and blocks the commit entirely — agent delegation stalls waiting for the hook to finish. Non-obvious because the hook appeared to hang with no output. Resolution: user removed the hook. When delegating commits to @developer, do NOT use `--no-verify` as a workaround — escalate to the user if the hook blocks.

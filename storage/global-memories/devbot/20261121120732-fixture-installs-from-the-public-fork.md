---
date: 2026-11-21
keywords: ["devbot", "fixture", "e2e", "audit", "install-source"]
---

## The e2e fixture installs from the public fork, not the repo you merge into

`tests/test-project/test-reinit.sh` installs dev-bot with `curl … raw.githubusercontent.com/hgraca/dev-bot/<branch>/install.sh`, because the canonical repo is private and raw.githubusercontent serves only public repositories. Consequence: an audit run **audits that fork's branch**, not your checkout — a fork two days stale produced a report whose FAILs described code already fixed, including a stale line number quoted from the fixture's own old copy. Two rules follow. Check the fork's `main` SHA against `origin/main` before trusting a run, and remember the launcher scripts come from the checkout you run while the *installed* dev-bot comes from the fork — the two can disagree. To audit an unmerged branch or a worktree, `DEV_BOT_TEST_LOCAL_SRC=<path>` mounts that tree and installs from it instead.

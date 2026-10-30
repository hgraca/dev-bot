---
date: 2026-10-30
keywords: ["devbot", "ci", "lint", "prettier", "pull-request"]
---

# dev-bot's CI lints only pull requests, so main can stay red

`.github/workflows/ci.yml` triggers on `pull_request` and `workflow_dispatch` only — never on a push to `main`. `make lint` checks **every tracked** `.md`, `.json`/`.jsonc` and `.yml` (`git ls-files …` minus `storage/` and `tests/`), so a memory note or doc committed straight to `main` with prettier drift stays unseen until the next pull request.

That pull request then fails on files it never touched: PR CI checks out the merge ref (`refs/pull/N/merge`), which includes `main`'s tree. The failure is neither a merge conflict nor caused by the branch — run the Makefile's exact prettier invocation over the flagged paths before hunting the diff.

The repair is to format the offending `main` files; a `style(memory)` commit on the PR branch is enough and fixes `main` when it merges. Do not go looking in the branch: `git diff origin/main...HEAD` will not list the flagged files.

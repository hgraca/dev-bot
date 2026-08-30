---
date: 2026-08-29
keywords: ["install", "release-tag", "bootstrap", "git"]
---

# Root install.sh installs latest release tag, falling back to main

The standalone bootstrap (`install.sh`) now resolves the ref to install in this
order: explicit `--branch`/`DEV_BOT_BRANCH` wins; otherwise the latest GitHub
release tag via `https://api.github.com/repos/{org}/{repo}/releases/latest`
(same pattern as the k8s module's `_fetch_latest_tag`); otherwise `main`.
Both the fresh-clone path (`git clone --depth 1 --branch <ref>`, works for
tags as detached HEAD) and the existing-clone update path are ref-aware:
tags use `git fetch origin tag` + `git checkout`, branches keep
`pull --ff-only`. In-clone installs (`make install`) and `--print-url` are
unchanged. dev-bot had 0 tags at decision time, so behavior is identical until
a release is cut — the change makes tag releases adoptable without touching
install docs.

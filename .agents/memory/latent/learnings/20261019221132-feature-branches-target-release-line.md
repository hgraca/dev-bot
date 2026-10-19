---
date: 2026-10-19
keywords: ["devbot", "release-line", "main", "branch", "rebase"]
aliases: ["release/v1.9", "main behind", "feature branch base"]
---

# Feature branches target the active release line, not `main`

dev-bot's `main` can lag the active `release/vX.Y` line by dozens of commits;
features land on the release line and `main` catches up later. Branch new work
off `release/vX.Y` — the branch the PR base targets — not `main`. A `main`
rebase is not a neutral exercise: it replays older code against newer tests and
failed seven unrelated checks in this session (mdctx latent-vs-whole-memory
assertions and the Intelephense pin/install test). Confirm the integration
branch from the repo's release history and tags before choosing a base; if a
rebase is needed, rebase onto `origin/release/vX.Y`.

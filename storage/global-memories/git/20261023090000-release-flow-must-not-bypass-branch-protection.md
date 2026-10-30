---
date: 2026-10-23
keywords: ["git", "release", "branch-protection", "tag", "dev-tools"]
aliases: ["tag.sh bypassed protection", "direct push to main", "Bypassed rule violations"]
---

## Release flow must not push a protected default branch

`tag.sh` (dev-bot's release tool) merges the source branch into the default branch locally and then pushes `main` plus the tag. On a repo whose default branch requires a pull request (GET-E/dev-tools), that push reported `Bypassed rule violations` and landed the release commit directly, twice.

If the PR is already merged, the push is a no-op and only the tag travels — that is the safe case. For an unmerged release commit, land it through a PR first (`git push <source-branch>` → `gh pr create` → merge), then run `tag` and `push`; the branch is in sync by then and only the tag is sent. Treat a bypass message as a failure, not as success. The guard added in GET-E/dev-bot#13 makes `tag.sh push` refuse to move a protected branch; do not work around it with `--admin`.

---
date: 2026-09-24
keywords: ["devbot", "search-memories", "git-branch", "index-refresh"]
trigger-on: ["search-memories-switches-branch"]
---

## `search-memories` can leave HEAD on a different branch — re-check the branch before committing

The memory search tooling is branch-aware: it refreshes its index when the index was built for a different git branch or checkout. In a session where several `search-memories` calls were made, the git **reflog showed a bare `checkout: moving from fix/<branch> to main`** that no agent command issued — and the next two `git commit` calls silently landed on `main` instead of the feature branch (the local `main` then sat 2 commits ahead of `origin/main` with commits whose content belonged to the feature branch). Nothing was lost — the feature branch still held its own commits — but the stray commits had to be removed (`git branch -f main origin/main`) and the files restored from the stray commits (`git checkout <stray-sha> -- <paths>`).

Rule: when a session calls `search-memories` (or any index-refresh tool) in a repo, re-assert the branch immediately before any history-writing git command — `git status -sb | head -1` or `git rev-parse --abbrev-ref HEAD` — and verify the branch in the commit output. Do not assume the branch you set earlier is still current. If commits land on the wrong branch, recover from the reflog rather than rewriting: the stray commits are the only copy of their content, so restore files with `git checkout <sha> -- <path>` before moving the branch back.

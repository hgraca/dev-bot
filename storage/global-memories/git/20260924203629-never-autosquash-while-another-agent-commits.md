---
date: 2026-09-24
keywords: ["git", "fixup", "autosquash", "concurrent-agents"]
trigger-on: ["git-autosquash-fixups", "concurrent-agent-branch"]
---

## Never autosquash a branch another agent is actively committing to

`git rebase -i --autosquash` replays every commit from the base you pass, giving all of them new SHAs — so on a shared, actively-worked branch it rewrites other agents' unpushed commits and holds the branch in a rebase state while they keep committing. Contiguous fixups are a false comfort: what matters is whether the *target* commits sit adjacent to the fixups. Verify with `git log --oneline <base>..HEAD` — if another author's commits lie between your fixups and their targets (or on top of them), autosquash must replay those too. Also resolve `git rev-parse --abbrev-ref '@{upstream}'` before calling commits "unpushed": a branch can be tracked (e.g. `origin/release/v1.6`) while `git branch -r --contains <sha>` is empty, meaning your commits — and the other agent's — are all still local. Creating a fixup is always the safe half; squashing is the destructive one. Defer it to whoever merges, or to a release step that folds fixups itself (dev-bot's `devbot release merge` autosquashes the `origin/<default>..<source>` range before tagging).

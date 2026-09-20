---
date: 2026-09-10
keywords: ["git", "shallow-clone", "merge-base", "ancestry", "depth-1"]
trigger-on: ["git-shallow-clone", "git-merge-base-ancestry"]
---

## A shallow clone makes `git merge-base --is-ancestor` fail in both directions

In a shallow clone (`git clone --depth 1`) the grafted boundary truncates HEAD's history, so both `git merge-base --is-ancestor <tag> HEAD` and `git merge-base --is-ancestor HEAD <tag>` return non-zero even when the tag genuinely is an ancestor of HEAD. Any logic that classifies HEAD relative to a tag (ahead / behind / diverged) therefore misreads an ahead branch as diverged — a false negative that can trigger a destructive action like an unwanted rebase. `git fetch --tags` alone does not fix it: it fetches the tag's side of history but leaves HEAD grafted. Fix: detect `git rev-parse --is-shallow-repository`; when the initial comparison is `diverged` and the repo is shallow, run `git fetch --unshallow --tags <remote>` (bound it — it can be slow on large repos) and re-classify before concluding diverged. A shallow clone checked out *detached on an older tag* classifies correctly as `behind`, because fetching the newer tag connects the history from the tag side; only the "branch with its own commits" case breaks.

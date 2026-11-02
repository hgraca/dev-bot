---
date: 2026-11-02
keywords: ["worktrees", "autosquash", "rebase", "fixup"]
---

# The fixup-squash tree check is invalid once the base has moved

`devbot:git-fixup-commits` verifies a squash by hashing `git diff <base>..HEAD` before and after and requiring an identical hash. That only holds while `<base>` is the same commit both times.

`worktree.sh create` cuts the branch from `origin/<default>`, and the pre-merge flow fetches the base again. If `origin/main` gained commits in the meantime, the autosquash rebase replays the branch onto the new tip: the branch legitimately acquires everything main gained, so the before-hash (computed from the old-based HEAD against the already-updated ref) differs and the check "fails" on a correct squash.

Verify with structural checks instead:

- `git show --stat HEAD` lists only the task's files;
- `git rev-parse HEAD^` equals `origin/<default>`;
- no `fixup!`/`squash!`/`amend!` subjects remain.

Capture the lease (`git rev-parse origin/<branch>`) before fetching, and fetch only `<default>`: fetching `<branch>` moves the lease onto someone else's tip.

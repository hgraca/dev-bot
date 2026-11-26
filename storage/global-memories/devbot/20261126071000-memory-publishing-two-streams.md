---
date: 2026-11-26
keywords: ["devbot", "memory", "pull-request", "commit-memory", "global-memories"]
---

## Memory publishing is two streams with two standing-PR titles

The wrap-up memory capture publishes its notes by the repository **and** stream that own them:

- **Project vault** (`<project>/<devbot_dir>/memory/...`) → the owning project's repository, standing
  PR titled `chore(agents): commit memories and lessons learned`, gated by the project's effective
  `commit_memory` and `git check-ignore`.
- **Global store** (`storage/global-memories/...`) → the dev-bot repository, standing PR titled
  `chore(global-memories): commit global memories and lessons learned`, always published regardless
  of any project's `commit_memory`.

One repository can carry both streams; never mix them in one branch or pull request. A note named
through the `latent/global` symlink must be resolved to its `storage/global-memories/...` target
before `check-ignore`, copy and `git add`; an ignore match on a global path is an error, never a
silent skip. Branch names carry the shell PID (`chore/commit-memories-<timestamp>-$$` or
`chore/global-memories-<timestamp>-$$`) so concurrent finish flows cannot collide.

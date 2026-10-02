---
date: 2026-09-28
keywords: ["git", "ls-remote", "remotes"]
trigger-on: ["git-multi-remote-verification"]
---

## `git ls-remote`'s extra argument is a ref pattern, not a second remote

`git ls-remote` takes exactly one repository plus optional ref *patterns*, so `git ls-remote --tags origin hgraca` queries `origin` only and filters its refs against the pattern `hgraca` — printing nothing and looking like the tag is missing, while the second remote is never contacted. Verify several remotes one invocation at a time (`git ls-remote --tags origin; git ls-remote --tags hgraca`) or loop over `git remote`.

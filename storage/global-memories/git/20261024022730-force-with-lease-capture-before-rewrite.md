---
date: 2026-10-24
keywords: ["git", "force-with-lease", "fetch", "push", "rewrite"]
aliases: ["lease refresh", "safe force push", "force-with-lease fetch order"]
---

## Capture the lease before rewriting, and never fetch the branch before the push

`git push --force-with-lease` compares the remote ref against the local remote-tracking ref, so fetching the branch after a colleague pushed updates that tracking ref to their tip and the lease then matches — the push silently overwrites their commit. The safe sequence for a rewritten branch is: read `git rev-parse origin/<branch>` before the rewrite, then `git push --force-with-lease=refs/heads/<branch>:<expected-oid> origin <branch>`, with no fetch of `<branch>` in between; fetching `<default>` for the rebase base is fine. The bare form is only safe while no fetch has touched the branch since its last known state.

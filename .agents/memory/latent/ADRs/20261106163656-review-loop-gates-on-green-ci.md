---
date: 2026-11-06
keywords: ["gh-review-loop", "ci-gate", "copilot-review", "mergeable"]
aliases: ["review loop terminal condition", "CI green before squash", "mergeable gate"]
see: ["ADRs/20261024022740-pr-stage-fixups-and-memory-commits.md"]
---

## The review loop ends on green CI and a mergeable PR, not just a clean review

Stakeholder decision (2026-11-06). `devbot:gh-review-loop` used to stop the moment a Copilot review introduced no new findings: squash the fixups, hand over the force-push. That let a pull request with red required checks or an unmergeable state reach the hand-over, so the terminal condition now includes the remote gates. A `### Gate` step sits between `Track` and `Finish`: every required check must be `pass` or `skipping` (`gh pr checks <pr> --repo <owner>/<repo> --required --json name,bucket`) and `gh pr view <pr> --repo <owner>/<repo> --json mergeable,mergeStateStatus` must report `MERGEABLE` and `CLEAN`. A failing check is fixed as its own `fixup!`, pushed, and the loop returns to `Request` — green checks against a stale review do not finish it, and `mergeable: UNKNOWN` while GitHub computes it is not a pass. `BEHIND` updates the branch with `gh pr update-branch` and re-enters the wait; `CONFLICTING`/`DIRTY` stops and asks the user, because a conflict is resolved by rewriting the branch, not by a fixup. A required no-fixup guard is expected to stay red until the squash and does not block the gate — the squash rewrites commits without changing the tree, so the checks stay green on the force-push. `software-development`, the `auto-dev` command, the `gh-review-loop` command and `github/docs.md` carry the same terminal condition; two BATS assertions pin the gate and that it precedes the squash.

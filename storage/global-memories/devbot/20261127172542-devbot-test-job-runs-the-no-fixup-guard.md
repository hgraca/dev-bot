---
date: 2026-11-27
keywords: ["devbot", "ci", "no-fixup-guard", "test-job", "squash"]
aliases: ["test job red until squash", "required job runs the fixup guard"]
---

## dev-bot's required `test` job runs the no-fixup guard, so it is red on every fixup-bearing branch

`GET-E/dev-bot` requires two contexts on `main`: `lint` and `test`. The `test` job waits on the three
`test-slice` jobs **and** runs a "No unfolded fixup commits" step, so any branch carrying a `fixup!` commit
fails `test` — a required check — even when every slice passed. The `no-fixup` check itself is ignored by
name (`fixup` substring), but `test` is not, so `pr-watch --until green` cannot report `6` on an unsquashed
branch; that is correct, not a bug, since the branch is not mergeable until it is folded. Read the gate once
after the squash is published: that push re-runs `test` green, because the squashed branch has no fixup
subjects. A red `test` whose log is only the fixup step is never a code failure, and a force-pushed branch
needs roughly seven minutes before the slices and `test` settle.

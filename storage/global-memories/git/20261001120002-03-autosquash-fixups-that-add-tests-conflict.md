---
date: 2026-10-01
keywords: ["git", "fixup", "autosquash", "rebase", "tests"]
trigger-on: ["git-autosquash", "git-fixup-commit", "history-rewrite"]
---

## `rebase --autosquash` cannot cleanly fold a fixup that adds tests to a shared test file

A `fixup!` authored at the branch tip carries hunk context from the tip, so folding it
into an earlier commit fails wherever a later commit changed the surrounding lines. This
bites hardest when the fixup adds a test block to the one test file every commit appends
to: git cannot place the block (its anchor tests do not exist yet at the target commit),
and after you resolve that, replaying the later test-adding commits conflicts again
because the fixup's block now sits among their anchors. The resolution is a "keep both"
union, which necessarily reorders the file — the final tree is content-equal but not
byte-equal to the pre-squash tip, so verify by diffing (expect only moved blocks, same
line count) rather than by tree hash. Prefer keeping test-adding corrections as ordinary
commits at the tip, or accept the reorder; do not expect a clean autosquash when fixups
and later commits both append to a single test file.

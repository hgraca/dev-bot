---
date: 2026-09-29
keywords: ["devbot", "address-review", "fixup", "hunk-splitting"]
---

# Address-review fixups per comment only work if each fix is a separate edit

The `devbot:address-review` protocol requires one `fixup!` commit per review comment, and that is only achievable when each comment's fix is written as its own edit. If several comments touch the same paragraph or the same contiguous region — here one documentation paragraph carried the fixes for five separate comments (F1/F2/F3/F7/F8), and a new test file carried five more as a single added block — git merges them into one hunk and they can no longer be separated without hand-editing patch headers. The mechanical consequences: `git add -p` cannot split a contiguous run of added lines, and piping hunk answers into it stages nothing outside a tty (see the `git add -p` note under `global/git`), so the deterministic route is to extract the wanted `@@` blocks from `git diff` and `git apply --cached` a partial patch, verifying with `git diff --cached` before each commit. Budget for it: twelve fixups cost roughly thirty staging calls. Where the comments genuinely serve one coherent behaviour described by one paragraph, the honest move is to put that prose in a single labelled fixup and name the comments it serves in the commit body, rather than pretending they were separable.

---
date: 2026-10-09
keywords: ["devbot", "guards", "force-push", "git"]
aliases: ["force push prohibited", "push --force blocked"]
---

## The guards module blocks force push — hand it to the human

`git push --force` (and `--force-with-lease`) is refused by dev-bot's `guards` hook with `[guards] Command blocked: force push is prohibited`; the block is intentional and must not be worked around (no `+refspec`, no alternate flag, no fallback command). When history rewriting — a fixup autosquash or a rebase — leaves a branch that needs a force push, stop and ask the human to run it: they own the decision to rewrite shared history. Report the exact commands (`git push --force-with-lease <remote> <branch>`) and the rewritten range so they can act. Ordinary fast-forward pushes are unaffected.

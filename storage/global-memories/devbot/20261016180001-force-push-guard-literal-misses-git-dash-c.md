---
date: 2026-10-16
keywords: ["devbot", "guards", "git", "force-push"]
aliases: ["guard regex", "git -C push", "force push prohibited"]
trigger-on: ["devbot-guard-rule"]
---

## A literal guard pattern misses `git -C <path> push --force` — and still matches prose

The `guards` rule `"regex": "git push --force"` is a plain substring match, so a force-push that
inserts `-C <path>` — `git -C /path/.agents/worktrees/feat push --force-with-lease`, the natural
form when acting on a worktree — does **not** match. The guard is silently bypassed, which is
how a worktree branch gets force-pushed despite the rule. Anchor the pattern to a command
position and allow the intervening arguments:

`(^|[\n;&|]\s*)git\b[^\n]*\bpush\b[^\n]*(\s-f\b|\s--force)`

It also catches `git push -f` and `--force-with-lease`, and — because `git` must start a command
segment (`^`, newline, `;`, `&`, `|`) — it does **not** fire on the phrase in prose. That matters:
the sibling rule `sudo .*` matches anywhere in the command, so `gh pr create --body "... sudo ..."`
(and even `echo 'git push --force'`) is blocked outright, refusing work that never executes the
guarded command. Prefer anchored patterns, and treat a guard hit as "reword or ask the human" —
never as "rephrase the command to slip past the pattern".

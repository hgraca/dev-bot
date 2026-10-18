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
how a worktree branch gets force-pushed despite the rule. Allow the intervening arguments:

`git\b(?:\s+(?:-C|-c)\s+(?:"(?:[^"\\]|\\.)*"|'[^']*'|\\[^\n]|[^\s"'\\])+|\s+(?:--git-dir|--work-tree|--namespace|--exec-path|--super-prefix|--config-env)\s+(?:"(?:[^"\\]|\\.)*"|'[^']*'|\\[^\n]|[^\s"'\\])+|\s+(?!(?:-C|-c|(?:--git-dir|--work-tree|--namespace|--exec-path|--super-prefix|--config-env))(?:\s|$))-(?:"(?:[^"\\]|\\.)*"|'[^']*'|\\[^\n]|[^\s"'\\])+)*\s+(?:push\b|"push"|'push')[^\n]*(\s-f\b|\s--force)`

Do **not** add a start-of-command anchor (`(^|[\n;&|]\s*)`): the guard evaluator (`guards.ts`)
anchors ordinary command segments itself and deliberately leaves runner segments (`bash -c`,
`env`, `xargs`, …) unanchored, so an explicit anchor would miss
`bash -c "git push --force"` and `env FOO=bar git push --force`. The unanchored pattern still
catches `git push -f` and `--force-with-lease`, while the evaluator's segment anchoring keeps it
from firing on prose. That matters:
the sibling rule `sudo .*` matches anywhere in the command, so `gh pr create --body "... sudo ..."`
(and even `echo 'git push --force'`) is blocked outright, refusing work that never executes the
guarded command. Prefer anchored patterns, and treat a guard hit as "reword or ask the human" —
never as "rephrase the command to slip past the pattern".

---
date: 2026-09-25
keywords: ["devbot", "guards", "bash", "rm-rf"]
trigger-on: ["devbot-guards", "bash-compound-command"]
---

## A guard match rejects the entire bash command, not just the matched segment — never append destructive cleanup to a verification command

dev-bot's guard rules are matched against the whole command string, so one matching pattern (for example the shipped `rm -rf` rule) fails the whole invocation — `[guards] Command blocked: rm -rf is blocked` and **nothing in the command runs**. A trailing cleanup in a compound command therefore costs the entire run: appending `&& rm -rf "$scratch"` to a multi-step verification discards every step that preceded it and reports nothing. Keep destructive cleanup out of verification commands (leave the scratch directories and clean them in a separate call), and do not route around a guard with an equivalent-but-unmatched form — the rule is a deliberate constraint, and the correct response to a block is to stop and surface it.

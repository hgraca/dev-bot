---
date: 2026-11-27
keywords: ["devbot", "commit", "cli", "subject", "message"]
aliases: ["commit tool loses the subject", "two -m flags", "devbot tool commit"]
---

## `devbot tool commit` with two `-m` flags drops the subject

Passing the subject and the body as two `-m` arguments loses the subject entirely: the body is then
split at its first blank line and used as subject and body, so the commit lands with a body bullet as
its subject and the real subject is gone.

Observed once on a bug-fix commit: `devbot tool commit -m "<subject>" -m "<Problems/Solutions body>" -- <paths>`
produced a subject reading `Problems: - …` and a body starting at `Solutions:`. The commit itself was
correct — only the message was mangled — and it needed `git commit --amend -F <file>` to repair.

Write the whole message to a file and use `git commit -F`, or pass the message as a single `-m` with
real newlines, and check `git log -1 --format='%s'` afterwards rather than trusting the tool's
success output. Amending is safe here only because the branch was unpushed; on a pushed branch the
repair is a normal follow-up, not a force-push.

---
date: 2026-10-24
keywords: ["git", "revert", "fixup", "commit-message"]
---

## Git writes a body for messages that look like they should be empty

An exemption written as "no body needed for `Merge`/`Revert`/`fixup!`" misdescribes git, because git generates a body for two of them:

- `git revert <sha>` writes `This reverts commit <sha>.` as the body.
- `git commit --fixup=amend:<sha>` copies the target commit's message as the body (plain `--fixup`/`--squash` do not; `--fixup` appends any `-m` as the body).

So the correct exemption is about **whose text it is**, not about having no body: the rules do not apply because git writes the subject and body. Scope it that way, and say that a marker prefix typed by hand is not an exemption — otherwise `git commit -m 'fixup! x'` becomes a way to skip the checklist.

Verified by creating both in a scratch repo. Applies to `devbot:git-commits`' message checklist and to any pre-commit validator built on it.

---
date: 2026-11-27
keywords: ["git", "gpg", "commit", "pinentry"]
aliases: ["failed to write commit object", "gpg signing timeout", "commit.gpgsign"]
trigger-on: ["git-commit-gpg-signing"]
---

## A git commit that cannot sign reports "failed to write commit object"

With `commit.gpgsign=true` in an environment that cannot prompt — an agent shell, a cron job, CI
without a passphrase-less key — gpg's pinentry never gets a TTY and the commit fails with
`gpg: signing failed: Timeout` followed by `fatal: failed to write commit object`. That message points
at the object store, so it reads as a disk or permission problem; `df`, `git hash-object -w` and the
`.git` ownership all check out fine. The object was never the problem: signing is. Check
`git config --get commit.gpgsign` and `git log -1 --format='%G?'` before chasing storage, and for a
signature-optional repository commit with `git -c commit.gpgsign=false` (or `--no-gpg-sign`) rather
than retrying, since a pinentry-less retry always times out.

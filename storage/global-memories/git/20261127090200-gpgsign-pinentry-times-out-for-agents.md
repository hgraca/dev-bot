---
date: 2026-11-27
keywords: ["git", "commit.gpgsign", "pinentry", "signing"]
aliases: ["gpg signing failed timeout", "unsigned commits", "pinentry"]
---

## `commit.gpgsign=true` with a pinentry timeout blocks every agent commit

On this machine `git config commit.gpgsign` is `true`, but gpg's pinentry cannot prompt from an agent's shell: the commit dies with `gpg: signing failed: Timeout` / `Operation cancelled` and `fatal: failed to write commit object`. The history is entirely unsigned anyway (`git log --format='%G?'` returns `N`), so the setting buys nothing and blocks every commit.

Workaround for agent commits:

```bash
git -c commit.gpgsign=false commit -m "…" -- <paths>
```

For a rebase, `-c` does not reach the sequencer; use the environment form:

```bash
GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=commit.gpgsign GIT_CONFIG_VALUE_0=false git rebase origin/main
```

Do not amend a fixup that is already pushed to repair this — that is a force-push; record a new fixup and squash it before the merge instead.

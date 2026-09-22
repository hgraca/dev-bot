---
date: 2026-09-22
keywords: ["devbot", "release", "memory-vault", "untracked-files"]
trigger-on: ["release-merge-dirty-tree", "release-blocked-by-untracked-note", "pending-vault-notes-before-release"]
---

## `release.sh merge` needs a fully clean tree, and pending memory notes are what make it dirty

`devbot`'s release flow is gated: `version` → release-notes file → `plan` → `merge`, `tag`, `push`, `release`. The first write, `merge`, refuses to proceed unless the working tree is entirely clean — and it counts **untracked** files, so a handful of freshly captured memory notes is enough to stop it with `FATAL: merge: the working tree is not clean`. That bites precisely at release time, because the vault is where a busy session's output lands: notes under `.agents/memory/thinking/` and `.agents/memory/work/` are gitignored and harmless, but a new note in the shipped global store (`storage/global-memories/<tech>/`, reached as `latent/global/<tech>/`) is a normal trackable path — `.gitignore` explicitly un-ignores `storage/global-memories/` — so it sits untracked until committed. On some machines a `.git/info/exclude` rule for `storage/global-memories/**` (machine-local, not committed) adds a second way to be surprised by it. Before starting a release, resolve pending notes deliberately: commit them (`git add` them; `-f` only if the local exclude shades the path), or move them aside — either way decide it, because leaving them means the merge stops and the release cannot proceed. Related: a note left untracked is also silently absent from every downstream install, so committing it is usually the right answer regardless of the release.

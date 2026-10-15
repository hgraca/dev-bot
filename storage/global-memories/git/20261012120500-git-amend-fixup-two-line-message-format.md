---
date: 2026-10-12
keywords: ["git", "fixup", "amend", "autosquash", "rebase"]
trigger-on: ["git-fixup-amend", "autosquash-amend-message"]
---

## `git commit --fixup=amend:` needs a single marker line, not a two-line subject

`git commit --fixup=amend:<sha>` produces a commit whose message must be `amend! <target subject>`, then a **blank line**, then the full replacement message (subject + body). Writing it as two adjacent lines (`amend! <subject>` / `<subject>` / blank / body) breaks autosquash: git's `%s` is the first _paragraph_ with newlines collapsed, so the marker's subject becomes `amend! <subject> <subject>`, no longer matching the target — `git rebase -i --autosquash` then shows it as a plain `pick` and never folds it. Verified on git 2.55: the single-line form yields the todo entry `fixup -C <sha>` (fold content **and** take the amend commit's message); the two-line form yields `pick`. Plain `fixup! <subject>` is unaffected — its subject is already one line.

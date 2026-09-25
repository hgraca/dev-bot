---
date: 2026-09-25
keywords: ["git", "autosquash", "fixup-commits", "rebase"]
trigger-on: ["git-autosquash-fixup", "git-fixup-commit"]
---

## Nested `fixup! fixup! fixup!` titles autosquash correctly — but only because every candidate folded into the same target

`git commit --fixup=<sha>` writes the subject as `fixup! <target subject>`. Correcting a fixup therefore produces `fixup! fixup! <subject>`, and correcting that produces a third level — which a reader sees as "weird titles". `git rebase -i --autosquash` resolves those by subject, placing each level immediately after the commit whose subject it names, so a 3-level chain folds correctly **as long as every intermediate commit is still in the todo list**.

The catch: subject matching is what makes nesting work, and it becomes ambiguous when two commits share a subject. In one branch a `fixup! fixup! feat(x)` and a `fixup! fixup! fixup! feat(x)` coexisted because two sibling fixups had been given the same target subject; the third-level commit could have attached to either. It was harmless only because both siblings folded into the *same* ultimate target. With different ultimate targets, one fixup would land on the wrong commit or be left standing as a standalone commit.

So before rebasing, print the plan and check that every fixup is placed: `GIT_SEQUENCE_EDITOR='grep -v "^#" "$1"; false' git rebase -i --autosquash <tight-base>` — the `false` aborts after printing, leaving history untouched. Then accept the reviewed list non-interactively with `GIT_SEQUENCE_EDITOR=: GIT_EDITOR=true git rebase -i --autosquash <tight-base>`. Always re-read `git log --oneline` afterwards: an unmatched fixup is silently left as a standalone commit rather than failing the rebase.

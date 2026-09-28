---
date: 2026-09-28
keywords: ["git", "fixup", "autosquash", "attribution", "rebase"]
trigger-on: ["git-fixup-commit", "git-autosquash", "history-rewrite"]
---

## Late-authored fixups conflict on autosquash — and "take the final content" smears attribution

A `fixup!` commit records a diff against the tree it was *created* on. If the fixup is authored after later commits have landed, its hunks carry context from those commits, so `git rebase -i --autosquash` — which moves the fixup next to its *target*, earlier in history — cannot apply it: `CONFLICT (content)` on every file whose surrounding lines the later commits changed (docs, usage text, test files). Resolving those conflicts by taking the file's *final* content (`git checkout <tip> -- <file>`) then smears attribution: the target commit absorbs files that belong to later commits (a later feature's test file lands in an earlier commit), so intermediate commits no longer build or pass their tests — while the final tree stays byte-identical and hides the damage until you inspect per-commit `--stat` or try to test an intermediate commit. Remedy: do not reorder when fixups were authored late. Group them into contiguous topics and replay each group as one commit by its **range diff** — on a base at the group's start, `git diff <first-of-group>^ <last-of-group> | git apply --index` then commit — which never reorders and never conflicts; verify the final tree hash is unchanged. The cleaner prevention is to create each `fixup!` while its target is still the branch tip, before later commits drift the context.

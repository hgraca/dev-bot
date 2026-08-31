---
date: 2026-08-31
keywords: ['git', 'autosquash', 'rebase', 'reword', 'GIT_SEQUENCE_EDITOR']
trigger-on: ['git-rebase-autosquash', 'git-reword-scripted']
---

## Autosquash todo lines put the subject after a `#` — sed edits silently no-op

When driving `git rebase -i --autosquash` with a scripted `GIT_SEQUENCE_EDITOR` (e.g. to swap `pick` → `reword` for specific commits), the todo lines are `pick <sha> # <subject>` — the subject comes **after a `#` comment marker**, not right after the sha. A sed like `s/^pick ([0-9a-f]+) fix\(api\):/reword \1 fix(api):/` matches nothing and the rebase proceeds silently with the picks unchanged — the reword never fires and no error is raised. Match the `#` explicitly: `s/^pick ([0-9a-f]+) # fix\(api\):/reword \1 # fix(api):/`. Verify after the rebase that the intended subjects actually changed (`git log --oneline`) rather than trusting the sequence editor ran.

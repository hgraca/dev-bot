---
date: 2026-05-10
keywords: ["opencode", "tool"]
---

## Blanket `*opencode*` `.gitignore` rule silently blocks new files in opencode tooling paths

The repo's `.gitignore` contains `*opencode*` (line 39) to ignore generated opencode config artefacts at root (e.g. `opencode.json`, `.opencode/`). Already-tracked files like `src/tools/opencode/update.sh` survive because gitignore does not affect tracked content — but **new files** added to `src/tools/opencode/` or `src/commands/patch-opencode/` are silently rejected by `git add`, with the error `paths are ignored by one of your .gitignore files`. `git status` does NOT list them as untracked, so the absence is easy to miss. Diagnose with `git check-ignore -v <path>` to see which rule matched.
Fix: Add explicit allow-list exceptions for intentional source paths, e.g. `!src/commands/patch-opencode/`, `!src/commands/patch-opencode/**`, `!src/tools/opencode/`, `!src/tools/opencode/**`. Place them after the `*opencode*` line. **Beware**: a `**` allow-list also re-includes generated noise like `__pycache__/`, `.pyc`, etc. that would otherwise be caught by global ignore patterns higher up. After adding the allow-list, follow up with explicit re-exclusions for those (e.g. `src/tools/opencode/__pycache__/`). See [[ADRs]] for the patching refactor that surfaced this.

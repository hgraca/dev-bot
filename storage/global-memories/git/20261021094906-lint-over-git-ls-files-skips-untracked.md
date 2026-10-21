---
date: 2026-10-21
keywords: ["git", "lint", "prettier", "untracked", "ci"]
aliases: ["git ls-files lint", "new file not formatted", "ci lint failure"]
---

## A lint target that lints `git ls-files` does not see new, untracked files

`make lint` in dev-bot builds its prettier and shellcheck file lists from `git ls-files`, so a brand-new file that is still untracked is skipped and the local run reports clean. The first CI run after the commit then fails on exactly that file (observed: `src/agentic/rfp/skills/rfp/SKILL.md` failed prettier after the module was committed). Before the first commit, either stage the new files so `git ls-files` includes them, or run the formatter directly on the new paths (`prettier --parser markdown --print-width 999 --embedded-language-formatting off --ignore-path /dev/null --write <file>`). Generalise: a clean lint over tracked files is not evidence that new files are formatted.

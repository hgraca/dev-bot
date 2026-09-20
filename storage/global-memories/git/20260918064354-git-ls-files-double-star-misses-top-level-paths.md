---
date: 2026-09-18
keywords: ["git", "ls-files", "pathspec", "glob"]
trigger-on: ["git-pathspec-glob"]
---

## `git ls-files 'dir/**/*.md'` silently omits files directly under `dir/`

Git pathspec globbing is not shell/`fnmatch` globbing: `**` behaves like a single-level wildcard, so `git ls-files 'docs/**/*.md'` matches only files ONE directory deeper (`docs/<sub>/<file>.md`) and omits every top-level `docs/*.md` — including `docs/index.md`. The returned count still looks plausible, so the omission is easy to miss, and any coverage/consistency check built on it under-reports and can pass vacuously. Use a directory pathspec instead — `git ls-files docs | grep '\.md$'` walks the whole subtree — or enumerate both levels explicitly (`'docs/*.md' 'docs/*/*.md'`). Verified in dev-bot: `git ls-files 'docs/**/*.md'` returned 25 of the 37 tracked markdown files under `docs/`.

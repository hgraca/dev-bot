---
date: 2026-04-22
keywords: ["git", "commit"]
---

## Documentation edits in one session can leave stale references in files not touched

When a previous session updates docs to use `curl` installer instead of `git clone`/`make up`, files not in that session's changeset can retain stale references. In this case, `about.md` still said "one `make up` installs" after `README.md`, `index.md`, and `developer-workflow.md` were already updated. Fix: always grep across all `docs/*.md` + `README.md` for the old phrasing before committing.

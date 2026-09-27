---
date: 2026-09-27
keywords: ["git", "numstat", "quotepath", "blame", "szz", "rename"]
trigger-on: ["git-log-numstat-parse", "szz-defect-linking", "git-blame-path"]
---

## Git C-quotes unusual paths unless you ask for `-z` / `core.quotePath=false`

`git log --name-only`/`--numstat` C-quotes paths with non-ASCII or special characters (`"caf\303\251.php"`) and escapes tabs/backslashes, so parsing with `split('\t')` stores a path that does not exist on disk and the file silently vanishes from later analysis. Use `--numstat -z`: records are NUL-separated and the path is verbatim (a rename emits an empty path field, then the old and new paths as their own NUL tokens). For `git show` diff parsing use `-c core.quotePath=false`, but note it does NOT unquote tabs/quotes/backslashes — `-z` is the reliable route where it exists. Two follow-on traps when linking defects (SZZ): `+++ `/`--- ` are file headers only *outside* a hunk (an added content line starting `+++` otherwise becomes a bogus path), and a rename/deletion must be blamed at the *old* pre-image path at the parent revision (`git show -M`) or the blame targets a path that does not exist yet.

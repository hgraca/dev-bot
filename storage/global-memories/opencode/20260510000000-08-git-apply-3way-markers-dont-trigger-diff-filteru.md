---
date: 2026-05-10
keywords: ["opencode"]
---

## `git apply --3way` markers don't trigger `--diff-filter=U`

Date: 2026-05-10 (RESOLVED 2026-05-10 in `7d3eaab`)
`patch-opencode.sh` L286 sanity-checks for unresolved conflicts via `git diff --name-only --diff-filter=U`, then proceeds to build. But `git apply --3way` writes textual `<<<<<<< / ======= / >>>>>>>` markers **inline** without setting the file to unmerged-status (different from a real `git merge` conflict). So the U-filter check passes with markers present in the file, and the build fails downstream with a confusing TS parse error (`Expected identifier but found "<<"`).
Fix (committed): `patch-opencode.sh` now checks BOTH `--diff-filter=U` AND `git grep -lE '^(<{7}|={7}|>{7}) ' -- '*.ts' '*.tsx' '*.js' '*.json' '*.md'` in three places — both 3-way detection branches (L249-253 success path, L268-273 failure-fallback path) AND the post-resume sanity check (L317+). Results deduped via `awk 'NF && !seen[$0]++'`. The same grep pattern also runs as a hard error gate before combined.patch generation.

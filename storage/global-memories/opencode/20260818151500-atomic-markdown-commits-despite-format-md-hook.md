---
date: 2026-08-18
keywords: ["opencode", "format-md", "atomic-commits", "markdown", "prettier"]
trigger-on: ["format-md-hook", "markdown-edit", "atomic-commits"]
---

## Keep markdown content commits atomic despite the format-md hook

When an opencode `on-file_edited-format-md` plugin hook auto-runs prettier on every .md save, the `edit` tool cannot produce a surgical markdown change — the whole file gets reformatted, polluting the content commit with wide unrelated diffs. Workaround for atomic commits: apply the content change with bash instead of the edit tool (a python one-liner string replace is the reliable path — hand-built unified diffs for `git apply`/`patch` are finicky: blank context lines must carry a leading space, yet git apply can still reject a well-formed hunk), verify the diff is exactly the intended lines, commit that clean diff, then run the format-md tool explicitly and commit the pure prettier churn separately as `style: format markdown with prettier`. Keeps review diffs focused while still honoring the repo's auto-format convention. Complements the mechanism note in `20260813210000-format-md-hook-reformats-whole-md-file-on-edit.md`.

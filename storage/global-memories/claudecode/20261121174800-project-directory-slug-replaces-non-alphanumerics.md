---
date: 2026-11-21
keywords: ["claudecode", "projects-directory", "slug"]
aliases: ["claude project folder name", "transcript directory naming", "replace non-alphanumeric"]
---

## Claude Code names a project directory by replacing every non-alphanumeric character

Claude Code stores transcripts under `<projects>/<slug>/<session>.jsonl`, where the slug is
`cwd.replace(/[^a-zA-Z0-9]/g, "-")` — not a slash-only transform. A dot becomes a dash: the project
`/home/me/repo/.agents/worktrees/fix` is stored as `-home-me-repo--agents-worktrees-fix` (note the
double dash), and a long path gets a `-<base36 hash>` suffix so the name stays within the length cap.
Verified in Claude Code 2.1.241: the bundle carries two slug functions, both with that regex, and a
transcript under `-home-herberto-Development-Get-e-dev-bot--agents-worktrees-full-audit-20261121-121000`
records `"cwd": "/home/herberto/Development/Get-e/dev-bot/.agents/worktrees/full-audit-20261121-121000"`.

So any code that locates a project's transcripts by reconstructing the slug must mirror that
transform, and must not trust a slash-only approximation: it silently misses every project whose
path contains a dot, a space, or another punctuation character. The projects root itself is
`$CLAUDE_PROJECTS_DIR` when set, otherwise `<CLAUDE_CONFIG_DIR or ~/.claude>/projects`.

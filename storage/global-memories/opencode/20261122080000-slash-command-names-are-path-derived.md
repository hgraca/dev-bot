---
date: 2026-11-22
keywords: ["opencode", "slash-command", "claudecode", "frontmatter", "commands-farm"]
aliases: ["command name from path", "frontmatter name is ignored", "colon command names"]
trigger-on: ["opencode-command-naming", "slash-command-namespace"]
---

## A file command's name comes from its path, never from its frontmatter

opencode 2.x derives a markdown command's name from its path below `commands/` — segments joined
with `/` — and **ignores the frontmatter `name:`** (verified on 2.3.2: files declaring
`name: devbot:audit` register as `devbot/audit` via `GET /api/command`). claudecode joins the
directory with `:` instead. So `.claude/commands/devbot/audit.md` and a flat
`devbot:audit.md` both give `/devbot:audit`, while `.opencode/commands/devbot/audit.md` gives
`/devbot/audit`. A `:` in the filename passes through verbatim — MCP prompt commands already use
that form — so a flat, colon-named file is the one shape both hosts read the same way. Verify a
host's registry directly (`GET /api/command` on opencode, `claude -p "/<name>"` on claudecode)
rather than trusting the farm's layout: the name is the host's decision, not the file's.

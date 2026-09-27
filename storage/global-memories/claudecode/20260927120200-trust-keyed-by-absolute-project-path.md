---
date: 2026-09-27
keywords: ["claudecode", "trust", "claude.json", "container"]
trigger-on: ["claude-code-container-share", "docker-claude-config-mount"]
---

## Claude Code trust/onboarding is keyed by absolute project path in ~/.claude.json

Claude Code stores the folder-trust dialog state in `~/.claude.json` under
`projects["<absolute path>"].hasTrustDialogAccepted` (and `hasCompletedOnboarding`
at the top level) — NOT inside `~/.claude/`, which holds settings, skills and
credentials. So mounting only `~/.claude/` into a container does not share trust:
the container's project path (`/app`) has no entry, and since the container is
`--rm`, accepting the dialog is lost every run. Sharing the host file is not
enough on its own either — the host's entries are keyed by host paths, not `/app`.

Fix pattern: mount the host `~/.claude.json` read-only and seed a container-local
copy that sets `hasCompletedOnboarding = true` and
`projects["<project>"].hasTrustDialogAccepted = true` before the harness starts.
Read-only + copy avoids writing a transient project entry back into the user's real
config, and avoids the single-file bind-mount rename hazard.

---
date: 2026-09-20
keywords: ["release", "git", "slash-command", "git-changelog"]
---

## `devbot:release`: a command that gates, a script that determines

Cutting a release is a `devbot:release` slash command plus a plain bash helper (`src/agentic/git/tools/release.sh`, subcommands `version` / `plan` / `merge` / `tag` / `push` / `release`). The helper owns everything deterministic; the command only gathers input, gates, and calls subcommands. The helper is deliberately **not** a `*.mcp.sh` — `_link_tools` farms only those, and a mutating release tool must not become globally callable by every agent.

Three consequences worth remembering. The approval preview is _generated_ by `plan`, so the preview and the executed steps cannot drift and the model composes nothing. No VCS mutation may precede approval, which is why `_default_branch` reads `refs/remotes/origin/HEAD` instead of calling `git remote set-head --auto` (that writes a ref — `merge` refreshes it instead). And the tag name and GitHub release title carry no `v` (`1.5.0`) while the changelog heading keeps `# Release v1.5.0`; the gitignored `release.v<MAJOR>-<MINOR>.no-vcs.md` is the single source for both the tag message and the release notes.
